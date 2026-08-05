package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineOverview
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineSection
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineTaskCenterState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class VirtualMachineTaskPollingStateTest {
    @Test
    fun `只有最终应用的离开导航才停止轮询`() {
        listOf(WorkspaceNavigationResult.REJECTED, WorkspaceNavigationResult.DEFERRED).forEach {
            assertFalse(
                shouldStopVirtualMachineTaskPollingAfterNavigation(
                    Module.VIRTUAL_MACHINES,
                    Module.FILES,
                    it,
                ),
            )
        }
        assertTrue(
            shouldStopVirtualMachineTaskPollingAfterNavigation(
                Module.VIRTUAL_MACHINES,
                Module.FILES,
                WorkspaceNavigationResult.APPLIED,
            ),
        )
        assertFalse(
            shouldStopVirtualMachineTaskPollingAfterNavigation(
                Module.VIRTUAL_MACHINES,
                Module.VIRTUAL_MACHINES,
                WorkspaceNavigationResult.ALREADY_SELECTED,
            ),
        )
    }

    @Test
    fun `仅在 VMM 可见且存在未完成任务时轮询`() {
        val running = overview(listOf(VirtualMachineTask("running", false, 40)))
        assertTrue(shouldPollVirtualMachineTasks(Module.VIRTUAL_MACHINES, running))
        assertFalse(shouldPollVirtualMachineTasks(Module.FILES, running))
        assertFalse(
            shouldPollVirtualMachineTasks(
                Module.VIRTUAL_MACHINES,
                overview(listOf(VirtualMachineTask("done", true, 100))),
            ),
        )
        assertFalse(shouldPollVirtualMachineTasks(Module.VIRTUAL_MACHINES, null))
    }

    @Test
    fun `轮询失败保留上次成功总览而成功只替换任务分区`() {
        val previous = overview(
            listOf(VirtualMachineTask("running", false, 40)),
            unavailable = setOf(VirtualMachineSection.TASKS),
        )
        val initial = WorkspaceState(
            profile = NasProfile("profile", "NAS", "https://nas.invalid", "tester"),
            selectedModule = Module.VIRTUAL_MACHINES,
            virtualMachines = Loadable.Ready(previous),
        )
        val failure = DsmFailure(null, "Synthetic", "Retry")

        val failed = initial.withVirtualMachineTaskPollingFailure(failure)

        assertSame(previous, (failed.virtualMachines as Loadable.Ready).value)
        assertSame(failure, failed.virtualMachineMutationState.taskPolling.failure)

        val completed = listOf(VirtualMachineTask("done", true, 100))
        val refreshed = failed.withVirtualMachineTaskPollingResult(completed)
        val refreshedOverview = (refreshed.virtualMachines as Loadable.Ready).value
        assertEquals(completed, refreshedOverview.tasks)
        assertFalse(VirtualMachineSection.TASKS in refreshedOverview.unavailableSections)
        assertEquals(VirtualMachineTaskCenterState.AVAILABLE, refreshedOverview.taskCenterState)
        assertEquals(VirtualMachineTaskPollingState(), refreshed.virtualMachineMutationState.taskPolling)
    }

    private fun overview(
        tasks: List<VirtualMachineTask>,
        unavailable: Set<VirtualMachineSection> = emptySet(),
    ) = VirtualMachineOverview(
        machines = emptyList(),
        hosts = emptyList(),
        storages = emptyList(),
        networks = emptyList(),
        images = emptyList(),
        protectionPlans = emptyList(),
        protectionSchedules = emptyList(),
        retentionPolicies = emptyList(),
        logs = emptyList(),
        tasks = tasks,
        taskCenterState = VirtualMachineTaskCenterState.AVAILABLE,
        unavailableSections = unavailable,
    )
}
