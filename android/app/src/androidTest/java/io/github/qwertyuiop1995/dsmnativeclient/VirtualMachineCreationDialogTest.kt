package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.LogEntry
import io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResource
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineCreation
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineOverview
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineSettings
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.VirtualMachineLifecycleConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.VirtualMachineCreationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.VirtualMachineSettingsDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class VirtualMachineCreationDialogTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 分步选择资源后提交稳定配置() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var submitted: VirtualMachineCreation? = null
        var draft by mutableStateOf(creationDraft())
        rule.setContent {
            LanStashTheme {
                VirtualMachineCreationDialog(
                    overview = overview(),
                    draft = draft,
                    submitting = false,
                    onDraftChange = { draft = it; true },
                    onConfirm = { submitted = draft.toCreationOrNull(); true },
                    onDismiss = { true },
                )
            }
        }

        rule.onNode(
            hasText(context.getString(R.string.virtual_machine_name)) and hasSetTextAction(),
        ).performTextInput("Synthetic VM")
        rule.onNodeWithText(context.getString(R.string.virtual_machine_next_step)).performClick()
        rule.onNodeWithText(context.getString(R.string.virtual_machine_cpu)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.virtual_machine_next_step)).performClick()
        rule.onNode(hasText("Synthetic network") and hasClickAction())
            .performScrollTo().assertHeightIsAtLeast(48.dp).performClick()
        rule.onNode(hasText("Synthetic disk image") and hasClickAction())
            .performScrollTo().assertHeightIsAtLeast(48.dp).performClick()
        rule.onNodeWithText(context.getString(R.string.virtual_machine_review))
            .performScrollTo().assertIsDisplayed()
        rule.onNodeWithText(
            context.getString(
                R.string.virtual_machine_review_item,
                context.getString(R.string.virtual_machine_name),
                "Synthetic VM",
            ),
        ).performScrollTo().assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.create)).performClick()

        rule.runOnIdle {
            check(submitted?.name == "Synthetic VM")
            check(submitted?.storageId == "storage-1")
            check(submitted?.networkId == "network-1")
            check(submitted?.diskImageId == "image-1")
        }
    }

    @Test
    fun 创建字段错误可感知且步骤向读屏报告() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var draft by mutableStateOf(creationDraft())
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

        val firstStep = context.getString(R.string.virtual_machine_creation_step, 1, 3)
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, firstStep),
        ).assertIsDisplayed()
        rule.onNode(
            hasText(context.getString(R.string.virtual_machine_name_required)) and
                SemanticsMatcher.expectValue(
                    SemanticsProperties.LiveRegion,
                    LiveRegionMode.Assertive,
                ),
        ).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.virtual_machine_next_step))
            .assertHeightIsAtLeast(48.dp)
            .assertIsNotEnabled()
    }

    @Test
    fun 自动启动整行提供开关状态与48dp触控入口() {
        var draft by mutableStateOf(creationDraft())
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

        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch) and
                SemanticsMatcher.expectValue(
                    SemanticsProperties.ToggleableState,
                    ToggleableState.Off,
                ),
        ).assertHeightIsAtLeast(48.dp).performClick()
        rule.runOnIdle { check(draft.autoStart) }
    }

    @Test
    fun 没有存储时说明原因并禁用创建() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var draft by mutableStateOf(creationDraft(storageId = ""))
        rule.setContent {
            LanStashTheme {
                VirtualMachineCreationDialog(
                    overview = overview().copy(storages = emptyList()),
                    draft = draft,
                    submitting = false,
                    onDraftChange = { draft = it; true },
                    onConfirm = { true },
                    onDismiss = { true },
                )
            }
        }

        rule.onNode(
            hasText(context.getString(R.string.virtual_machine_name)) and hasSetTextAction(),
        ).performTextInput("Synthetic VM")
        rule.onNodeWithText(context.getString(R.string.virtual_machine_next_step)).performClick()
        rule.onNodeWithText(context.getString(R.string.virtual_machine_next_step)).performClick()
        rule.onNodeWithText(context.getString(R.string.virtual_machine_no_storage))
            .performScrollTo().assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.create)).assertIsNotEnabled()
    }

    @Test
    fun 常规设置使用稳定标识并提交结构化值() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var submitted: VirtualMachineSettings? = null
        val baseline = VirtualMachineSettings("Old name", "Old description", 2, 2048, false)
        var draft by mutableStateOf(VirtualMachineSettingsDraftState.from(baseline))
        rule.setContent {
            LanStashTheme {
                VirtualMachineSettingsDialog(
                    draft = draft,
                    baseline = baseline,
                    submitting = false,
                    onDraftChange = { draft = it; true },
                    onConfirm = { submitted = draft.toSettingsOrNull(); true },
                    onDismiss = { true },
                )
            }
        }

        val nameField = rule.onNode(
            hasText(context.getString(R.string.virtual_machine_name)) and hasSetTextAction(),
        )
        nameField.performTextClearance()
        nameField.performTextInput("Updated VM")
        rule.onNodeWithText(context.getString(R.string.virtual_machine_auto_start)).performClick()
        rule.onNodeWithText(context.getString(R.string.save))
            .assertHeightIsAtLeast(48.dp)
            .performClick()

        rule.runOnIdle {
            check(submitted?.name == "Updated VM")
            check(submitted?.description == "Old description")
            check(submitted?.cpuCount == 2)
            check(submitted?.memoryMiB == 2048)
            check(submitted?.autoStart == true)
        }
    }

    @Test
    fun 设置字段错误使用断言式提示并阻止保存() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val baseline = VirtualMachineSettings("Invalid VM", "", 1, 2048, false)
        var draft by mutableStateOf(
            VirtualMachineSettingsDraftState.from(baseline).copy(cpu = "0"),
        )
        rule.setContent {
            LanStashTheme {
                VirtualMachineSettingsDialog(
                    draft = draft,
                    baseline = baseline,
                    submitting = false,
                    onDraftChange = { draft = it; true },
                    onConfirm = { true },
                    onDismiss = { true },
                )
            }
        }

        rule.onNode(
            hasText(context.getString(R.string.virtual_machine_cpu_range)) and
                SemanticsMatcher.expectValue(
                    SemanticsProperties.LiveRegion,
                    LiveRegionMode.Assertive,
                ),
        ).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.save))
            .assertHeightIsAtLeast(48.dp)
            .assertIsNotEnabled()
    }

    @Test
    fun 深色两倍字体下可滚动到创建复核() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var draft by mutableStateOf(creationDraft())
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(density.density, fontScale = 2f),
            ) {
                LanStashTheme(darkTheme = true) {
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
        }

        rule.onNode(
            hasText(context.getString(R.string.virtual_machine_name)) and hasSetTextAction(),
        ).performTextInput("Large text VM")
        rule.onNodeWithText(context.getString(R.string.virtual_machine_next_step)).performClick()
        rule.onNodeWithText(context.getString(R.string.virtual_machine_next_step)).performClick()
        rule.onNodeWithText(context.getString(R.string.virtual_machine_review))
            .performScrollTo()
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.create))
            .assertHeightIsAtLeast(48.dp)
            .assertIsDisplayed()
    }

    @Test
    fun 创建草稿与步骤重建后保留且不重放确认() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val restoration = StateRestorationTester(rule)
        var draft by mutableStateOf(creationDraft())
        var confirmCount = 0
        restoration.setContent {
            LanStashTheme {
                VirtualMachineCreationDialog(
                    overview = overview(),
                    draft = draft,
                    submitting = false,
                    onDraftChange = { draft = it; true },
                    onConfirm = { confirmCount++; true },
                    onDismiss = { true },
                )
            }
        }

        rule.onNode(
            hasText(context.getString(R.string.virtual_machine_name)) and hasSetTextAction(),
        ).performTextInput("Restored VM")
        rule.onNodeWithText(context.getString(R.string.virtual_machine_next_step)).performClick()
        restoration.emulateSavedInstanceStateRestore()

        check(draft.name == "Restored VM")
        val secondStep = context.getString(R.string.virtual_machine_creation_step, 2, 3)
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, secondStep),
        ).assertIsDisplayed()
        check(confirmCount == 0)
    }

    @Test
    fun 设置草稿重建后保留且不重放确认() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val restoration = StateRestorationTester(rule)
        val baseline = VirtualMachineSettings("Old name", "", 2, 2048, false)
        var draft by mutableStateOf(VirtualMachineSettingsDraftState.from(baseline))
        var confirmCount = 0
        restoration.setContent {
            LanStashTheme {
                VirtualMachineSettingsDialog(
                    draft = draft,
                    baseline = baseline,
                    submitting = false,
                    onDraftChange = { draft = it; true },
                    onConfirm = { confirmCount++; true },
                    onDismiss = { true },
                )
            }
        }

        rule.onNode(hasText("Old name") and hasSetTextAction()).performTextClearance()
        rule.onNode(
            hasText(context.getString(R.string.virtual_machine_name)) and hasSetTextAction(),
        ).performTextInput("Restored settings")
        restoration.emulateSavedInstanceStateRestore()

        rule.onNodeWithText("Restored settings").assertIsDisplayed()
        check(confirmCount == 0)
    }

    @Test
    fun 生命周期确认重建后保留且不重放请求() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val restoration = StateRestorationTester(rule)
        val target = VirtualMachineLifecycleTarget(
            profileId = "profile-1",
            resourceId = "guest-1",
            operation = VirtualMachineLifecycleOperation.CONTROL,
            baselineState = ResourceState.RUNNING,
            command = "shutdown",
        )
        var confirmCount = 0
        restoration.setContent {
            LanStashTheme {
                VirtualMachineLifecycleConfirmationDialog(
                    target = target,
                    resourceName = "Synthetic VM",
                    onConfirm = { confirmCount++; true },
                    onDismiss = { true },
                )
            }
        }

        restoration.emulateSavedInstanceStateRestore()

        rule.onNodeWithText(
            context.getString(R.string.shutdown_virtual_machine_title, "Synthetic VM"),
        ).assertIsDisplayed()
        check(confirmCount == 0)
    }

    @Test
    fun 创建确认接收后立即禁用以阻止双击() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var draft by mutableStateOf(creationDraft(step = 2, name = "Single request"))
        var submitting by mutableStateOf(false)
        var confirmCount = 0
        rule.setContent {
            LanStashTheme {
                VirtualMachineCreationDialog(
                    overview = overview(),
                    draft = draft,
                    submitting = submitting,
                    onDraftChange = { draft = it; true },
                    onConfirm = {
                        if (submitting) {
                            false
                        } else {
                            submitting = true
                            confirmCount++
                            true
                        }
                    },
                    onDismiss = { true },
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.create)).performClick()
        rule.onNodeWithText(context.getString(R.string.create)).assertIsNotEnabled()
        check(confirmCount == 1)
    }

    private fun overview() = VirtualMachineOverview(
        machines = emptyList(),
        hosts = emptyList(),
        storages = listOf(resource("storage-1", "Synthetic storage")),
        networks = listOf(resource("network-1", "Synthetic network")),
        images = listOf(
            resource("image-1", "Synthetic disk image").copy(metadata = mapOf("type" to "disk")),
        ),
        protectionPlans = emptyList(),
        protectionSchedules = emptyList(),
        retentionPolicies = emptyList(),
        logs = emptyList<LogEntry>(),
    )

    private fun creationDraft(
        step: Int = 0,
        name: String = "",
        storageId: String = "storage-1",
    ) = VirtualMachineCreationDraftState(
        step = step,
        name = name,
        storageId = storageId,
    )

    private fun resource(id: String, name: String) = ManagedResource(
        id = id,
        name = name,
        detail = "",
        state = ResourceState.HEALTHY,
    )
}
