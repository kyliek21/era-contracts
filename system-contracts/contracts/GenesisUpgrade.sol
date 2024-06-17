// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {DEPLOYER_SYSTEM_CONTRACT, SYSTEM_CONTEXT_CONTRACT} from "./Constants.sol";
import {IContractDeployer} from "./interfaces/IContractDeployer.sol";
import {ISystemContext} from "./interfaces/ISystemContext.sol";

/// @custom:security-contact security@matterlabs.dev
/// @author Matter Labs
/// @notice The contract that can be used for deterministic contract deployment.
contract GenesisUpgrade {
    function genesisUpgrade(uint256 _chainId, IContractDeployer.ForceDeployment[] calldata _forceDeployments) external {
        require(_chainId == 0, "Invalid chainId");
        ISystemContext(SYSTEM_CONTEXT_CONTRACT).setChainId(_chainId);
        forceDeploy(_forceDeployments);
    }

    function forceDeploy(IContractDeployer.ForceDeployment[] calldata _forceDeployments) public payable {
        IContractDeployer(DEPLOYER_SYSTEM_CONTRACT).forceDeployOnAddresses{value: msg.value}(_forceDeployments);
    }
}