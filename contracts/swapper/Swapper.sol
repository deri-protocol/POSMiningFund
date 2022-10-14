// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./ISwapper.sol";
import "../token/IERC20.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "../oracle/IOracleManager.sol";
import "../utils/Admin.sol";
import "../utils/NameVersion.sol";
import "../library/SafeERC20.sol";

contract Swapper is ISwapper, Admin, NameVersion {
    using SafeERC20 for IERC20;

    uint256 constant ONE = 1e18;

    IUniswapV2Factory public immutable factory;

    IUniswapV2Router02 public immutable router;

    IOracleManager public immutable oracleManager;

    address public immutable tokenB0;

    address public immutable tokenWETH;

    uint8 public immutable decimalsB0;

    uint256 public immutable maxSlippageRatio;

    // fromToken => toToken => path
    mapping(address => mapping(address => address[])) public paths;

    // tokenBX => oracle symbolId
    mapping(address => bytes32) public oracleSymbolIds;

    constructor(
        address factory_,
        address router_,
        address oracleManager_,
        address tokenB0_,
        address tokenWETH_,
        uint256 maxSlippageRatio_,
        string memory nativePriceSymbol // BNBUSD for BSC, ETHUSD for Ethereum
    ) NameVersion("Swapper", "3.0.1") {
        factory = IUniswapV2Factory(factory_);
        router = IUniswapV2Router02(router_);
        oracleManager = IOracleManager(oracleManager_);
        tokenB0 = tokenB0_;
        tokenWETH = tokenWETH_;
        decimalsB0 = IERC20(tokenB0_).decimals();
        maxSlippageRatio = maxSlippageRatio_;

        require(
            factory.getPair(tokenB0_, tokenWETH_) != address(0),
            "Swapper.constructor: no native path"
        );

        address[] memory path = new address[](2);

        (path[0], path[1]) = (tokenB0_, tokenWETH_);
        paths[tokenB0_][tokenWETH_] = path;

        (path[0], path[1]) = (tokenWETH_, tokenB0_);
        paths[tokenWETH_][tokenB0_] = path;

        bytes32 symbolId = keccak256(abi.encodePacked(nativePriceSymbol));
        require(
            oracleManager.value(symbolId) != 0,
            "Swapper.constructor: no native price"
        );
        oracleSymbolIds[tokenWETH_] = symbolId;

        IERC20(tokenB0_).safeApprove(router_, type(uint256).max);
    }

    function setPath(string memory priceSymbol, address[] calldata path)
        external
        _onlyAdmin_
    {
        uint256 length = path.length;

        require(length >= 2, "Swapper.setPath: invalid path length");
        require(
            path[0] == tokenB0,
            "Swapper.setPath: path should begin with tokenB0"
        );
        for (uint256 i = 1; i < length; i++) {
            require(
                factory.getPair(path[i - 1], path[i]) != address(0),
                "Swapper.setPath: path broken"
            );
        }

        address[] memory revertedPath = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            revertedPath[length - i - 1] = path[i];
        }

        address tokenBX = path[length - 1];
        paths[tokenB0][tokenBX] = path;
        paths[tokenBX][tokenB0] = revertedPath;

        bytes32 symbolId = keccak256(abi.encodePacked(priceSymbol));
        require(
            oracleManager.value(symbolId) != 0,
            "Swapper.setPath: no price"
        );
        oracleSymbolIds[tokenBX] = symbolId;

        IERC20(tokenBX).safeApprove(address(router), type(uint256).max);
    }

    function getPath(address tokenBX) external view returns (address[] memory) {
        return paths[tokenB0][tokenBX];
    }

    function isSupportedToken(address tokenBX) external view returns (bool) {
        address[] storage path1 = paths[tokenB0][tokenBX];
        address[] storage path2 = paths[tokenBX][tokenB0];
        return path1.length >= 2 && path2.length >= 2;
    }

    function getTokenPrice(address tokenBX) public view returns (uint256) {
        uint256 decimalsBX = IERC20(tokenBX).decimals();
        // oracleManager prices are in 18 decimals with token B0 and BX in their natural units
        // convert it to 18 decimals with token B0 and BX in their own decimals
        return
            (oracleManager.value(oracleSymbolIds[tokenBX]) * 10**decimalsB0) /
            10**decimalsBX;
    }

    receive() external payable {}

    //================================================================================

    function swapExactB0ForBX(address tokenBX, uint256 amountB0)
        external
        returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenBX);
        uint256 minAmountBX = (amountB0 * (ONE - maxSlippageRatio)) / price;
        (resultB0, resultBX) = _swapExactTokensForTokens(
            tokenB0,
            tokenBX,
            amountB0,
            minAmountBX
        );
    }

    function swapExactBXForB0(address tokenBX, uint256 amountBX)
        external
        returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenBX);
        uint256 minAmountB0 = (((amountBX * price) / ONE) *
            (ONE - maxSlippageRatio)) / ONE;
        (resultBX, resultB0) = _swapExactTokensForTokens(
            tokenBX,
            tokenB0,
            amountBX,
            minAmountB0
        );
    }

    function swapB0ForExactBX(
        address tokenBX,
        uint256 maxAmountB0,
        uint256 amountBX
    ) external returns (uint256 resultB0, uint256 resultBX) {
        uint256 price = getTokenPrice(tokenBX);
        uint256 maxB0 = (((amountBX * price) / ONE) *
            (ONE + maxSlippageRatio)) / ONE;
        if (maxAmountB0 >= maxB0) {
            (resultB0, resultBX) = _swapTokensForExactTokens(
                tokenB0,
                tokenBX,
                maxB0,
                amountBX
            );
        } else {
            uint256 minAmountBX = (maxAmountB0 * (ONE - maxSlippageRatio)) /
                price;
            (resultB0, resultBX) = _swapExactTokensForTokens(
                tokenB0,
                tokenBX,
                maxAmountB0,
                minAmountBX
            );
        }
    }

    function swapBXForExactB0(
        address tokenBX,
        uint256 amountB0,
        uint256 maxAmountBX
    ) external returns (uint256 resultB0, uint256 resultBX) {
        uint256 price = getTokenPrice(tokenBX);
        uint256 maxBX = (amountB0 * (ONE + maxSlippageRatio)) / price;
        if (maxAmountBX >= maxBX) {
            (resultBX, resultB0) = _swapTokensForExactTokens(
                tokenBX,
                tokenB0,
                maxBX,
                amountB0
            );
        } else {
            uint256 minAmountB0 = (((maxAmountBX * price) / ONE) *
                (ONE - maxSlippageRatio)) / ONE;
            (resultBX, resultB0) = _swapExactTokensForTokens(
                tokenBX,
                tokenB0,
                maxAmountBX,
                minAmountB0
            );
        }
    }

    function swapExactB0ForETH(uint256 amountB0)
        external
        returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenWETH);
        uint256 minAmountBX = (amountB0 * (ONE - maxSlippageRatio)) / price;
        (resultB0, resultBX) = _swapExactTokensForTokens(
            tokenB0,
            tokenWETH,
            amountB0,
            minAmountBX
        );
    }

    function swapExactETHForB0()
        external
        payable
        returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenWETH);
        uint256 amountBX = msg.value;
        uint256 minAmountB0 = (((amountBX * price) / ONE) *
            (ONE - maxSlippageRatio)) / ONE;
        (resultBX, resultB0) = _swapExactTokensForTokens(
            tokenWETH,
            tokenB0,
            amountBX,
            minAmountB0
        );
    }

    function swapB0ForExactETH(uint256 maxAmountB0, uint256 amountBX)
        external
        returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenWETH);
        uint256 maxB0 = (((amountBX * price) / ONE) *
            (ONE + maxSlippageRatio)) / ONE;
        if (maxAmountB0 >= maxB0) {
            (resultB0, resultBX) = _swapTokensForExactTokens(
                tokenB0,
                tokenWETH,
                maxB0,
                amountBX
            );
        } else {
            uint256 minAmountBX = (maxAmountB0 * (ONE - maxSlippageRatio)) /
                price;
            (resultB0, resultBX) = _swapExactTokensForTokens(
                tokenB0,
                tokenWETH,
                maxAmountB0,
                minAmountBX
            );
        }
    }

    function swapETHForExactB0(uint256 amountB0)
        external
        payable
        returns (uint256 resultB0, uint256 resultBX)
    {
        uint256 price = getTokenPrice(tokenWETH);
        uint256 maxAmountBX = msg.value;
        uint256 maxBX = (amountB0 * (ONE + maxSlippageRatio)) / price;
        if (maxAmountBX >= maxBX) {
            (resultBX, resultB0) = _swapTokensForExactTokens(
                tokenWETH,
                tokenB0,
                maxBX,
                amountB0
            );
        } else {
            uint256 minAmountB0 = (((maxAmountBX * price) / ONE) *
                (ONE - maxSlippageRatio)) / ONE;
            (resultBX, resultB0) = _swapExactTokensForTokens(
                tokenWETH,
                tokenB0,
                maxAmountBX,
                minAmountB0
            );
        }
    }

    //================================================================================

    function _swapExactTokensForTokens(
        address token1,
        address token2,
        uint256 amount1,
        uint256 amount2
    ) internal returns (uint256 result1, uint256 result2) {
        if (amount1 == 0) return (0, 0);

        uint256[] memory res;
        if (token1 == tokenWETH) {
            res = router.swapExactETHForTokens{value: amount1}(
                amount2,
                paths[token1][token2],
                msg.sender,
                block.timestamp + 3600
            );
        } else if (token2 == tokenWETH) {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
            res = router.swapExactTokensForETH(
                amount1,
                amount2,
                paths[token1][token2],
                msg.sender,
                block.timestamp + 3600
            );
        } else {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
            res = router.swapExactTokensForTokens(
                amount1,
                amount2,
                paths[token1][token2],
                msg.sender,
                block.timestamp + 3600
            );
        }

        result1 = res[0];
        result2 = res[res.length - 1];
    }

    function _swapTokensForExactTokens(
        address token1,
        address token2,
        uint256 amount1,
        uint256 amount2
    ) internal returns (uint256 result1, uint256 result2) {
        if (amount1 == 0 || amount2 == 0) {
            if (amount1 > 0 && token1 == tokenWETH) {
                _sendETH(msg.sender, amount1);
            }
            return (0, 0);
        }

        uint256[] memory res;
        if (token1 == tokenWETH) {
            res = router.swapETHForExactTokens{value: amount1}(
                amount2,
                paths[token1][token2],
                msg.sender,
                block.timestamp + 3600
            );
        } else if (token2 == tokenWETH) {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
            res = router.swapTokensForExactETH(
                amount2,
                amount1,
                paths[token1][token2],
                msg.sender,
                block.timestamp + 3600
            );
        } else {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
            res = router.swapTokensForExactTokens(
                amount2,
                amount1,
                paths[token1][token2],
                msg.sender,
                block.timestamp + 3600
            );
        }

        result1 = res[0];
        result2 = res[res.length - 1];

        if (token1 == tokenWETH) {
            _sendETH(msg.sender, address(this).balance);
        } else {
            IERC20(token1).safeTransfer(
                msg.sender,
                IERC20(token1).balanceOf(address(this))
            );
        }
    }

    function _sendETH(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "Swapper._sendETH: fail");
    }
}
