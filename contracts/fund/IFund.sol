// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "../utils/INameVersion.sol";
import "../utils/IAdmin.sol";

interface IFund is INameVersion, IAdmin {
    function implementation() external view returns (address);

    function setImplementation(address newImplementation) external;
}
