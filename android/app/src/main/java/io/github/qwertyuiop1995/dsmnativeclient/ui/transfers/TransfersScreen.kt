package io.github.qwertyuiop1995.dsmnativeclient.ui.transfers

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.FilterChip
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material.icons.outlined.UploadFile
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.AppViewModel
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.WorkspaceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferDirection
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import io.github.qwertyuiop1995.dsmnativeclient.ui.EmptyState
import io.github.qwertyuiop1995.dsmnativeclient.ui.formatBytes
import io.github.qwertyuiop1995.dsmnativeclient.ui.formatRemainingDuration

internal enum class TransferSourceFilter {
    ALL,
    DOWNLOADS,
    UPLOADS,
    NAS_TASKS,
}

internal fun TransferSourceFilter.matches(direction: TransferDirection): Boolean = when (this) {
    TransferSourceFilter.ALL -> true
    TransferSourceFilter.DOWNLOADS -> direction == TransferDirection.DOWNLOAD
    TransferSourceFilter.UPLOADS -> direction == TransferDirection.UPLOAD
    TransferSourceFilter.NAS_TASKS -> direction == TransferDirection.SERVER
}

@Composable
internal fun TransfersScreen(state: WorkspaceState, model: AppViewModel) {
    if (state.transfers.isEmpty()) {
        EmptyState(
            stringResource(R.string.no_transfer_tasks),
            stringResource(R.string.transfers_description),
            Icons.Outlined.SwapVert,
        )
        return
    }

    var sourceFilter by rememberSaveable(state.profile.id) {
        mutableStateOf(TransferSourceFilter.ALL)
    }
    val filteredTransfers = state.transfers.filter { sourceFilter.matches(it.direction) }

    Column(Modifier.fillMaxSize()) {
        Text(
            stringResource(R.string.transfer_filter_source),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 16.dp, top = 12.dp),
        )
        LazyRow(
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(TransferSourceFilter.entries, key = TransferSourceFilter::name) { filter ->
                FilterChip(
                    selected = sourceFilter == filter,
                    onClick = { sourceFilter = filter },
                    label = { Text(stringResource(filter.labelResource())) },
                )
            }
        }
        if (state.transfers.any {
                it.state in setOf(
                    TransferState.SUCCEEDED,
                    TransferState.FAILED,
                    TransferState.CANCELLED,
                )
            }) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                TextButton(onClick = model::clearFinishedTransfers) {
                    Text(stringResource(R.string.clear_finished_transfers))
                }
            }
        }
        if (filteredTransfers.isEmpty()) {
            Box(
                modifier = Modifier.weight(1f).fillMaxWidth(),
            ) {
                EmptyState(
                    stringResource(R.string.no_filtered_transfer_tasks),
                    stringResource(R.string.no_filtered_transfer_tasks_description),
                    Icons.Outlined.SwapVert,
                )
            }
            return@Column
        }
        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(filteredTransfers, key = { it.id }) { task ->
                Card {
                    ListItem(
                        headlineContent = {
                            Text(task.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        },
                        supportingContent = {
                            TransferTaskDetails(task)
                        },
                        leadingContent = {
                            Icon(
                                when (task.state) {
                                    TransferState.SUCCEEDED -> Icons.Outlined.CheckCircle
                                    TransferState.FAILED -> Icons.Outlined.ErrorOutline
                                    TransferState.CANCELLED -> Icons.Outlined.Info
                                    else -> when (task.direction) {
                                        TransferDirection.DOWNLOAD -> Icons.Outlined.Download
                                        TransferDirection.UPLOAD -> Icons.Outlined.UploadFile
                                        TransferDirection.SERVER -> Icons.Outlined.SwapVert
                                    }
                                },
                                contentDescription = null,
                                tint = when (task.state) {
                                    TransferState.SUCCEEDED -> MaterialTheme.colorScheme.primary
                                    TransferState.FAILED -> MaterialTheme.colorScheme.error
                                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                                },
                            )
                        },
                        trailingContent = {
                            TransferActions(
                                state = task.state,
                                direction = task.direction,
                                canPause = model.canPauseTransfer(task.id),
                                canResume = model.canResumeTransfer(task.id),
                                canRetry = model.canRetryTransfer(task.id),
                                onPause = { model.pauseTransfer(task.id) },
                                onResume = { model.resumeTransfer(task.id) },
                                onCancel = { model.cancelTransfer(task.id) },
                                onRetry = { model.retryTransfer(task.id) },
                            )
                        },
                    )
                }
            }
        }
    }
}

