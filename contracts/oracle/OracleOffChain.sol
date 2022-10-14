// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IOracleOffChain.sol";
import "../utils/NameVersion.sol";

contract OracleOffChain is IOracleOffChain, NameVersion {
    string public symbol;
    bytes32 public immutable symbolId;
    address public immutable signer;
    uint256 public immutable delayAllowance;

    // We use one slot storage to store 2 historical values and their timestamps
    // each timestamp takes 32 bits, which can hold timestamp range from 1 to 4294967295 (year 2106)
    // each value takes 96 bits with accuracy of 1e-18, which can hold value range from 1e-18 to 79,228,162,514.26
    //    time1           value1           time2          value2
    // |----------|--------------------|----------|--------------------|
    //     32               96              32              96
    struct History {
        uint32 timestamp1;
        uint96 value1;
        uint32 timestamp2;
        uint96 value2;
    }
    History public history;
    uint256 public lastSignatureTimestamp;

    constructor(
        string memory symbol_,
        address signer_,
        uint256 delayAllowance_,
        uint256 value_
    ) NameVersion("OracleOffChain", "3.0.3") {
        symbol = symbol_;
        symbolId = keccak256(abi.encodePacked(symbol_));
        signer = signer_;
        delayAllowance = delayAllowance_;
        history.value2 = uint96(value_);
    }

    function timestamp() external view returns (uint256) {
        return history.timestamp2;
    }

    function value() external view returns (uint256) {
        return history.value2;
    }

    function getValue() external view returns (uint256) {
        History memory hist = history;
        if (block.timestamp != hist.timestamp2) {
            revert(
                string(
                    abi.encodePacked(
                        bytes("OracleOffChain.getValue: "),
                        bytes(symbol),
                        bytes(" expired")
                    )
                )
            );
        }
        return hist.value2;
    }

    function updateValue(
        uint256 timestamp_,
        uint256 value_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) external returns (bool) {
        require(value_ != 0);
        History memory hist = history;
        // this is the first update in this block and value_ is newer and valid (not too old)
        if (
            block.timestamp > hist.timestamp2 &&
            timestamp_ > lastSignatureTimestamp &&
            block.timestamp < timestamp_ + delayAllowance
        ) {
            bytes32 message = keccak256(
                abi.encodePacked(symbolId, timestamp_, value_)
            );
            bytes32 hash = keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", message)
            );
            address signatory = ecrecover(hash, v_, r_, s_);
            require(
                signatory == signer,
                "OracleOffChain.updateValue: invalid signature"
            );

            if (value_ == hist.value2) {
                history.timestamp2 = uint32(block.timestamp);
            } else {
                history = History({
                    timestamp1: hist.timestamp2,
                    value1: hist.value2,
                    timestamp2: uint32(block.timestamp),
                    value2: uint96(value_)
                });
            }
            lastSignatureTimestamp = timestamp_;
            emit NewValue(timestamp_, value_);
            return true;
        }
        return false;
    }

    function getValueWithHistory()
        external
        view
        returns (
            uint256 curValue,
            uint256 preTimestamp,
            uint256 preValue
        )
    {
        History memory hist = history;
        if (block.timestamp != hist.timestamp2) {
            revert(
                string(
                    abi.encodePacked(
                        bytes("OracleOffChain.getValueWithHistory: "),
                        bytes(symbol),
                        bytes(" expired")
                    )
                )
            );
        }
        return (hist.value2, hist.timestamp1, hist.value1);
    }
}
