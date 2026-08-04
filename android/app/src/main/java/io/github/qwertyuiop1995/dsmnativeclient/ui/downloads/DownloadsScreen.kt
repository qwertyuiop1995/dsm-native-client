package io.github.qwertyuiop1995.dsmnativeclient.ui.downloads

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.UploadFile
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.AppViewModel
import io.github.qwertyuiop1995.dsmnativeclient.DownloadControlOperation
import io.github.qwertyuiop1995.dsmnativeclient.DownloadCreationSourceKind
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.WorkspaceState
import io.github.qwertyuiop1995.dsmnativeclient.canStartDownloadCreation
import io.github.qwertyuiop1995.dsmnativeclient.downloadCreationRequiresRefreshBeforeDismiss
import io.github.qwertyuiop1995.dsmnativeclient.downloadControlRequiresRefreshBeforeDismiss
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.ui.AdaptiveLayoutPolicy
import io.github.qwertyuiop1995.dsmnativeclient.ui.DownloadDestinationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.DownloadSettingsDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.EmptyState
import io.github.qwertyuiop1995.dsmnativeclient.ui.LoadableContent
import io.github.qwertyuiop1995.dsmnativeclient.ui.StatusIcon
import io.github.qwertyuiop1995.dsmnativeclient.ui.displayName

