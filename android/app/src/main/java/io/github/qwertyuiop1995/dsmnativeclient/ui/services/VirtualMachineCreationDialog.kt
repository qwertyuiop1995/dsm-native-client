package io.github.qwertyuiop1995.dsmnativeclient.ui.services

import androidx.annotation.StringRes
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.VirtualMachineCreationDraftState
import io.github.qwertyuiop1995.dsmnativeclient.VirtualMachineCreationDiskDraftState
import io.github.qwertyuiop1995.dsmnativeclient.VirtualMachineCreationNetworkDraftState
import io.github.qwertyuiop1995.dsmnativeclient.VirtualMachineSettingsDraftState
import io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResource
import io.github.qwertyuiop1995.dsmnativeclient.domain.MAX_VIRTUAL_MACHINE_DISKS
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineOverview
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineSettings

@Composable
internal fun VirtualMachineCreationDialog(
    overview: VirtualMachineOverview,
    draft: VirtualMachineCreationDraftState,
    submitting: Boolean,
    onDraftChange: (VirtualMachineCreationDraftState) -> Boolean,
    onConfirm: () -> Boolean,
    onDismiss: () -> Boolean,
) {
    val diskImages = overview.images.filter { it.metadata["type"] == "disk" }
    val cpuValue = draft.cpu.toIntOrNull()
    val memoryValue = draft.memory.toIntOrNull()
    val diskValue = draft.disk.toIntOrNull()
    val nameError = nameError(draft.name)
    val descriptionError = draft.description.length > 1_024
    val cpuError = cpuValue == null || cpuValue !in 1..64
    val memoryError = memoryValue == null || memoryValue !in 128..1_048_576
    val diskError = draft.diskImageId == null && (diskValue == null || diskValue !in 1..1_048_576)
    val additionalDiskErrors = draft.additionalDisks.map {
        it.diskImageId == null &&
            (it.disk.toIntOrNull()?.let { value -> value !in 1..1_048_576 } ?: true)
    }
    val nameValid = !nameError && !descriptionError
    val resourcesValid = !cpuError && !memoryError && !diskError &&
        additionalDiskErrors.none { it }
    val validNetworkIds = overview.networks.map(ManagedResource::id).toSet()
    val validImageIds = diskImages.map(ManagedResource::id).toSet()
    val placementValid = overview.storages.any { it.id == draft.storageId } &&
        (listOf(draft.networkId) + draft.additionalNetworkInterfaces.map { it.networkId })
            .filterNotNull().all { it in validNetworkIds } &&
        (listOf(draft.diskImageId) + draft.additionalDisks.map { it.diskImageId })
            .filterNotNull().all { it in validImageIds }
    val stepDescription = stringResource(R.string.virtual_machine_creation_step, draft.step + 1, 3)

    AlertDialog(
        modifier = Modifier.imePadding(),
        onDismissRequest = { if (!submitting) onDismiss() },
        title = { Text(stringResource(R.string.create_virtual_machine)) },
        text = {
            BackHandler(enabled = !submitting) {
                if (draft.step > 0) {
                    onDraftChange(draft.copy(step = draft.step - 1))
                } else {
                    onDismiss()
                }
            }
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 560.dp)
                    .verticalScroll(rememberScrollState()),
            ) {
                Text(
                    stepDescription,
                    modifier = Modifier.semantics {
                        stateDescription = stepDescription
                        liveRegion = LiveRegionMode.Polite
                    },
                )
                LinearProgressIndicator(
                    progress = { (draft.step + 1) / 3f },
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 12.dp),
                )
                when (draft.step) {
                    0 -> BasicsStep(
                        name = draft.name,
                        description = draft.description,
                        autoStart = draft.autoStart,
                        enabled = !submitting,
                        nameError = nameError,
                        descriptionError = descriptionError,
                        onNameChange = { onDraftChange(draft.copy(name = it.take(64))) },
                        onDescriptionChange = {
                            onDraftChange(draft.copy(description = it.take(1_024)))
                        },
                        onAutoStartChange = { onDraftChange(draft.copy(autoStart = it)) },
                    )
                    1 -> ResourcesStep(
                        cpu = draft.cpu,
                        memory = draft.memory,
                        disk = draft.disk,
                        diskImageId = draft.diskImageId,
                        additionalDisks = draft.additionalDisks,
                        enabled = !submitting,
                        cpuError = cpuError,
                        memoryError = memoryError,
                        diskError = diskError,
                        additionalDiskErrors = additionalDiskErrors,
                        onCpuChange = {
                            onDraftChange(draft.copy(cpu = it.filter(Char::isDigit).take(2)))
                        },
                        onMemoryChange = {
                            onDraftChange(draft.copy(memory = it.filter(Char::isDigit).take(7)))
                        },
                        onDiskChange = {
                            onDraftChange(draft.copy(disk = it.filter(Char::isDigit).take(7)))
                        },
                        onAdditionalDiskChange = { index, value ->
                            onDraftChange(
                                draft.copy(
                                    additionalDisks = draft.additionalDisks.mapIndexed { itemIndex, item ->
                                        if (itemIndex == index) item.copy(
                                            disk = value.filter(Char::isDigit).take(7),
                                        ) else item
                                    },
                                ),
                            )
                        },
                        onAddDisk = {
                            if (draft.additionalDisks.size < MAX_VIRTUAL_MACHINE_DISKS - 1) onDraftChange(
                                draft.copy(
                                    additionalDisks = draft.additionalDisks +
                                        VirtualMachineCreationDiskDraftState(),
                                ),
                            )
                        },
                        onRemoveDisk = { index ->
                            onDraftChange(
                                draft.copy(
                                    additionalDisks = draft.additionalDisks.filterIndexed {
                                            itemIndex, _ -> itemIndex != index
                                    },
                                ),
                            )
                        },
                    )
                    else -> {
                        PlacementStep(
                            storages = overview.storages,
                            networks = overview.networks,
                            diskImages = diskImages,
                            storageId = draft.storageId,
                            networkId = draft.networkId,
                            imageId = draft.diskImageId,
                            additionalDisks = draft.additionalDisks,
                            additionalNetworkInterfaces = draft.additionalNetworkInterfaces,
                            enabled = !submitting,
                            onStorageChange = { onDraftChange(draft.copy(storageId = it)) },
                            onNetworkChange = { onDraftChange(draft.copy(networkId = it)) },
                            onImageChange = { onDraftChange(draft.copy(diskImageId = it)) },
                            onAdditionalDiskImageChange = { index, imageId ->
                                onDraftChange(
                                    draft.copy(
                                        additionalDisks = draft.additionalDisks.mapIndexed {
                                                itemIndex, item ->
                                            if (itemIndex == index) item.copy(diskImageId = imageId)
                                            else item
                                        },
                                    ),
                                )
                            },
                            onAdditionalNetworkChange = { index, networkId ->
                                onDraftChange(
                                    draft.copy(
                                        additionalNetworkInterfaces =
                                            draft.additionalNetworkInterfaces.mapIndexed {
                                                    itemIndex, item ->
                                                if (itemIndex == index) item.copy(networkId = networkId)
                                                else item
                                            },
                                    ),
                                )
                            },
                            onAddNetwork = {
                                onDraftChange(
                                    draft.copy(
                                        additionalNetworkInterfaces =
                                            draft.additionalNetworkInterfaces +
                                                VirtualMachineCreationNetworkDraftState(),
                                    ),
                                )
                            },
                            onRemoveNetwork = { index ->
                                onDraftChange(
                                    draft.copy(
                                        additionalNetworkInterfaces =
                                            draft.additionalNetworkInterfaces.filterIndexed {
                                                    itemIndex, _ -> itemIndex != index
                                            },
                                    ),
                                )
                            },
                        )
                        CreationReview(
                            overview = overview,
                            diskImages = diskImages,
                            name = draft.name.trim(),
                            description = draft.description.trim(),
                            autoStart = draft.autoStart,
                            cpu = checkNotNull(cpuValue),
                            memory = checkNotNull(memoryValue),
                            disk = checkNotNull(diskValue),
                            storageId = draft.storageId,
                            networkId = draft.networkId,
                            imageId = draft.diskImageId,
                            additionalDisks = draft.additionalDisks,
                            additionalNetworkInterfaces = draft.additionalNetworkInterfaces,
                        )
                    }
                }
            }
        },
        dismissButton = {
            if (draft.step == 0) {
                TextButton(
                    onClick = { onDismiss() },
                    enabled = !submitting,
                    modifier = Modifier.heightIn(min = 48.dp),
                ) {
                    Text(stringResource(R.string.cancel))
                }
            } else {
                TextButton(
                    onClick = { onDraftChange(draft.copy(step = draft.step - 1)) },
                    enabled = !submitting,
                    modifier = Modifier.heightIn(min = 48.dp),
                ) {
                    Text(stringResource(R.string.virtual_machine_previous_step))
                }
            }
        },
        confirmButton = {
            if (draft.step < 2) {
                val valid = if (draft.step == 0) nameValid else resourcesValid
                TextButton(
                    onClick = { onDraftChange(draft.copy(step = draft.step + 1)) },
                    enabled = valid && !submitting,
                    modifier = Modifier.heightIn(min = 48.dp),
                ) {
                    Text(stringResource(R.string.virtual_machine_next_step))
                }
            } else {
                TextButton(
                    enabled = placementValid && !submitting,
                    modifier = Modifier.heightIn(min = 48.dp),
                    onClick = { onConfirm() },
                ) {
                    Text(stringResource(R.string.create))
                }
            }
        },
    )
}

