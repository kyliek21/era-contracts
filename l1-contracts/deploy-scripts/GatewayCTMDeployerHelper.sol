// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Diamond} from "contracts/state-transition/libraries/Diamond.sol";

import {ChainTypeManager} from "contracts/state-transition/ChainTypeManager.sol";

import {L2_BRIDGEHUB_ADDR} from "contracts/common/L2ContractAddresses.sol";

import {VerifierParams, IVerifier} from "contracts/state-transition/chain-interfaces/IVerifier.sol";
import {ProxyAdmin} from "@openzeppelin/contracts-v4/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts-v4/proxy/transparent/TransparentUpgradeableProxy.sol";
import {InitializeDataNewChain as DiamondInitializeDataNewChain} from "contracts/state-transition/chain-interfaces/IDiamondInit.sol";
import {ChainTypeManagerInitializeData, ChainCreationParams, IChainTypeManager} from "contracts/state-transition/IChainTypeManager.sol";

import {Utils} from "./Utils.sol";

import {L2ContractHelper} from "contracts/common/libraries/L2ContractHelper.sol";

import {GatewayCTMDeployerConfig, DeployedContracts, ADDRESS_ONE} from "contracts/state-transition/chain-deps/GatewayCTMDeployer.sol";

// solhint-disable gas-custom-errors

struct InnerDeployConfig {
    address deployerAddr;
    bytes32 salt;
}

