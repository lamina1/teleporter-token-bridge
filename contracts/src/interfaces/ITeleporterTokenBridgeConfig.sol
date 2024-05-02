// (c) 2024, Translaminal, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.18;

/**
 * @notice Interface for Configuration of a Teleporter token bridge that sends tokens to another chain.
 *
 */
interface ITeleporterTokenBridgeConfig {
    /**
     * @notice Emitted when a fee option is modified (added or removed).
     */
    event FeeOptionChanged(address indexed feeAddress, bool indexed added);

    /**
     * @notice Emitted when an allowed relayer is modified (added or removed).
     */
    event RelayerChanged(address indexed relayerAddress, bool indexed added);

    /**
     * @notice Add / remove a given fee address from fee options.
     * @param feeAddress is the address of the fee token to set.
     * @param add is true if this fee token should be added, false if it should be removed.
     */
    function setFeeOption(address feeAddress, bool add) external;

    /**
     * @notice Add / remove a given relayer address from allowed relayers.
     * @param relayerAddress is the address of the relayer to set.
     * @param add is true if this relayer should be added, false if it should be removed.
     */
    function setRelayer(address relayerAddress, bool add) external;
}