@Composable
internal fun DownloadsScreen(state: WorkspaceState, model: AppViewModel) {
    var selected by remember { mutableStateOf<DownloadTask?>(null) }
    var showDiscovery by rememberSaveable { mutableStateOf(false) }
    var settingsUnavailable by rememberSaveable { mutableStateOf(false) }
    val taskFileLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument(),
    ) { uri ->
        uri?.let {
            if (!model.createDownloadFromFile(it)) model.openDownloadCreationEditor()
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val expandedLayout = AdaptiveLayoutPolicy.usesDownloadListDetail(maxWidth.value)
        val downloadControl = state.downloadControlState
        val downloadCreation = state.downloadCreationState
        val settingsState = state.downloadSettingsState
        val settingsIdle = !settingsState.editorVisible && !settingsState.mutationInProgress &&
            !settingsState.mutationRefreshInProgress && settingsState.mutationResult == null &&
            settingsState.mutationFailure == null
        val downloadActionsEnabled = !state.isPerformingAction && downloadControl.target == null &&
            downloadCreation.target == null && settingsIdle
        val creationActionsEnabled = downloadControl.target == null &&
            canStartDownloadCreation(state.isPerformingAction, downloadCreation) &&
            downloadCreation.pendingDiscoveryUri == null && settingsIdle
        val settingsActionsEnabled = creationActionsEnabled
    Scaffold(
        contentWindowInsets = WindowInsets(0),
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { if (creationActionsEnabled) model.openDownloadCreationEditor() },
                icon = { Icon(Icons.Outlined.Add, null) },
                text = { Text(stringResource(R.string.add_download)) },
                modifier = Modifier
                    .alpha(if (creationActionsEnabled) 1f else 0.38f)
                    .then(if (creationActionsEnabled) Modifier else Modifier.semantics { disabled() }),
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                if (state.supportsDownloadRss || state.supportsDownloadBtSearch) {
                    TextButton(
                        enabled = creationActionsEnabled,
                        onClick = {
                            showDiscovery = true
                            if (state.supportsDownloadRss) model.loadDownloadRssSites()
                        },
                    ) {
                        Icon(Icons.Outlined.Search, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.download_discovery))
                    }
                }
                TextButton(
                    enabled = settingsActionsEnabled,
                    onClick = {
                        if (state.supportsDownloadSettings) {
                            model.openDownloadSettings()
                        } else {
                            settingsUnavailable = true
                        }
                    },
                ) {
                    Icon(Icons.Outlined.Tune, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.download_settings_title))
                }
            }
            if (downloadControl.mutationResult != null || downloadControl.mutationFailure != null) {
                DownloadControlMutationFeedbackCard(
                    result = downloadControl.mutationResult,
                    failure = downloadControl.mutationFailure,
                    refreshFailure = downloadControl.mutationRefreshFailure,
                    refreshInProgress = downloadControl.mutationRefreshInProgress,
                    refreshCompleted = downloadControl.mutationRefreshCompleted,
                    mustRefresh = downloadControlRequiresRefreshBeforeDismiss(downloadControl),
                    currentMatches = downloadControl.mutationRefreshMatches,
                    deleteFiles = downloadControl.target?.operation ==
                        DownloadControlOperation.DELETE_TASK_AND_FILES,
                    onRefresh = model::refreshDownloadControlMutation,
                    onDismiss = { model.dismissDownloadControlMutation() },
                )
            }
            if (
                downloadCreation.target != null || downloadCreation.mutationInProgress ||
                downloadCreation.mutationResult != null || downloadCreation.mutationFailure != null
            ) {
                DownloadCreationMutationFeedbackCard(
                    state = downloadCreation,
                    mustRefresh = downloadCreationRequiresRefreshBeforeDismiss(downloadCreation),
                    onRefresh = model::refreshDownloadCreationMutation,
                    onDismiss = { model.dismissDownloadCreationMutation() },
                    onEdit = { model.editDownloadCreationAfterResult() },
                )
            }
            Box(Modifier.weight(1f).fillMaxWidth()) {
                if (expandedLayout) {
                    Row(Modifier.fillMaxSize()) {
                        DownloadTaskList(
                            state = state,
                            model = model,
                            expanded = true,
                            selectedTaskId = state.downloadDetailsTask?.id,
                            actionsEnabled = downloadActionsEnabled,
                            onTaskActions = { selected = it },
                            modifier = Modifier.weight(0.42f).fillMaxSize(),
                        )
                        VerticalDivider()
                        val detail = state.downloadDetailsTask
                        if (detail == null) {
                            Box(Modifier.weight(0.58f).fillMaxSize()) {
                                EmptyState(
                                    title = stringResource(R.string.download_select_task),
                                    message = stringResource(R.string.download_select_task_description),
                                    icon = Icons.Outlined.Download,
                                )
                            }
                        } else {
                            DownloadTaskDetailsPane(
                                task = detail,
                                onDismiss = model::closeDownloadTaskDetails,
                                modifier = Modifier
                                    .weight(0.58f)
                                    .fillMaxSize()
                                    .padding(bottom = 88.dp),
                            )
                        }
                    }
                } else {
                    DownloadTaskList(
                        state = state,
                        model = model,
                        expanded = false,
                        selectedTaskId = null,
                        actionsEnabled = downloadActionsEnabled,
                        onTaskActions = { selected = it },
                    )
                }
            }
        }
    }
    if (state.downloadCreationState.editorVisible) {
        DownloadDialog(
            state = state,
            model = model,
            onConfirm = { uri, destination ->
                val sourceKind = if (uri.trim().startsWith("magnet:", ignoreCase = true)) {
                    DownloadCreationSourceKind.MAGNET
                } else {
                    DownloadCreationSourceKind.LINK
                }
                if (model.createDownload(uri, destination, sourceKind)) {
                    model.cancelDownloadDestinationSelection()
                }
            },
            onChooseFile = {
                model.cancelDownloadDestinationSelection()
                taskFileLauncher.launch(
                    arrayOf(
                        "application/x-bittorrent",
                        "application/x-nzb",
                        "text/plain",
                        "application/octet-stream",
                    ),
                )
            },
            onDismiss = {
                if (model.closeDownloadCreationEditor()) {
                    model.cancelDownloadDestinationSelection()
                }
            },
        )
    }
    if (state.downloadSettingsState.editorVisible) {
        DownloadSettingsDialog(
            state = state,
            onRetry = model::loadDownloadSettings,
            onDraftChange = model::updateDownloadSettingsDraft,
            onSave = model::saveDownloadSettings,
            onRefreshMutation = model::refreshDownloadSettingsMutation,
            onDismissMutation = model::dismissDownloadSettingsMutation,
            onDismiss = model::closeDownloadSettings,
        )
    }
    if (showDiscovery) {
        DownloadDiscoveryDialog(
            state = state,
            model = model,
            canCreateTask = creationActionsEnabled,
            onCreateTask = { title, uri, sourceKind ->
                if (model.beginDiscoveryDownloadCreation(title, uri, sourceKind)) {
                    model.beginDownloadDestinationSelection()
                }
            },
            onDismiss = {
                model.closeDownloadDiscovery()
                showDiscovery = false
            },
        )
    }
    val pendingDiscoveryUri = state.downloadCreationState.pendingDiscoveryUri
    val pendingDiscoverySource = state.downloadCreationState.pendingDiscoverySource
    if (pendingDiscoveryUri != null && pendingDiscoverySource != null) {
        if (state.downloadDestinationPicker != null) {
            DownloadDestinationDialog(
                state = state,
                model = model,
                onSelected = { destination ->
                    if (model.createDownload(pendingDiscoveryUri, destination, pendingDiscoverySource)) {
                        model.cancelDownloadDestinationSelection()
                        model.cancelDiscoveryDownloadCreation()
                    }
                },
                onDismiss = {
                    model.cancelDownloadDestinationSelection()
                    model.cancelDiscoveryDownloadCreation()
                },
            )
        }
    }
    if (settingsUnavailable) {
        AlertDialog(
            onDismissRequest = { settingsUnavailable = false },
            title = { Text(stringResource(R.string.download_settings_unavailable_title)) },
            text = { Text(stringResource(R.string.download_settings_unavailable_message)) },
            confirmButton = {
                TextButton(onClick = { settingsUnavailable = false }) {
                    Text(stringResource(R.string.close))
                }
            },
        )
    }
    selected?.let { task ->
        DownloadTaskActionsDialog(
            taskTitle = task.title.ifBlank { stringResource(R.string.unnamed_download) },
            taskState = task.status,
            enabled = downloadActionsEnabled,
            onDetails = {
                model.openDownloadTaskDetails(task)
                selected = null
            },
            onPause = { if (model.requestDownloadPause(task.id)) selected = null },
            onResume = { if (model.requestDownloadResume(task.id)) selected = null },
            onRemove = { if (model.requestDownloadDeletion(task.id, false)) selected = null },
            onRemoveWithFiles = {
                if (model.requestDownloadDeletion(task.id, true)) selected = null
            },
            onDismiss = { selected = null },
        )
    }
    val showDetailsDialog = state.downloadDetailsTask != null && !expandedLayout
    if (showDetailsDialog) state.downloadDetailsTask?.let { task ->
        DownloadTaskDetailsDialog(task = task, onDismiss = model::closeDownloadTaskDetails)
    }
    downloadControl.target
        ?.takeIf { downloadControl.confirmationRequested }
        ?.let { target ->
        DownloadDeletionConfirmationDialog(
            taskTitle = target.taskBaseline.title.ifBlank {
                stringResource(R.string.unnamed_download)
            },
            deleteFiles = target.operation == DownloadControlOperation.DELETE_TASK_AND_FILES,
            persistentRejection = downloadControl.mutationFailure != null,
            onConfirm = model::confirmDownloadDeletion,
            onDismiss = model::cancelDownloadDeletion,
        )
    }
    }
}

