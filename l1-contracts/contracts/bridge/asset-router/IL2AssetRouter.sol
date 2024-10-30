// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IL2AssetRouter {
    event WithdrawalInitiatedAssetRouter(
        uint256 chainId,
        address indexed l2Sender,
        bytes32 indexed assetId,
        bytes assetData
    );

    function withdraw(bytes32 _assetId, bytes calldata _transferData) external;

    function L1_ASSET_ROUTER() external view returns (address);

    function withdrawLegacyBridge(address _l1Receiver, address _l2Token, uint256 _amount, address _sender) external;

    /// @dev Used to set the assetHandlerAddress for a given assetId.
    /// @dev Will be used by ZK Gateway
    function setAssetHandlerAddress(uint256 _originChainId, bytes32 _assetId, address _assetAddress) external;
}
