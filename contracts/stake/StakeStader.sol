// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IStaker.sol";
import "./IStaderSource.sol";
import "../library/SafeMath.sol";
import "../utils/NameVersion.sol";
import "../token/IERC20.sol";
import "../swapper/ISwapper.sol";
import "../library/SafeERC20.sol";

contract StakeStader is IStaker, NameVersion {
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    IStaderSource public immutable source;
    IERC20 public stakerBnb;
    ISwapper public swapper;
    IERC20 public tokenB0;

    address public fund;

    mapping(address => uint256[]) public userWithdrawalRequestId;

    //    struct WithdrawalRequest {
    //        uint256 uuid;
    //        uint256 amountInBnbX;
    //        uint256 startTime;
    //    }

    constructor(
        address source_,
        address stakerBnb_,
        address swapper_,
        address tokenB0_,
        address _fund
    ) NameVersion("StakeStader", "1.0.0") {
        source = IStaderSource(source_);
        stakerBnb = IERC20(stakerBnb_);
        stakerBnb.approve(source_, type(uint256).max);
        swapper = ISwapper(swapper_);
        tokenB0 = IERC20(tokenB0_);

        _approveSwapper(address(stakerBnb));
        fund = _fund;
    }

    modifier onlyFund() {
        require(msg.sender == fund, "only fund");
        _;
    }

    function deposit() external payable {
        source.deposit{value: address(this).balance}();
    }

    function convertToBnb(uint256 amountInStakerBnb)
        external
        view
        returns (uint256 bnbAmount)
    {
        bnbAmount = source.convertBnbXToBnb(amountInStakerBnb);
    }

    function convertToStakerBnb(uint256 amountInBnb)
        external
        view
        returns (uint256 stakerBnbAmount)
    {
        stakerBnbAmount = source.convertBnbToBnbX(amountInBnb);
    }

    function requestWithdraw(address user, uint256 amount) external onlyFund {
        source.requestWithdraw(amount);
        IStaderSource.WithdrawalRequest[] memory withdrawlRequest = source
            .getUserWithdrawalRequests(address(this));
        userWithdrawalRequestId[user].push(withdrawlRequest.length - 1);
    }

    function claimWithdraw(address user, uint256 id) external onlyFund {
        uint256[] storage userIds = userWithdrawalRequestId[user];
        uint256 i;
        bool isValid;
        for (i = 0; i < userIds.length; i++) {
            if (userIds[i] == id) {
                isValid = true;
                break;
            }
        }
        require(isValid, "claimWithdraw: invalid id");
        userIds[i] = userIds[userIds.length - 1];
        userIds.pop();
        source.claimWithdraw(id);
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success, "StakeStader.claimWithdraw: fail");
    }

    function swapStakerBnbToB0(uint256 amountInStakerBnb)
        external
        onlyFund
        returns (uint256)
    {
        (uint256 resultB0, ) = swapper.swapExactBXForB0(
            address(stakerBnb),
            amountInStakerBnb
        );
        tokenB0.transfer(msg.sender, resultB0);
        return resultB0;
    }

    function _approveSwapper(address underlying) internal {
        uint256 allowance = IERC20(underlying).allowance(
            address(this),
            address(swapper)
        );
        if (allowance != type(uint256).max) {
            if (allowance != 0) {
                IERC20(underlying).safeApprove(address(swapper), 0);
            }
            IERC20(underlying).safeApprove(address(swapper), type(uint256).max);
        }
    }

    receive() external payable {}
}
