// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.18;

import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {TeleporterOwnerUpgradeable} from "@teleporter/upgrades/TeleporterOwnerUpgradeable.sol";
import {
    ITeleporterTokenBridge,
    SendTokensInput,
    SendAndCallInput,
    BridgeMessageType,
    BridgeMessage,
    SingleHopSendMessage,
    SingleHopCallMessage,
    MultiHopSendMessage,
    MultiHopCallMessage
} from "./interfaces/ITeleporterTokenBridge.sol";
import {SendReentrancyGuard} from "./utils/SendReentrancyGuard.sol";
import {IWarpMessenger} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {TeleporterTokenBridgeConfig} from "./TeleporterTokenBridgeConfig.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.1/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts@4.8.1/token/ERC20/utils/SafeERC20.sol";
import {SafeERC20TransferFrom} from "./utils/SafeERC20TransferFrom.sol";

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
abstract contract TeleporterTokenSource is
    ITeleporterTokenBridge,
    TeleporterTokenBridgeConfig,
    TeleporterOwnerUpgradeable,
    SendReentrancyGuard
{
    /// @notice The blockchain ID of the chain this contract is deployed on.
    bytes32 public immutable blockchainID;

    /**
     * @notice Tracks the balances of tokens sent to other bridge instances.
     * Bridges are not allowed to unwrap more than has been sent to them.
     * @dev (destinationBlockchainID, destinationBridgeAddress) -> balance
     */
    mapping(
        bytes32 destinationBlockchainID
            => mapping(address destinationBridgeAddress => uint256 balance)
    ) public bridgedBalances;

    /**
     * @notice Initializes this source token bridge instance to send
     * tokens to the specified destination chain and token bridge instance.
     */
    constructor(
        address teleporterRegistryAddress,
        address teleporterManager,
        address[] memory initialFeeOptions,
        address[] memory initialRelayers
    )
        TeleporterTokenBridgeConfig(teleporterManager, initialFeeOptions, initialRelayers)
        TeleporterOwnerUpgradeable(teleporterRegistryAddress, teleporterManager)
    {
        blockchainID = IWarpMessenger(0x0200000000000000000000000000000000000005).getBlockchainID();
    }

    /**
     * @notice Sends tokens to the specified destination token bridge instance.
     *
     * @dev Increases the bridge balance sent to each destination token bridge instance,
     * and uses Teleporter to send a cross chain message.
     * Requirements:
     *
     * - `input.destinationBlockchainID` cannot be the same as the current blockchainID
     * - `input.destinationBridgeAddress` cannot be the zero address
     * - `input.recipient` cannot be the zero address
     * - `amount` must be greater than 0
     */
    function _send(
        SendTokensInput memory input,
        address originSenderAddress,
        uint256 amount,
        bool isMultihop
    ) internal sendNonReentrant {
        require(input.recipient != address(0), "TeleporterTokenSource: zero recipient address");
        require(input.requiredGasLimit > 0, "TeleporterTokenSource: zero required gas limit");
        require(input.secondaryFee == 0, "TeleporterTokenSource: non-zero secondary fee");
        // Handle fees
        input.primaryFee = _handleFee(originSenderAddress, input.primaryFeeAddress, input.primaryFee);
        // Prepare send
        _prepareSend(
            input.destinationBlockchainID,
            input.destinationBridgeAddress,
            amount,
            isMultihop
        );

        BridgeMessage memory message = BridgeMessage({
            messageType: BridgeMessageType.SINGLE_HOP_SEND,
            amount: amount,
            payload: abi.encode(SingleHopSendMessage({recipient: input.recipient}))
        });

        // Send message to the destination bridge address
        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: input.destinationBlockchainID,
                destinationAddress: input.destinationBridgeAddress,
                feeInfo: TeleporterFeeInfo({feeTokenAddress: input.primaryFeeAddress, amount: input.primaryFee}),
                requiredGasLimit: input.requiredGasLimit,
                allowedRelayerAddresses: allowedRelayers,
                message: abi.encode(message)
            })
        );

        if (isMultihop) {
            emit TokensRouted(messageID, input, amount);
        } else {
            emit TokensSent(messageID, msg.sender, input, amount);
        }
    }

    function _sendAndCall(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        SendAndCallInput memory input,
        uint256 amount,
        bool isMultihop
    ) internal sendNonReentrant {
        require(
            input.recipientContract != address(0),
            "TeleporterTokenSource: zero recipient contract address"
        );
        require(input.requiredGasLimit > 0, "TeleporterTokenSource: zero required gas limit");
        require(input.recipientGasLimit > 0, "TeleporterTokenSource: zero recipient gas limit");
        require(
            input.recipientGasLimit < input.requiredGasLimit,
            "TeleporterTokenSource: invalid recipient gas limit"
        );
        require(
            input.fallbackRecipient != address(0),
            "TeleporterTokenSource: zero fallback recipient address"
        );
        // Handle fees
        input.primaryFee = _handleFee(originSenderAddress, input.primaryFeeAddress, input.primaryFee);
        // Prepare send
        _prepareSend(
            input.destinationBlockchainID,
            input.destinationBridgeAddress,
            amount,
            isMultihop
        );

        BridgeMessage memory message = BridgeMessage({
            messageType: BridgeMessageType.SINGLE_HOP_CALL,
            amount: amount,
            payload: abi.encode(
                SingleHopCallMessage({
                    sourceBlockchainID: sourceBlockchainID,
                    originSenderAddress: originSenderAddress,
                    recipientContract: input.recipientContract,
                    recipientPayload: input.recipientPayload,
                    recipientGasLimit: input.recipientGasLimit,
                    fallbackRecipient: input.fallbackRecipient
                })
                )
        });

        // Send message to the destination bridge address
        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: input.destinationBlockchainID,
                destinationAddress: input.destinationBridgeAddress,
                feeInfo: TeleporterFeeInfo({feeTokenAddress: input.primaryFeeAddress, amount: input.primaryFee}),
                requiredGasLimit: input.requiredGasLimit,
                allowedRelayerAddresses: allowedRelayers,
                message: abi.encode(message)
            })
        );

        if (isMultihop) {
            emit TokensAndCallRouted(messageID, input, amount);
        } else {
            emit TokensAndCallSent(messageID, originSenderAddress, input, amount);
        }
    }

    /**
     * @dev See {ITeleporterUpgradeable-_receiveTeleporterMessage}
     *
     * Verifies the Teleporter token bridge sending back tokens has enough balance,
     * and adjusts the bridge balance accordingly. If the final destination for this token
     * is this contract, the tokens are withdrawn and sent to the recipient. Otherwise,
     * a multi-hop is performed, and the tokens are forwarded to the destination token bridge.
     * Requirements:
     *
     * - `sourceBlockchainID` and `originSenderAddress` have enough bridge balance to send back.
     * - `input.destinationBridgeAddress` is this contract is this chain is the final destination.
     */
    function _receiveTeleporterMessage(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        bytes memory message
    ) internal override {
        BridgeMessage memory bridgeMessage = abi.decode(message, (BridgeMessage));

        // Check that bridge instance returning has sufficient amount in balance
        uint256 senderBalance = bridgedBalances[sourceBlockchainID][originSenderAddress];
        require(
            senderBalance >= bridgeMessage.amount,
            "TeleporterTokenSource: insufficient bridge balance"
        );

        // Decrement the bridge balance by the unwrap amount
        bridgedBalances[sourceBlockchainID][originSenderAddress] =
            senderBalance - bridgeMessage.amount;

        if (bridgeMessage.messageType == BridgeMessageType.SINGLE_HOP_SEND) {
            SingleHopSendMessage memory payload =
                abi.decode(bridgeMessage.payload, (SingleHopSendMessage));
            _withdraw(payload.recipient, bridgeMessage.amount);
            return;
        } else if (bridgeMessage.messageType == BridgeMessageType.SINGLE_HOP_CALL) {
            SingleHopCallMessage memory payload =
                abi.decode(bridgeMessage.payload, (SingleHopCallMessage));

            // Verify that the payload's source blockchain ID
            // matches the source blockchain ID passed from Teleporter.
            // Prevents a destination bridge from accessing tokens attributed
            // to another destination bridge instance.
            require(
                payload.sourceBlockchainID == sourceBlockchainID,
                "TeleporterTokenSource: mismatched source blockchain ID"
            );
            _handleSendAndCall(payload, bridgeMessage.amount);
            return;
        } else if (bridgeMessage.messageType == BridgeMessageType.MULTI_HOP_SEND) {
            MultiHopSendMessage memory payload =
                abi.decode(bridgeMessage.payload, (MultiHopSendMessage));
            _send(
                SendTokensInput({
                    destinationBlockchainID: payload.destinationBlockchainID,
                    destinationBridgeAddress: payload.destinationBridgeAddress,
                    recipient: payload.recipient,
                    primaryFeeAddress: payload.secondaryFeeAddress,
                    primaryFee: payload.secondaryFee,
                    secondaryFeeAddress: address(0),
                    secondaryFee: 0,
                    requiredGasLimit: payload.secondaryGasLimit
                }),
                payload.originSenderAddress,
                bridgeMessage.amount,
                true
            );
            return;
        } else if (bridgeMessage.messageType == BridgeMessageType.MULTI_HOP_CALL) {
            MultiHopCallMessage memory payload =
                abi.decode(bridgeMessage.payload, (MultiHopCallMessage));
            _sendAndCall(
                sourceBlockchainID,
                payload.originSenderAddress,
                SendAndCallInput({
                    destinationBlockchainID: payload.destinationBlockchainID,
                    destinationBridgeAddress: payload.destinationBridgeAddress,
                    recipientContract: payload.recipientContract,
                    recipientPayload: payload.recipientPayload,
                    requiredGasLimit: payload.secondaryRequiredGasLimit,
                    recipientGasLimit: payload.recipientGasLimit,
                    fallbackRecipient: payload.fallbackRecipient,
                    primaryFeeAddress: payload.secondaryFeeAddress,
                    primaryFee: payload.secondaryFee,
                    secondaryFeeAddress: address(0),
                    secondaryFee: 0
                }),
                bridgeMessage.amount,
                true
            );
            return;
        }
    }

    /**
     * @notice Deposits tokens from the sender to this contract,
     * and returns the adjusted amount of tokens deposited.
     * @param amount is initial amount sent to this contract.
     * @return The actual amount deposited to this contract.
     */
    function _deposit(uint256 amount) internal virtual returns (uint256);

    /**
     * @notice Withdraws tokens to the recipient address.
     * @param recipient The address to withdraw tokens to
     * @param amount The amount of tokens to withdraw
     */
    function _withdraw(address recipient, uint256 amount) internal virtual;

    /**
     * @notice Processes a send and call message by calling the recipient contract.
     * @param message The send and call message include recipient calldata
     * @param amount The amount of tokens to be sent to the recipient
     */
    function _handleSendAndCall(
        SingleHopCallMessage memory message,
        uint256 amount
    ) internal virtual;

    /**
     * @dev Prepares tokens to be sent to another chain by handling the
     * locking of the token amount in this contract and updating the accounting
     * balances.
     */
    function _prepareSend(
        bytes32 destinationBlockchainID,
        address destinationBridgeAddress,
        uint256 amount,
        bool isMultihop
    ) private {
        require(
            destinationBlockchainID != bytes32(0),
            "TeleporterTokenSource: zero destination blockchain ID"
        );
        require(
            destinationBlockchainID != blockchainID,
            "TeleporterTokenSource: cannot bridge to same chain"
        );
        require(
            destinationBridgeAddress != address(0),
            "TeleporterTokenSource: zero destination bridge address"
        );

        // If this send is not a multi-hop, deposit the funds sent from the user to the bridge,
        // and set to adjusted amount after deposit.
        // If it is a multi-hop, the amount is already deposited.
        if (!isMultihop) {
            amount = _deposit(amount);
        }

        // Increase bridge balance
        bridgedBalances[destinationBlockchainID][destinationBridgeAddress] += amount;
    }

    /**
     * @dev Handle charging the fee for the token transfer.
     */
    function _handleFee(
        address sender,
        address feeAddress,
        uint256 fee
    ) private returns (uint256) {
        require(feeOptions[feeAddress], "TeleporterTokenSource: invalid fee token specified");
        uint256 adjustedFeeAmount = 0;
        if (fee > 0) {
            adjustedFeeAmount = SafeERC20TransferFrom.safeTransferFrom(IERC20(feeAddress), sender, fee);
            SafeERC20.safeIncreaseAllowance(
                IERC20(feeAddress), address(_getTeleporterMessenger()), adjustedFeeAmount
            );
        }
        return adjustedFeeAmount;
    }
}
