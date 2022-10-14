// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IOracle.sol";
import "../token/IERC20.sol";
import "../utils/NameVersion.sol";

contract OracleWoo is IOracle, NameVersion {
    string public symbol;
    bytes32 public immutable symbolId;

    IWooracleV1 public immutable feed;
    uint256 public immutable baseDecimals;
    uint256 public immutable quoteDecimals;

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

    constructor(string memory symbol_, address feed_)
        NameVersion("OracleWoo", "3.0.3")
    {
        symbol = symbol_;
        symbolId = keccak256(abi.encodePacked(symbol_));
        feed = IWooracleV1(feed_);
        baseDecimals = IERC20(IWooracleV1(feed_)._BASE_TOKEN_()).decimals();
        quoteDecimals = IERC20(IWooracleV1(feed_)._QUOTE_TOKEN_()).decimals();
    }

    function timestamp() external pure returns (uint256) {
        revert("OracleWoo.timestamp: no timestamp");
    }

    function value() public view returns (uint256 val) {
        val = feed._I_();
        if (baseDecimals != quoteDecimals) {
            val = (val * (10**baseDecimals)) / (10**quoteDecimals);
        }
    }

    function getValue() external view returns (uint256 val) {
        require((val = value()) != 0, "OracleWoo.getValue: 0");
    }

    function getValueWithHistory()
        external
        returns (
            uint256 curValue,
            uint256 preTimestamp,
            uint256 preValue
        )
    {
        History memory hist = history;
        if (hist.timestamp2 == block.timestamp) {
            // history already updated in current block
            return (hist.value2, hist.timestamp1, hist.value1);
        }

        curValue = value();
        require(curValue != 0 && curValue <= type(uint96).max);

        if (curValue == hist.value2) {
            // use (timestamp1, value1) as pre value
            preTimestamp = hist.timestamp1;
            preValue = hist.value1;
            // update history.timestamp2
            history.timestamp2 = uint32(block.timestamp);
        } else {
            // use (timestamp2, value2) as pre value
            preTimestamp = hist.timestamp2;
            preValue = hist.value2;
            // update history
            history = History({
                timestamp1: hist.timestamp2,
                value1: hist.value2,
                timestamp2: uint32(block.timestamp),
                value2: uint96(curValue)
            });
        }
    }
}

interface IWooracleV1 {
    function _BASE_TOKEN_() external view returns (address);

    function _QUOTE_TOKEN_() external view returns (address);

    function _I_() external view returns (uint256);
}
