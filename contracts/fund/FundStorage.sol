// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "../utils/Admin.sol";
import "../token/ERC20.sol";

abstract contract FundStorage is ERC20, Admin {
    // admin will be truned in to Timelock after deployment

    event NewImplementation(address newImplementation);

    bool internal _mutex;

    modifier _reentryLock_() {
        require(!_mutex, "Pool: reentry");
        _mutex = true;
        _;
        _mutex = false;
    }

    address public implementation;

    uint256 public redeemId;

    uint256 public pendingBnb;

    uint256 public pendingShare;

    mapping(address => RedeemRequest[]) public userRedeemRequests;

    struct RedeemRequest {
        uint256 id;
        uint256 amountInBnb;
        uint256 amountInStakerBnb;
        uint256 share;
        uint256 startTime;
    }

    constructor() ERC20("Fund LP", "FLP") {}
}
