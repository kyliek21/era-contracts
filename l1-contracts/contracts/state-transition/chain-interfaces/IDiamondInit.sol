// SPDX-License-Identifier: MIT
// We use a floating point pragma here so it can be used within other projects that interact with the ZKsync ecosystem without using our exact pragma version.
pragma solidity ^0.8.21;

import {IVerifier, VerifierParams} from "./IVerifier.sol";
import {FeeParams} from "../chain-deps/ZKChainStorage.sol";

/// @param chainId the id of the chain
/// @param bridgehub the address of the bridgehub contract
/// @param chainTypeManager contract's address
/// @param protocolVersion initial protocol version
/// @param validatorTimelock address of the validator timelock that delays execution
/// @param admin address who can manage the contract
/// @param baseTokenAssetId asset id of the base token of the chain
/// @param storedBatchZero hash of the initial genesis batch
/// @param dualVerifier address of Wrapper Verifier contract
/// @param plonkVerifier address of PLONK Verifier contract
/// @param fflonkVerifier address of FFLONK Verifier contract
/// @param fflonkProofLength length of the FFLONK proof type
/// @param verifierParams Verifier config parameters that describes the circuit to be verified
/// @param l2BootloaderBytecodeHash The hash of bootloader L2 bytecode
/// @param l2DefaultAccountBytecodeHash The hash of default account L2 bytecode
/// @param priorityTxMaxGasLimit maximum number of the L2 gas that a user can request for L1 -> L2 transactions
/// @param feeParams Fee parameters to be used for L1->L2 transactions
/// @param blobVersionedHashRetriever Address of contract used to pull the blob versioned hash for a transaction.
// solhint-disable-next-line gas-struct-packing
struct InitializeData {
    uint256 chainId;
    address bridgehub;
    address chainTypeManager;
    uint256 protocolVersion;
    address admin;
    address validatorTimelock;
    bytes32 baseTokenAssetId;
    bytes32 storedBatchZero;
    IVerifier dualVerifier;
    address plonkVerifier;
    address fflonkVerifier;
    uint256 fflonkProofLength;
    VerifierParams verifierParams;
    bytes32 l2BootloaderBytecodeHash;
    bytes32 l2DefaultAccountBytecodeHash;
    uint256 priorityTxMaxGasLimit;
    FeeParams feeParams;
    address blobVersionedHashRetriever;
}

/// @param dualVerifier address of Wrapper Verifier contract
/// @param plonkVerifier address of PLONK Verifier contract
/// @param fflonkVerifier address of FFLONK Verifier contract
/// @param fflonkProofLength length of the FFLONK proof type
/// @param verifierParams Verifier config parameters that describes the circuit to be verified
/// @param l2BootloaderBytecodeHash The hash of bootloader L2 bytecode
/// @param l2DefaultAccountBytecodeHash The hash of default account L2 bytecode
/// @param priorityTxMaxGasLimit maximum number of the L2 gas that a user can request for L1 -> L2 transactions
/// @param feeParams Fee parameters to be used for L1->L2 transactions
/// @param blobVersionedHashRetriever Address of contract used to pull the blob versioned hash for a transaction.
struct InitializeDataNewChain {
    IVerifier dualVerifier;
    address plonkVerifier;
    address fflonkVerifier;
    uint256 fflonkProofLength;
    VerifierParams verifierParams;
    bytes32 l2BootloaderBytecodeHash;
    bytes32 l2DefaultAccountBytecodeHash;
    uint256 priorityTxMaxGasLimit;
    FeeParams feeParams;
    address blobVersionedHashRetriever;
}

interface IDiamondInit {
    function initialize(InitializeData calldata _initData) external returns (bytes32);
}
