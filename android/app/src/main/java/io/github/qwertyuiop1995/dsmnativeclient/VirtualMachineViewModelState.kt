package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.*
import java.security.MessageDigest

enum class VirtualMachineMutationKind {
    CREATION,
    IMAGE_IMPORT,
    SETTINGS,
    LIFECYCLE,
}

enum class VirtualMachineMutationVerification {
    MATCHES,
    DIFFERS,
    DISAPPEARED,
    UNAVAILABLE,
}

enum class VirtualMachineLifecycleOperation {
    CONTROL,
    DELETE_MACHINE,
    DELETE_IMAGE,
    DELETE_NETWORK,
    RENAME_NETWORK,
}

data class VirtualMachineLifecycleTarget(
    val profileId: String,
    val resourceId: String,
    val operation: VirtualMachineLifecycleOperation,
    val baselineState: ResourceState,
    val command: String? = null,
) {
    init {
        require(profileId.isNotBlank() && resourceId.isNotBlank()) { "virtual_machine.invalid_target" }
        require(
            operation in setOf(
                VirtualMachineLifecycleOperation.CONTROL,
                VirtualMachineLifecycleOperation.RENAME_NETWORK,
            ) && !command.isNullOrBlank() || operation !in setOf(
                VirtualMachineLifecycleOperation.CONTROL,
                VirtualMachineLifecycleOperation.RENAME_NETWORK,
            ) && command == null,
        ) { "virtual_machine.invalid_lifecycle_operation" }
        require(
            operation != VirtualMachineLifecycleOperation.CONTROL ||
                virtualMachineControlExpectedState(baselineState, checkNotNull(command)) != null,
        ) { "virtual_machine.invalid_control_baseline" }
    }
}

internal fun virtualMachineControlExpectedState(
    baselineState: ResourceState,
    command: String,
): ResourceState? = when {
    command == "poweron" && baselineState == ResourceState.STOPPED -> ResourceState.RUNNING
    command in setOf("poweroff", "shutdown") && baselineState == ResourceState.RUNNING ->
        ResourceState.STOPPED
    else -> null
}

data class VirtualMachineCreationDraftState(
    val step: Int = 0,
    val name: String = "",
    val description: String = "",
    val autoStart: Boolean = false,
    val cpu: String = "1",
    val memory: String = "1024",
    val disk: String = "10",
    val storageId: String = "",
    val networkId: String? = null,
    val diskImageId: String? = null,
) {
    fun toCreationOrNull(): VirtualMachineCreation? {
        val cleanName = name.trim()
        val cleanDescription = description.trim()
        val cpuValue = cpu.toIntOrNull()
        val memoryValue = memory.toIntOrNull()
        val diskValue = disk.toIntOrNull()
        if (step !in 0..2 || cleanName.isEmpty() || cleanName.length > 64 ||
            cleanName.any(Char::isISOControl) || cleanDescription.length > 1_024 ||
            cpuValue !in 1..64 || memoryValue !in 128..1_048_576 ||
            diskValue !in 1..1_048_576 || storageId.isBlank()
        ) return null
        return VirtualMachineCreation(
            name = cleanName,
            description = cleanDescription,
            cpuCount = checkNotNull(cpuValue),
            memoryMiB = checkNotNull(memoryValue),
            diskGiB = checkNotNull(diskValue),
            storageId = storageId.trim(),
            networkId = networkId?.trim()?.takeIf(String::isNotEmpty),
            diskImageId = diskImageId?.trim()?.takeIf(String::isNotEmpty),
            autoStart = autoStart,
        )
    }

    companion object {
        fun from(value: VirtualMachineCreation, step: Int = 2) = VirtualMachineCreationDraftState(
            step = step,
            name = value.name,
            description = value.description,
            autoStart = value.autoStart,
            cpu = value.cpuCount.toString(),
            memory = value.memoryMiB.toString(),
            disk = value.diskGiB.toString(),
            storageId = value.storageId,
            networkId = value.networkId,
            diskImageId = value.diskImageId,
        )
    }
}

