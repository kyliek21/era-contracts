// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EvmConstants.sol";

import {ACCOUNT_CODE_STORAGE_SYSTEM_CONTRACT} from "./Constants.sol";

// We consider all the contracts (including system ones) as warm.
uint160 constant PRECOMPILES_END = 0xffff;

// Denotes that passGas has been consumed
uint256 constant INF_PASS_GAS = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

uint256 constant IS_ACCOUNT_EVM_PREFIX = 1 << 255;
uint256 constant IS_ACCOUNT_WARM_PREFIX = 1 << 254;
uint256 constant IS_SLOT_WARM_PREFIX = 1 << 253;

contract EvmGasManager {
    struct SlotInfo {
        bool warm;
        uint256 originalValue;
    }

    // We dont care about the size, since none of it will be stored/pub;ushed anywya
    struct EVMStackFrameInfo {
        bool isStatic;
        uint256 passGas;
    }

    // The following storage variables are not used anywhere explicitly and are just used to obtain the storage pointers
    // to use the transient storage with.
    mapping(address => bool) private warmAccounts;
    mapping(address => mapping(uint256 => SlotInfo)) private warmSlots;
    EVMStackFrameInfo[] private evmStackFrames;

    modifier onlySystemEvm() {
        // cache use is safe since we do not support SELFDESTRUCT
        uint256 slot = IS_ACCOUNT_EVM_PREFIX | uint256(uint160(msg.sender));
        bool isEVM;
        assembly {
            isEVM := tload(slot)
        }

        if (!isEVM) {
            isEVM = ACCOUNT_CODE_STORAGE_SYSTEM_CONTRACT.isAccountEVM(msg.sender);
            if (isEVM) {
                assembly {
                    tstore(slot, isEVM)
                }
            }
        }

        require(isEVM, "only system evm");
        _;
    }

    /*
        returns true if the account was already warm
    */
    function warmAccount(address account) external payable onlySystemEvm returns (bool wasWarm) {
        if (uint160(account) < PRECOMPILES_END) return true;

        uint256 slot = IS_ACCOUNT_WARM_PREFIX | uint256(uint160(account));

        assembly {
            wasWarm := tload(slot)
        }

        if (!wasWarm) {
            assembly {
                tstore(slot, 1)
            }
        }
    }

    function isSlotWarm(uint256 _slot) external view returns (bool isWarm) {
        uint256 slot = IS_SLOT_WARM_PREFIX | uint256(uint160(msg.sender));
        assembly {
            mstore(0, slot)
            mstore(0x20, _slot)
            slot := keccak256(0, 64)
        }

        assembly {
            isWarm := tload(slot)
        }
    }

    function warmSlot(uint256 _slot, uint256 _currentValue) external payable onlySystemEvm returns (bool isWarm, uint256 originalValue) {
        uint256 slot = IS_SLOT_WARM_PREFIX | uint256(uint160(msg.sender));
        assembly {
            mstore(0, slot)
            mstore(0x20, _slot)
            slot := keccak256(0, 64)
        }

        assembly {
            isWarm := tload(slot)
        }

        if (isWarm) {
            assembly {
                originalValue := tload(add(slot, 1))
            }
        } else {
            originalValue = _currentValue;

            assembly {
                tstore(slot, 1)
                tstore(add(slot, 1), originalValue)
            }
        }
    }

    /*

    The flow is the following:

    When conducting call:
        1. caller calls to an EVM contract pushEVMFrame with the corresponding gas
        2. callee calls consumeEvmFrame to get the gas & make sure that subsequent callee wont be able to read it.
        3. callee sets the return gas
        4. callee calls popEVMFrame to return the gas to the caller & remove the frame

    */

    function pushEVMFrame(uint256 _passGas, bool _isStatic) external {
        EVMStackFrameInfo memory frame = EVMStackFrameInfo({passGas: _passGas, isStatic: _isStatic});

        evmStackFrames.push(frame);
    }

    function consumeEvmFrame() external returns (uint256 passGas, bool isStatic) {
        if (evmStackFrames.length == 0) return (INF_PASS_GAS, false);

        EVMStackFrameInfo storage frameInfo = evmStackFrames[evmStackFrames.length - 1];

        passGas = frameInfo.passGas;
        isStatic = frameInfo.isStatic;

        // Mark as used
        frameInfo.passGas = INF_PASS_GAS;
    }

    function popEVMFrame() external {
        evmStackFrames.pop();
    }
}
