// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../utils/INameVersion.sol';
import "./RouterStorage.sol";
import '../pool/IPool.sol';

interface IRouter {

    function requestTrade(
        address pool,
        string memory symbolName,
        int256 tradeVolume,
        int256 priceLimit,
        RouterStorage.ExtraCall calldata beforeTrade,
        RouterStorage.ExtraCall calldata afterTrade
    ) external payable;

}
