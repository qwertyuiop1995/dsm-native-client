package io.github.qwertyuiop1995.dsmnativeclient.ui.services

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineDiskController
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineHardware
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineNetworkModel
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineTaskCenterState
import java.text.NumberFormat

internal const val VIRTUAL_MACHINE_DETAIL_SCROLL_TEST_TAG = "virtual_machine_detail_scroll"
internal const val VIRTUAL_MACHINE_TASKS_SCROLL_TEST_TAG = "virtual_machine_tasks_scroll"

/** 虚拟机详情只展示官方只读配置，不展示机器、磁盘、网卡或 MAC 标识。 */
@Composable
internal fun VirtualMachineReadOnlyDetailContent(
    stateLabel: String,
    hardware: VirtualMachineHardware?,
    hardwareAvailable: Boolean,
    onRetry: () -> Unit,
    actions: @Composable () -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 560.dp)
            .testTag(VIRTUAL_MACHINE_DETAIL_SCROLL_TEST_TAG),
        contentPadding = PaddingValues(vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item { Text(stateLabel, style = MaterialTheme.typography.bodyLarge) }
        item {
            Text(
                stringResource(R.string.virtual_machine_hardware_configuration),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.semantics { heading() },
            )
        }
        if (!hardwareAvailable || hardware == null) {
            item {
                VirtualMachineReadOnlyStateMessage(
                    title = stringResource(R.string.virtual_machine_hardware_unavailable_title),
                    message = stringResource(R.string.virtual_machine_hardware_unavailable_message),
                    error = true,
                    onRetry = onRetry,
                    fillsContainer = false,
                )
            }
        } else {
            item {
                Text(
                    stringResource(R.string.virtual_machine_disks),
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.semantics { heading() },
                )
            }
            if (hardware.disks.isEmpty()) {
                item { Text(stringResource(R.string.virtual_machine_no_disks)) }
            } else {
                itemsIndexed(
                    items = hardware.disks,
                    key = { _, disk -> disk.id },
                ) { index, disk ->
                    val size = stringResource(
                        R.string.virtual_machine_disk_size_mib,
                        NumberFormat.getIntegerInstance().format(disk.sizeMiB),
                    )
                    val reclamation = stringResource(
                        if (disk.spaceReclamationEnabled) {
                            R.string.virtual_machine_space_reclamation_enabled
                        } else {
                            R.string.virtual_machine_space_reclamation_disabled
                        },
                    )
                    ListItem(
                        headlineContent = {
                            Text(stringResource(R.string.virtual_machine_disk_number, index + 1))
                        },
                        supportingContent = {
                            Text(
                                stringResource(
                                    R.string.virtual_machine_disk_summary,
                                    size,
                                    disk.controller.displayName(),
                                    reclamation,
                                ),
                            )
                        },
                    )
                    HorizontalDivider()
                }
            }
            item {
                Text(
                    stringResource(R.string.virtual_machine_network_interfaces),
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.padding(top = 4.dp).semantics { heading() },
                )
            }
            if (hardware.networkInterfaces.isEmpty()) {
                item { Text(stringResource(R.string.virtual_machine_no_network_interfaces)) }
            } else {
                itemsIndexed(
                    items = hardware.networkInterfaces,
                    key = { _, networkInterface -> networkInterface.id },
                ) { index, networkInterface ->
                    ListItem(
                        headlineContent = {
                            Text(
                                stringResource(
                                    R.string.virtual_machine_network_interface_number,
                                    index + 1,
                                ),
                            )
                        },
                        supportingContent = {
                            Text(
                                stringResource(
                                    R.string.virtual_machine_network_interface_summary,
                                    networkInterface.networkName.ifBlank {
                                        stringResource(
                                            R.string.virtual_machine_network_name_unavailable,
                                        )
                                    },
                                    networkInterface.model.displayName(),
                                ),
                            )
                        },
                    )
                    HorizontalDivider()
                }
            }
        }
        item {
            Column(
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                actions()
            }
        }
    }
}

