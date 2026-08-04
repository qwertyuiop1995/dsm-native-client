package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.NetworkCheck
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.AppViewModel
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.ActiveConnection
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.localization.localize
import io.github.qwertyuiop1995.dsmnativeclient.ui.ConfirmDialog

@Composable
internal fun NasConnectionScreen(
    connections: List<ActiveConnection>,
    connectionsAvailable: Boolean,
    target: ActiveConnection?,
    mutationResult: MutationResult?,
    mutationFailure: DsmFailure?,
    refreshFailure: DsmFailure?,
    mutationInProgress: Boolean,
    refreshInProgress: Boolean,
    refreshCompleted: Boolean,
    isPerformingAction: Boolean,
    model: AppViewModel,
) = NasConnectionContent(
    connections = connections,
    connectionsAvailable = connectionsAvailable,
    target = target,
    mutationResult = mutationResult,
    mutationFailure = mutationFailure,
    refreshFailure = refreshFailure,
    mutationInProgress = mutationInProgress,
    refreshInProgress = refreshInProgress,
    refreshCompleted = refreshCompleted,
    isPerformingAction = isPerformingAction,
    onRequestDisconnect = model::requestConnectionDisconnect,
    onCancelRequest = model::cancelConnectionDisconnectRequest,
    onConfirmRequest = model::confirmConnectionDisconnect,
    onRefreshMutation = model::refreshConnectionMutation,
    onDismissResult = model::dismissConnectionMutationResult,
    onRefreshList = { model.load(Module.NAS_SETTINGS) },
)

@Composable
internal fun NasConnectionContent(
    connections: List<ActiveConnection>,
    connectionsAvailable: Boolean,
    target: ActiveConnection?,
    mutationResult: MutationResult?,
    mutationFailure: DsmFailure?,
    refreshFailure: DsmFailure?,
    mutationInProgress: Boolean,
    refreshInProgress: Boolean = false,
    refreshCompleted: Boolean,
    isPerformingAction: Boolean,
    onRequestDisconnect: (ActiveConnection) -> Boolean,
    onCancelRequest: () -> Unit,
    onConfirmRequest: () -> Boolean,
    onRefreshMutation: () -> Unit,
    onDismissResult: () -> Unit,
    onRefreshList: () -> Unit,
) {
    val targetStillPresent = target?.let { selected -> connections.any { it.id == selected.id } }
    LazyColumn {
        if (mutationInProgress) {
            item { ConnectionSavingCard(target) }
        } else if (mutationResult != null && target != null) {
            item {
                ConnectionMutationFeedbackCard(
                    target = target,
                    result = mutationResult,
                    refreshCompleted = refreshCompleted,
                    targetStillPresent = targetStillPresent == true,
                    refreshFailure = refreshFailure,
                    refreshInProgress = refreshInProgress,
                    onRefresh = onRefreshMutation,
                    onDismiss = onDismissResult,
                )
            }
        } else if (mutationFailure != null && target != null) {
            item {
                ConnectionMutationFailureCard(
                    target = target,
                    failure = mutationFailure,
                    onDismiss = onDismissResult,
                )
            }
        }

        if (!connectionsAvailable || connections.isEmpty()) {
            item {
                Column(
                    Modifier.fillMaxWidth().padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        stringResource(
                            if (connectionsAvailable) R.string.no_active_connections
                            else R.string.connections_unavailable,
                        ),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        stringResource(
                            if (connectionsAvailable) R.string.no_active_connections_hint
                            else R.string.connections_unavailable_hint,
                        ),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    TextButton(
                        onClick = onRefreshList,
                        enabled = !isPerformingAction,
                    ) {
                        Text(stringResource(R.string.refresh_connections))
                    }
                }
            }
        } else {
            items(connections, key = { it.id }) { connection ->
                ConnectionListItem(
                    connection = connection,
                    enabled = connection.canDisconnect && !isPerformingAction && target == null &&
                        mutationResult == null && mutationFailure == null,
                    onDisconnect = { onRequestDisconnect(connection) },
                )
                HorizontalDivider(Modifier.padding(start = 72.dp))
            }
        }
    }

    if (target != null && !mutationInProgress && mutationResult == null && mutationFailure == null) {
        val webConnection = target.type.equals("HTTP/HTTPS", ignoreCase = true)
        val targetSummary = connectionTargetSummary(target)
        val impact = stringResource(
            when {
                target.isCurrent -> R.string.disconnect_current_connection_message
                webConnection -> R.string.disconnect_web_connection_message
                else -> R.string.disconnect_service_connection_message
            },
        )
        ConfirmDialog(
            title = stringResource(
                if (target.isCurrent) R.string.disconnect_current_connection_title
                else R.string.disconnect_connection_title,
            ),
            message = stringResource(R.string.connection_confirmation_message, targetSummary, impact),
            confirm = stringResource(
                if (target.isCurrent) R.string.disconnect_current_connection
                else R.string.disconnect_connection,
            ),
            destructive = true,
            onConfirm = { onConfirmRequest() },
            onDismiss = onCancelRequest,
        )
    }
}

