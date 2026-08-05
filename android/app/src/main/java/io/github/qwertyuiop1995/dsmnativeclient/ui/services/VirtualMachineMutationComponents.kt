package io.github.qwertyuiop1995.dsmnativeclient.ui.services

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.VirtualMachineLifecycleOperation
import io.github.qwertyuiop1995.dsmnativeclient.VirtualMachineLifecycleTarget
import io.github.qwertyuiop1995.dsmnativeclient.VirtualMachineMutationKind
import io.github.qwertyuiop1995.dsmnativeclient.VirtualMachineMutationVerification
import io.github.qwertyuiop1995.dsmnativeclient.VirtualMachineMutationWorkspaceState
import io.github.qwertyuiop1995.dsmnativeclient.canContinueEditingVirtualMachineMutation
import io.github.qwertyuiop1995.dsmnativeclient.canDismissVirtualMachineMutation
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.localization.localize
import io.github.qwertyuiop1995.dsmnativeclient.virtualMachineMutationRequiresRefreshBeforeDismiss

internal data class VirtualMachineFeedbackPolicy(
    @StringRes val title: Int,
    @StringRes val message: Int,
    val assertive: Boolean,
)

internal fun virtualMachineFeedbackPolicy(result: MutationResult): VirtualMachineFeedbackPolicy = when (
    result.status
) {
    MutationResultStatus.CONFIRMED_SUCCESS -> VirtualMachineFeedbackPolicy(
        R.string.virtual_machine_feedback_confirmed_title,
        R.string.virtual_machine_feedback_confirmed_message,
        false,
    )
    MutationResultStatus.PARTIAL_SUCCESS -> VirtualMachineFeedbackPolicy(
        R.string.virtual_machine_feedback_partial_title,
        R.string.virtual_machine_feedback_partial_message,
        true,
    )
    MutationResultStatus.SUBMITTED_BUT_UNVERIFIED -> VirtualMachineFeedbackPolicy(
        R.string.virtual_machine_feedback_check_title,
        R.string.virtual_machine_feedback_unverified_message,
        true,
    )
    MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION -> VirtualMachineFeedbackPolicy(
        R.string.virtual_machine_feedback_check_title,
        R.string.virtual_machine_feedback_cancel_after_submission_message,
        true,
    )
    MutationResultStatus.PERMISSION_DENIED -> VirtualMachineFeedbackPolicy(
        R.string.virtual_machine_feedback_permission_title,
        R.string.virtual_machine_feedback_permission_message,
        true,
    )
    MutationResultStatus.UNSUPPORTED -> VirtualMachineFeedbackPolicy(
        R.string.virtual_machine_feedback_unavailable_title,
        R.string.virtual_machine_feedback_unsupported_message,
        true,
    )
    MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> VirtualMachineFeedbackPolicy(
        R.string.virtual_machine_feedback_cancelled_title,
        R.string.virtual_machine_feedback_cancelled_message,
        true,
    )
    MutationResultStatus.CONFIRMED_FAILURE -> VirtualMachineFeedbackPolicy(
        if (result.errorCategory == MutationErrorCategory.CONFLICT) {
            R.string.virtual_machine_feedback_conflict_title
        } else R.string.virtual_machine_feedback_failed_title,
        if (result.errorCategory == MutationErrorCategory.CONFLICT) {
            R.string.virtual_machine_feedback_conflict_message
        } else R.string.virtual_machine_feedback_failed_message,
        true,
    )
}

