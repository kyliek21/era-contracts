// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @author Matter Labs
interface IL2Bridge {
    function finalizeDeposit(bytes32 _assetInfo, bytes calldata _data) external;

    function withdraw(address _l1Receiver, address _l2Token, uint256 _amount) external;

    function l1TokenAddress(address _l2Token) external view returns (address);

    function l2TokenAddress(address _l1Token) external view returns (address);

    function l1Bridge() external view returns (address);

    function setAssetAddress(bytes32 _assetInfo, address _assetAddress) external;
}