library GatewayCTMDeployerHelper {
    // bytes public create2Calldata;
    // address public ctmDeployerAddress;

    // DeployedContracts internal deployedContracts;
    // GatewayCTMDeployerConfig internal config;

    // constructor() {
    //     config = _config;

    //     (bytes32 bytecodeHash, bytes memory deployData) = Utils.getDeploymentCalldata(
    //         _create2Salt, 
    //         Utils.readZKFoundryBytecode("GatewayCTMDeployer.sol", "GatewayCTMDeployer"),
    //         abi.encode(_config)
    //     );

    //     // Create2Factory has the same interface as the usual deployer.
    //     create2Calldata = deployData;

    //     ctmDeployerAddress = Utils.getL2AddressViaCreate2Factory(_create2Salt, bytecodeHash, abi.encode(_config));
    // }


    function calculateAddresses(bytes32 _create2Salt, GatewayCTMDeployerConfig memory config) internal returns (
        DeployedContracts memory contracts,
        bytes memory create2Calldata,
        address ctmDeployerAddress
    ) {
        (bytes32 bytecodeHash, bytes memory deployData) = Utils.getDeploymentCalldata(
            _create2Salt, 
            Utils.readZKFoundryBytecode("GatewayCTMDeployer.sol", "GatewayCTMDeployer"),
            abi.encode(config)
        );

        // Create2Factory has the same interface as the usual deployer.
        create2Calldata = deployData;

        ctmDeployerAddress = Utils.getL2AddressViaCreate2Factory(_create2Salt, bytecodeHash, abi.encode(config));

        InnerDeployConfig memory innerConfig = InnerDeployConfig({
            deployerAddr: ctmDeployerAddress,
            salt: config.salt
        });

        // Caching some values
        bytes32 salt = config.salt;
        uint256 eraChainId = config.eraChainId;
        uint256 l1ChainId = config.l1ChainId;

        contracts = _deployFacetsAndUpgrades(
            salt,
            eraChainId,
            l1ChainId,
            config.rollupL2DAValidatorAddress,
            config.governanceAddress,
            contracts,
            innerConfig
        );
        contracts = _deployVerifier(config.testnetVerifier, contracts, innerConfig);

        contracts.stateTransition.validatorTimelock = _deployInternal(
            "ValidatorTimelock",
            "ValidatorTimelock.sol",
            abi.encode(ctmDeployerAddress, 0, eraChainId),
            innerConfig
        );

        contracts = _deployCTM(salt, config, contracts, innerConfig);
    }

    function _deployFacetsAndUpgrades(
        bytes32 _salt,
        uint256 _eraChainId,
        uint256 _l1ChainId,
        address _rollupL2DAValidatorAddress,
        address _governanceAddress,
        DeployedContracts memory _deployedContracts,
        InnerDeployConfig memory innerConfig
    ) internal returns (DeployedContracts memory) {
        _deployedContracts.stateTransition.mailboxFacet = _deployInternal(
            "MailboxFacet",
            "Mailbox.sol",
            abi.encode(_eraChainId, _l1ChainId),
            innerConfig
        );

        _deployedContracts.stateTransition.executorFacet = _deployInternal(
            "ExecutorFacet",
            "Executor.sol",
            abi.encode(_l1ChainId),
            innerConfig
        );

        _deployedContracts.stateTransition.gettersFacet = _deployInternal(
            "GettersFacet",
            "Getters.sol",
            hex"",
            innerConfig
        );

        address rollupDAManager;
        (_deployedContracts, rollupDAManager) = _deployRollupDAManager(
            _salt,
            _rollupL2DAValidatorAddress,
            _governanceAddress,
            _deployedContracts,
            innerConfig
        );
        _deployedContracts.stateTransition.adminFacet = _deployInternal(
            "AdminFacet",
            "Admin.sol",
            abi.encode(_l1ChainId, rollupDAManager),
            innerConfig
        );

        _deployedContracts.stateTransition.diamondInit = _deployInternal(
            "DiamondInit",
            "DiamondInit.sol",
            hex"",
            innerConfig
        );
        _deployedContracts.stateTransition.genesisUpgrade = _deployInternal(
            "L1GenesisUpgrade",
            "L1GenesisUpgrade.sol",
            hex"",
            innerConfig
        );

        return _deployedContracts;
    }

    function _deployVerifier(
        bool _testnetVerifier,
        DeployedContracts memory _deployedContracts,
        InnerDeployConfig memory innerConfig

    ) internal returns (DeployedContracts memory) {
        if (_testnetVerifier) {
            _deployedContracts.stateTransition.verifier = _deployInternal(
                "TestnetVerifier",
                "TestnetVerifier.sol",
                hex"",
                innerConfig
            );
        } else {
            _deployedContracts.stateTransition.verifier = _deployInternal(
                "Verifier",
                "Verifier.sol",
                hex"",
                innerConfig
            );
        }
        return _deployedContracts;
    }

    function _deployRollupDAManager(
        bytes32 _salt,
        address _rollupL2DAValidatorAddress,
        address _governanceAddress,
        DeployedContracts memory _deployedContracts,
        InnerDeployConfig memory innerConfig
    ) internal returns (DeployedContracts memory, address) {
        address daManager = _deployInternal(
            "RollupDAManager",
            "RollupDAManager.sol",
            hex"",
            innerConfig
        );

        address validiumDAValidator = _deployInternal(
            "ValidiumL1DAValidator",
            "ValidiumL1DAValidator.sol",
            hex"",
            innerConfig
        );

        address relayedSLDAValidator = _deployInternal(
            "RelayedSLDAValidator",
            "RelayedSLDAValidator.sol",
            hex"",
            innerConfig
        );

        _deployedContracts.daContracts.rollupDAManager = daManager;
        _deployedContracts.daContracts.relayedSLDAValidator = relayedSLDAValidator;
        _deployedContracts.daContracts.validiumDAValidator = validiumDAValidator;

        return (_deployedContracts, daManager);
    }

    function _deployCTM(
        bytes32 _salt,
        GatewayCTMDeployerConfig memory _config,
        DeployedContracts memory _deployedContracts,
        InnerDeployConfig memory innerConfig
    ) internal returns (DeployedContracts memory) {
        _deployedContracts.stateTransition.chainTypeManagerImplementation = _deployInternal(
            "ChainTypeManager",
            "ChainTypeManager.sol",
            abi.encode(L2_BRIDGEHUB_ADDR),
            innerConfig
        );

        address proxyAdmin = _deployInternal(
            "ProxyAdmin",
            "ProxyAdmin.sol",
            hex"",
            innerConfig
        );
        _deployedContracts.stateTransition.chainTypeManagerProxyAdmin = proxyAdmin;

        Diamond.FacetCut[] memory facetCuts = new Diamond.FacetCut[](4);
        facetCuts[0] = Diamond.FacetCut({
            facet: _deployedContracts.stateTransition.adminFacet,
            action: Diamond.Action.Add,
            isFreezable: false,
            selectors: _config.adminSelectors
        });
        facetCuts[1] = Diamond.FacetCut({
            facet: _deployedContracts.stateTransition.gettersFacet,
            action: Diamond.Action.Add,
            isFreezable: false,
            selectors: _config.gettersSelectors
        });
        facetCuts[2] = Diamond.FacetCut({
            facet: _deployedContracts.stateTransition.mailboxFacet,
            action: Diamond.Action.Add,
            isFreezable: true,
            selectors: _config.mailboxSelectors
        });
        facetCuts[3] = Diamond.FacetCut({
            facet: _deployedContracts.stateTransition.executorFacet,
            action: Diamond.Action.Add,
            isFreezable: true,
            selectors: _config.executorSelectors
        });

        DiamondInitializeDataNewChain memory initializeData = DiamondInitializeDataNewChain({
            verifier: IVerifier(_deployedContracts.stateTransition.verifier),
            verifierParams: _config.verifierParams,
            l2BootloaderBytecodeHash: _config.bootloaderHash,
            l2DefaultAccountBytecodeHash: _config.defaultAccountHash,
            priorityTxMaxGasLimit: _config.priorityTxMaxGasLimit,
            feeParams: _config.feeParams,
            blobVersionedHashRetriever: ADDRESS_ONE
        });

        Diamond.DiamondCutData memory diamondCut = Diamond.DiamondCutData({
            facetCuts: facetCuts,
            initAddress: _deployedContracts.stateTransition.diamondInit,
            initCalldata: abi.encode(initializeData)
        });

        _deployedContracts.diamondCutData = abi.encode(diamondCut);

        ChainCreationParams memory chainCreationParams = ChainCreationParams({
            genesisUpgrade: _deployedContracts.stateTransition.genesisUpgrade,
            genesisBatchHash: _config.genesisRoot,
            genesisIndexRepeatedStorageChanges: uint64(_config.genesisRollupLeafIndex),
            genesisBatchCommitment: _config.genesisBatchCommitment,
            diamondCut: diamondCut,
            forceDeploymentsData: _config.forceDeploymentsData
        });

        ChainTypeManagerInitializeData memory diamondInitData = ChainTypeManagerInitializeData({
            owner: _config.governanceAddress,
            validatorTimelock: _deployedContracts.stateTransition.validatorTimelock,
            chainCreationParams: chainCreationParams,
            protocolVersion: _config.protocolVersion
        });

        _deployedContracts.stateTransition.chainTypeManagerProxy = _deployInternal(
            "TransparentUpgradeableProxy",
            "TransparentUpgradeableProxy.sol",
            abi.encode(
                _deployedContracts.stateTransition.chainTypeManagerImplementation,
                proxyAdmin,
                abi.encodeCall(ChainTypeManager.initialize, (diamondInitData))
            ),
            innerConfig
        );

        return _deployedContracts;
    }

    function _deployInternal(
        string memory contractName, 
        string memory fileName, 
        bytes memory params,
        InnerDeployConfig memory config
    ) private returns (address) {
        bytes memory bytecode = Utils.readZKFoundryBytecode(fileName, contractName);
        
        return L2ContractHelper.computeCreate2Address(
            config.deployerAddr,
            config.salt,
            L2ContractHelper.hashL2Bytecode(bytecode),
            keccak256(params)
        );
    }
}
