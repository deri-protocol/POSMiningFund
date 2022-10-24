// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "../utils/NameVersion.sol";
import "../library/SafeMath.sol";
import "../library/SafeERC20.sol";
import "../library/DpmmLinearPricing.sol";
import "../token/IERC20.sol";
import "../swapper/ISwapper.sol";
import "../pool/IPool.sol";
import "../stake/IStaker.sol";
import "./FundStorage.sol";
import "../test/Log.sol";

contract FundImplementation is FundStorage, NameVersion {
    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;
    using Log for *;

    event Invest(
        address indexed user,
        uint256 amount,
        uint256 bnbAmount,
        uint256 marginAmount,
        int256 shareValue,
        uint256 newShareAmount
    );

    event RequestRedeem(
        address indexed user,
        uint256 indexed timestamp,
        uint256 redeemShareAmount,
        uint256 redeemBnbx,
        uint256 redeemBnb
    );

    event ClaimRedeem(
        address indexed user,
        uint256 indexed timestamp,
        uint256 burnShareAmount
    );

    event InstantRedeem(
        address indexed user,
        uint256 indexed timestamp,
        uint256 burnShareAmount
    );

    int256 public constant ONE = 1E18;

    uint256 public constant UONE = 1E18;

    uint256 public constant stakeRatio = 9E17;

    ISwapper public immutable swapper;

    IPool public immutable pool;

    ILensOracleManager public immutable oracleManager;

    ILensPool public immutable lensPool;

    IERC20 public immutable tokenB0;

    IStaker public immutable staker;

    IERC20 public immutable stakerBnb;

    address public immutable symbolAddress;

    string public constant symbolName = "BNBUSD";

    bytes32 public immutable symbolId;

    int256 public immutable minTradeVolume;

    struct PositionInfo {
        string symbol;
        int256 volume;
        int256 cost;
        int256 cumulativeFundingPerVolume;
        int256 dpmmPnl;
        int256 indexPnl;
        int256 accFunding;
    }

    struct AccountInfo {
        int256 amountB0;
        int256 vaultLiquidity;
    }

    struct SymbolInfo {
        address oracleManager;
        bytes32 symbolId;
        int256 alpha;
        int256 fundingPeriod;
        int256 netVolume;
        int256 curIndexPrice;
        int256 markPrice;
        uint256 fundingTimestamp;
        int256 cumulativeFundingPerVolume;
        int256 tradersPnl;
        int256 curCumulativeFundingPerVolume;
        int256 K;
    }

    constructor(
        address _swapper,
        address _pool,
        address _staker
    ) NameVersion("FundImplementation", "1.0.0") {
        swapper = ISwapper(_swapper);
        pool = IPool(_pool);
        tokenB0 = IERC20(pool.tokenB0());
        oracleManager = ILensOracleManager(pool.oracleManager());
        lensPool = ILensPool(_pool);

        staker = IStaker(_staker);
        stakerBnb = IERC20(staker.stakerBnb());

        symbolId = keccak256(abi.encodePacked(symbolName));
        symbolAddress = ILensSymbolManager(pool.symbolManager()).symbols(
            symbolId
        );
        minTradeVolume = ILensSymbol(symbolAddress).minTradeVolume();
    }

    function approveInvest() external _onlyAdmin_ {
        _approveSwapper(address(swapper), address(tokenB0));
        _approvePool(address(pool), address(tokenB0));
    }

    function invest(uint256 amount, int256 priceLimit) external {
        address user = msg.sender;
        require(
            userRedeemRequests[user].share > 0,
            "invest: ongoing claim request"
        );
        // transfer in B0
        tokenB0.safeTransferFrom(user, address(this), amount);

        // calculate shareValue before invest
        (int256 preTotalValue, int256 preShareValue) = calculateTotalValue(
            true
        );

        // B0 swap and stake
        uint256 stakingAmount = (amount * stakeRatio) / UONE;
        (, uint256 bnbAmount) = swapper.swapExactB0ForETH(stakingAmount);
        staker.deposit{value: bnbAmount}();

        // B0 add margin and short
        uint256 addAmount = tokenB0.balanceOf(address(this));
        pool.addMargin(
            address(tokenB0),
            addAmount,
            new IPool.OracleSignature[](0)
        );

        balanceBnbDiff(priceLimit);

        // calculate shareValue after invest and mint
        (int256 curTotalValue, ) = calculateTotalValue(true);

        uint256 mintShare = (((curTotalValue - preTotalValue) * ONE) /
            preShareValue).itou();
        _mint(user, mintShare);

        emit Invest(
            user,
            amount,
            bnbAmount,
            addAmount,
            preShareValue,
            mintShare
        );
    }

    function requestRedeem() external {
        address user = msg.sender;
        require(
            userRedeemRequests[user].share > 0,
            "requestRedeem: ongoing claim request"
        );

        uint256 amountShare = balanceOf(user);
        require(amountShare > 0, "requestRedeem: zero balance");
        IERC20(address(this)).safeTransferFrom(
            user,
            address(this),
            amountShare
        );

        // B0 swap and stake
        uint256 ratio = (amountShare * UONE) / (totalSupply() - pendingShare);
        uint256 amountInStakerBnb = (stakerBnb.balanceOf(address(staker)) *
            ratio) / UONE;
        uint256 amountInBnb = staker.convertToBnb(amountInStakerBnb);

        userRedeemRequests[user] = RedeemRequest({
            amountInBnb: amountInBnb,
            amountInStakerBnb: amountInStakerBnb,
            share: amountShare,
            startTime: block.timestamp
        });

        // request withdraw
        staker.requestWithdraw(user, amountInStakerBnb);
        pendingBnb += amountInBnb;
        pendingShare += amountShare;

        emit RequestRedeem(
            user,
            block.timestamp,
            amountShare,
            amountInStakerBnb,
            amountInBnb
        );
    }

    function claimRedeem(int256 priceLimit) external {
        address user = msg.sender;
        RedeemRequest storage redeemRequest = userRedeemRequests[user];
        require(redeemRequest.share > 0, "claimRedeem: no redeem record");

        pendingBnb -= redeemRequest.amountInBnb;
        pendingShare -= redeemRequest.share;

        // close bnb position
        balanceBnbDiff(priceLimit);

        // calculate position value
        uint256 tokenId = getPtokenId(address(this));
        AccountInfo memory accountInfo = getAccountInfo(tokenId);
        PositionInfo memory positionInfo = getPositionInfo(tokenId);
        int256 positionValue = accountInfo.amountB0 +
            accountInfo.vaultLiquidity +
            positionInfo.accFunding +
            positionInfo.dpmmPnl.min(positionInfo.indexPnl);
        int256 amountB0 = accountInfo.amountB0 + positionInfo.accFunding;
        uint256 removeAmount = (positionValue.itou() * redeemRequest.share) /
            totalSupply();
        if (amountB0 < 0) removeAmount += (-amountB0).itou();
        if (removeAmount > 0)
            pool.removeMargin(
                address(tokenB0),
                removeAmount,
                new IPool.OracleSignature[](0)
            );

        // claim BNB, then swap BNB to B0
        staker.claimWithdraw(user);
        (uint256 resultB0, ) = swapper.swapExactETHForB0{
            value: address(this).balance
        }();

        // burn share token
        _burn(user, redeemRequest.share);

        // transfer out B0
        tokenB0.transfer(user, tokenB0.balanceOf(address(this)));
        emit ClaimRedeem(user, block.timestamp, redeemRequest.share);
        delete userRedeemRequests[user];
    }

    function instantRedeem(int256 priceLimit) external {
        address user = msg.sender;
        uint256 amountShare = balanceOf(user);
        require(amountShare > 0, "requestRedeem: zero balance");

        // B0 swap and stake
        uint256 ratio = (amountShare * UONE) / (totalSupply() - pendingShare);
        uint256 amountInStakerBnb = (stakerBnb.balanceOf(address(staker)) *
            ratio) / UONE;
        uint256 resultB0 = staker.swapStakerBnbToB0(amountInStakerBnb);

        // close bnb position
        balanceBnbDiff(priceLimit);

        // calculate position value
        uint256 tokenId = getPtokenId(address(this));
        AccountInfo memory accountInfo = getAccountInfo(tokenId);
        PositionInfo memory positionInfo = getPositionInfo(tokenId);
        int256 positionValue = accountInfo.amountB0 +
            accountInfo.vaultLiquidity +
            positionInfo.accFunding +
            positionInfo.dpmmPnl.min(positionInfo.indexPnl);
        int256 amountB0 = accountInfo.amountB0 + positionInfo.accFunding;
        uint256 removeAmount = (positionValue.itou() * amountShare) /
            totalSupply();
        if (amountB0 < 0) removeAmount += (-amountB0).itou();
        if (removeAmount > 0)
            pool.removeMargin(
                address(tokenB0),
                removeAmount,
                new IPool.OracleSignature[](0)
            );

        // burt share token
        _burn(user, amountShare);

        // transfer out B0
        tokenB0.transfer(user, tokenB0.balanceOf(address(this)));

        emit InstantRedeem(user, block.timestamp, amountShare);
    }

    function rebalance(
        bool isAdd,
        uint256 amount,
        int256 priceLimit
    ) external _onlyAdmin_ {
        if (isAdd) {
            uint256 tokenId = getPtokenId(address(this));
            AccountInfo memory accountInfo = getAccountInfo(tokenId);
            PositionInfo memory positionInfo = getPositionInfo(tokenId);
            int256 amountB0 = accountInfo.amountB0 + positionInfo.accFunding;
            uint256 removeAmount = amountB0 >= 0
                ? amount
                : amount + (-amountB0).itou();
            if (removeAmount > 0)
                pool.removeMargin(
                    address(tokenB0),
                    removeAmount,
                    new IPool.OracleSignature[](0)
                );
            (, uint256 bnbAmount) = swapper.swapExactB0ForETH(amount);
            staker.deposit{value: bnbAmount}();
        } else {
            uint256 resultB0 = staker.swapStakerBnbToB0(amount);
            pool.addMargin(
                address(tokenB0),
                resultB0,
                new IPool.OracleSignature[](0)
            );
        }

        balanceBnbDiff(priceLimit);
    }

    function _approveSwapper(address _swapper, address asset) internal {
        uint256 allowance = IERC20(asset).allowance(
            address(this),
            address(_swapper)
        );
        if (allowance != type(uint256).max) {
            if (allowance != 0) {
                IERC20(asset).safeApprove(_swapper, 0);
            }
            IERC20(asset).safeApprove(_swapper, type(uint256).max);
        }
    }

    function _approvePool(address _pool, address asset) internal {
        uint256 allowance = IERC20(asset).allowance(address(this), _pool);
        if (allowance == 0) {
            IERC20(asset).safeApprove(address(_pool), type(uint256).max);
        }
    }

    //=====================
    // HELPERS
    // ====================
    function getPrice() internal view returns (uint256) {
        return oracleManager.value(symbolId);
    }

    function getPtokenId(address account)
        internal
        view
        returns (uint256 tokenId)
    {
        tokenId = ILensDToken(lensPool.pToken()).getTokenIdOf(account);
    }

    function getAccountInfo(uint256 tokenId)
        internal
        view
        returns (AccountInfo memory accountInfo)
    {
        if (tokenId != 0) {
            ILensPool.PoolTdInfo memory tmp = lensPool.tdInfos(tokenId);
            accountInfo.amountB0 = tmp.amountB0;
            accountInfo.vaultLiquidity = ILensVault(tmp.vault)
                .getVaultLiquidity()
                .utoi();
        }
    }

    function getPositionInfo(uint256 tokenId)
        internal
        view
        returns (PositionInfo memory positionInfo)
    {
        if (tokenId != 0) {
            ILensSymbol s = ILensSymbol(symbolAddress);
            ILensSymbol.Position memory p = s.positions(tokenId);

            positionInfo.symbol = s.symbol();
            positionInfo.volume = p.volume;
            positionInfo.cost = p.cost;
            positionInfo.cumulativeFundingPerVolume = p
                .cumulativeFundingPerVolume;

            SymbolInfo memory info;
            info.symbolId = keccak256(abi.encodePacked(positionInfo.symbol));
            info.fundingTimestamp = s.fundingTimestamp();
            info.oracleManager = s.oracleManager();
            info.alpha = s.alpha();
            info.fundingPeriod = s.fundingPeriod();
            info.netVolume = s.netVolume();
            info.curIndexPrice = ILensOracleManager(info.oracleManager)
                .value(info.symbolId)
                .utoi();
            int256 liquidity = ILensPool(address(pool)).liquidity() +
                ILensPool(address(pool)).lpsPnl();
            info.K = (info.curIndexPrice * info.alpha) / liquidity;
            info.markPrice = DpmmLinearPricing.calculateMarkPrice(
                info.curIndexPrice,
                info.K,
                info.netVolume
            );
            info.cumulativeFundingPerVolume = s.cumulativeFundingPerVolume();

            int256 diff = ((info.markPrice - info.curIndexPrice) *
                (block.timestamp - info.fundingTimestamp).utoi()) /
                info.fundingPeriod;
            unchecked {
                info.curCumulativeFundingPerVolume =
                    info.cumulativeFundingPerVolume +
                    diff;
            }

            int256 closeCost = DpmmLinearPricing.calculateCost(
                info.curIndexPrice,
                info.K,
                info.netVolume,
                -p.volume
            );
            positionInfo.dpmmPnl = -(p.cost + closeCost);
            positionInfo.indexPnl = -(p.cost -
                (info.curIndexPrice * p.volume) /
                ONE);
            positionInfo.accFunding =
                ((p.cumulativeFundingPerVolume -
                    info.curCumulativeFundingPerVolume) * p.volume) /
                ONE;
        }
    }

    function getStakingInfo()
        internal
        view
        returns (uint256 bnbAmount, uint256 bnbValue)
    {
        bnbAmount =
            pendingBnb +
            staker.convertToBnb(stakerBnb.balanceOf(address(staker)));
        bnbValue = (getPrice() * bnbAmount) / UONE;
    }

    function calculateTotalValue(bool isDeposit)
        public
        view
        returns (int256 totalValue, int256 shareValue)
    {
        uint256 tokenId = getPtokenId(address(this));
        if (tokenId != 0) {
            AccountInfo memory accountInfo = getAccountInfo(tokenId);
            PositionInfo memory positionInfo = getPositionInfo(tokenId);
            int256 positionValue = accountInfo.amountB0 +
                accountInfo.vaultLiquidity +
                positionInfo.accFunding;
            if (
                (positionInfo.dpmmPnl > positionInfo.indexPnl && isDeposit) ||
                (positionInfo.dpmmPnl < positionInfo.indexPnl && !isDeposit)
            ) {
                positionValue += positionInfo.dpmmPnl;
            } else {
                positionValue += positionInfo.indexPnl;
            }
            (, uint256 bnbValue) = getStakingInfo();
            totalValue = positionValue + bnbValue.utoi();
        } else {
            (, uint256 bnbValue) = getStakingInfo();
            totalValue = bnbValue.utoi();
        }
        shareValue = totalSupply() > 0
            ? (totalValue * ONE) / totalSupply().utoi()
            : ONE;
    }

    function balanceBnbDiff(int256 priceLimit) public returns (int256 diff) {
        uint256 tokenId = getPtokenId(address(this));
        ILensSymbol s = ILensSymbol(symbolAddress);
        int256 shortAmount = s.positions(tokenId).volume;
        uint256 longAmount = pendingBnb +
            staker.convertToBnb(stakerBnb.balanceOf(address(staker)));
        diff =
            ((longAmount.utoi() + shortAmount) / minTradeVolume) *
            minTradeVolume;
        if (diff != 0) {
            pool.trade(
                symbolName,
                -diff,
                priceLimit,
                new IPool.OracleSignature[](0)
            );
        }
    }
}

