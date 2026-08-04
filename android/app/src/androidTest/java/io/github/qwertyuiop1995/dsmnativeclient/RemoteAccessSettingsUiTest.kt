package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasRemoteAccessSettings
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.RemoteAccessConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.RemoteAccessEditDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.RemoteAccessSettingsContent
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class RemoteAccessSettingsUiTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun 正常状态显示两项值和目标化编辑按钮() {
        val context = context()
        rule.setContent { LanStashTheme { content(settings()) } }
        rule.onNodeWithContentDescription(context.getString(
            R.string.remote_access_value_description,
            context.getString(R.string.quickconnect_relay),
            context.getString(R.string.remote_access_enabled),
        )).assertIsDisplayed()
        rule.onNodeWithContentDescription(context.getString(R.string.edit_remote_access_description))
            .assertHeightIsAtLeast(48.dp)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
    }

    @Test
    fun 整体读取失败显示原因和刷新恢复() {
        val context = context()
        rule.setContent { LanStashTheme { content(null, available = false) } }
        rule.onNodeWithText(context.getString(R.string.remote_access_read_failed_title)).assertIsDisplayed()
        rule.onNodeWithContentDescription(context.getString(R.string.refresh_remote_access_description))
            .assertIsDisplayed()
            .assertHeightIsAtLeast(48.dp)
    }

    @Test
    fun 单项不可用不会被显示成关闭() {
        val context = context()
        rule.setContent { LanStashTheme { content(settings(relay = null, router = true)) } }
        rule.onNodeWithContentDescription(context.getString(
            R.string.remote_access_value_description,
            context.getString(R.string.quickconnect_relay),
            context.getString(R.string.remote_access_value_unavailable),
        )).assertIsDisplayed()
        rule.onNodeWithContentDescription(context.getString(
            R.string.remote_access_value_description,
            context.getString(R.string.router_configuration),
            context.getString(R.string.remote_access_enabled),
        )).assertIsDisplayed()
    }

    @Test
    fun 只读环境显示状态和通俗说明但没有编辑入口() {
        val context = context()
        rule.setContent { LanStashTheme { content(settings().copy(canManage = false)) } }
        rule.onNodeWithText(context.getString(R.string.remote_access_read_only_title)).assertIsDisplayed()
        rule.onAllNodesWithContentDescription(context.getString(R.string.edit_remote_access_description))
            .assertCountEquals(0)
    }

    @Test
    fun 可信中继连接保护中继但允许修改路由配置() {
        val context = context()
        val protected = settings().copy(isConnectedThroughTrustedRelay = true)
        rule.setContent { LanStashTheme {
            RemoteAccessEditDialog(protected, protected, true, {}, {}, {})
        } }
        rule.onNodeWithContentDescription(context.getString(
            R.string.remote_access_protected_switch_description,
            context.getString(R.string.quickconnect_relay),
            context.getString(R.string.remote_access_relay_protected_editor),
        )).assertIsNotEnabled()
        rule.onNodeWithContentDescription(context.getString(R.string.router_configuration)).assertIsEnabled()
    }

    @Test
    fun 确认回调返回false时仍保留完整风险摘要() {
        val context = context()
        var calls = 0
        rule.setContent { LanStashTheme {
            RemoteAccessConfirmationDialog(
                baseline = settings(),
                draft = settings(relay = false, router = false),
                onConfirm = { calls += 1; false },
                onDismiss = {},
            )
        } }
        rule.onNodeWithText(context.getString(R.string.save_remote_access)).performClick()
        rule.onNodeWithText(context.getString(R.string.disable_relay_impact)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.disable_router_configuration_impact)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.remote_access_confirmation_changed_message))
            .assertIsDisplayed()
        rule.runOnIdle { check(calls == 1) }
    }

    @Test
    fun 两倍字体窄屏下确认风险和失败恢复提示可滚动到达() {
        val context = context()
        rule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(3f, 2f)) {
                LanStashTheme {
                    RemoteAccessConfirmationDialog(
                        baseline = settings(),
                        draft = settings(relay = false, router = false),
                        onConfirm = { false },
                        onDismiss = {},
                    )
                }
            }
        }
        rule.onNodeWithText(context.getString(R.string.save_remote_access)).performClick()
        rule.onNodeWithText(context.getString(R.string.disable_router_configuration_impact))
            .performScrollTo()
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.remote_access_confirmation_changed_message))
            .performScrollTo()
            .assertIsDisplayed()
    }

    @Test
    fun 未确认结果显示三计数且刷新成功前禁止离开() {
        val context = context()
        val refreshed = mutableStateOf(false)
        rule.setContent { LanStashTheme {
            content(
                value = settings(),
                draft = settings(relay = false, router = true),
                result = unverified(),
                refreshCompleted = refreshed.value,
            )
        } }
        rule.onNodeWithText(context.getString(R.string.remote_access_feedback_counts, 0, 0, 2)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.continue_editing)).assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.discard_changes)).assertIsNotEnabled()
        rule.runOnIdle { refreshed.value = true }
        rule.onNodeWithText(context.getString(R.string.continue_editing)).assertIsEnabled()
        rule.onNodeWithText(context.getString(R.string.discard_changes)).assertIsEnabled()
    }

    @Test
    fun 异常反馈使用强提醒并保留专项刷新恢复() {
        val context = context()
        rule.setContent { LanStashTheme {
            content(
                value = settings(),
                draft = settings(),
                failure = DsmFailure(null, "Synthetic failure", "Retry"),
            )
        } }
        rule.onNode(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_remote_access))
            .assertIsDisplayed()
            .assertHeightIsAtLeast(48.dp)
    }

    @Test
    fun 刷新失败时继续和放弃保持禁用且仍可重试() {
        val context = context()
        rule.setContent { LanStashTheme {
            content(
                value = settings(),
                draft = settings(relay = false, router = true),
                result = result(MutationResultStatus.CONFIRMED_SUCCESS),
                refreshFailure = DsmFailure(null, "Synthetic refresh failure", "Retry"),
            )
        } }
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_remote_access)).assertIsEnabled()
        rule.onNodeWithText(context.getString(R.string.continue_editing)).assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.done)).assertIsNotEnabled()
    }

    @Test
    fun 八类结果渲染并覆盖部分取消后冲突和已提交权限门禁() {
        val context = context()
        data class Case(
            val result: MutationResult,
            val title: Int,
            val mustRefresh: Boolean,
        )
        val cases = listOf(
            Case(result(MutationResultStatus.CONFIRMED_SUCCESS), R.string.settings_feedback_success_title, false),
            Case(result(MutationResultStatus.PARTIAL_SUCCESS), R.string.settings_feedback_partial_title, true),
            Case(result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED), R.string.settings_feedback_check_title, true),
            Case(result(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION), R.string.settings_feedback_check_title, true),
            Case(result(MutationResultStatus.PERMISSION_DENIED, submitted = true), R.string.settings_feedback_permission_title, true),
            Case(result(MutationResultStatus.UNSUPPORTED), R.string.settings_feedback_unavailable_title, false),
            Case(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION), R.string.settings_feedback_cancelled_title, false),
            Case(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    errorCategory = MutationErrorCategory.CONFLICT,
                ),
                R.string.settings_feedback_conflict_title,
                true,
            ),
        )
        val selected = mutableStateOf(cases.first())
        rule.setContent { LanStashTheme {
            content(value = settings(), draft = settings(relay = false), result = selected.value.result)
        } }
        cases.forEach { case ->
            rule.runOnIdle { selected.value = case }
            rule.onNodeWithText(context.getString(case.title)).assertIsDisplayed()
            if (case.mustRefresh) {
                rule.onNodeWithText(context.getString(R.string.continue_editing)).assertIsNotEnabled()
            } else {
                rule.onNodeWithText(context.getString(R.string.continue_editing)).assertIsEnabled()
            }
        }
    }

    @Test
    fun 深色两倍字体下刷新按钮保持48dp和Button角色() {
        val context = context()
        rule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 2f)) {
                LanStashTheme(darkTheme = true) { content(null, available = false) }
            }
        }
        rule.onNodeWithContentDescription(context.getString(R.string.refresh_remote_access_description))
            .assertHeightIsAtLeast(48.dp)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
    }

    @androidx.compose.runtime.Composable
    private fun content(
        value: NasRemoteAccessSettings?,
        available: Boolean = true,
        draft: NasRemoteAccessSettings? = null,
        result: MutationResult? = null,
        failure: DsmFailure? = null,
        refreshFailure: DsmFailure? = null,
        refreshCompleted: Boolean = false,
    ) = RemoteAccessSettingsContent(
        settings = value,
        settingsAvailable = available,
        baseline = draft,
        draft = draft,
        mutationInProgress = false,
        mutationResult = result,
        mutationFailure = failure,
        refreshFailure = refreshFailure,
        refreshInProgress = false,
        refreshCompleted = refreshCompleted,
        isPerformingAction = false,
        onEdit = {},
        onRefresh = {},
        onContinueEditing = {},
        onDismissResult = {},
        onRefreshSettings = {},
    )

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun settings(relay: Boolean? = true, router: Boolean? = true) = NasRemoteAccessSettings(
        isRelayEnabled = relay,
        isRouterConfigurationEnabled = router,
        isConnectedThroughTrustedRelay = false,
        canManage = true,
    )

    private fun unverified() = MutationResult(
        schemaVersion = 1,
        status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
        operation = "remoteAccess",
        submitted = true,
        requiresRefresh = true,
        counts = MutationResultCounts(0, 0, 2),
    )

    private fun result(
        status: MutationResultStatus,
        submitted: Boolean = status in setOf(
            MutationResultStatus.CONFIRMED_SUCCESS,
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
        errorCategory: MutationErrorCategory? = when (status) {
            MutationResultStatus.PERMISSION_DENIED -> MutationErrorCategory.PERMISSION
            MutationResultStatus.UNSUPPORTED -> MutationErrorCategory.UNSUPPORTED
            MutationResultStatus.CONFIRMED_FAILURE -> MutationErrorCategory.SERVER
            else -> null
        },
    ) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "remoteAccess",
        submitted = submitted,
        requiresRefresh = status in setOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
        counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(2, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 2)
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
            else -> MutationResultCounts(0, 2, 0)
        },
        errorCategory = errorCategory,
    )
}
