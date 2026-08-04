package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineSettings
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.VirtualMachineMutationFeedbackCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.VirtualMachineMutationFeedbackDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.virtualMachineFeedbackPolicy
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class VirtualMachineMutationFeedbackTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 八类结果均有独立持久反馈策略() {
        val expected = mapOf(
            MutationResultStatus.CONFIRMED_SUCCESS to R.string.virtual_machine_feedback_confirmed_title,
            MutationResultStatus.PARTIAL_SUCCESS to R.string.virtual_machine_feedback_partial_title,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED to R.string.virtual_machine_feedback_check_title,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION to
                R.string.virtual_machine_feedback_check_title,
            MutationResultStatus.PERMISSION_DENIED to R.string.virtual_machine_feedback_permission_title,
            MutationResultStatus.UNSUPPORTED to R.string.virtual_machine_feedback_unavailable_title,
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION to
                R.string.virtual_machine_feedback_cancelled_title,
            MutationResultStatus.CONFIRMED_FAILURE to R.string.virtual_machine_feedback_failed_title,
        )
        expected.forEach { (status, title) ->
            assertEquals(title, virtualMachineFeedbackPolicy(result(status)).title)
        }
    }

    @Test
    fun 未确认结果显示计数并在刷新前阻止关闭() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var refreshCount = 0
        var dismissCount = 0
        showDialog(
            mutationState(
                result = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
            ),
            onRefresh = { refreshCount++; true },
            onContinueEditing = { true },
            onDismiss = { dismissCount++; true },
        )

        rule.onNodeWithText(context.getString(R.string.virtual_machine_feedback_counts, 0, 0, 1))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_virtual_machines))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.onNodeWithText(context.getString(R.string.close_checked_virtual_machine_feedback))
            .assertIsNotEnabled()
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive),
        ).assertIsDisplayed()
        assertEquals(1, refreshCount)
        assertEquals(0, dismissCount)
    }

    @Test
    fun 四类刷新核对状态均展示且只匹配结果使用礼貌通知() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val messages = mapOf(
            VirtualMachineMutationVerification.MATCHES to R.string.virtual_machine_feedback_refresh_matches,
            VirtualMachineMutationVerification.DIFFERS to R.string.virtual_machine_feedback_refresh_differs,
            VirtualMachineMutationVerification.DISAPPEARED to
                R.string.virtual_machine_feedback_refresh_disappeared,
            VirtualMachineMutationVerification.UNAVAILABLE to
                R.string.virtual_machine_feedback_refresh_unavailable,
        )
        var current by mutableStateOf(VirtualMachineMutationVerification.MATCHES)
        rule.setContent {
            LanStashTheme {
                VirtualMachineMutationFeedbackCard(
                    mutationState(
                        result = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
                        refreshCompleted = true,
                        verification = current,
                    ),
                )
            }
        }
        messages.forEach { (verification, message) ->
            rule.runOnIdle { current = verification }
            rule.onNodeWithText(context.getString(message)).assertIsDisplayed()
        }
    }

    @Test
    fun 已确认成功使用礼貌通知并允许关闭() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var dismissCount = 0
        showDialog(
            mutationState(result = result(MutationResultStatus.CONFIRMED_SUCCESS)),
            onDismiss = { dismissCount++; true },
        )

        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite),
        ).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.close))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        assertEquals(1, dismissCount)
    }

    @Test
    fun 创建未提交失败可继续编辑且明确关闭仍可放弃() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var continueCount = 0
        var dismissCount = 0
        showDialog(
            mutationState(result = result(MutationResultStatus.CONFIRMED_FAILURE)),
            onContinueEditing = { continueCount++; true },
            onDismiss = { dismissCount++; true },
        )

        rule.onNodeWithText(context.getString(R.string.continue_editing))
            .assertHeightIsAtLeast(48.dp)
            .assertIsEnabled()
            .performClick()
        assertEquals(1, continueCount)
        assertEquals(0, dismissCount)
        rule.onNodeWithText(context.getString(R.string.close)).performClick()
        assertEquals(1, dismissCount)
    }

    @Test
    fun 设置未提交失败可继续编辑() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var continueCount = 0
        showDialog(
            mutationState(
                result = result(MutationResultStatus.PERMISSION_DENIED),
                kind = VirtualMachineMutationKind.SETTINGS,
            ),
            onContinueEditing = { continueCount++; true },
        )

        rule.onNodeWithText(context.getString(R.string.continue_editing)).performClick()
        assertEquals(1, continueCount)
    }

    @Test
    fun 异常与刷新失败在深色两倍字体下保持刷新门禁() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val failure = DsmFailure(
            code = null,
            message = "Synthetic failure",
            recovery = "Synthetic recovery",
            kind = DsmErrorKind.UNKNOWN,
        )
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(density.density, fontScale = 2f),
            ) {
                LanStashTheme(darkTheme = true) {
                    VirtualMachineMutationFeedbackDialog(
                        state = mutationState(failure = failure, refreshFailure = failure),
                        onRefresh = { true },
                        onContinueEditing = { true },
                        onDismiss = { true },
                    )
                }
            }
        }

        rule.onNodeWithText(context.getString(R.string.refresh_and_check_virtual_machines))
            .assertHeightIsAtLeast(48.dp)
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.close_checked_virtual_machine_feedback))
            .assertIsNotEnabled()
    }

    private fun showDialog(
        state: VirtualMachineMutationWorkspaceState,
        onRefresh: () -> Boolean = { true },
        onContinueEditing: () -> Boolean = { true },
        onDismiss: () -> Boolean = { true },
    ) {
        rule.setContent {
            LanStashTheme {
                VirtualMachineMutationFeedbackDialog(
                    state,
                    onRefresh,
                    onContinueEditing,
                    onDismiss,
                )
            }
        }
    }

    private fun mutationState(
        result: MutationResult? = null,
        failure: DsmFailure? = null,
        refreshFailure: DsmFailure? = null,
        refreshCompleted: Boolean = false,
        verification: VirtualMachineMutationVerification? = null,
        kind: VirtualMachineMutationKind = VirtualMachineMutationKind.CREATION,
    ) = VirtualMachineMutationWorkspaceState(
        creationEditorVisible = kind == VirtualMachineMutationKind.CREATION,
        creationDraft = VirtualMachineCreationDraftState().takeIf {
            kind == VirtualMachineMutationKind.CREATION
        },
        settingsEditorVisible = kind == VirtualMachineMutationKind.SETTINGS,
        settingsTargetId = "guest-1".takeIf { kind == VirtualMachineMutationKind.SETTINGS },
        settingsBaseline = VirtualMachineSettings("VM", "", 2, 2_048, false).takeIf {
            kind == VirtualMachineMutationKind.SETTINGS
        },
        settingsDraft = VirtualMachineSettingsDraftState(
            name = "VM",
            description = "",
            cpu = "2",
            memory = "2048",
            autoStart = false,
        ).takeIf { kind == VirtualMachineMutationKind.SETTINGS },
        target = target(kind),
        mutationResult = result,
        mutationFailure = failure,
        mutationRefreshFailure = refreshFailure,
        mutationRefreshCompleted = refreshCompleted,
        mutationVerification = verification,
    )

    private fun target(kind: VirtualMachineMutationKind) = VirtualMachineMutationTarget(
        profileId = "profile-1",
        kind = kind,
        operation = if (kind == VirtualMachineMutationKind.SETTINGS) {
            "virtualMachineSet"
        } else "virtualMachineCreate",
        resourceId = "guest-1".takeIf { kind == VirtualMachineMutationKind.SETTINGS },
        requestFingerprint = "0".repeat(64),
    )

    private fun result(status: MutationResultStatus): MutationResult {
        val submitted = status in setOf(
            MutationResultStatus.CONFIRMED_SUCCESS,
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        )
        val requiresRefresh = status in setOf(
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        )
        val counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
            else -> MutationResultCounts(0, 1, 0)
        }
        return MutationResult(
            schemaVersion = 1,
            status = status,
            operation = "virtualMachineCreate",
            submitted = submitted,
            requiresRefresh = requiresRefresh,
            counts = counts,
            errorCategory = if (status == MutationResultStatus.CONFIRMED_FAILURE) {
                MutationErrorCategory.SERVER
            } else null,
        )
    }
}