@Composable
private fun BasicsStep(
    name: String,
    description: String,
    autoStart: Boolean,
    enabled: Boolean,
    nameError: Boolean,
    descriptionError: Boolean,
    onNameChange: (String) -> Unit,
    onDescriptionChange: (String) -> Unit,
    onAutoStartChange: (Boolean) -> Unit,
) {
    OutlinedTextField(
        value = name,
        onValueChange = onNameChange,
        enabled = enabled,
        isError = nameError,
        singleLine = true,
        label = { Text(stringResource(R.string.virtual_machine_name)) },
        supportingText = {
            ValidationSupportingText(
                if (nameError) {
                    if (name.isBlank()) R.string.virtual_machine_name_required
                    else R.string.virtual_machine_name_invalid
                } else R.string.virtual_machine_name_hint,
                nameError,
            )
        },
        modifier = Modifier.fillMaxWidth(),
    )
    OutlinedTextField(
        value = description,
        onValueChange = onDescriptionChange,
        enabled = enabled,
        isError = descriptionError,
        label = { Text(stringResource(R.string.virtual_machine_description)) },
        supportingText = {
            if (descriptionError) {
                ValidationSupportingText(R.string.virtual_machine_description_invalid, true)
            } else {
                Text(stringResource(R.string.virtual_machine_character_count, description.length, 1_024))
            }
        },
        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
    )
    ListItem(
        headlineContent = { Text(stringResource(R.string.virtual_machine_auto_start)) },
        supportingContent = { Text(stringResource(R.string.virtual_machine_auto_start_hint)) },
        trailingContent = {
            Switch(checked = autoStart, onCheckedChange = null, enabled = enabled)
        },
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .toggleable(
                value = autoStart,
                enabled = enabled,
                role = Role.Switch,
                onValueChange = onAutoStartChange,
            ),
    )
}

