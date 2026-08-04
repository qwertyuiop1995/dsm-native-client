package io.github.qwertyuiop1995.dsmnativeclient.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.github.qwertyuiop1995.dsmnativeclient.AppViewModel
import io.github.qwertyuiop1995.dsmnativeclient.FileCopyMoveOperation
import io.github.qwertyuiop1995.dsmnativeclient.FileStationMutationOperation
import io.github.qwertyuiop1995.dsmnativeclient.Loadable
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.WorkspaceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.localization.localize

@Composable
internal fun FileCopyMoveDialog(state: WorkspaceState, model: AppViewModel) {
    val operation = state.fileCopyMove ?: return
    val mutation = state.fileStationMutationState
    val isCopy = operation.operation == FileCopyMoveOperation.COPY
    val destinationTitle = operation.location.path.substringAfterLast('/').ifBlank {
        stringResource(R.string.shared_folders)
    }
    val sameFolder = operation.items.any {
        it.path.substringBeforeLast('/', "") == operation.location.path
    }

    Dialog(
        onDismissRequest = model::cancelFileCopyMove,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(
                Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .navigationBarsPadding(),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(
                        onClick = model::cancelFileCopyMove,
                        enabled = !state.isPerformingAction,
                        modifier = Modifier.size(48.dp),
                    ) {
                        Icon(Icons.Outlined.Close, stringResource(R.string.close))
                    }
                    Column(Modifier.weight(1f).padding(horizontal = 8.dp)) {
                        Text(
                            stringResource(
                                if (isCopy) R.string.copy_selected_items else R.string.move_selected_items,
                            ),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            stringResource(R.string.items_selected_count, operation.items.size),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
                HorizontalDivider()
                Row(
                    modifier = Modifier.fillMaxWidth().padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(
                        onClick = model::goBackFileCopyMoveFolder,
                        enabled = operation.history.isNotEmpty() && !state.isPerformingAction,
                        modifier = Modifier.size(48.dp),
                    ) {
                        Icon(
                            Icons.AutoMirrored.Outlined.ArrowBack,
                            stringResource(R.string.photo_folder_up),
                        )
                    }
                    Column(Modifier.weight(1f)) {
                        Text(
                            stringResource(R.string.move_destination),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            destinationTitle,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    when (val folders = state.fileCopyMoveFolders) {
                        Loadable.Idle, Loadable.Loading ->
                            CircularProgressIndicator(Modifier.align(Alignment.Center))
                        is Loadable.Failed -> FileDestinationFailure(
                            folders,
                            model::retryFileCopyMoveFolders,
                        )
                        is Loadable.Ready -> {
                            val paths = operation.items.map(FileItem::path)
                            val available = folders.value.items.filter { folder ->
                                folder.isDirectory && paths.none { source ->
                                    folder.path == source || folder.path.startsWith("$source/")
                                }
                            }
                            if (available.isEmpty()) {
                                EmptyState(
                                    stringResource(R.string.no_subfolders),
                                    stringResource(R.string.move_here_description),
                                    Icons.Outlined.FolderOpen,
                                )
                            } else {
                                LazyColumn(Modifier.fillMaxSize()) {
                                    items(available, key = FileItem::path) { folder ->
                                        ListItem(
                                            headlineContent = {
                                                Text(
                                                    folder.name,
                                                    maxLines = 1,
                                                    overflow = TextOverflow.Ellipsis,
                                                )
                                            },
                                            supportingContent = if (folder.canWrite) null else {
                                                { Text(stringResource(R.string.folder_read_only)) }
                                            },
                                            leadingContent = {
                                                Icon(Icons.Outlined.Folder, contentDescription = null)
                                            },
                                            trailingContent = {
                                                TextButton(
                                                    onClick = { model.openFileCopyMoveFolder(folder) },
                                                    modifier = Modifier.heightIn(min = 48.dp),
                                                ) {
                                                    Text(stringResource(R.string.open))
                                                }
                                            },
                                        )
                                        HorizontalDivider()
                                    }
                                }
                            }
                        }
                    }
                }
                if (operation.location.path.isNotBlank() && !operation.location.canWrite) {
                    Text(
                        stringResource(R.string.photo_move_destination_read_only),
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                if (state.isPerformingAction) LinearProgressIndicator(Modifier.fillMaxWidth())
                HorizontalDivider()
                Row(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TextButton(
                        onClick = model::cancelFileCopyMove,
                        enabled = !state.isPerformingAction,
                        modifier = Modifier.heightIn(min = 48.dp),
                    ) {
                        Text(stringResource(R.string.cancel))
                    }
                    Button(
                        onClick = { model.requestFileCopyMoveConfirmation() },
                        enabled = operation.location.path.isNotBlank() && operation.location.canWrite &&
                            !sameFolder && !state.isPerformingAction && !mutation.confirmationRequested,
                        modifier = Modifier.padding(start = 8.dp).heightIn(min = 48.dp),
                    ) {
                        Text(stringResource(if (isCopy) R.string.copy_here else R.string.move_here))
                    }
                }
            }
        }
    }

    val confirmationTarget = mutation.draftTarget?.takeIf { target ->
        mutation.confirmationRequested && target.operation in setOf(
            FileStationMutationOperation.COPY,
            FileStationMutationOperation.MOVE,
        )
    }
    confirmationTarget?.let { target ->
        FileStationMutationConfirmationDialog(
            target = target,
            onConfirm = model::confirmFileCopyMove,
            onDismiss = model::cancelPendingFileStationMutation,
        )
    }
}

@Composable
private fun FileDestinationFailure(failure: Loadable.Failed, onRetry: () -> Unit) {
    val localized = failure.error.localize(LocalContext.current)
    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            Icons.Outlined.ErrorOutline,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.error,
        )
        Text(
            localized.message,
            modifier = Modifier.padding(top = 16.dp),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            localized.recovery,
            modifier = Modifier.padding(top = 8.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Button(
            onClick = onRetry,
            modifier = Modifier.padding(top = 20.dp).heightIn(min = 48.dp),
        ) {
            Text(stringResource(R.string.retry))
        }
    }
}
