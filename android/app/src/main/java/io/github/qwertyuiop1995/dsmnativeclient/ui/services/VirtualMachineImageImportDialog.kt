package io.github.qwertyuiop1995.dsmnativeclient.ui.services

import android.text.format.Formatter
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.Loadable
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.VirtualMachineImageImportDraftState
import io.github.qwertyuiop1995.dsmnativeclient.VirtualMachineImageImportSource
import io.github.qwertyuiop1995.dsmnativeclient.VirtualMachineLocalImageImportSubmission
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResource
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineLocalImageRejection
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineLocalImageValidation
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineImageType

@Composable
@OptIn(ExperimentalLayoutApi::class)
internal fun VirtualMachineImageImportDialog(
    draft: VirtualMachineImageImportDraftState,
    storages: List<ManagedResource>,
    submitting: Boolean,
    onDraftChange: (VirtualMachineImageImportDraftState) -> Boolean,
    onOpenFolder: (FileItem) -> Boolean,
    onBackFolder: () -> Boolean,
    onSelectFile: (FileItem) -> Boolean,
    onRetry: () -> Boolean,
    onConfirm: () -> Boolean,
    onDismiss: () -> Boolean,
    onRequestLocalFile: (() -> Boolean)? = null,
    onSelectStagingDirectory: ((FileItem) -> Boolean)? = null,
    onConfirmLocal: ((VirtualMachineLocalImageImportSubmission) -> Boolean)? = null,
) {
    val localSourceAvailable = onRequestLocalFile != null &&
        onSelectStagingDirectory != null && onConfirmLocal != null
    BackHandler(enabled = !submitting) {
        if (draft.browserHistory.isNotEmpty()) {
            onBackFolder()
        } else onDismiss()
    }
    AlertDialog(
        onDismissRequest = {
            if (!submitting) {
                if (draft.browserHistory.isNotEmpty()) onBackFolder() else onDismiss()
            }
        },
        title = { Text(stringResource(R.string.virtual_machine_image_import_title)) },
        text = {
            LazyColumn(
                modifier = Modifier.fillMaxWidth().heightIn(max = 560.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                item {
                    Text(
                        stringResource(
                            if (draft.source == VirtualMachineImageImportSource.LOCAL) {
                                R.string.virtual_machine_local_image_import_description
                            } else R.string.virtual_machine_image_import_description,
                        ),
                    )
                }
                if (localSourceAvailable) item {
                    Text(stringResource(R.string.virtual_machine_image_source_location))
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        VirtualMachineImageImportSource.entries.forEach { source ->
                            FilterChip(
                                selected = draft.source == source,
                                onClick = { onDraftChange(draft.copy(source = source)) },
                                enabled = !submitting,
                                label = { Text(stringResource(source.labelResource())) },
                                modifier = Modifier.heightIn(min = 48.dp),
                            )
                        }
                    }
                }
                item {
                    OutlinedTextField(
                        value = draft.imageName,
                        onValueChange = { onDraftChange(draft.copy(imageName = it)) },
                        label = { Text(stringResource(R.string.virtual_machine_image_name)) },
                        enabled = !submitting,
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                if (draft.source == VirtualMachineImageImportSource.NAS) item {
                    Text(stringResource(R.string.virtual_machine_image_type))
                }
                if (draft.source == VirtualMachineImageImportSource.NAS) item {
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        VirtualMachineImageType.entries.forEach { type ->
                            FilterChip(
                                selected = draft.imageType == type,
                                onClick = { onDraftChange(draft.copy(imageType = type)) },
                                enabled = !submitting,
                                label = { Text(stringResource(type.labelResource())) },
                                modifier = Modifier.heightIn(min = 48.dp),
                            )
                        }
                    }
                }
                item { Text(stringResource(R.string.virtual_machine_image_storage)) }
                item {
                    Column(Modifier.selectableGroup()) {
                        storages.forEach { storage ->
                            val selected = draft.storage?.id == storage.id
                            ListItem(
                                headlineContent = { Text(storage.name) },
                                leadingContent = {
                                    RadioButton(
                                        selected = selected,
                                        onClick = null,
                                        enabled = !submitting,
                                    )
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .heightIn(min = 48.dp)
                                    .selectable(
                                        selected = selected,
                                        enabled = !submitting,
                                        role = Role.RadioButton,
                                    ) { onDraftChange(draft.copy(storage = storage)) },
                            )
                        }
                    }
                }
                if (draft.source == VirtualMachineImageImportSource.NAS) {
                    item {
                        Text(
                            stringResource(
                                R.string.virtual_machine_image_source_value,
                                draft.sourceFile?.name
                                    ?: stringResource(R.string.virtual_machine_image_no_file),
                            ),
                        )
                    }
                    item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            draft.browserPath.substringAfterLast('/').ifBlank {
                                stringResource(R.string.virtual_machine_image_browser_root)
                            },
                            modifier = Modifier.weight(1f),
                        )
                        if (draft.browserHistory.isNotEmpty()) {
                            TextButton(
                                onClick = { onBackFolder() },
                                enabled = !submitting,
                                modifier = Modifier.heightIn(min = 48.dp),
                            ) { Text(stringResource(R.string.virtual_machine_image_browser_back)) }
                        }
                    }
                }
                    when (val content = draft.browserItems) {
                    Loadable.Idle, Loadable.Loading -> item {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(24.dp),
                            horizontalArrangement = Arrangement.Center,
                        ) { CircularProgressIndicator() }
                    }
                    is Loadable.Failed -> item {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .semantics { liveRegion = LiveRegionMode.Polite },
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                stringResource(R.string.virtual_machine_image_browser_failed),
                                modifier = Modifier.weight(1f),
                            )
                            TextButton(
                                onClick = { onRetry() },
                                enabled = !submitting,
                                modifier = Modifier.heightIn(min = 48.dp),
                            ) { Text(stringResource(R.string.retry)) }
                        }
                    }
                    is Loadable.Ready -> {
                        if (content.value.items.isEmpty()) item {
                            Text(stringResource(R.string.virtual_machine_image_browser_empty))
                        }
                        item {
                            Column(Modifier.selectableGroup()) {
                                content.value.items.forEach { item ->
                                    val selected = draft.sourceFile == item
                                    val touchTarget = Modifier
                                        .fillMaxWidth()
                                        .heightIn(min = 48.dp)
                                    val interaction = if (item.isDirectory) {
                                        touchTarget.clickable(enabled = !submitting && item.canRead) {
                                            onOpenFolder(item)
                                        }
                                    } else {
                                        touchTarget.selectable(
                                            selected = selected,
                                            enabled = !submitting && item.canRead,
                                            role = Role.RadioButton,
                                        ) { onSelectFile(item) }
                                    }
                                    ListItem(
                                        headlineContent = { Text(item.name) },
                                        supportingContent = {
                                            Text(
                                                if (item.isDirectory) stringResource(R.string.folder)
                                                else item.path,
                                            )
                                        },
                                        leadingContent = {
                                            if (!item.isDirectory) {
                                                RadioButton(
                                                    selected = selected,
                                                    onClick = null,
                                                    enabled = !submitting && item.canRead,
                                                )
                                            }
                                        },
                                        modifier = interaction,
                                    )
                                }
                            }
                        }
                    }
                    }
                } else {
                    item {
                        LocalImageSourceFields(
                            draft = draft,
                            submitting = submitting,
                            onRequestLocalFile = checkNotNull(onRequestLocalFile),
                            onOpenFolder = onOpenFolder,
                            onBackFolder = onBackFolder,
                            onRetry = onRetry,
                            onSelectStagingDirectory = checkNotNull(onSelectStagingDirectory),
                        )
                    }
                }
            }
        },
        confirmButton = {
            val localSubmission = draft.toLocalSubmissionOrNull()
            TextButton(
                onClick = {
                    if (draft.source == VirtualMachineImageImportSource.NAS) onConfirm()
                    else localSubmission?.let { checkNotNull(onConfirmLocal)(it) }
                },
                enabled = !submitting && if (draft.source == VirtualMachineImageImportSource.NAS) {
                    draft.toImportOrNull() != null
                } else localSubmission != null,
                modifier = Modifier.heightIn(min = 48.dp),
            ) {
                Text(
                    stringResource(
                        if (draft.source == VirtualMachineImageImportSource.LOCAL) {
                            R.string.virtual_machine_local_image_import_confirm
                        } else R.string.virtual_machine_image_import_confirm,
                    ),
                )
            }
        },
        dismissButton = {
            TextButton(
                onClick = { onDismiss() },
                enabled = !submitting,
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(stringResource(R.string.cancel)) }
        },
    )
}

