package io.github.qwertyuiop1995.dsmnativeclient.domain

import org.junit.Assert.assertEquals
import org.junit.Test

class ContainerOverviewSummaryTest {
    @Test
    fun `容器总览只区分明确运行停止与其他状态`() {
        val summary = overview(
            containers = listOf(
                resource("running", ResourceState.RUNNING),
                resource("stopped", ResourceState.STOPPED),
                resource("paused", ResourceState.PAUSED),
                resource("healthy", ResourceState.HEALTHY),
                resource("unknown", ResourceState.UNKNOWN),
            ),
        ).toSummary()

        assertEquals(5, summary.totalContainers)
        assertEquals(1, summary.runningContainers)
        assertEquals(1, summary.stoppedContainers)
        assertEquals(3, summary.otherContainers)
    }

    @Test
    fun `成功读取的空附属分区保留可用零数量`() {
        val summary = overview().toSummary()

        assertEquals(ContainerSectionCount.Available(0), summary.images)
        assertEquals(ContainerSectionCount.Available(0), summary.networks)
        assertEquals(ContainerSectionCount.Available(0), summary.projects)
    }

    @Test
    fun `附属分区失败表达不可用而不冒充零或已有数量`() {
        val summary = overview(
            images = listOf(resource("image", ResourceState.HEALTHY)),
            networks = listOf(resource("network", ResourceState.UNKNOWN)),
            projects = listOf(resource("project", ResourceState.RUNNING)),
            unavailableSections = setOf(ContainerSection.IMAGES, ContainerSection.PROJECTS),
        ).toSummary()

        assertEquals(ContainerSectionCount.Unavailable, summary.images)
        assertEquals(ContainerSectionCount.Available(1), summary.networks)
        assertEquals(ContainerSectionCount.Unavailable, summary.projects)
    }

    @Test
    fun `事件内容和资源详情不进入派生总览`() {
        val base = overview(
            containers = listOf(resource("container", ResourceState.RUNNING)),
        )
        val withEvent = base.copy(
            events = listOf(
                LogEntry(
                    id = "sensitive-event-id",
                    level = LogLevel.INFO,
                    timeEpochSeconds = 1,
                    user = "synthetic-user",
                    event = "synthetic-event-content",
                ),
            ),
        )

        assertEquals(base.toSummary(), withEvent.toSummary())
    }

    private fun overview(
        containers: List<ManagedResource> = emptyList(),
        images: List<ManagedResource> = emptyList(),
        networks: List<ManagedResource> = emptyList(),
        projects: List<ManagedResource> = emptyList(),
        unavailableSections: Set<ContainerSection> = emptySet(),
    ) = ContainerOverview(
        containers = containers,
        images = images,
        networks = networks,
        projects = projects,
        unavailableSections = unavailableSections,
    )

    private fun resource(id: String, state: ResourceState) = ManagedResource(
        id = "sensitive-$id-id",
        name = "Synthetic $id",
        detail = "sensitive-$id-detail",
        state = state,
    )
}