@Composable
private fun ResourcesStep(
    cpu: String,
    memory: String,
    disk: String,
    diskImageId: String?,
    additionalDisks: List<VirtualMachineCreationDiskDraftState>,
    enabled: Boolean,
    cpuError: Boolean,
    memoryError: Boolean,
    diskError: Boolean,
    additionalDiskErrors: List<Boolean>,
    onCpuChange: (String) -> Unit,
    onMemoryChange: (String) -> Unit,
    onDiskChange: (String) -> Unit,
    onAdditionalDiskChange: (Int, String) -> Unit,
    onAddDisk: () -> Unit,
    onRemoveDisk: (Int) -> Unit,
) {
    NumberField(
        cpu,
        onCpuChange,
        R.string.virtual_machine_cpu,
        R.string.virtual_machine_cpu_range,
        cpuError,
        enabled,
    )
    NumberField(
        memory,
        onMemoryChange,
        R.string.virtual_machine_memory_mib,
        R.string.virtual_machine_memory_range,
        memoryError,
        enabled,
    )
    if (diskImageId == null) {
        NumberField(
            disk,
            onDiskChange,
            R.string.virtual_machine_disk_gib,
            R.string.virtual_machine_disk_range,
            diskError,
            enabled,
        )
    } else {
        Text(stringResource(R.string.virtual_machine_image_original_capacity))
    }
    additionalDisks.forEachIndexed { index, diskDraft ->
        PlacementHeading(R.string.virtual_machine_additional_disk_number, index + 2)
        if (diskDraft.diskImageId == null) {
            NumberField(
                diskDraft.disk,
                { onAdditionalDiskChange(index, it) },
                R.string.virtual_machine_disk_gib,
                R.string.virtual_machine_disk_range,
                additionalDiskErrors.getOrElse(index) { true },
                enabled,
            )
        } else {
            Text(stringResource(R.string.virtual_machine_image_original_capacity))
        }
        TextButton(
            onClick = { onRemoveDisk(index) },
            enabled = enabled,
            modifier = Modifier.heightIn(min = 48.dp),
        ) { Text(stringResource(R.string.virtual_machine_remove_disk_number, index + 2)) }
    }
    TextButton(
        onClick = onAddDisk,
        enabled = enabled && additionalDisks.size < MAX_VIRTUAL_MACHINE_DISKS - 1,
        modifier = Modifier.heightIn(min = 48.dp),
    ) { Text(stringResource(R.string.virtual_machine_add_disk)) }
}