@Composable
private fun LocalImageSourceFields(
    draft: VirtualMachineImageImportDraftState,
    submitting: Boolean,
    onRequestLocalFile: () -> Boolean,
    onOpenFolder: (FileItem) -> Boolean,
    onBackFolder: () -> Boolean,
    onRetry: () -> Boolean,
    onSelectStagingDirectory: (FileItem) -> Boolean,
) {
    val context = LocalContext.current
    val validation = draft.localValidation()
    Text(stringResource(R.string.virtual_machine_local_image_file))
    Text(
        draft.localFile?.let { selection ->
            stringResource(
                R.string.virtual_machine_local_image_file_value,
                selection.displayName,
                selection.sizeBytes?.let { Formatter.formatFileSize(context, it) }
                    ?: stringResource(R.string.virtual_machine_local_image_size_unknown),
            )
        } ?: stringResource(R.string.virtual_machine_image_no_file),
    )
    if (validation is VirtualMachineLocalImageValidation.Rejected) {
        Text(
            stringResource(validation.reason.messageResource(draft.localFile?.displayName.orEmpty())),
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive },
        )
    } else if (validation is VirtualMachineLocalImageValidation.Accepted) {
        Text(
            stringResource(
                R.string.virtual_machine_local_image_detected_type,
                stringResource(validation.value.imageType.labelResource()),
            ),
        )
    }
    TextButton(
        onClick = { onRequestLocalFile() },
        enabled = !submitting,
        modifier = Modifier.heightIn(min = 48.dp),
    ) {
        Text(
            stringResource(
                if (draft.localFile == null) R.string.virtual_machine_local_image_choose_file
                else R.string.virtual_machine_local_image_choose_another_file,
            ),
        )
    }
    Text(stringResource(R.string.virtual_machine_local_image_staging_directory))
    Text(
        draft.localStagingDirectory?.path
            ?: stringResource(R.string.virtual_machine_local_image_no_staging_directory),
    )
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            draft.browserPath.substringAfterLast('/').ifBlank {
                stringResource(R.string.virtual_machine_image_browser_root)
            },
            modifier = Modifier.weight(1f),
        )
        if (draft.browserHistory.isNotEmpty()) {
            TextButton(
                onClick = { onBackFolder() },
                enabled = !submitting,
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(stringResource(R.string.virtual_machine_image_browser_back)) }
        }
    }
    when (val content = draft.browserItems) {
        Loadable.Idle, Loadable.Loading -> Row(
            modifier = Modifier.fillMaxWidth().padding(24.dp),
            horizontalArrangement = Arrangement.Center,
        ) { CircularProgressIndicator() }
        is Loadable.Failed -> Row(
            modifier = Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                stringResource(R.string.virtual_machine_local_image_staging_load_failed),
                modifier = Modifier.weight(1f),
            )
            TextButton(
                onClick = { onRetry() },
                enabled = !submitting,
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(stringResource(R.string.retry)) }
        }
        is Loadable.Ready -> {
            val directories = content.value.items.filter(FileItem::isDirectory)
            if (directories.isEmpty()) {
                Text(stringResource(R.string.virtual_machine_local_image_staging_empty))
            }
            directories.forEach { directory ->
                ListItem(
                    headlineContent = { Text(directory.name) },
                    supportingContent = { Text(stringResource(R.string.folder)) },
                    trailingContent = {
                        TextButton(
                            onClick = { onSelectStagingDirectory(directory) },
                            enabled = !submitting && directory.canWrite,
                            modifier = Modifier.heightIn(min = 48.dp),
                        ) {
                            Text(
                                stringResource(
                                    R.string.virtual_machine_local_image_use_staging_directory,
                                    directory.name,
                                ),
                            )
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .clickable(enabled = !submitting && directory.canRead) {
                            onOpenFolder(directory)
                        },
                )
            }
        }
    }
    Text(stringResource(R.string.virtual_machine_local_image_cleanup_notice))
}