@Composable
private fun DownloadTaskList(
    state: WorkspaceState,
    model: AppViewModel,
    expanded: Boolean,
    selectedTaskId: String?,
    actionsEnabled: Boolean,
    onTaskActions: (DownloadTask) -> Unit,
    modifier: Modifier = Modifier.fillMaxSize(),
) {
    Box(modifier) {
        LoadableContent(
            value = state.downloads,
            emptyTitle = stringResource(R.string.no_download_tasks),
            emptyMessage = stringResource(R.string.add_download_description),
            onRetry = { model.load(Module.DOWNLOADS) },
        ) { tasks ->
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 96.dp),
            ) {
                items(tasks, key = DownloadTask::id) { task ->
                    val isSelected = expanded && selectedTaskId == task.id
                    val rowModifier = Modifier
                        .fillMaxWidth()
                        .then(
                            if (isSelected) {
                                Modifier.background(MaterialTheme.colorScheme.secondaryContainer)
                            } else {
                                Modifier
                            },
                        )
                        .then(
                            if (expanded) {
                                Modifier
                                    .clickable { model.openDownloadTaskDetails(task) }
                                    .semantics { selected = isSelected }
                            } else {
                                Modifier
                            },
                        )
                    ListItem(
                        headlineContent = {
                            Text(
                                task.title.ifBlank { stringResource(R.string.unnamed_download) },
                                maxLines = if (expanded) 2 else 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        },
                        supportingContent = {
                            Column {
                                Text(task.status.displayName())
                                val total = task.size
                                val transferred = task.transferred
                                if (total != null && total > 0 && transferred != null) {
                                    LinearProgressIndicator(
                                        progress = {
                                            (transferred.toFloat() / total.toFloat()).coerceIn(0f, 1f)
                                        },
                                        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                                    )
                                }
                            }
                        },
                        leadingContent = { StatusIcon(task.status) },
                        trailingContent = {
                            val taskTitle = task.title.ifBlank {
                                stringResource(R.string.unnamed_download)
                            }
                            IconButton(
                                enabled = actionsEnabled,
                                onClick = { onTaskActions(task) },
                            ) {
                                Icon(
                                    Icons.Outlined.MoreVert,
                                    contentDescription = stringResource(
                                        R.string.download_task_action_description,
                                        stringResource(R.string.task_actions),
                                        taskTitle,
                                    ),
                                )
                            }
                        },
                        colors = androidx.compose.material3.ListItemDefaults.colors(
                            containerColor = androidx.compose.ui.graphics.Color.Transparent,
                        ),
                        modifier = rowModifier,
                    )
                    HorizontalDivider(Modifier.padding(start = 72.dp))
                }
            }
        }
    }
}