data class VirtualMachineSettingsDraftState(
    val name: String,
    val description: String,
    val cpu: String,
    val memory: String,
    val autoStart: Boolean,
) {
    fun toSettingsOrNull(): VirtualMachineSettings? {
        val cleanName = name.trim()
        val cleanDescription = description.trim()
        val cpuValue = cpu.toIntOrNull()
        val memoryValue = memory.toIntOrNull()
        if (cleanName.isEmpty() || cleanName.length > 64 || cleanName.any(Char::isISOControl) ||
            cleanDescription.length > 1_024 || cpuValue !in 1..64 || memoryValue !in 128..1_048_576
        ) return null
        return VirtualMachineSettings(
            cleanName,
            cleanDescription,
            checkNotNull(cpuValue),
            checkNotNull(memoryValue),
            autoStart,
        )
    }

    companion object {
        fun from(value: VirtualMachineSettings) = VirtualMachineSettingsDraftState(
            name = value.name,
            description = value.description,
            cpu = value.cpuCount.toString(),
            memory = value.memoryMiB.toString(),
            autoStart = value.autoStart,
        )
    }
}

data class VirtualMachineImageImportDraftState(
    val imageName: String = "",
    val imageType: VirtualMachineImageType = VirtualMachineImageType.DISK,
    val storage: ManagedResource? = null,
    val sourceFile: FileItem? = null,
    val browserPath: String = "",
    val browserHistory: List<String> = emptyList(),
    val browserItems: Loadable<FilePage> = Loadable.Idle,
) {
    fun toImportOrNull(): VirtualMachineImageImport? {
        val name = imageName.trim()
        val file = sourceFile ?: return null
        val targetStorage = storage ?: return null
        if (name.isEmpty() || name.any(Char::isISOControl) || file.path.isBlank() ||
            !file.path.startsWith('/') || file.isDirectory || !file.canRead ||
            !targetStorage.isEligibleForVirtualMachineImageImport()
        ) return null
        return VirtualMachineImageImport(name, imageType, file, targetStorage)
    }
}

/** VMM 写目标只保存稳定标识和请求指纹，不保存 NAS 返回的完整资源内容。 */
data class VirtualMachineMutationTarget(
    val profileId: String,
    val kind: VirtualMachineMutationKind,
    val operation: String,
    val resourceId: String?,
    val requestFingerprint: String,
) {
    init {
        require(profileId.isNotBlank()) { "virtual_machine.invalid_profile" }
        require(operation.isNotBlank()) { "virtual_machine.invalid_operation" }
        require(resourceId == null || resourceId.isNotBlank()) { "virtual_machine.invalid_target" }
        require(requestFingerprint.length == 64 && requestFingerprint.all { it in "0123456789abcdef" }) {
            "virtual_machine.invalid_fingerprint"
        }
    }
}

data class VirtualMachineMutationWorkspaceState(
    val creationEditorVisible: Boolean = false,
    val creationDraft: VirtualMachineCreationDraftState? = null,
    val imageImportEditorVisible: Boolean = false,
    val imageImportDraft: VirtualMachineImageImportDraftState? = null,
    /** 仅在当前 Workspace 内存中保存，用于配置重建后的只读任务核对。 */
    val imageImportTaskId: String? = null,
    val settingsEditorVisible: Boolean = false,
    val settingsTargetId: String? = null,
    val settingsBaseline: VirtualMachineSettings? = null,
    val settingsDraft: VirtualMachineSettingsDraftState? = null,
    val lifecycleConfirmationTarget: VirtualMachineLifecycleTarget? = null,
    val lifecycleConfirmationRequested: Boolean = false,
    val target: VirtualMachineMutationTarget? = null,
    val mutationInProgress: Boolean = false,
    val mutationResult: MutationResult? = null,
    val mutationFailure: DsmFailure? = null,
    val mutationRefreshFailure: DsmFailure? = null,
    val mutationRefreshInProgress: Boolean = false,
    val mutationRefreshCompleted: Boolean = false,
    val mutationVerification: VirtualMachineMutationVerification? = null,
    val mutationGeneration: Long = 0L,
)





internal data class VirtualMachineOverviewRequestToken(
    val profileId: String,
    val generation: Long,
)


internal fun virtualMachineMutationTarget(
    profileId: String,
    kind: VirtualMachineMutationKind,
    operation: String,
    resourceId: String?,
    requestParts: List<String>,
): VirtualMachineMutationTarget {
    val digest = MessageDigest.getInstance("SHA-256")
    listOf(kind.name, operation, resourceId.orEmpty()).plus(requestParts).forEach { value ->
        val bytes = value.toByteArray(Charsets.UTF_8)
        digest.update(
            byteArrayOf(
                (bytes.size ushr 24).toByte(),
                (bytes.size ushr 16).toByte(),
                (bytes.size ushr 8).toByte(),
                bytes.size.toByte(),
            ),
        )
        digest.update(bytes)
    }
    return VirtualMachineMutationTarget(
        profileId = profileId,
        kind = kind,
        operation = operation,
        resourceId = resourceId?.trim()?.takeIf(String::isNotEmpty),
        requestFingerprint = digest.digest()
            .joinToString("") { byte -> (byte.toInt() and 0xff).toString(16).padStart(2, '0') },
    )
}