@Composable
private fun NumberField(
    value: String,
    onValueChange: (String) -> Unit,
    @StringRes label: Int,
    @StringRes supporting: Int,
    isError: Boolean,
    enabled: Boolean,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        enabled = enabled,
        isError = isError,
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        label = { Text(stringResource(label)) },
        supportingText = { ValidationSupportingText(supporting, isError) },
        modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
    )
}

@Composable
private fun PlacementStep(
    storages: List<ManagedResource>,
    networks: List<ManagedResource>,
    diskImages: List<ManagedResource>,
    storageId: String,
    networkId: String?,
    imageId: String?,
    additionalDisks: List<VirtualMachineCreationDiskDraftState>,
    additionalNetworkInterfaces: List<VirtualMachineCreationNetworkDraftState>,
    enabled: Boolean,
    onStorageChange: (String) -> Unit,
    onNetworkChange: (String?) -> Unit,
    onImageChange: (String?) -> Unit,
    onAdditionalDiskImageChange: (Int, String?) -> Unit,
    onAdditionalNetworkChange: (Int, String?) -> Unit,
    onAddNetwork: () -> Unit,
    onRemoveNetwork: (Int) -> Unit,
) {
    PlacementHeading(R.string.virtual_machine_storage)
    Column(Modifier.selectableGroup()) {
        if (storages.isEmpty()) {
            Text(
                stringResource(R.string.virtual_machine_no_storage),
                modifier = Modifier.padding(16.dp).semantics { liveRegion = LiveRegionMode.Assertive },
            )
        } else {
            storages.forEach { storage ->
                PlacementChoice(storage.name, storageId == storage.id, enabled) {
                    onStorageChange(storage.id)
                }
            }
        }
    }
    PlacementHeading(R.string.virtual_machine_network)
    Column(Modifier.selectableGroup()) {
        PlacementChoice(
            stringResource(R.string.virtual_machine_disconnected_network),
            networkId == null,
            enabled,
        ) { onNetworkChange(null) }
        networks.forEach { network ->
            PlacementChoice(network.name, networkId == network.id, enabled) {
                onNetworkChange(network.id)
            }
        }
    }
    additionalNetworkInterfaces.forEachIndexed { index, networkInterface ->
        PlacementHeading(R.string.virtual_machine_additional_network_number, index + 2)
        Column(Modifier.selectableGroup()) {
            PlacementChoice(
                stringResource(R.string.virtual_machine_disconnected_network),
                networkInterface.networkId == null,
                enabled,
            ) { onAdditionalNetworkChange(index, null) }
            networks.forEach { network ->
                PlacementChoice(network.name, networkInterface.networkId == network.id, enabled) {
                    onAdditionalNetworkChange(index, network.id)
                }
            }
        }
        TextButton(
            onClick = { onRemoveNetwork(index) },
            enabled = enabled,
            modifier = Modifier.heightIn(min = 48.dp),
        ) { Text(stringResource(R.string.virtual_machine_remove_network_number, index + 2)) }
    }
    TextButton(
        onClick = onAddNetwork,
        enabled = enabled,
        modifier = Modifier.heightIn(min = 48.dp),
    ) { Text(stringResource(R.string.virtual_machine_add_network)) }
    PlacementHeading(R.string.virtual_machine_disk_source)
    Column(Modifier.selectableGroup()) {
        PlacementChoice(
            stringResource(R.string.virtual_machine_empty_disk),
            imageId == null,
            enabled,
        ) { onImageChange(null) }
        diskImages.forEach { image ->
            PlacementChoice(image.name, imageId == image.id, enabled) { onImageChange(image.id) }
        }
    }
    if (imageId != null) Text(stringResource(R.string.virtual_machine_image_original_capacity))
    additionalDisks.forEachIndexed { index, disk ->
        PlacementHeading(R.string.virtual_machine_additional_disk_source_number, index + 2)
        Column(Modifier.selectableGroup()) {
            PlacementChoice(
                stringResource(R.string.virtual_machine_empty_disk),
                disk.diskImageId == null,
                enabled,
            ) { onAdditionalDiskImageChange(index, null) }
            diskImages.forEach { image ->
                PlacementChoice(image.name, disk.diskImageId == image.id, enabled) {
                    onAdditionalDiskImageChange(index, image.id)
                }
            }
        }
        if (disk.diskImageId != null) {
            Text(stringResource(R.string.virtual_machine_image_original_capacity))
        }
    }
}