@Composable
private fun DownloadDialog(
    state: WorkspaceState,
    model: AppViewModel,
    onConfirm: (String, String?) -> Unit,
    onChooseFile: () -> Unit,
    onDismiss: () -> Unit,
) {
    val creation = state.downloadCreationState
    val uri = creation.uriDraft
    val destination = creation.destinationDraft
    AlertDialog(
        onDismissRequest = onDismiss,
        shape = MaterialTheme.shapes.extraLarge,
        title = { Text(stringResource(R.string.add_download_task), fontWeight = FontWeight.Bold) },
        text = {
            Column(
                modifier = Modifier
                    .heightIn(max = 520.dp)
                    .verticalScroll(rememberScrollState())
                    .imePadding(),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                OutlinedTextField(
                    value = uri,
                    onValueChange = { model.updateDownloadCreationDraft(it, destination) },
                    label = { Text(stringResource(R.string.url_or_magnet)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    minLines = 2,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = destination,
                    onValueChange = { model.updateDownloadCreationDraft(uri, it) },
                    label = { Text(stringResource(R.string.save_to_optional)) },
                    singleLine = true,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.fillMaxWidth(),
                )
                FilledTonalButton(
                    onClick = model::beginDownloadDestinationSelection,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Outlined.FolderOpen, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.browse_nas_folders))
                }
                Button(onClick = onChooseFile, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Outlined.UploadFile, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.choose_download_task_file))
                }
                Text(
                    stringResource(R.string.download_task_file_note),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = {
            Button(
                onClick = { onConfirm(uri, destination.ifBlank { null }) },
                enabled = uri.isNotBlank() && !state.isPerformingAction,
                modifier = Modifier.heightIn(min = 48.dp),
                shape = MaterialTheme.shapes.medium,
            ) { Text(stringResource(R.string.create_task), fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(stringResource(R.string.cancel))
            }
        },
    )
    if (state.downloadDestinationPicker != null) {
        DownloadDestinationDialog(
            state = state,
            model = model,
            onSelected = { selected ->
                model.updateDownloadCreationDraft(uri, selected)
                model.cancelDownloadDestinationSelection()
            },
        )
    }
}
