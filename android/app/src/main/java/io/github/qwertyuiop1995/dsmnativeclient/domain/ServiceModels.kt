package io.github.qwertyuiop1995.dsmnativeclient.domain

enum class ResourceState {
    RUNNING,
    STOPPED,
    PAUSED,
    WAITING,
    HEALTHY,
    WARNING,
    ERROR,
    UNKNOWN,
}

data class ManagedResource(
    val id: String,
    val name: String,
    val detail: String,
    val state: ResourceState,
    val metadata: Map<String, String> = emptyMap(),
    val localizedLabel: ManagedResourceLabel? = null,
)

enum class ManagedResourceLabel {
    SECURITY_AUTO_BLOCK,
    SECURITY_DOS_PROTECTION,
    SECURITY_FIREWALL,
}

data class ContainerOverview(
    val containers: List<ManagedResource>,
    val images: List<ManagedResource>,
    val networks: List<ManagedResource>,
    val projects: List<ManagedResource>,
    val events: List<LogEntry> = emptyList(),
    val unavailableSections: Set<ContainerSection> = emptySet(),
)

enum class ContainerSection { IMAGES, NETWORKS, PROJECTS, EVENTS }

data class ContainerRegistryImage(
    val name: String,
    val registry: String,
    val description: String?,
    val starCount: Int,
    val isOfficial: Boolean,
    val isAutomated: Boolean,
    val isTrusted: Boolean,
) {
    val id: String get() = "$registry/$name"
}

enum class VirtualMachineSection { HOSTS, STORAGES, NETWORKS, IMAGES, PROTECTION, LOGS }

data class VirtualMachineOverview(
    val machines: List<ManagedResource>,
    val hosts: List<ManagedResource>,
    val storages: List<ManagedResource>,
    val networks: List<ManagedResource>,
    val images: List<ManagedResource>,
    val protectionPlans: List<ManagedResource>,
    val protectionSchedules: List<ManagedResource>,
    val retentionPolicies: List<ManagedResource>,
    val logs: List<LogEntry>,
    val unavailableSections: Set<VirtualMachineSection> = emptySet(),
)

data class VirtualMachineCreation(
    val name: String,
    val description: String,
    val cpuCount: Int,
    val memoryMiB: Int,
    val diskGiB: Int,
    val storageId: String,
    val networkId: String?,
    val diskImageId: String?,
    val autoStart: Boolean,
)

data class VirtualMachineSettings(
    val name: String,
    val description: String,
    val cpuCount: Int,
    val memoryMiB: Int,
    val autoStart: Boolean,
)

enum class LogLevel { INFO, WARNING, ERROR, UNKNOWN }

data class LogEntry(
    val id: String,
    val level: LogLevel,
    val timeEpochSeconds: Long?,
    val user: String,
    val event: String,
)