interface ILensPool {
    struct PoolLpInfo {
        address vault;
        int256 amountB0;
        int256 liquidity;
        int256 cumulativePnlPerLiquidity;
    }
    struct PoolTdInfo {
        address vault;
        int256 amountB0;
    }

    function pToken() external view returns (address);

    function symbolManager() external view returns (address);

    function tdInfos(uint256 pTokenId)
        external
        view
        returns (PoolTdInfo memory);

    function liquidity() external view returns (int256);

    function lpsPnl() external view returns (int256);
}

interface ILensVault {
    function comptroller() external view returns (address);

    function getVaultLiquidity() external view returns (uint256);

    function getMarketsIn() external view returns (address[] memory);
}

interface ILensSymbolManager {
    function implementation() external view returns (address);

    function initialMarginRequired() external view returns (int256);

    function getSymbolsLength() external view returns (uint256);

    function indexedSymbols(uint256 index) external view returns (address);

    function getActiveSymbols(uint256 pTokenId)
        external
        view
        returns (address[] memory);

    function symbols(bytes32 symbolId) external view returns (address);
}

interface ILensSymbol {
    function nameId() external view returns (bytes32);

    function symbol() external view returns (string memory);

    function implementation() external view returns (address);

    function manager() external view returns (address);

    function oracleManager() external view returns (address);

