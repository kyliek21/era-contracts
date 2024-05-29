// hardhat import should be the first import in the file
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import * as hardhat from "hardhat";
import { Command } from "commander";
import { Wallet, ethers } from "ethers";
import { Deployer } from "../src.ts/deploy";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { web3Provider, GAS_MULTIPLIER, SYSTEM_CONFIG } from "./utils";
import { deployedAddressesFromEnv } from "../src.ts/deploy-utils";
import { initialBridgehubDeployment } from "../src.ts/deploy-process";
import {
  ethTestConfig,
  getAddressFromEnv,
  getNumberFromEnv,
  ADDRESS_ONE,
  REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
  priorityTxMaxGasLimit,
} from "../src.ts/utils";

import { Wallet as ZkWallet, Provider as ZkProvider, utils as zkUtils } from "zksync-ethers";
import { IStateTransitionManagerFactory } from "../typechain/IStateTransitionManagerFactory";
import { TestnetERC20TokenFactory } from "../typechain/TestnetERC20TokenFactory";
import { BOOTLOADER_FORMAL_ADDRESS } from "zksync-ethers/build/src/utils";

const provider = web3Provider();

async function main() {
  const program = new Command();

  program.version("0.1.0").name("deploy").description("deploy L1 contracts");

  program
    .command("deploy-sync-layer-contracts")
    .option("--private-key <private-key>")
    .option("--chain-id <chain-id>")
    .option("--gas-price <gas-price>")
    .option("--owner-address <owner-address>")
    .option("--create2-salt <create2-salt>")
    .option("--diamond-upgrade-init <version>")
    .option("--only-verifier")
    .action(async (cmd) => {
      if (process.env.CONTRACTS_BASE_NETWORK_ZKSYNC !== "true") {
        throw new Error("This script is only for zkSync network");
      }

      const provider = new ZkProvider(process.env.API_WEB3_JSON_RPC_HTTP_URL);
      const deployWallet = cmd.privateKey
        ? new ZkWallet(cmd.privateKey, provider)
        : (ZkWallet.fromMnemonic(
            process.env.MNEMONIC ? process.env.MNEMONIC : ethTestConfig.mnemonic,
            "m/44'/60'/0'/0/1"
          ).connect(provider) as ethers.Wallet | ZkWallet);

      console.log(`Using deployer wallet: ${deployWallet.address}`);

      const ownerAddress = cmd.ownerAddress ? cmd.ownerAddress : deployWallet.address;
      console.log(`Using owner address: ${ownerAddress}`);

      const gasPrice = cmd.gasPrice
        ? parseUnits(cmd.gasPrice, "gwei")
        : (await provider.getGasPrice()).mul(GAS_MULTIPLIER);
      console.log(`Using gas price: ${formatUnits(gasPrice, "gwei")} gwei`);

      const nonce = cmd.nonce ? parseInt(cmd.nonce) : await deployWallet.getTransactionCount();
      console.log(`Using nonce: ${nonce}`);

      const create2Salt = cmd.create2Salt ? cmd.create2Salt : ethers.utils.hexlify(ethers.utils.randomBytes(32));

      const deployer = new Deployer({
        deployWallet,
        addresses: deployedAddressesFromEnv(),
        ownerAddress,
        verbose: true,
      });

      if (deployer.isZkMode()) {
        console.log("Deploying on a zkSync network!");
      }
      deployer.addresses.Bridges.SharedBridgeProxy = getAddressFromEnv("CONTRACTS_L2_SHARED_BRIDGE_ADDR");

      await initialBridgehubDeployment(deployer, [], gasPrice, true, create2Salt);
      await initialBridgehubDeployment(deployer, [], gasPrice, false, create2Salt);
      const bridgehub = deployer.bridgehubContract(deployer.deployWallet);
      const l1ChainId = getNumberFromEnv("ETH_CLIENT_CHAIN_ID");
      const l1BridgehubAddress = getAddressFromEnv("CONTRACTS_BRIDGEHUB_PROXY_ADDR");
      await deployer.executeUpgrade(
        bridgehub.address,
        0,
        bridgehub.interface.encodeFunctionData("registerCounterpart", [l1ChainId, l1BridgehubAddress])
      );
    });

  program
    .command("register-sync-layer")
    .option("--private-key <private-key>")
    .option("--chain-id <chain-id>")
    .option("--gas-price <gas-price>")
    .option("--owner-address <owner-address>")
    .option("--create2-salt <create2-salt>")
    .option("--diamond-upgrade-init <version>")
    .option("--only-verifier")
    .action(async (cmd) => {
      // Now, all the operations are done on L1
      const deployWallet = cmd.privateKey
        ? new Wallet(cmd.privateKey, provider)
        : Wallet.fromMnemonic(
            process.env.MNEMONIC ? process.env.MNEMONIC : ethTestConfig.mnemonic,
            "m/44'/60'/0'/0/1"
          ).connect(provider);

      const ownerAddress = cmd.ownerAddress ? cmd.ownerAddress : deployWallet.address;
      console.log(`Using owner address: ${ownerAddress}`);
      const deployer = new Deployer({
        deployWallet,
        addresses: deployedAddressesFromEnv(),
        ownerAddress,
        verbose: true,
      });
      await registerSLContractsOnL1(deployer);
    });

  program
    .command("migrate-to-sync-layer")
    .option("--private-key <private-key>")
    .option("--chain-id <chain-id>")
    .option("--gas-price <gas-price>")
    .option("--owner-address <owner-address>")
    .option("--create2-salt <create2-salt>")
    .option("--diamond-upgrade-init <version>")
    .option("--only-verifier")
    .action(async (cmd) => {
      console.log("Starting migration of the current chain to sync layer");

      const deployWallet = cmd.privateKey
        ? new Wallet(cmd.privateKey, provider)
        : Wallet.fromMnemonic(
            process.env.MNEMONIC ? process.env.MNEMONIC : ethTestConfig.mnemonic,
            "m/44'/60'/0'/0/1"
          ).connect(provider);
      const ownerAddress = cmd.ownerAddress ? cmd.ownerAddress : deployWallet.address;

      const deployer = new Deployer({
        deployWallet,
        addresses: deployedAddressesFromEnv(),
        ownerAddress,
        verbose: true,
      });

      const syncLayerChainId = getNumberFromEnv("SYNC_LAYER_CHAIN_ID");
      const gasPrice = cmd.gasPrice
        ? parseUnits(cmd.gasPrice, "gwei")
        : (await provider.getGasPrice()).mul(GAS_MULTIPLIER);

      const currentChainId = getNumberFromEnv("CHAIN_ETH_ZKSYNC_NETWORK_ID");

      const stm = deployer.stateTransitionManagerContract(deployer.deployWallet);

      const counterPart = getAddressFromEnv("SYNC_LAYER_STATE_TRANSITION_PROXY_ADDR");

      // FIXME: do it more gracefully
      deployer.addresses.StateTransition.AdminFacet = getAddressFromEnv("SYNC_LAYER_ADMIN_FACET_ADDR");
      deployer.addresses.StateTransition.MailboxFacet = getAddressFromEnv("SYNC_LAYER_MAILBOX_FACET_ADDR");
      deployer.addresses.StateTransition.ExecutorFacet = getAddressFromEnv("SYNC_LAYER_EXECUTOR_FACET_ADDR");
      deployer.addresses.StateTransition.GettersFacet = getAddressFromEnv("SYNC_LAYER_GETTERS_FACET_ADDR");
      deployer.addresses.StateTransition.Verifier = getAddressFromEnv("SYNC_LAYER_VERIFIER_ADDR");
      deployer.addresses.BlobVersionedHashRetriever = getAddressFromEnv(
        "SYNC_LAYER_BLOB_VERSIONED_HASH_RETRIEVER_ADDR"
      );
      deployer.addresses.StateTransition.DiamondInit = getAddressFromEnv("SYNC_LAYER_DIAMOND_INIT_ADDR");

      const receipt = await deployer.moveChainToSyncLayer(syncLayerChainId, gasPrice, false);

      const syncLayerAddress = await stm.getHyperchain(syncLayerChainId);

      const l2TxHash = zkUtils.getL2HashFromPriorityOp(receipt, syncLayerAddress);

      console.log("Hash of the transaction on SL chain: ", l2TxHash);

      const syncLayerProvider = new ZkProvider(process.env.SYNC_LAYER_API_WEB3_JSON_RPC_HTTP_URL);

      const txL2Handle = syncLayerProvider.getL2TransactionFromPriorityOp(
        await deployWallet.provider.getTransaction(receipt.transactionHash)
      );

      const receiptOnSL = await (await txL2Handle).wait();
      console.log("Finalized on SL with hash:", receiptOnSL.transactionHash);

      const stmOnSL = IStateTransitionManagerFactory.connect(counterPart, syncLayerProvider);
      const hyperchainAddress = await stmOnSL.getHyperchain(currentChainId);
      console.log(`CONTRACTS_DIAMOND_PROXY_ADDR=${hyperchainAddress}`);

      console.log("Success!");
    });

  program
    .command("recover-from-failed-migration")
    .option("--private-key <private-key>")
    .option("--failed-tx-l2-hash <failed-tx-l2-hash>")
    .option("--chain-id <chain-id>")
    .option("--gas-price <gas-price>")
    .option("--owner-address <owner-address>")
    .option("--create2-salt <create2-salt>")
    .option("--diamond-upgrade-init <version>")
    .option("--only-verifier")
    .action(async (cmd) => {
      const syncLayerChainId = getNumberFromEnv("SYNC_LAYER_CHAIN_ID");
      const syncLayerProvider = new ZkProvider(process.env.SYNC_LAYER_API_WEB3_JSON_RPC_HTTP_URL);
      console.log("Obtaining proof...");
      const proof = await getTxFailureProof(syncLayerProvider, cmd.failedTxL2Hash);

      const deployWallet = cmd.privateKey
        ? new Wallet(cmd.privateKey, provider)
        : Wallet.fromMnemonic(
            process.env.MNEMONIC ? process.env.MNEMONIC : ethTestConfig.mnemonic,
            "m/44'/60'/0'/0/1"
          ).connect(provider);
      console.log(deployWallet.address);
      const ownerAddress = cmd.ownerAddress ? cmd.ownerAddress : deployWallet.address;
      const deployer = new Deployer({
        deployWallet,
        addresses: deployedAddressesFromEnv(),
        ownerAddress,
        verbose: true,
      });

      const hyperchain = deployer.stateTransitionContract(deployer.deployWallet);

      console.log(await hyperchain.getAdmin());

      console.log("Executing recovery...");

      await (
        await hyperchain.recoverFromFailedMigrationToSyncLayer(
          syncLayerChainId,
          proof.l2BatchNumber,
          proof.l2MessageIndex,
          proof.l2TxNumberInBatch,
          proof.merkleProof
        )
      ).wait();

      console.log("Success!");
    });

  program
    .command("prepare-validators")
    .option("--private-key <private-key>")
    .option("--chain-id <chain-id>")
    .option("--gas-price <gas-price>")
    .option("--owner-address <owner-address>")
    .option("--create2-salt <create2-salt>")
    .option("--diamond-upgrade-init <version>")
    .option("--only-verifier")
    .action(async (cmd) => {
      const syncLayerProvider = new ZkProvider(process.env.SYNC_LAYER_API_WEB3_JSON_RPC_HTTP_URL);
      const currentChainId = getNumberFromEnv("CHAIN_ETH_ZKSYNC_NETWORK_ID");

      // Right now the new admin is the wallet itself.
      const adminWallet = cmd.privateKey
        ? new ZkWallet(cmd.privateKey, syncLayerProvider)
        : ZkWallet.fromMnemonic(
            process.env.MNEMONIC ? process.env.MNEMONIC : ethTestConfig.mnemonic,
            "m/44'/60'/0'/0/1"
          ).connect(syncLayerProvider);

      const operators = [
        process.env.ETH_SENDER_SENDER_OPERATOR_COMMIT_ETH_ADDR,
        process.env.ETH_SENDER_SENDER_OPERATOR_BLOBS_ETH_ADDR,
      ];

      const deployer = new Deployer({
        deployWallet: adminWallet,
        addresses: deployedAddressesFromEnv(),
        ownerAddress: adminWallet.address,
        verbose: true,
      });

      console.log("Enabling validators");

      // FIXME: do it in cleaner way
      deployer.addresses.ValidatorTimeLock = getAddressFromEnv("SYNC_LAYER_VALIDATOR_TIMELOCK_ADDR");
      const timelock = deployer.validatorTimelock(deployer.deployWallet);

      for (const operator of operators) {
        await deployer.deployWallet.sendTransaction({
          to: operator,
          value: ethers.utils.parseEther("5"),
        });

        await (await timelock.addValidator(currentChainId, operator)).wait();
      }

      // FIXME: this method includes bridgehub manipulation, but in the future it won't.
      deployer.addresses.StateTransition.StateTransitionProxy = getAddressFromEnv(
        "SYNC_LAYER_STATE_TRANSITION_PROXY_ADDR"
      );
      deployer.addresses.Bridgehub.BridgehubProxy = getAddressFromEnv("SYNC_LAYER_BRIDGEHUB_PROXY_ADDR");

      // FIXME? Do we want to
      console.log("Setting default token multiplier");

      const hyperchain = deployer.stateTransitionContract(deployer.deployWallet);

      console.log("The default ones token multiplier");
      await (await hyperchain.setTokenMultiplier(1, 1)).wait();

      console.log("Success!");
    });

  await program.parseAsync(process.argv);
}