@Composable
internal fun VirtualMachineMutationFeedbackDialog(
    state: VirtualMachineMutationWorkspaceState,
    onRefresh: () -> Boolean,
    onContinueEditing: () -> Boolean,
    onDismiss: () -> Boolean,
) {
    val canDismiss = canDismissVirtualMachineMutation(state)
    val canContinueEditing = canContinueEditingVirtualMachineMutation(state)
    AlertDialog(
        onDismissRequest = { if (canDismiss) onDismiss() },
        title = { Text(stringResource(state.target?.kind.feedbackTitle() ?: R.string.virtual_machines)) },
        text = {
            VirtualMachineMutationFeedbackCard(state)
        },
        dismissButton = {
            val requiresRefresh = virtualMachineMutationRequiresRefreshBeforeDismiss(state)
            if (canContinueEditing) {
                TextButton(
                    onClick = { onContinueEditing() },
                    modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
                ) {
                    Text(stringResource(R.string.continue_editing))
                }
            } else if ((requiresRefresh && !canDismiss) || state.mutationRefreshFailure != null) {
                TextButton(
                    onClick = { onRefresh() },
                    enabled = !state.mutationInProgress && !state.mutationRefreshInProgress,
                    modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
                ) {
                    Text(stringResource(R.string.refresh_and_check_virtual_machines))
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onDismiss() },
                enabled = canDismiss,
                modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
            ) {
                Text(
                    stringResource(
                        if (virtualMachineMutationRequiresRefreshBeforeDismiss(state)) {
                            R.string.close_checked_virtual_machine_feedback
                        } else R.string.close,
                    ),
                )
            }
        },
    )
}

@Composable
internal fun VirtualMachineMutationFeedbackCard(state: VirtualMachineMutationWorkspaceState) {
    val policy = state.mutationResult?.let(::virtualMachineFeedbackPolicy)
    val verificationAssertive = state.mutationVerification != null &&
        state.mutationVerification != VirtualMachineMutationVerification.MATCHES
    val liveRegionMode = if (
        state.mutationFailure != null || state.mutationRefreshFailure != null ||
        policy?.assertive == true || verificationAssertive
    ) LiveRegionMode.Assertive else LiveRegionMode.Polite
    Card(
        modifier = Modifier.fillMaxWidth().semantics { liveRegion = liveRegionMode },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 360.dp)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            Text(
                when {
                    state.mutationInProgress -> stringResource(R.string.virtual_machine_feedback_in_progress_title)
                    state.mutationFailure != null -> stringResource(R.string.virtual_machine_feedback_failed_title)
                    else -> stringResource(checkNotNull(policy).title)
                },
            )
            when {
                state.mutationInProgress -> {
                    Text(
                        stringResource(R.string.virtual_machine_feedback_in_progress_message),
                        modifier = Modifier.padding(top = 8.dp),
                    )
                    LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 12.dp))
                }
                state.mutationFailure != null -> Text(
                    state.mutationFailure.localize(LocalContext.current).combined,
                    modifier = Modifier.padding(top = 8.dp),
                )
                policy != null -> Text(
                    stringResource(policy.message),
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            state.mutationResult?.counts?.let { counts ->
                Text(
                    stringResource(
                        R.string.virtual_machine_feedback_counts,
                        counts.succeeded,
                        counts.failed,
                        counts.unknown,
                    ),
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            if (state.mutationRefreshInProgress) {
                Text(
                    stringResource(R.string.virtual_machine_feedback_refreshing),
                    modifier = Modifier.padding(top = 12.dp),
                )
                LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = 8.dp))
            }
            state.mutationRefreshFailure?.let { failure ->
                Text(
                    failure.localize(LocalContext.current).combined,
                    modifier = Modifier.padding(top = 12.dp),
                )
            }
            state.mutationVerification?.let { verification ->
                Text(
                    stringResource(verification.messageResource()),
                    modifier = Modifier.padding(top = 12.dp),
                )
            }
        }
    }
}

