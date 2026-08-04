package io.github.qwertyuiop1995.dsmnativeclient.domain

/** 附属分区的本地计数；读取失败与真实空列表必须保持不同语义。 */
internal sealed interface ContainerSectionCount {
    data class Available(val count: Int) : ContainerSectionCount {
        init {
            require(count >= 0) { "Container section count cannot be negative" }
        }
    }

    data object Unavailable : ContainerSectionCount
}

/**
 * 仅从已经读取的稳定列表字段派生的 Container Manager 总览。
 *
 * 此模型不复制资源标识、详情、事件或其他可能包含敏感内容的字段。
 */
internal data class ContainerOverviewSummary(
    val totalContainers: Int,
    val runningContainers: Int,
    val stoppedContainers: Int,
    val otherContainers: Int,
    val images: ContainerSectionCount,
    val networks: ContainerSectionCount,
    val projects: ContainerSectionCount,
)

internal fun ContainerOverview.toSummary(): ContainerOverviewSummary {
    val running = containers.count { it.state == ResourceState.RUNNING }
    val stopped = containers.count { it.state == ResourceState.STOPPED }
    return ContainerOverviewSummary(
        totalContainers = containers.size,
        runningContainers = running,
        stoppedContainers = stopped,
        otherContainers = containers.size - running - stopped,
        images = sectionCount(ContainerSection.IMAGES, images.size),
        networks = sectionCount(ContainerSection.NETWORKS, networks.size),
        projects = sectionCount(ContainerSection.PROJECTS, projects.size),
    )
}

private fun ContainerOverview.sectionCount(
    section: ContainerSection,
    count: Int,
): ContainerSectionCount = if (section in unavailableSections) {
    ContainerSectionCount.Unavailable
} else {
    ContainerSectionCount.Available(count)
}
