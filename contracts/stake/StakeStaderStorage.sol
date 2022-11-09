// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "../utils/Admin.sol";

abstract contract StakeStaderStorage is Admin {
    event NewImplementation(address newImplementation);

    address public implementation;

    uint256 public withdrawlRequestNum;

    mapping(address => uint256) public withdrawalRequestId;

    mapping(uint256 => address) public withdrawlRequestUser;
}
