package io.github.qwertyuiop1995.dsmnativeclient

import android.view.KeyEvent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.LogEntry
import io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResource
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineOverview
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.VirtualMachineCreationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class VirtualMachineCreationSystemBackTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 系统返回从第三步回到第二步并保留草稿() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var draft by mutableStateOf(creationDraft(step = 2))
        var dismissCount = 0
        rule.setContent {
            LanStashTheme {
                VirtualMachineCreationDialog(
                    overview = overview(),
                    draft = draft,
                    submitting = false,
                    onDraftChange = { draft = it; true },
                    onConfirm = { true },
                    onDismiss = { dismissCount++; true },
                )
            }
        }

        pressSystemBack()

        rule.onNodeWithText(context.getString(R.string.virtual_machine_cpu)).assertIsDisplayed()
        rule.runOnIdle {
            check(draft.step == 1)
            check(draft.name == "Synthetic VM")
            check(dismissCount == 0)
        }
    }

    @Test
    fun 系统返回从第二步回到第一步() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var draft by mutableStateOf(creationDraft(step = 1))
        rule.setContent {
            LanStashTheme {
                VirtualMachineCreationDialog(
                    overview = overview(),
                    draft = draft,
                    submitting = false,
                    onDraftChange = { draft = it; true },
                    onConfirm = { true },
                    onDismiss = { true },
                )
            }
        }

        pressSystemBack()

        rule.onNodeWithText(context.getString(R.string.virtual_machine_name)).assertIsDisplayed()
        rule.runOnIdle { check(draft.step == 0) }
    }

    @Test
    fun 系统返回在第一步请求关闭向导() {
        var visible by mutableStateOf(true)
        var dismissCount = 0
        rule.setContent {
            LanStashTheme {
                if (visible) {
                    VirtualMachineCreationDialog(
                        overview = overview(),
                        draft = creationDraft(step = 0),
                        submitting = false,
                        onDraftChange = { true },
                        onConfirm = { true },
                        onDismiss = {
                            dismissCount++
                            visible = false
                            true
                        },
                    )
                }
            }
        }

        pressSystemBack()

        rule.runOnIdle {
            check(!visible)
            check(dismissCount == 1)
        }
    }

    @Test
    fun 提交期间系统返回不改变步骤也不请求关闭() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var draft by mutableStateOf(creationDraft(step = 2))
        var draftChangeCount = 0
        var dismissCount = 0
        rule.setContent {
            LanStashTheme {
                VirtualMachineCreationDialog(
                    overview = overview(),
                    draft = draft,
                    submitting = true,
                    onDraftChange = {
                        draftChangeCount++
                        draft = it
                        true
                    },
                    onConfirm = { true },
                    onDismiss = { dismissCount++; true },
                )
            }
        }

        pressSystemBack()

        rule.onNodeWithText(context.getString(R.string.create_virtual_machine)).assertIsDisplayed()
        rule.runOnIdle {
            check(draft.step == 2)
            check(draftChangeCount == 0)
            check(dismissCount == 0)
        }
    }

    @Test
    fun 业务门禁拒绝退出时系统返回保持当前步骤() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val draft = creationDraft(step = 2)
        var draftChangeCount = 0
        rule.setContent {
            LanStashTheme {
                VirtualMachineCreationDialog(
                    overview = overview(),
                    draft = draft,
                    submitting = false,
                    onDraftChange = {
                        draftChangeCount++
                        false
                    },
                    onConfirm = { true },
                    onDismiss = { false },
                )
            }
        }

        pressSystemBack()

        rule.onNodeWithText(context.getString(R.string.virtual_machine_review)).assertIsDisplayed()
        rule.runOnIdle { check(draftChangeCount == 1) }
    }

    private fun creationDraft(step: Int) = VirtualMachineCreationDraftState(
        step = step,
        name = "Synthetic VM",
        storageId = "storage-1",
    )

    private fun overview() = VirtualMachineOverview(
        machines = emptyList(),
        hosts = emptyList(),
        storages = listOf(resource("storage-1", "Synthetic storage")),
        networks = emptyList(),
        images = emptyList(),
        protectionPlans = emptyList(),
        protectionSchedules = emptyList(),
        retentionPolicies = emptyList(),
        logs = emptyList<LogEntry>(),
    )

    private fun resource(id: String, name: String) = ManagedResource(
        id = id,
        name = name,
        detail = "",
        state = ResourceState.HEALTHY,
    )

    private fun pressSystemBack() {
        rule.waitForIdle()
        InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
    }
}
