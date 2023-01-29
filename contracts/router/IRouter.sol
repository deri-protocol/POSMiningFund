// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../utils/INameVersion.sol';
import '../pool/IPool.sol';

interface IRouter {

    function requestTrade(
        address account,
        address pool,
        string memory symbolName,
        int256 tradeVolume,
        int256 priceLimit,
        address caller,
        bytes[2] calldata data,
        uint256[2] calldata value
    ) external payable;

}
