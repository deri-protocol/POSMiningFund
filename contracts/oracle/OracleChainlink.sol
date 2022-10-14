// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IOracle.sol";
import "../library/SafeMath.sol";
import "../utils/NameVersion.sol";

contract OracleChainlink is IOracle, NameVersion {
    using SafeMath for int256;

    string public symbol;
    bytes32 public immutable symbolId;

    IChainlinkFeed public immutable feed;
    uint256 public immutable feedDecimals;

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
        NameVersion("OracleChainlink", "3.0.3")
    {
        symbol = symbol_;
        symbolId = keccak256(abi.encodePacked(symbol_));
        feed = IChainlinkFeed(feed_);
        feedDecimals = IChainlinkFeed(feed_).decimals();
    }

    function timestamp() external view returns (uint256) {
        (uint256 updatedAt, ) = _getLatestRoundData();
        return updatedAt;
    }

    function value() public view returns (uint256 val) {
        (, int256 answer) = _getLatestRoundData();
        val = answer.itou();
        if (feedDecimals != 18) {
            val *= 10**(18 - feedDecimals);
        }
    }

    function getValue() external view returns (uint256 val) {
        val = value();
    }

    function _getLatestRoundData() internal view returns (uint256, int256) {
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        require(
            answeredInRound >= roundId,
            "OracleChainlink._getLatestRoundData: stale"
        );
        require(
            updatedAt != 0,
            "OracleChainlink._getLatestRoundData: incomplete round"
        );
        require(answer > 0, "OracleChainlink._getLatestRoundData: answer <= 0");
        return (updatedAt, answer);
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
        require(curValue <= type(uint96).max);

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

interface IChainlinkFeed {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
