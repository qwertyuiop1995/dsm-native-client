package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResource
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineDisk
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineDiskController
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineGuestDetails
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineHardware
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineNetworkInterface
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineNetworkModel
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.VIRTUAL_MACHINE_DETAIL_SCROLL_TEST_TAG
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.VirtualMachineGuestDetailsScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import java.text.NumberFormat
import org.junit.Rule
import org.junit.Test

class VirtualMachineGuestDetailsUiTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 加载状态提供加载语义以及48dp返回和刷新入口() {
        val context = context()
        var retryCount = 0
        var navigateUpCount = 0

        setGuestContent(
            guest = Loadable.Loading,
            onRetry = { retryCount += 1 },
            onNavigateUp = { navigateUpCount += 1 },
        )

        rule.onNodeWithContentDescription(context.getString(R.string.loading)).assertIsDisplayed()
        rule.onNodeWithContentDescription(context.getString(R.string.go_up))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.onNodeWithContentDescription(context.getString(R.string.refresh))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle {
            check(navigateUpCount == 1)
            check(retryCount == 1)
        }
    }

    @Test
    fun 错误状态说明下一步并允许重试且不展示内部失败详情() {
        val context = context()
        var retryCount = 0
        setGuestContent(
            guest = Loadable.Failed(
                DsmFailure(
                    code = null,
                    message = "internal-guest-load-failure",
                    recovery = "internal-guest-load-recovery",
                ),
            ),
            onRetry = { retryCount += 1 },
        )

        rule.onNodeWithText(context.getString(R.string.service_section_unavailable_title))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.service_section_unavailable_message))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.refresh))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.onNodeWithText("internal-guest-load", substring = true).assertDoesNotExist()
        rule.runOnIdle { check(retryCount == 1) }
    }

    @Test
    fun 正常状态只显示来宾与硬件只读投影且不含写操作或内部标识() {
        val context = context()
        var retryCount = 0
        setGuestContent(guest = Loadable.Ready(guestDetails()), onRetry = { retryCount += 1 })

        val diskSize = context.getString(
            R.string.virtual_machine_disk_size_mib,
            NumberFormat.getIntegerInstance().format(10_240),
        )
        rule.onNodeWithText("Synthetic guest").assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.running)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.virtual_machine_hardware_configuration))
            .assertIsDisplayed()
        rule.onNodeWithText(
            context.getString(
                R.string.virtual_machine_disk_summary,
                diskSize,
                context.getString(R.string.virtual_machine_hardware_virtio),
                context.getString(R.string.virtual_machine_space_reclamation_enabled),
            ),
        ).assertIsDisplayed()
        rule.onNodeWithContentDescription(context.getString(R.string.refresh)).performClick()
        listOf(
            R.string.start,
            R.string.edit_virtual_machine,
            R.string.normal_shutdown,
            R.string.force_shutdown,
            R.string.delete,
        ).forEach { action ->
            rule.onAllNodesWithText(context.getString(action)).assertCountEquals(0)
        }
        listOf(
            "private-guest-id",
            "private-machine-id",
            "private-disk-id",
            "private-network-id",
            "private-nic-id",
            "internal-guest-detail",
        ).forEach { internalValue ->
            rule.onNodeWithText(internalValue, substring = true).assertDoesNotExist()
        }
        rule.runOnIdle { check(retryCount == 1) }
    }

    @Test
    fun 两倍字体下合法空硬件仍可滚动到普通空态且顶栏保持可达() {
        val context = context()
        setGuestContent(
            guest = Loadable.Ready(guestDetails(emptyHardware = true)),
            fontScale = 2f,
            compact = true,
            darkTheme = true,
        )

        rule.onNodeWithTag(VIRTUAL_MACHINE_DETAIL_SCROLL_TEST_TAG).assert(hasScrollAction())
        rule.onNodeWithTag(VIRTUAL_MACHINE_DETAIL_SCROLL_TEST_TAG).performScrollToNode(
            hasText(context.getString(R.string.virtual_machine_no_disks)),
        )
        rule.onNodeWithText(context.getString(R.string.virtual_machine_no_disks)).assertIsDisplayed()
        rule.onNodeWithTag(VIRTUAL_MACHINE_DETAIL_SCROLL_TEST_TAG).performScrollToNode(
            hasText(context.getString(R.string.virtual_machine_no_network_interfaces)),
        )
        rule.onNodeWithText(context.getString(R.string.virtual_machine_no_network_interfaces))
            .assertIsDisplayed()
        rule.onNodeWithContentDescription(context.getString(R.string.go_up))
            .assertIsDisplayed()
            .assertHeightIsAtLeast(48.dp)
        rule.onNodeWithContentDescription(context.getString(R.string.refresh))
            .assertIsDisplayed()
            .assertHeightIsAtLeast(48.dp)
    }

    private fun setGuestContent(
        guest: Loadable<VirtualMachineGuestDetails>,
        fontScale: Float = 1f,
        compact: Boolean = false,
        darkTheme: Boolean = false,
        onRetry: () -> Unit = {},
        onNavigateUp: () -> Unit = {},
    ) {
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(density.density, fontScale),
            ) {
                LanStashTheme(darkTheme = darkTheme) {
                    Box(
                        Modifier
                            .width(if (compact) 320.dp else 360.dp)
                            .height(if (compact) 320.dp else 640.dp),
                    ) {
                        VirtualMachineGuestDetailsScreen(
                            guest = guest,
                            onRetry = onRetry,
                            onNavigateUp = onNavigateUp,
                        )
                    }
                }
            }
        }
    }

    private fun guestDetails(emptyHardware: Boolean = false) = VirtualMachineGuestDetails(
        resource = ManagedResource(
            id = "private-guest-id",
            name = "Synthetic guest",
            detail = "internal-guest-detail",
            state = ResourceState.RUNNING,
            metadata = mapOf("guest_id" to "private-guest-id"),
        ),
        hardware = VirtualMachineHardware(
            machineId = "private-machine-id",
            disks = if (emptyHardware) {
                emptyList()
            } else {
                listOf(
                    VirtualMachineDisk(
                        id = "private-disk-id",
                        sizeMiB = 10_240,
                        controller = VirtualMachineDiskController.VIRTIO,
                        spaceReclamationEnabled = true,
                    ),
                )
            },
            networkInterfaces = if (emptyHardware) {
                emptyList()
            } else {
                listOf(
                    VirtualMachineNetworkInterface(
                        id = "private-nic-id",
                        networkId = "private-network-id",
                        networkName = "Default Network",
                        model = VirtualMachineNetworkModel.E1000,
                    ),
                )
            },
        ),
    )

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
}
