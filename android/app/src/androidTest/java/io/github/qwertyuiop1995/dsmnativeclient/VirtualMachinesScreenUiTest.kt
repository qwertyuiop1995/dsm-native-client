package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.VirtualMachineEmptyContent
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.virtualMachineLifecycleCommands
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.virtualMachineTabSupportsDeletion
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class VirtualMachinesScreenUiTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 空虚拟机说明原因并提供48dp创建入口() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var createCount = 0
        rule.setContent {
            LanStashTheme {
                VirtualMachineEmptyContent(
                    supportsCreation = true,
                    hasStorage = true,
                    enabled = true,
                    onCreate = { createCount++; true },
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.virtual_machine_empty_create_message))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.create_virtual_machine))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        assertTrue(createCount == 1)
    }

    @Test
    fun 不支持创建时给出外部下一步且不显示写入口() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        rule.setContent {
            LanStashTheme {
                VirtualMachineEmptyContent(
                    supportsCreation = false,
                    hasStorage = false,
                    enabled = true,
                    onCreate = { false },
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.virtual_machine_empty_external_message))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.create_virtual_machine)).assertDoesNotExist()
    }

    @Test
    fun 网络分区保持只读而虚拟机和映像允许公开删除() {
        assertFalse(virtualMachineTabSupportsDeletion(3))
        assertTrue(virtualMachineTabSupportsDeletion(0))
        assertTrue(virtualMachineTabSupportsDeletion(4))
    }

    @Test
    fun 虚拟机电源操作只显示与当前状态匹配的命令() {
        assertEquals(
            setOf("poweron"),
            virtualMachineLifecycleCommands(ResourceState.STOPPED),
        )
        assertEquals(
            setOf("shutdown", "poweroff"),
            virtualMachineLifecycleCommands(ResourceState.RUNNING),
        )
        ResourceState.entries
            .filter { it != ResourceState.STOPPED && it != ResourceState.RUNNING }
            .forEach { state ->
                assertTrue("$state 不应显示虚拟机电源操作", virtualMachineLifecycleCommands(state).isEmpty())
            }
    }
}
