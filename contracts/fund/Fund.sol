// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IFund.sol";
import "./FundStorage.sol";

contract Fund is FundStorage {
    function setImplementation(address newImplementation) external _onlyAdmin_ {
        require(
            IFund(newImplementation).nameId() ==
                keccak256(abi.encodePacked("FundImplementation")),
            "Fund.setImplementation: not pool implementation"
        );
        implementation = newImplementation;
        emit NewImplementation(newImplementation);
    }

    fallback() external payable {
        _delegate();
    }

    receive() external payable {}

    function _delegate() internal {
        address imp = implementation;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), imp, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