    function symbolId() external view returns (bytes32);

    function feeRatio() external view returns (int256);

    function alpha() external view returns (int256);

    function fundingPeriod() external view returns (int256);

    function minTradeVolume() external view returns (int256);

    function minInitialMarginRatio() external view returns (int256);

    function initialMarginRatio() external view returns (int256);

    function maintenanceMarginRatio() external view returns (int256);

    function pricePercentThreshold() external view returns (int256);

    function timeThreshold() external view returns (uint256);

    function isCloseOnly() external view returns (bool);

    function priceId() external view returns (bytes32);

    function volatilityId() external view returns (bytes32);

    function feeRatioITM() external view returns (int256);

    function feeRatioOTM() external view returns (int256);

    function strikePrice() external view returns (int256);

    function isCall() external view returns (bool);

    function netVolume() external view returns (int256);

    function netCost() external view returns (int256);

    function indexPrice() external view returns (int256);

    function fundingTimestamp() external view returns (uint256);

    function cumulativeFundingPerVolume() external view returns (int256);

    function tradersPnl() external view returns (int256);

    function initialMarginRequired() external view returns (int256);

    function nPositionHolders() external view returns (uint256);

    struct Position {
        int256 volume;
        int256 cost;
        int256 cumulativeFundingPerVolume;
    }

    function positions(uint256 pTokenId)
        external
        view
        returns (Position memory);

    function power() external view returns (uint256);
}

interface ILensDToken {
    function getTokenIdOf(address account) external view returns (uint256);
}

interface ILensOracleManager {
    function value(bytes32 symbolId) external view returns (uint256);
}
