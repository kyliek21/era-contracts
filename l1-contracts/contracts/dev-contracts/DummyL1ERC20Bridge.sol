// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {L1ERC20Bridge} from "../bridge/L1ERC20Bridge.sol";
import {IL1SharedBridge} from "../bridge/interfaces/IL1SharedBridge.sol";
import {IL1NativeTokenVault} from "../bridge/interfaces/IL1NativeTokenVault.sol";

contract DummyL1ERC20Bridge is L1ERC20Bridge {
    constructor(
        IL1SharedBridge _l1SharedBridge,
        IL1NativeTokenVault _l1NativeTokenVault
    ) L1ERC20Bridge(_l1SharedBridge, _l1NativeTokenVault) {}

    function setValues(
        address _l2NativeTokenVault,
        address _l2TokenBeacon,
        bytes32 _l2TokenProxyBytecodeHash
    ) external {
        l2NativeTokenVault = _l2NativeTokenVault;
        l2TokenBeacon = _l2TokenBeacon;
        l2TokenProxyBytecodeHash = _l2TokenProxyBytecodeHash;
    }
}