internal fun virtualMachineMutationRequiresRefreshBeforeDismiss(
    state: VirtualMachineMutationWorkspaceState,
): Boolean = state.imageImportTaskId != null || state.mutationFailure != null || state.mutationResult?.let { result ->
    result.requiresRefresh || result.counts.unknown > 0 ||
        result.status in setOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        )
} == true

internal fun virtualMachineMutationBlocksWorkspaceExit(
    state: VirtualMachineMutationWorkspaceState,
): Boolean {
    if (state.creationEditorVisible || state.imageImportEditorVisible || state.settingsEditorVisible ||
        state.lifecycleConfirmationRequested || state.mutationInProgress ||
        state.mutationRefreshInProgress
    ) return true
    if (state.imageImportTaskId != null) return true
    return state.target != null && virtualMachineMutationRequiresRefreshBeforeDismiss(state)
}

internal fun canDismissVirtualMachineMutation(
    state: VirtualMachineMutationWorkspaceState,
): Boolean = state.target != null && state.imageImportTaskId == null &&
    !state.mutationInProgress && !state.mutationRefreshInProgress &&
    (!virtualMachineMutationRequiresRefreshBeforeDismiss(state) ||
        state.mutationRefreshCompleted && state.mutationVerification != null)

internal fun canContinueEditingVirtualMachineMutation(
    state: VirtualMachineMutationWorkspaceState,
): Boolean {
    val target = state.target ?: return false
    val result = state.mutationResult ?: return false
    if (state.mutationInProgress || state.mutationRefreshInProgress || state.mutationFailure != null ||
        result.submitted || result.requiresRefresh || result.status !in setOf(
            MutationResultStatus.CONFIRMED_FAILURE,
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
        )
    ) return false
    return when (target.kind) {
        VirtualMachineMutationKind.CREATION ->
            state.creationEditorVisible && state.creationDraft != null
        VirtualMachineMutationKind.IMAGE_IMPORT ->
            state.imageImportEditorVisible && state.imageImportDraft?.toImportOrNull() != null
        VirtualMachineMutationKind.SETTINGS ->
            state.settingsEditorVisible && state.settingsTargetId != null &&
                state.settingsBaseline != null && state.settingsDraft != null
        VirtualMachineMutationKind.LIFECYCLE -> false
    }
}

internal fun canStartVirtualMachineMutation(
    isPerformingAction: Boolean,
    state: VirtualMachineMutationWorkspaceState,
): Boolean = !isPerformingAction && state.target == null && !state.mutationInProgress &&
    !state.mutationRefreshInProgress && state.mutationResult == null && state.mutationFailure == null

internal fun virtualMachineMutationCallbackMatches(
    repositoryMatches: Boolean,
    profileMatches: Boolean,
    stateTarget: VirtualMachineMutationTarget?,
    callbackTarget: VirtualMachineMutationTarget,
    stateGeneration: Long,
    callbackGeneration: Long,
    globalGeneration: Long,
): Boolean = repositoryMatches && profileMatches && stateTarget == callbackTarget &&
    stateGeneration == callbackGeneration && globalGeneration == callbackGeneration

internal fun virtualMachineOverviewCallbackMatches(
    repositoryMatches: Boolean,
    selectedModule: Module,
    currentProfileId: String,
    token: VirtualMachineOverviewRequestToken,
    globalGeneration: Long,
): Boolean = repositoryMatches && selectedModule == Module.VIRTUAL_MACHINES &&
    currentProfileId == token.profileId && token.generation == globalGeneration

internal fun virtualMachineOrdinaryLoadBlocked(
    state: VirtualMachineMutationWorkspaceState,
): Boolean = state.creationEditorVisible || state.imageImportEditorVisible || state.settingsEditorVisible ||
    state.lifecycleConfirmationRequested || state.target != null || state.mutationInProgress ||
    state.mutationRefreshInProgress || state.mutationResult != null || state.mutationFailure != null

internal fun cancelledVirtualMachineMutationResult(
    target: VirtualMachineMutationTarget,
): MutationResult = MutationResult(
    schemaVersion = 1,
    status = MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
    operation = target.operation,
    submitted = true,
    requiresRefresh = true,
    counts = MutationResultCounts(succeeded = 0, failed = 0, unknown = 1),
    errorCategory = MutationErrorCategory.UNKNOWN,
    diagnosticTag = "vmm.${target.kind.name.lowercase()}.cancelled-externally",
)