@Composable
internal fun TransferTaskDetails(
    task: io.github.qwertyuiop1995.dsmnativeclient.domain.TransferTask,
    nowEpochMillis: Long = System.currentTimeMillis(),
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            task.detail,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        val transferProgress = task.progress
        val isActive = task.state in setOf(
            TransferState.WAITING,
            TransferState.RUNNING,
            TransferState.CANCELLING,
        )
        val shouldShowProgress = isActive || task.direction != TransferDirection.SERVER
        if (shouldShowProgress) {
            if (transferProgress != null) {
                LinearProgressIndicator(
                    progress = { transferProgress },
                    modifier = Modifier.fillMaxWidth(),
                )
            } else if (isActive) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            }
        }
        if (task.direction == TransferDirection.SERVER) {
            transferProgress?.takeIf { isActive }?.let { progress ->
                Text(
                    stringResource(
                        R.string.nas_task_percent_progress,
                        (progress * 100).toInt().coerceIn(0, 100),
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            Text(
                stringResource(
                    R.string.transfer_bytes_progress,
                    formatBytes(task.completedBytes),
                    task.totalBytes?.let(::formatBytes)
                        ?: stringResource(R.string.unknown_size),
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (task.state == TransferState.RUNNING) {
                task.speedBytesPerSecond(nowEpochMillis)?.let { speed ->
                    val remaining = task.estimatedRemainingSeconds(nowEpochMillis)
                    Text(
                        if (remaining == null) {
                            stringResource(R.string.transfer_speed, formatBytes(speed))
                        } else {
                            stringResource(
                                R.string.transfer_speed_remaining,
                                formatBytes(speed),
                                formatRemainingDuration(remaining),
                            )
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        task.errorMessage?.let { message ->
            Text(
                message,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        if (task.requiresRefresh) {
            Text(
                stringResource(
                    if (task.direction == TransferDirection.SERVER) {
                        R.string.nas_task_refresh_before_retry
                    } else {
                        R.string.transfer_refresh_before_retry
                    },
                ),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@androidx.annotation.StringRes
private fun TransferSourceFilter.labelResource(): Int = when (this) {
    TransferSourceFilter.ALL -> R.string.transfer_filter_all
    TransferSourceFilter.DOWNLOADS -> R.string.transfer_filter_downloads
    TransferSourceFilter.UPLOADS -> R.string.transfer_filter_uploads
    TransferSourceFilter.NAS_TASKS -> R.string.transfer_filter_nas_tasks
}

@Composable
internal fun TransferActions(
    state: TransferState,
    direction: TransferDirection,
    canPause: Boolean,
    canResume: Boolean,
    canRetry: Boolean,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onCancel: () -> Unit,
    onRetry: () -> Unit,
) {
    when {
        state == TransferState.CANCELLING -> Text(
            stringResource(R.string.transfer_cancelling),
            style = MaterialTheme.typography.labelMedium,
        )

        canResume -> Column(horizontalAlignment = Alignment.End) {
            TextButton(onClick = onResume) {
                Text(stringResource(R.string.resume_download))
            }
            TextButton(onClick = onCancel) {
                Text(stringResource(R.string.cancel))
            }
        }

        canPause -> TextButton(onClick = onPause) {
            Text(stringResource(R.string.pause_download))
        }

        canRetry -> TextButton(onClick = onRetry) {
            Text(
                stringResource(
                    if (direction == TransferDirection.DOWNLOAD) {
                        R.string.resume_download
                    } else {
                        R.string.retry_from_start
                    },
                ),
            )
        }

        state in setOf(TransferState.WAITING, TransferState.RUNNING, TransferState.PAUSED) -> {
            TextButton(onClick = onCancel) {
                Text(stringResource(R.string.cancel))
            }
        }
    }
}
