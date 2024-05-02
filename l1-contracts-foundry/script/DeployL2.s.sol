pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {stdToml} from "forge-std/StdToml.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Utils} from "./Utils.sol";
import {L2ContractHelper} from "contracts/common/libraries/L2ContractHelper.sol";
import {REQUIRED_L2_GAS_PRICE_PER_PUBDATA, MAX_GAS_PER_TRANSACTION} from "contracts/common/Config.sol";
import {L2_DEPLOYER_SYSTEM_CONTRACT_ADDR} from "contracts/common/L2ContractAddresses.sol";
import {AddressAliasHelper} from "contracts/vendor/AddressAliasHelper.sol";

import {Bridgehub} from "contracts/bridgehub/Bridgehub.sol";
import {L2TransactionRequestDirect} from "contracts/bridgehub/IBridgehub.sol";

contract DeployL2Script is Script {
    using stdToml for string;

    address constant ADDRESS_ONE = 0x0000000000000000000000000000000000000001;
    address constant DETERMINISTIC_CREATE2_ADDRESS = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    Config config;

    struct Config {
        address bridgehubAddress;
        address l1SharedBridgeProxy;
        address governance;
        address erc20BridgeProxy;
        uint256 chainId;
        address l2SharedBridgeImplementation;
        address l2SharedBridgeProxy;
    }

    function initializeConfig() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script-config/config-deploy-l2.toml");
        string memory toml = vm.readFile(path);
        config.bridgehubAddress = toml.readAddress("$.bridgehubAddress");
        config.governance = toml.readAddress("$.governance");
        config.l1SharedBridgeProxy = toml.readAddress("$.l1sharedBridgeProxy");
        config.chainId = toml.readUint("$.chainId");
        config.erc20BridgeProxy = toml.readAddress("$.erc20BridgeProxy");
    }

    function run() public {
        initializeConfig();
        deployFactoryDeps();
        deploySharedBridge();
        deploySharedBridgeProxy();
        saveOutput();
    }

    function saveOutput() internal {
        vm.serializeAddress("root", "l2_shared_bridge_implementation", config.l2SharedBridgeImplementation);
        string memory toml = vm.serializeAddress("root", "l2_shared_bridge_proxy", config.l2SharedBridgeProxy);
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script-out/output-deploy-l2.toml");
        vm.writeToml(toml, path);
    }

    function readHardheadBytecode(string memory artifactPath) public returns (bytes memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, artifactPath);
        string memory json = vm.readFile(path);
        bytes memory bytecode = vm.parseJson(json, ".bytecode");
        return bytecode;
    }

    function deployFactoryDeps() public {
        // HACK: We use the bytecode builded by hardhat to deploy the contracts
        bytes memory l2StandartErc20FactoryBytecode = readHardheadBytecode(
            "/../l2-contracts/artifacts-zk/@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol/UpgradeableBeacon.json"
        );
        bytes memory beaconProxy = readHardheadBytecode(
            "/../l2-contracts/artifacts-zk/@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol/BeaconProxy.json"
        );
        bytes memory l2StandartErc20Bytecode = readHardheadBytecode(
            "/../l2-contracts/artifacts-zk/contracts/bridge/L2StandardERC20.sol/L2StandardERC20.json"
        );
        bytes[] memory factoryDeps = new bytes[](3);
        factoryDeps[0] = l2StandartErc20FactoryBytecode;
        factoryDeps[1] = beaconProxy;
        factoryDeps[2] = l2StandartErc20Bytecode;
        publishBytecodes(factoryDeps);
    }

    function deploySharedBridge() public {
        // HACK: We use the bytecode builded by hardhat to deploy the contracts
        bytes memory l2SharedBridgeBytecode = readHardheadBytecode(
            "/../l2-contracts/artifacts-zk/contracts/bridge/L2SharedBridge.sol/L2SharedBridge.json"
        );
        bytes memory beaconProxy = readHardheadBytecode(
            "/../l2-contracts/artifacts-zk/@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol/BeaconProxy.json"
        );
        bytes[] memory factoryDeps = new bytes[](1);

        bytes memory constructorData = abi.encode("(uint256)", 0);

        config.l2SharedBridgeImplementation = L2ContractHelper.computeCreate2Address(
            msg.sender,
            "",
            L2ContractHelper.hashL2Bytecode(l2SharedBridgeBytecode),
            keccak256(constructorData)
        );

        factoryDeps[0] = beaconProxy;
        deployThroughL1({
            bytecode: l2SharedBridgeBytecode,
            constructorargs: constructorData,
            create2salt: "",
            l2GasLimit: MAX_GAS_PER_TRANSACTION,
            factoryDeps: factoryDeps
        });
    }

    function deploySharedBridgeProxy() public {
        bytes memory l2StandartErc20Bytecode = readHardheadBytecode(
            "/../l2-contracts/artifacts-zk/contracts/bridge/L2StandardERC20.sol/L2StandardERC20.json"
        );
        bytes32 l2StandartErc20BytecodeHash = L2ContractHelper.hashL2Bytecode(l2StandartErc20Bytecode);
        bytes memory proxyInitializationParams = abi.encodeWithSignature(
            "initialize(address,address,bytes32,address)",
            config.l1SharedBridgeProxy,
            config.erc20BridgeProxy,
            l2StandartErc20BytecodeHash
        );

        address l2GovernorAddress = AddressAliasHelper.applyL1ToL2Alias(config.governance);

        bytes memory l2SharedBridgeProxyConstructorData = abi.encode(
            "(address, address, bytes)",
            config.l2SharedBridgeImplementation,
            l2GovernorAddress,
            proxyInitializationParams
        );

        /// loading TransparentUpgradeableProxy bytecode
        bytes memory l2SharedBridgeProxyBytecode = readHardheadBytecode(
            "/../l2-contracts/artifacts-zk/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol/TransparentUpgradeableProxy.json"
        );
        bytes32 l2SharedBridgeProxyBytecodeHash = L2ContractHelper.hashL2Bytecode(l2SharedBridgeProxyBytecode);
        config.l2SharedBridgeProxy = L2ContractHelper.computeCreate2Address(
            msg.sender,
            "",
            l2SharedBridgeProxyBytecodeHash,
            keccak256(l2SharedBridgeProxyConstructorData)
        );

        deployThroughL1({
            bytecode: l2SharedBridgeProxyBytecode,
            constructorargs: l2SharedBridgeProxyConstructorData,
            create2salt: "",
            l2GasLimit: MAX_GAS_PER_TRANSACTION,
            factoryDeps: new bytes[](0)
        });
    }

    function publishBytecodes(bytes[] memory factoryDeps) public {
        runL1L2Transaction("", MAX_GAS_PER_TRANSACTION, factoryDeps, 0x0000000000000000000000000000000000000000);
    }

    function deployThroughL1(
        bytes memory bytecode,
        bytes memory constructorargs,
        bytes32 create2salt,
        uint256 l2GasLimit,
        bytes[] memory factoryDeps
    ) public {
        bytes32 bytecodeHash = L2ContractHelper.hashL2Bytecode(bytecode);

        bytes memory deployData = abi.encodeWithSignature(
            "create2(bytes32, bytes32, bytes calldata)",
            create2salt,
            bytecodeHash,
            constructorargs
        );

        bytes[] memory _factoryDeps = new bytes[](factoryDeps.length + 1);

        for (uint256 i = 0; i < factoryDeps.length; i++) {
            _factoryDeps[i] = factoryDeps[i];
        }
        _factoryDeps[factoryDeps.length] = bytecode;

        runL1L2Transaction(deployData, l2GasLimit, _factoryDeps, L2_DEPLOYER_SYSTEM_CONTRACT_ADDR);
    }

    function runL1L2Transaction(
        bytes memory l2Calldata,
        uint256 l2GasLimit,
        bytes[] memory factoryDeps,
        address dstAddress
    ) public {
        Bridgehub bridgehub = Bridgehub(config.bridgehubAddress);
        uint256 gasPrice = Utils.bytesToUint256(vm.rpc("eth_gasPrice", "[]"));

        uint256 requiredValueToDeploy = bridgehub.l2TransactionBaseCost(
            config.chainId,
            gasPrice,
            l2GasLimit,
            REQUIRED_L2_GAS_PRICE_PER_PUBDATA
        );

        L2TransactionRequestDirect memory l2TransactionRequestDirect = L2TransactionRequestDirect({
            chainId: config.chainId,
            mintValue: requiredValueToDeploy,
            l2Contract: dstAddress,
            l2Value: 0,
            l2Calldata: l2Calldata,
            l2GasLimit: l2GasLimit,
            l2GasPerPubdataByteLimit: REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
            factoryDeps: factoryDeps,
            refundRecipient: msg.sender
        });

        vm.startBroadcast();
        address baseTokenAddress = bridgehub.baseToken(config.chainId);
        if (ADDRESS_ONE != baseTokenAddress) {
            IERC20 baseToken = IERC20(baseTokenAddress);
            baseToken.approve(config.l1SharedBridgeProxy, requiredValueToDeploy);
            requiredValueToDeploy = 0;
        }

        bridgehub.requestL2TransactionDirect{value: requiredValueToDeploy}(l2TransactionRequestDirect);

        vm.stopBroadcast();
    }
}