internal fun virtualMachineSettingsBaseline(
    resource: io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResource,
): VirtualMachineSettings? {
    val name = resource.name.takeIf {
        it.isNotBlank() && it.length <= 64 && it.none(Char::isISOControl)
    } ?: return null
    val description = resource.metadata["description"]?.takeIf { it.length <= 1_024 }
        ?: return null
    val cpu = resource.metadata["vcpu_num"]?.toIntOrNull()?.takeIf { it in 1..64 }
        ?: return null
    val memory = resource.metadata["vram_size"]?.toIntOrNull()?.takeIf { it in 128..1_048_576 }
        ?: return null
    val autorun = resource.metadata["autorun"]?.toIntOrNull()?.takeIf { it == 0 || it == 2 }
        ?: return null
    return VirtualMachineSettings(
        name = name,
        description = description,
        cpuCount = cpu,
        memoryMiB = memory,
        autoStart = autorun == 2,
    )
}

internal fun virtualMachineMutationVerification(
    state: VirtualMachineMutationWorkspaceState,
    overview: VirtualMachineOverview,
): VirtualMachineMutationVerification {
    val target = state.target ?: return VirtualMachineMutationVerification.UNAVAILABLE
    return when (target.kind) {
        VirtualMachineMutationKind.CREATION -> {
            // 创建结果未返回稳定 guest_id；同名列表项可能来自其他客户端，不能据此归属本次写入。
            VirtualMachineMutationVerification.UNAVAILABLE
        }
        VirtualMachineMutationKind.IMAGE_IMPORT -> {
            // 未确认结果没有稳定 image_id，不能按名称认领其他客户端创建的映像。
            VirtualMachineMutationVerification.UNAVAILABLE
        }
        VirtualMachineMutationKind.SETTINGS -> {
            val id = state.settingsTargetId ?: target.resourceId
                ?: return VirtualMachineMutationVerification.UNAVAILABLE
            val desired = state.settingsDraft?.toSettingsOrNull()
                ?: return VirtualMachineMutationVerification.UNAVAILABLE
            val machine = overview.machines.firstOrNull { it.id == id }
                ?: return VirtualMachineMutationVerification.DISAPPEARED
            val observed = virtualMachineSettingsBaseline(machine)
                ?: return VirtualMachineMutationVerification.UNAVAILABLE
            if (observed == desired) {
                VirtualMachineMutationVerification.MATCHES
            } else {
                VirtualMachineMutationVerification.DIFFERS
            }
        }
        VirtualMachineMutationKind.LIFECYCLE -> {
            val lifecycle = state.lifecycleConfirmationTarget
                ?: return VirtualMachineMutationVerification.UNAVAILABLE
            val sectionUnavailable = when (lifecycle.operation) {
                VirtualMachineLifecycleOperation.DELETE_IMAGE ->
                    io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineSection.IMAGES
                VirtualMachineLifecycleOperation.DELETE_NETWORK ->
                    io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineSection.NETWORKS
                VirtualMachineLifecycleOperation.RENAME_NETWORK ->
                    io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineSection.NETWORKS
                else -> null
            } in overview.unavailableSections
            if (sectionUnavailable) return VirtualMachineMutationVerification.UNAVAILABLE
            val resource = when (lifecycle.operation) {
                VirtualMachineLifecycleOperation.DELETE_IMAGE -> overview.images
                VirtualMachineLifecycleOperation.DELETE_NETWORK -> overview.networks
                VirtualMachineLifecycleOperation.RENAME_NETWORK -> overview.networks
                else -> overview.machines
            }.firstOrNull { it.id == lifecycle.resourceId }
                ?: return VirtualMachineMutationVerification.DISAPPEARED
            if (lifecycle.operation == VirtualMachineLifecycleOperation.RENAME_NETWORK) {
                return if (resource.name == lifecycle.command) {
                    VirtualMachineMutationVerification.MATCHES
                } else {
                    VirtualMachineMutationVerification.DIFFERS
                }
            }
            if (lifecycle.operation != VirtualMachineLifecycleOperation.CONTROL) {
                return VirtualMachineMutationVerification.DIFFERS
            }
            val expected = virtualMachineControlExpectedState(
                lifecycle.baselineState,
                checkNotNull(lifecycle.command),
            ) ?: return VirtualMachineMutationVerification.UNAVAILABLE
            if (resource.state == expected) {
                VirtualMachineMutationVerification.MATCHES
            } else {
                VirtualMachineMutationVerification.DIFFERS
            }
        }
    }
}