@Composable
internal fun ConnectionListItem(
    connection: ActiveConnection,
    enabled: Boolean,
    onDisconnect: () -> Unit,
) {
    val targetDescription = stringResource(
        R.string.disconnect_connection_accessibility,
        connection.user.ifBlank { stringResource(R.string.unknown_account) },
        connection.client.ifBlank { stringResource(R.string.unknown_device) },
        if (connection.type.equals("HTTP/HTTPS", ignoreCase = true)) {
            stringResource(R.string.web_connection)
        } else {
            stringResource(R.string.service_connection, connection.service)
        },
    )
    ListItem(
        headlineContent = {
            Text(
                stringResource(
                    R.string.connection_account_and_service,
                    connection.user.ifBlank { stringResource(R.string.unknown_account) },
                    connection.service,
                ),
            )
        },
        supportingContent = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(connection.client.ifBlank { stringResource(R.string.unknown_device) })
                when {
                    connection.isCurrent -> Text(stringResource(R.string.current_connection))
                    !connection.canDisconnect -> Text(stringResource(R.string.connection_cannot_disconnect))
                }
            }
        },
        leadingContent = { Icon(Icons.Outlined.NetworkCheck, null) },
        trailingContent = if (connection.canDisconnect) {
            {
                TextButton(
                    onClick = onDisconnect,
                    enabled = enabled,
                    modifier = Modifier.heightIn(min = 48.dp).semantics {
                        role = Role.Button
                        contentDescription = targetDescription
                    },
                ) {
                    Text(stringResource(R.string.disconnect_connection))
                }
            }
        } else {
            null
        },
    )
}

internal data class ConnectionFeedbackPolicy(
    @StringRes val title: Int,
    @StringRes val message: Int,
    val canRefresh: Boolean,
    val mustRefreshBeforeDismiss: Boolean,
    val isAssertive: Boolean,
)

internal fun connectionFeedbackPolicy(result: MutationResult): ConnectionFeedbackPolicy {
    require(result.operation == "connectionDisconnect") { "connection.unexpected-operation" }
    val submittedOrConflict = result.submitted || result.requiresRefresh ||
        result.errorCategory == MutationErrorCategory.CONFLICT
    return when (result.status) {
        MutationResultStatus.CONFIRMED_SUCCESS -> ConnectionFeedbackPolicy(
            R.string.connection_feedback_disconnected_title,
            R.string.connection_feedback_disconnected_message,
            canRefresh = false,
            mustRefreshBeforeDismiss = false,
            isAssertive = false,
        )
        MutationResultStatus.PARTIAL_SUCCESS -> ConnectionFeedbackPolicy(
            R.string.connection_feedback_check_title,
            R.string.connection_feedback_partial_message,
            canRefresh = true,
            mustRefreshBeforeDismiss = true,
            isAssertive = true,
        )
        MutationResultStatus.SUBMITTED_BUT_UNVERIFIED -> ConnectionFeedbackPolicy(
            R.string.connection_feedback_check_title,
            R.string.connection_feedback_unverified_message,
            canRefresh = true,
            mustRefreshBeforeDismiss = true,
            isAssertive = true,
        )
        MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION -> ConnectionFeedbackPolicy(
            R.string.connection_feedback_check_title,
            R.string.connection_feedback_cancel_after_submission,
            canRefresh = true,
            mustRefreshBeforeDismiss = true,
            isAssertive = true,
        )
        MutationResultStatus.PERMISSION_DENIED -> ConnectionFeedbackPolicy(
            R.string.connection_feedback_permission_title,
            R.string.connection_feedback_permission_message,
            canRefresh = submittedOrConflict,
            mustRefreshBeforeDismiss = submittedOrConflict,
            isAssertive = true,
        )
        MutationResultStatus.UNSUPPORTED -> ConnectionFeedbackPolicy(
            R.string.connection_feedback_unavailable_title,
            R.string.connection_feedback_unsupported_message,
            canRefresh = submittedOrConflict,
            mustRefreshBeforeDismiss = submittedOrConflict,
            isAssertive = true,
        )
        MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> ConnectionFeedbackPolicy(
            R.string.connection_feedback_cancelled_title,
            R.string.connection_feedback_cancelled_message,
            canRefresh = false,
            mustRefreshBeforeDismiss = false,
            isAssertive = false,
        )
        MutationResultStatus.CONFIRMED_FAILURE -> ConnectionFeedbackPolicy(
            if (result.errorCategory == MutationErrorCategory.CONFLICT) {
                R.string.connection_feedback_conflict_title
            } else {
                R.string.connection_feedback_failed_title
            },
            if (result.errorCategory == MutationErrorCategory.CONFLICT) {
                R.string.connection_feedback_conflict_message
            } else {
                R.string.connection_feedback_failed_message
            },
            canRefresh = submittedOrConflict,
            mustRefreshBeforeDismiss = submittedOrConflict,
            isAssertive = true,
        )
    }
}

