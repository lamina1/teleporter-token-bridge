// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.18;

import "./interfaces/ITeleporterTokenBridgeConfig.sol";
import {Ownable} from "@openzeppelin/contracts@4.8.1/access/Ownable.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/**
 * @title TeleporterTokenSource
 * @dev Abstract contract for a Teleporter token bridge that sends tokens to {TeleporterTokenDestination} instances.
 *
 * This contract also handles multi-hop transfers, where tokens sent from a {TeleporterTokenDestination}
 * instance are forwarded to another {TeleporterTokenDestination} instance.
 *
 * @custom:security-contact https://github.com/ava-labs/teleporter-token-bridge/blob/main/SECURITY.md
 */
abstract contract TeleporterTokenBridgeConfig is ITeleporterTokenBridgeConfig, Ownable {
    /**
     * @notice Tracks the fee options that are allowed for this bridge instance.
     * @dev address -> bool
     */
    mapping(address => bool) public feeOptions;

    /**
     * @notice Tracks the list of relayers that are allowed to send messages originated by this bridge instance.
     */
    address[] public allowedRelayers;

    /**
     * @notice Tracks the index of each relayer address for better addition / removal.
     * @dev address -> uint256
     */
    mapping(address => uint256) private _relayerIdx;

    /**
     * @notice Initializes this contract with an owner and initial arrays
     * of allowed fee tokens and relayers
     */
    constructor(
        address initialOwner,
        address[] memory initialFeeOptions,
        address[] memory initialRelayers
    ) {
        // Set the initial owner
        transferOwnership(initialOwner);
        // Add the initial fee options
        for (uint256 i = 0; i < initialFeeOptions.length; i++) {
            _setFeeOption(initialFeeOptions[i], true);
        }
        // Add the initial relayers
        for (uint256 i = 0; i < initialRelayers.length; i++) {
            _setRelayer(initialRelayers[i], true);
        }
    }

    /**
     * @notice Add / remove a given fee address from fee options.
     * @param feeAddress is the address of the fee token to set.
     * @param add is true if this fee token should be added, false if it should be removed.
     */
    function setFeeOption(address feeAddress, bool add) external override onlyOwner {
        _setFeeOption(feeAddress, add);
    }

    /**
     * @notice Add / remove a given relayer address from allowed relayers.
     * @param relayerAddress is the address of the relayer to set.
     * @param add is true if this relayer should be added, false if it should be removed.
     */
    function setRelayer(address relayerAddress, bool add) external override onlyOwner {
        _setRelayer(relayerAddress, add);
    }

    /**
     * @notice Internal function to add / remove a given fee address from fee options.
     * @param feeAddress is the address of the fee token to set.
     * @param add is true if this fee token should be added, false if it should be removed.
     */
    function _setFeeOption(address feeAddress, bool add) internal {
        if (add) {
            require(!feeOptions[feeAddress], "Fee option already exists");
            feeOptions[feeAddress] = true;
        } else {
            require(feeOptions[feeAddress], "Fee option does not exist");
            feeOptions[feeAddress] = false;
        }
        emit FeeOptionChanged(feeAddress, add);
    }

    /**
     * @notice Internal function to add / remove a given relayer address from allowed relayers.
     * @param relayerAddress is the address of the relayer to set.
     * @param add is true if this relayer should be added, false if it should be removed.
     */
    function _setRelayer(address relayerAddress, bool add) internal {
        if (add) {
            require(_relayerIdx[relayerAddress] == 0, "Relayer already exists");
            _relayerIdx[relayerAddress] = allowedRelayers.length + 1;
            allowedRelayers.push(relayerAddress);
        } else {
            require(_relayerIdx[relayerAddress] != 0, "Relayer does not exist");
            uint256 idx = _relayerIdx[relayerAddress] - 1;
            uint256 lastIdx = allowedRelayers.length - 1;
            address lastRelayer = allowedRelayers[lastIdx];
            allowedRelayers[idx] = lastRelayer;
            _relayerIdx[lastRelayer] = idx + 1;
            allowedRelayers.pop();
            _relayerIdx[relayerAddress] = 0;
        }
        emit RelayerChanged(relayerAddress, add);
    }
}
