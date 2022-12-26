// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "../utils/INameVersion.sol";
import "../utils/IAdmin.sol";

interface IFund is INameVersion, IAdmin {
    function implementation() external view returns (address);

    function setImplementation(address newImplementation) external;

    function invest(address account, uint256 amount, int256 priceLimit) external;

    function requestRedeem() external;

    function claimRedeem(address account, int256 priceLimit) external;

    function instantRedeem(address account, int256 priceLimit) external;

    function rebalance(
        bool isAdd,
        uint256 amount,
        int256 priceLimit
    ) external;

    function calculateTotalValue(bool isDeposit)
        external
        view
        returns (
            int256,
            int256,
            int256,
            int256
        );
}
