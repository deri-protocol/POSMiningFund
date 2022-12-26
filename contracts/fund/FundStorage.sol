// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../utils/Admin.sol";
import "../token/ERC20.sol";

abstract contract FundStorage is ERC20, Admin, AccessControl {
    // admin will be truned in to Timelock after deployment

    event NewImplementation(address newImplementation);

    bool internal _mutex;

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER");

    modifier _reentryLock_() {
        require(!_mutex, "Pool: reentry");
        _mutex = true;
        _;
        _mutex = false;
    }

    address public implementation;

    uint256 public pendingBnb;

    uint256 public pendingShare;

    mapping(address => RedeemRequest) public userRedeemRequests;

    struct RedeemRequest {
        uint256 amountInBnb;
        uint256 amountInStakerBnb;
        uint256 share;
        uint256 startTime;
    }

    mapping(address => bool) public isRouter;

    constructor() ERC20("Fund LP", "FLP") {
        _setupRole(KEEPER_ROLE, msg.sender);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(KEEPER_ROLE, DEFAULT_ADMIN_ROLE);
    }
}