@Composable
internal fun ConnectionSavingCard(target: ActiveConnection?) {
    FeedbackCard(liveRegion = LiveRegionMode.Polite, isError = false) {
        Text(stringResource(R.string.connection_disconnecting_title), style = MaterialTheme.typography.titleMedium)
        target?.let { Text(connectionTargetSummary(it)) }
        Text(stringResource(R.string.connection_disconnecting_message))
        LinearProgressIndicator(Modifier.fillMaxWidth())
    }
}

@Composable
internal fun ConnectionMutationFeedbackCard(
    target: ActiveConnection,
    result: MutationResult,
    refreshCompleted: Boolean,
    targetStillPresent: Boolean,
    refreshFailure: DsmFailure?,
    refreshInProgress: Boolean = false,
    onRefresh: () -> Unit,
    onDismiss: () -> Unit,
) {
    val policy = connectionFeedbackPolicy(result)
    FeedbackCard(
        liveRegion = if (policy.isAssertive) LiveRegionMode.Assertive else LiveRegionMode.Polite,
        isError = result.status == MutationResultStatus.PERMISSION_DENIED ||
            result.status == MutationResultStatus.CONFIRMED_FAILURE,
    ) {
        Text(stringResource(policy.title), style = MaterialTheme.typography.titleMedium)
        Text(connectionTargetSummary(target))
        Text(stringResource(policy.message))
        if (target.isCurrent) {
            Text(stringResource(R.string.connection_feedback_current_recovery))
        }
        val counts = result.counts
        if (counts.succeeded + counts.failed + counts.unknown > 0) {
            Text(
                stringResource(
                    R.string.connection_feedback_counts,
                    counts.succeeded,
                    counts.failed,
                    counts.unknown,
                ),
                style = MaterialTheme.typography.bodySmall,
            )
        }
        if (refreshCompleted) {
            Text(
                stringResource(
                    if (targetStillPresent) R.string.connection_refresh_still_present
                    else R.string.connection_refresh_target_absent,
                ),
                style = MaterialTheme.typography.bodySmall,
            )
        }
        refreshFailure?.let { Text(it.localize(LocalContext.current).combined) }
        if (refreshInProgress) {
            Text(stringResource(R.string.refreshing_connection), style = MaterialTheme.typography.bodySmall)
            LinearProgressIndicator(Modifier.fillMaxWidth())
        }
        if (policy.canRefresh) {
            TextButton(
                onClick = onRefresh,
                enabled = !refreshInProgress,
                modifier = Modifier.align(Alignment.End),
            ) {
                Text(stringResource(R.string.refresh_and_check_connection))
            }
        }
        TextButton(
            onClick = onDismiss,
            enabled = !refreshInProgress &&
                (!policy.mustRefreshBeforeDismiss || refreshCompleted),
            modifier = Modifier.align(Alignment.End),
        ) {
            Text(stringResource(R.string.done))
        }
    }
}

@Composable
internal fun ConnectionMutationFailureCard(
    target: ActiveConnection,
    failure: DsmFailure,
    onDismiss: () -> Unit,
) {
    FeedbackCard(liveRegion = LiveRegionMode.Assertive, isError = true) {
        Text(stringResource(R.string.connection_feedback_failed_title), style = MaterialTheme.typography.titleMedium)
        Text(connectionTargetSummary(target))
        Text(failure.localize(LocalContext.current).combined)
        if (target.isCurrent) Text(stringResource(R.string.connection_feedback_current_recovery))
        TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
            Text(stringResource(R.string.done))
        }
    }
}

@Composable
private fun FeedbackCard(
    liveRegion: LiveRegionMode,
    isError: Boolean,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(16.dp).semantics { this.liveRegion = liveRegion },
        colors = CardDefaults.cardColors(
            containerColor = if (isError) MaterialTheme.colorScheme.errorContainer
            else MaterialTheme.colorScheme.secondaryContainer,
        ),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            content = content,
        )
    }
}

@Composable
private fun connectionTargetSummary(connection: ActiveConnection): String = stringResource(
    R.string.connection_target_summary,
    connection.user.ifBlank { stringResource(R.string.unknown_account) },
    connection.client.ifBlank { stringResource(R.string.unknown_device) },
    if (connection.type.equals("HTTP/HTTPS", ignoreCase = true)) {
        stringResource(R.string.web_connection)
    } else {
        stringResource(R.string.service_connection, connection.service)
    },
)