@Composable
private fun PlacementHeading(@StringRes label: Int, vararg values: Any) {
    Text(stringResource(label, *values), modifier = Modifier.padding(top = 12.dp, bottom = 4.dp))
}

@Composable
private fun PlacementChoice(
    label: String,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .selectable(
                selected = selected,
                enabled = enabled,
                role = Role.RadioButton,
                onClick = onClick,
            )
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = null, enabled = enabled)
        Spacer(Modifier.width(8.dp))
        Text(label)
    }
}

@Composable
private fun CreationReview(
    overview: VirtualMachineOverview,
    diskImages: List<ManagedResource>,
    name: String,
    description: String,
    autoStart: Boolean,
    cpu: Int,
    memory: Int,
    disk: Int,
    storageId: String,
    networkId: String?,
    imageId: String?,
    additionalDisks: List<VirtualMachineCreationDiskDraftState>,
    additionalNetworkInterfaces: List<VirtualMachineCreationNetworkDraftState>,
) {
    val unavailable = stringResource(R.string.virtual_machine_selection_unavailable)
    HorizontalDivider(Modifier.padding(vertical = 12.dp))
    Text(stringResource(R.string.virtual_machine_review))
    ReviewItem(R.string.virtual_machine_name, name)
    ReviewItem(
        R.string.virtual_machine_description,
        description.ifBlank { stringResource(R.string.virtual_machine_not_provided) },
    )
    ReviewItem(
        R.string.virtual_machine_cpu,
        stringResource(R.string.virtual_machine_processor_count, cpu),
    )
    ReviewItem(
        R.string.virtual_machine_memory_mib,
        stringResource(R.string.virtual_machine_memory_value, memory),
    )
    if (imageId == null) {
        ReviewItem(
            R.string.virtual_machine_disk_gib,
            stringResource(R.string.virtual_machine_disk_value, disk),
        )
    }
    additionalDisks.forEachIndexed { index, diskDraft ->
        ReviewItem(
            R.string.virtual_machine_disks,
            if (diskDraft.diskImageId == null) {
                stringResource(
                    R.string.virtual_machine_additional_empty_disk_review,
                    index + 2,
                    diskDraft.disk,
                )
            } else {
                stringResource(
                    R.string.virtual_machine_additional_image_disk_review,
                    index + 2,
                    diskImages.firstOrNull { it.id == diskDraft.diskImageId }?.name ?: unavailable,
                )
            },
        )
    }
    ReviewItem(
        R.string.virtual_machine_storage,
        overview.storages.firstOrNull { it.id == storageId }?.name ?: unavailable,
    )
    ReviewItem(
        R.string.virtual_machine_network,
        if (networkId == null) {
            stringResource(R.string.virtual_machine_disconnected_network)
        } else {
            overview.networks.firstOrNull { it.id == networkId }?.name ?: unavailable
        },
    )
    additionalNetworkInterfaces.forEachIndexed { index, networkInterface ->
        ReviewItem(
            R.string.virtual_machine_network_interfaces,
            stringResource(
                R.string.virtual_machine_additional_network_review,
                index + 2,
                networkInterface.networkId?.let { selectedId ->
                    overview.networks.firstOrNull { it.id == selectedId }?.name
                } ?: stringResource(R.string.virtual_machine_disconnected_network),
            ),
        )
    }
    ReviewItem(
        R.string.virtual_machine_disk_source,
        if (imageId == null) {
            stringResource(R.string.virtual_machine_empty_disk)
        } else {
            stringResource(
                R.string.virtual_machine_image_source_review,
                diskImages.firstOrNull { it.id == imageId }?.name ?: unavailable,
            )
        },
    )
    ReviewItem(
        R.string.virtual_machine_auto_start,
        stringResource(if (autoStart) R.string.enabled else R.string.disabled),
    )
}