async function registerSLContractsOnL1(deployer: Deployer) {
  /// STM asset info
  /// l2Bridgehub in L1Bridghub
  const bridgehubOnSyncLayer = getAddressFromEnv("SYNC_LAYER_BRIDGEHUB_PROXY_ADDR");

  const chainId = getNumberFromEnv("CHAIN_ETH_ZKSYNC_NETWORK_ID");

  console.log(`Bridghub on SyncLayer: ${bridgehubOnSyncLayer}`);
  console.log(`SyncLayer chain Id: ${chainId}`);

  const l1STM = deployer.stateTransitionManagerContract(deployer.deployWallet);
  const l1Bridgehub = deployer.bridgehubContract(deployer.deployWallet);
  console.log(deployer.addresses.StateTransition.StateTransitionProxy);
  const syncLayerAddress = await l1STM.getHyperchain(chainId);
  // this script only works when owner is the deployer
  console.log("Registering SyncLayer chain id on the STM");
  await deployer.executeUpgrade(
    l1STM.address,
    0,
    l1Bridgehub.interface.encodeFunctionData("registerSyncLayer", [chainId, true])
  );

  console.log("Registering Bridgehub counter part on the SyncLayer");
  await deployer.executeUpgrade(
    l1Bridgehub.address, // kl todo fix. The BH has the counterpart, the BH needs to be deployed on L2, and the STM needs to be registered in the L2 BH.
    0,
    l1Bridgehub.interface.encodeFunctionData("registerCounterpart", [chainId, bridgehubOnSyncLayer])
  );
  console.log("SyncLayer registration completed in L1 Bridgehub");

  const gasPrice = (await deployer.deployWallet.provider.getGasPrice()).mul(GAS_MULTIPLIER);
  const value = (
    await l1Bridgehub.l2TransactionBaseCost(chainId, gasPrice, priorityTxMaxGasLimit, REQUIRED_L2_GAS_PRICE_PER_PUBDATA)
  ).mul(10);
  const baseTokenAddress = await l1Bridgehub.baseToken(chainId);
  const ethIsBaseToken = baseTokenAddress == ADDRESS_ONE;
  if (!ethIsBaseToken) {
    const baseToken = TestnetERC20TokenFactory.connect(baseTokenAddress, this.deployWallet);
    await (await baseToken.transfer(this.addresses.Governance, value)).wait();
    await this.executeUpgrade(
      baseTokenAddress,
      0,
      baseToken.interface.encodeFunctionData("approve", [this.addresses.Bridges.SharedBridgeProxy, value.mul(2)])
    );
  }
  const stmDeploymentTracker = deployer.stmDeploymentTracker(deployer.deployWallet);

  const receipt = await deployer.executeUpgrade(
    l1Bridgehub.address,
    value,
    l1Bridgehub.interface.encodeFunctionData("requestL2TransactionTwoBridges", [
      {
        chainId,
        mintValue: value,
        l2Value: 0,
        l2GasLimit: priorityTxMaxGasLimit,
        l2GasPerPubdataByteLimit: SYSTEM_CONFIG.requiredL2GasPricePerPubdata,
        refundRecipient: deployer.deployWallet.address,
        secondBridgeAddress: stmDeploymentTracker.address,
        secondBridgeValue: 0,
        secondBridgeCalldata: ethers.utils.defaultAbiCoder.encode(
          ["bool", "address", "address"],
          [false, l1STM.address, getAddressFromEnv("SYNC_LAYER_STATE_TRANSITION_PROXY_ADDR")]
        ),
      },
    ])
  );
  const l2TxHash = zkUtils.getL2HashFromPriorityOp(receipt, syncLayerAddress);
  console.log("STM asset registered in L2SharedBridge on SL l2 tx hash: ", l2TxHash);
  const receipt2 = await deployer.executeUpgrade(
    l1Bridgehub.address,
    value,
    l1Bridgehub.interface.encodeFunctionData("requestL2TransactionTwoBridges", [
      {
        chainId,
        mintValue: value,
        l2Value: 0,
        l2GasLimit: priorityTxMaxGasLimit,
        l2GasPerPubdataByteLimit: SYSTEM_CONFIG.requiredL2GasPricePerPubdata,
        refundRecipient: deployer.deployWallet.address,
        secondBridgeAddress: stmDeploymentTracker.address,
        secondBridgeValue: 0,
        secondBridgeCalldata: ethers.utils.defaultAbiCoder.encode(
          ["bool", "address", "address"],
          [true, l1STM.address, getAddressFromEnv("SYNC_LAYER_STATE_TRANSITION_PROXY_ADDR")]
        ),
      },
    ])
  );
  const l2TxHash2 = zkUtils.getL2HashFromPriorityOp(receipt2, syncLayerAddress);
  console.log("STM asset registered in L2 Bridgehub on SL", l2TxHash2);
}

// TODO: maybe move it to SDK
async function getTxFailureProof(provider: ZkProvider, l2TxHash: string) {
  const receipt = await provider.getTransactionReceipt(ethers.utils.hexlify(l2TxHash));
  const successL2ToL1LogIndex = receipt.l2ToL1Logs.findIndex(
    (l2ToL1log) => l2ToL1log.sender == BOOTLOADER_FORMAL_ADDRESS && l2ToL1log.key == l2TxHash
  );
  const successL2ToL1Log = receipt.l2ToL1Logs[successL2ToL1LogIndex];
  if (successL2ToL1Log.value != ethers.constants.HashZero) {
    throw new Error("The tx was successful");
  }

  const proof = await provider.getLogProof(l2TxHash, successL2ToL1LogIndex);
  return {
    l2BatchNumber: receipt.l1BatchNumber,
    l2MessageIndex: proof.id,
    l2TxNumberInBatch: receipt.l1BatchTxIndex,
    merkleProof: proof.proof,
  };
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Error:", err);
    process.exit(1);
  });