@Composable
internal fun VirtualMachineLifecycleConfirmationDialog(
    target: VirtualMachineLifecycleTarget,
    resourceName: String,
    onConfirm: () -> Boolean,
    onDismiss: () -> Boolean,
) {
    val command = target.command.orEmpty()
    val title = when (target.operation) {
        VirtualMachineLifecycleOperation.CONTROL -> when (command) {
            "poweron" -> stringResource(R.string.start_virtual_machine_title, resourceName)
            else -> stringResource(R.string.shutdown_virtual_machine_title, resourceName)
        }
        VirtualMachineLifecycleOperation.DELETE_MACHINE,
        VirtualMachineLifecycleOperation.DELETE_IMAGE,
        VirtualMachineLifecycleOperation.DELETE_NETWORK,
        -> stringResource(R.string.delete_named_item, resourceName)
        VirtualMachineLifecycleOperation.RENAME_NETWORK ->
            stringResource(R.string.rename_virtual_machine_network_title, resourceName)
    }
    val message = when (target.operation) {
        VirtualMachineLifecycleOperation.CONTROL -> when (command) {
            "poweron" -> stringResource(R.string.start_virtual_machine_message)
            else -> stringResource(R.string.shutdown_virtual_machine_message)
        }
        VirtualMachineLifecycleOperation.DELETE_MACHINE ->
            stringResource(R.string.delete_virtual_machine_message)
        VirtualMachineLifecycleOperation.DELETE_IMAGE -> stringResource(R.string.delete_image_message)
        VirtualMachineLifecycleOperation.DELETE_NETWORK -> stringResource(R.string.delete_network_message)
        VirtualMachineLifecycleOperation.RENAME_NETWORK ->
            stringResource(R.string.rename_virtual_machine_network_message, command)
    }
    val confirm = when (target.operation) {
        VirtualMachineLifecycleOperation.CONTROL -> when (command) {
            "poweron" -> stringResource(R.string.start)
            else -> stringResource(R.string.normal_shutdown)
        }
        VirtualMachineLifecycleOperation.RENAME_NETWORK -> stringResource(R.string.save)
        else -> stringResource(R.string.delete)
    }
    AlertDialog(
        onDismissRequest = { onDismiss() },
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = {
            TextButton(
                onClick = { onConfirm() },
                modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
            ) { Text(confirm) }
        },
        dismissButton = {
            TextButton(
                onClick = { onDismiss() },
                modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
            ) { Text(stringResource(R.string.cancel)) }
        },
    )
}

@Composable
internal fun VirtualMachineTaskCleanupConfirmationDialog(
    taskCount: Int,
    onConfirm: () -> Boolean,
    onDismiss: () -> Boolean,
) {
    AlertDialog(
        onDismissRequest = { onDismiss() },
        title = { Text(stringResource(R.string.virtual_machine_clear_finished_tasks_title)) },
        text = {
            Text(
                pluralStringResource(
                    R.plurals.virtual_machine_clear_finished_tasks_message,
                    taskCount,
                    taskCount,
                ),
            )
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm() },
                modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
            ) { Text(stringResource(R.string.virtual_machine_clear_finished_tasks)) }
        },
        dismissButton = {
            TextButton(
                onClick = { onDismiss() },
                modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
            ) { Text(stringResource(R.string.cancel)) }
        },
    )
}

@StringRes
private fun VirtualMachineMutationKind?.feedbackTitle(): Int = when (this) {
    VirtualMachineMutationKind.CREATION -> R.string.create_virtual_machine
    VirtualMachineMutationKind.IMAGE_IMPORT -> R.string.virtual_machine_image_import_title
    VirtualMachineMutationKind.TASK_CLEANUP -> R.string.virtual_machine_task_cleanup_feedback_title
    VirtualMachineMutationKind.SETTINGS -> R.string.edit_virtual_machine
    VirtualMachineMutationKind.LIFECYCLE -> R.string.virtual_machine_action
    null -> R.string.virtual_machines
}

@StringRes
private fun VirtualMachineMutationVerification.messageResource(): Int = when (this) {
    VirtualMachineMutationVerification.MATCHES -> R.string.virtual_machine_feedback_refresh_matches
    VirtualMachineMutationVerification.DIFFERS -> R.string.virtual_machine_feedback_refresh_differs
    VirtualMachineMutationVerification.DISAPPEARED -> R.string.virtual_machine_feedback_refresh_disappeared
    VirtualMachineMutationVerification.UNAVAILABLE -> R.string.virtual_machine_feedback_refresh_unavailable
}