private fun VirtualMachineLocalImageRejection.messageResource(displayName: String): Int = when {
    this == VirtualMachineLocalImageRejection.UNSUPPORTED_EXTENSION &&
        displayName.trim().endsWith(".ova", ignoreCase = true) ->
        R.string.virtual_machine_local_image_ova_unsupported
    this == VirtualMachineLocalImageRejection.INVALID_DISPLAY_NAME ->
        R.string.virtual_machine_local_image_invalid_name
    this == VirtualMachineLocalImageRejection.UNSUPPORTED_EXTENSION ->
        R.string.virtual_machine_local_image_unsupported_format
    this == VirtualMachineLocalImageRejection.SIZE_UNKNOWN ->
        R.string.virtual_machine_local_image_size_unknown_error
    this == VirtualMachineLocalImageRejection.INVALID_SIZE ->
        R.string.virtual_machine_local_image_invalid_size
    else -> R.string.virtual_machine_local_image_disk_too_large
}

private fun VirtualMachineImageImportSource.labelResource(): Int = when (this) {
    VirtualMachineImageImportSource.NAS -> R.string.virtual_machine_image_source_nas
    VirtualMachineImageImportSource.LOCAL -> R.string.virtual_machine_image_source_local
}

private fun VirtualMachineImageType.labelResource(): Int = when (this) {
    VirtualMachineImageType.DISK -> R.string.virtual_machine_image_type_disk
    VirtualMachineImageType.VDSM -> R.string.virtual_machine_image_type_vdsm
    VirtualMachineImageType.ISO -> R.string.virtual_machine_image_type_iso
}
