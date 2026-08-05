package io.github.qwertyuiop1995.dsmnativeclient.ui.services

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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.Loadable
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.VirtualMachineImageImportDraftState
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResource
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
) {
    BackHandler(enabled = !submitting) {
        if (draft.browserHistory.isNotEmpty()) onBackFolder() else onDismiss()
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
                    Text(stringResource(R.string.virtual_machine_image_import_description))
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
                item { Text(stringResource(R.string.virtual_machine_image_type)) }
                item {
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
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm() },
                enabled = !submitting && draft.toImportOrNull() != null,
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(stringResource(R.string.virtual_machine_image_import_confirm)) }
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

private fun VirtualMachineImageType.labelResource(): Int = when (this) {
    VirtualMachineImageType.DISK -> R.string.virtual_machine_image_type_disk
    VirtualMachineImageType.VDSM -> R.string.virtual_machine_image_type_vdsm
    VirtualMachineImageType.ISO -> R.string.virtual_machine_image_type_iso
}