@Composable
private fun ReviewItem(@StringRes label: Int, value: String) {
    Text(
        stringResource(R.string.virtual_machine_review_item, stringResource(label), value),
        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
    )
}

@Composable
private fun ValidationSupportingText(@StringRes message: Int, isError: Boolean) {
    Text(
        stringResource(message),
        modifier = if (isError) {
            Modifier.semantics { liveRegion = LiveRegionMode.Assertive }
        } else Modifier,
    )
}

private fun nameError(name: String): Boolean =
    name.trim().isEmpty() || name.trim().length > 64 || name.any(Char::isISOControl)

@Composable
internal fun VirtualMachineSettingsDialog(
    draft: VirtualMachineSettingsDraftState,
    baseline: VirtualMachineSettings,
    submitting: Boolean,
    onDraftChange: (VirtualMachineSettingsDraftState) -> Boolean,
    onConfirm: () -> Boolean,
    onDismiss: () -> Boolean,
) {
    val cpuValue = draft.cpu.toIntOrNull()
    val memoryValue = draft.memory.toIntOrNull()
    val nameError = nameError(draft.name)
    val descriptionError = draft.description.length > 1_024
    val cpuError = cpuValue == null || cpuValue !in 1..64
    val memoryError = memoryValue == null || memoryValue !in 128..1_048_576
    val desired = draft.toSettingsOrNull()
    val valid = !nameError && !descriptionError && !cpuError && !memoryError && desired != baseline
    AlertDialog(
        modifier = Modifier.imePadding(),
        onDismissRequest = { if (!submitting) onDismiss() },
        title = { Text(stringResource(R.string.edit_virtual_machine)) },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 560.dp)
                    .verticalScroll(rememberScrollState()),
            ) {
                BasicsStep(
                    name = draft.name,
                    description = draft.description,
                    autoStart = draft.autoStart,
                    enabled = !submitting,
                    nameError = nameError,
                    descriptionError = descriptionError,
                    onNameChange = { onDraftChange(draft.copy(name = it.take(64))) },
                    onDescriptionChange = {
                        onDraftChange(draft.copy(description = it.take(1_024)))
                    },
                    onAutoStartChange = { onDraftChange(draft.copy(autoStart = it)) },
                )
                NumberField(
                    draft.cpu,
                    {
                        onDraftChange(draft.copy(cpu = it.filter(Char::isDigit).take(2)))
                    },
                    R.string.virtual_machine_cpu,
                    R.string.virtual_machine_cpu_range,
                    cpuError,
                    !submitting,
                )
                NumberField(
                    draft.memory,
                    {
                        onDraftChange(draft.copy(memory = it.filter(Char::isDigit).take(7)))
                    },
                    R.string.virtual_machine_memory_mib,
                    R.string.virtual_machine_memory_range,
                    memoryError,
                    !submitting,
                )
            }
        },
        dismissButton = {
            TextButton(
                onClick = { onDismiss() },
                enabled = !submitting,
                modifier = Modifier.heightIn(min = 48.dp),
            ) {
                Text(stringResource(R.string.cancel))
            }
        },
        confirmButton = {
            TextButton(
                enabled = valid && !submitting,
                modifier = Modifier.heightIn(min = 48.dp),
                onClick = { onConfirm() },
            ) {
                Text(stringResource(R.string.save))
            }
        },
    )
}
