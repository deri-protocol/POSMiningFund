// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;
import "../token/IERC20.sol";
import "../utils/INameVersion.sol";
import "../utils/IAdmin.sol";

interface IStaker is INameVersion, IAdmin {
    function deposit() external payable;

    function convertToBnb(uint256 amountInStakerBnb)
        external
        view
        returns (uint256);

    function convertToStakerBnb(uint256 amountInBnb)
        external
        view
        returns (uint256);

    function requestWithdraw(address, uint256) external;

    function claimWithdraw(address) external;

    function stakerBnb() external returns (IERC20);

    function swapStakerBnbToB0(uint256 amountInStakerBnb)
        external
        returns (uint256);
}