/** 有限只读任务中心；服务端内部状态字符串和任务标识不进入默认界面。 */
@Composable
internal fun VirtualMachineTaskCenterContent(
    tasks: List<VirtualMachineTask>,
    state: VirtualMachineTaskCenterState,
    onRetry: () -> Unit,
) {
    when (state) {
        VirtualMachineTaskCenterState.AVAILABLE -> if (tasks.isEmpty()) {
            VirtualMachineReadOnlyStateMessage(
                title = stringResource(R.string.virtual_machine_tasks_empty_title),
                message = stringResource(R.string.virtual_machine_tasks_empty_message),
                error = false,
                onRetry = onRetry,
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().testTag(VIRTUAL_MACHINE_TASKS_SCROLL_TEST_TAG),
                contentPadding = PaddingValues(vertical = 8.dp),
            ) {
                itemsIndexed(tasks, key = { _, task -> task.id }) { index, task ->
                    val stateText = stringResource(
                        if (task.isFinished) {
                            R.string.virtual_machine_task_finished
                        } else {
                            R.string.virtual_machine_task_in_progress
                        },
                    )
                    val detail = task.progressPercent?.let { progress ->
                        stringResource(
                            R.string.virtual_machine_task_summary_with_progress,
                            stateText,
                            stringResource(R.string.virtual_machine_task_progress, progress),
                        )
                    } ?: stateText
                    ListItem(
                        headlineContent = {
                            Text(stringResource(R.string.virtual_machine_task_number, index + 1))
                        },
                        supportingContent = { Text(detail) },
                        leadingContent = {
                            Icon(Icons.AutoMirrored.Outlined.ListAlt, contentDescription = null)
                        },
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    )
                    HorizontalDivider(Modifier.padding(start = 72.dp))
                }
            }
        }
        VirtualMachineTaskCenterState.CAPABILITY_UNAVAILABLE -> {
            VirtualMachineReadOnlyStateMessage(
                title = stringResource(R.string.virtual_machine_tasks_unavailable_title),
                message = stringResource(
                    R.string.virtual_machine_tasks_capability_unavailable_message,
                ),
                error = false,
                onRetry = onRetry,
            )
        }
        VirtualMachineTaskCenterState.INVALID_RESPONSE -> {
            VirtualMachineReadOnlyStateMessage(
                title = stringResource(R.string.virtual_machine_tasks_unavailable_title),
                message = stringResource(R.string.virtual_machine_tasks_invalid_message),
                error = true,
                onRetry = onRetry,
            )
        }
        VirtualMachineTaskCenterState.LOAD_FAILED -> {
            VirtualMachineReadOnlyStateMessage(
                title = stringResource(R.string.virtual_machine_tasks_unavailable_title),
                message = stringResource(R.string.virtual_machine_tasks_load_failed_message),
                error = true,
                onRetry = onRetry,
            )
        }
    }
}

@Composable
private fun VirtualMachineReadOnlyStateMessage(
    title: String,
    message: String,
    error: Boolean,
    onRetry: () -> Unit,
    fillsContainer: Boolean = true,
) {
    val liveRegionMode = if (error) LiveRegionMode.Assertive else LiveRegionMode.Polite
    if (!fillsContainer) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
                .semantics { liveRegion = liveRegionMode },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            VirtualMachineReadOnlyStateMessageContent(title, message, error, onRetry)
        }
        return
    }
    LazyColumn(
        modifier = Modifier.fillMaxSize().semantics { liveRegion = liveRegionMode },
        contentPadding = PaddingValues(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        item {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                VirtualMachineReadOnlyStateMessageContent(title, message, error, onRetry)
            }
        }
    }
}

@Composable
private fun VirtualMachineReadOnlyStateMessageContent(
    title: String,
    message: String,
    error: Boolean,
    onRetry: () -> Unit,
) {
    Icon(
        if (error) Icons.Outlined.ErrorOutline else Icons.Outlined.Info,
        contentDescription = null,
    )
    Text(
        title,
        style = MaterialTheme.typography.titleMedium,
        modifier = Modifier.semantics { heading() },
    )
    Text(message, style = MaterialTheme.typography.bodyMedium)
    FilledTonalButton(
        onClick = onRetry,
        modifier = Modifier.heightIn(min = 48.dp),
    ) {
        Text(stringResource(R.string.refresh))
    }
}

@Composable
private fun VirtualMachineDiskController.displayName(): String = when (this) {
    VirtualMachineDiskController.VIRTIO -> stringResource(R.string.virtual_machine_hardware_virtio)
    VirtualMachineDiskController.IDE -> stringResource(R.string.virtual_machine_disk_controller_ide)
    VirtualMachineDiskController.SATA -> stringResource(R.string.virtual_machine_disk_controller_sata)
}

@Composable
private fun VirtualMachineNetworkModel.displayName(): String = when (this) {
    VirtualMachineNetworkModel.VIRTIO -> stringResource(R.string.virtual_machine_hardware_virtio)
    VirtualMachineNetworkModel.E1000 -> stringResource(R.string.virtual_machine_network_model_e1000)
    VirtualMachineNetworkModel.RTL8139 -> stringResource(
        R.string.virtual_machine_network_model_rtl8139,
    )
}
