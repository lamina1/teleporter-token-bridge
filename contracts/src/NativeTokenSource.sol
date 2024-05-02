// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.18;

import {TeleporterTokenSource} from "./TeleporterTokenSource.sol";
import {INativeTokenBridge} from "./interfaces/INativeTokenBridge.sol";
import {INativeSendAndCallReceiver} from "./interfaces/INativeSendAndCallReceiver.sol";
import {
    SendTokensInput,
    SendAndCallInput,
    SingleHopCallMessage
} from "./interfaces/ITeleporterTokenBridge.sol";
import {CallUtils} from "./utils/CallUtils.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/**
 * @title NativeTokenSource
 * @notice This contract is an {INativeTokenBridge} that sends native tokens to another chain's
 * {ITeleporterTokenBridge} instance, and gets represented by the tokens of that destination
 * token bridge instance.
 *
 * @custom:security-contact https://github.com/ava-labs/teleporter-token-bridge/blob/main/SECURITY.md
 */
contract NativeTokenSource is INativeTokenBridge, TeleporterTokenSource {
    /**
     * @notice Initializes this source token bridge instance
     * @dev Teleporter fees can be paid in ERC20 tokens as configured by token bridge owner
     */
    constructor(
        address teleporterRegistryAddress,
        address teleporterManager,
        address[] memory initialFeeOptions,
        address[] memory initialRelayers
    ) TeleporterTokenSource(teleporterRegistryAddress, teleporterManager, initialFeeOptions, initialRelayers) {}

    /**
     * @dev See {INativeTokenBridge-send}
     */
    function send(SendTokensInput calldata input) external payable {
        _send(input, msg.sender, msg.value, false);
    }

    function sendAndCall(SendAndCallInput calldata input) external payable {
        _sendAndCall(blockchainID, msg.sender, input, msg.value, false);
    }

    /**
     * @dev See {TeleportTokenSource-_deposit}
     * Deposits the native tokens sent to this contract
     */
    function _deposit(uint256 amount) internal virtual override returns (uint256) {
        // Noop, since native coins are already in contract
        return amount;
    }

    /**
     * @dev See {TeleportTokenSource-_withdraw}
     * Withdraws the wrapped tokens for native tokens,
     * and sends them to the recipient.
     */
    function _withdraw(address recipient, uint256 amount) internal virtual override {
        emit TokensWithdrawn(recipient, amount);
        payable(recipient).transfer(amount);
    }

    /**
     * @dev See {TeleporterTokenDestination-_handleSendAndCall}
     *
     * Send the native tokens to the recipient contract as a part of the call to
     * {INativeSendAndCallReceiver-receiveTokens} on the recipient contract.
     * If the call fails or doesn't spend all of the tokens, the remaining amount is
     * sent to the fallback recipient.
     */
    function _handleSendAndCall(
        SingleHopCallMessage memory message,
        uint256 amount
    ) internal virtual override {
        // Encode the call to {INativeSendAndCallReceiver-receiveTokens}
        bytes memory payload = abi.encodeCall(
            INativeSendAndCallReceiver.receiveTokens,
            (message.sourceBlockchainID, message.originSenderAddress, message.recipientPayload)
        );

        // Call the destination contract with the given payload, gas amount, and value.
        bool success = CallUtils._callWithExactGasAndValue(
            message.recipientGasLimit, amount, message.recipientContract, payload
        );

        // If the call failed, send the funds to the fallback recipient.
        if (success) {
            emit CallSucceeded(message.recipientContract, amount);
        } else {
            emit CallFailed(message.recipientContract, amount);
            payable(message.fallbackRecipient).transfer(amount);
        }
    }
}
