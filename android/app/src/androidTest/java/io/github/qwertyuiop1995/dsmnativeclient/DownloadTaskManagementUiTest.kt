package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
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
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.ui.downloads.DownloadControlMutationFeedbackCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.downloads.DownloadDestinationEditConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.downloads.DownloadDeletionConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.downloads.DownloadTaskActionsDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class DownloadTaskManagementUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun 运行任务只显示暂停动作() {
        setActions(ResourceState.RUNNING)
        rule.onNodeWithText(context.getString(R.string.pause)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.resume)).assertDoesNotExist()
    }

    @Test fun 等待任务只显示暂停动作() {
        setActions(ResourceState.WAITING)
        rule.onNodeWithText(context.getString(R.string.pause)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.resume)).assertDoesNotExist()
    }

    @Test fun 暂停任务只显示继续动作() {
        setActions(ResourceState.PAUSED)
        rule.onNodeWithText(context.getString(R.string.resume)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.pause)).assertDoesNotExist()
    }

    @Test fun 其他状态不显示无效控制动作() {
        setActions(ResourceState.ERROR)
        rule.onNodeWithText(context.getString(R.string.pause)).assertDoesNotExist()
        rule.onNodeWithText(context.getString(R.string.resume)).assertDoesNotExist()
    }

    @Test fun 持久结果存在时写动作不可点击() {
        setActions(ResourceState.RUNNING, enabled = false)
        rule.onNodeWithText(context.getString(R.string.pause)).assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.remove_task)).assertIsNotEnabled()
    }

    @Test fun TalkBack动作说明包含任务名() {
        setActions(ResourceState.RUNNING)
        val description = context.getString(
            R.string.download_task_action_description,
            context.getString(R.string.pause),
            "Ubuntu ISO",
        )
        rule.onNodeWithContentDescription(description).assertIsDisplayed()
    }

    @Test fun 暂停和两种删除动作都准确回调() {
        var pauses = 0
        var removes = 0
        var removesWithFiles = 0
        rule.setContent { LanStashTheme { DownloadTaskActionsDialog(
            "Ubuntu ISO", ResourceState.RUNNING, true,
            onDetails = {}, onPause = { pauses += 1 }, onResume = {},
            onRemove = { removes += 1 }, onRemoveWithFiles = { removesWithFiles += 1 },
            onDismiss = {},
        ) } }
        rule.onNodeWithText(context.getString(R.string.pause)).performClick()
        rule.onNodeWithText(context.getString(R.string.remove_task)).performClick()
        rule.onNodeWithText(context.getString(R.string.remove_task_and_files)).performClick()
        rule.runOnIdle { check(pauses == 1 && removes == 1 && removesWithFiles == 1) }
    }

    @Test fun 继续动作准确回调() {
        var resumes = 0
        rule.setContent { LanStashTheme { DownloadTaskActionsDialog(
            "Ubuntu ISO", ResourceState.PAUSED, true,
            onDetails = {}, onPause = {}, onResume = { resumes += 1 },
            onRemove = {}, onRemoveWithFiles = {}, onDismiss = {},
        ) } }
        rule.onNodeWithText(context.getString(R.string.resume)).performClick()
        rule.runOnIdle { check(resumes == 1) }
    }

    @Test fun 官方能力存在时保存位置动作可见且准确回调() {
        var edits = 0
        rule.setContent { LanStashTheme { DownloadTaskActionsDialog(
            "Ubuntu ISO", ResourceState.RUNNING, true,
            onDetails = {}, onPause = {}, onResume = {},
            onRemove = {}, onRemoveWithFiles = {}, onDismiss = {},
            canEditDestination = true,
            onEditDestination = { edits += 1 },
        ) } }

        rule.onNodeWithText(context.getString(R.string.change_download_destination)).performClick()
        rule.runOnIdle { check(edits == 1) }
    }

    @Test fun 保存位置确认显示当前新目录和影响说明() {
        var confirmations = 0
        rule.setContent { LanStashTheme { DownloadDestinationEditConfirmationDialog(
            taskTitle = "Ubuntu ISO",
            currentDestination = "/downloads",
            newDestination = "/archive",
            persistentRejection = false,
            onConfirm = { confirmations += 1; true },
            onDismiss = {},
        ) } }

        rule.onNodeWithText(context.getString(R.string.current_download_destination_summary, "/downloads"))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.new_download_destination_summary, "/archive"))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.change_download_destination_effect))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.confirm_change_download_destination))
            .performClick()
        rule.runOnIdle { check(confirmations == 1) }
    }

    @Test fun 两倍字体窄屏仍可滚动并确认保存位置() {
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                Box(Modifier.width(220.dp).height(280.dp)) {
                    DownloadDestinationEditConfirmationDialog(
                        taskTitle = "Ubuntu ISO with a long synthetic title",
                        currentDestination = "/downloads/current/path",
                        newDestination = "/archive/new/path",
                        persistentRejection = false,
                        onConfirm = { true },
                        onDismiss = {},
                    )
                }
            }
        }

        rule.onNodeWithText(context.getString(R.string.confirm_change_download_destination))
            .assertIsDisplayed().assertIsEnabled()
    }

    @Test fun 两种删除使用不同确认按钮和风险摘要() {
        var deleteFiles by mutableStateOf(false)
        rule.setContent { LanStashTheme { DownloadDeletionConfirmationDialog(
            taskTitle = "Ubuntu ISO", deleteFiles = deleteFiles,
            onConfirm = { true }, onDismiss = {},
        ) } }
        rule.onNodeWithText(context.getString(R.string.confirm_remove_task_only)).assertIsDisplayed()
        rule.runOnIdle { deleteFiles = true }
        rule.onNodeWithText(context.getString(R.string.confirm_remove_task_and_files)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.download_delete_files_risk_summary))
            .assertIsDisplayed()
    }

    @Test fun 确认目标变化时保留确认框并提示() {
        setDeletion(deleteFiles = true, onConfirm = { false })
        rule.onNodeWithText(context.getString(R.string.confirm_remove_task_and_files)).performClick()
        rule.onNodeWithText(context.getString(R.string.download_deletion_confirmation_changed))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.confirm_remove_task_and_files))
            .assertIsDisplayed()
    }

    @Test fun 重建后仍显示持久确认拒绝提示() {
        rule.setContent { LanStashTheme { DownloadDeletionConfirmationDialog(
            taskTitle = "Ubuntu ISO", deleteFiles = true, persistentRejection = true,
            onConfirm = { true }, onDismiss = {},
        ) } }
        rule.onNodeWithText(context.getString(R.string.download_deletion_confirmation_changed))
            .assertIsDisplayed()
    }

    @Test fun 八种结构化状态都有持久标题() {
        var currentStatus by mutableStateOf(MutationResultStatus.CONFIRMED_SUCCESS)
        rule.setContent { LanStashTheme { DownloadControlMutationFeedbackCard(
            result = result(currentStatus), failure = null, refreshFailure = null,
            refreshInProgress = false, refreshCompleted = false, mustRefresh = true,
            currentMatches = null,
            deleteFiles = false, onRefresh = {}, onDismiss = {},
        ) } }
        MutationResultStatus.entries.forEach { nextStatus ->
            rule.runOnIdle { currentStatus = nextStatus }
            val expected = when (nextStatus) {
                MutationResultStatus.CONFIRMED_SUCCESS -> R.string.download_control_confirmed_title
                MutationResultStatus.PARTIAL_SUCCESS -> R.string.download_control_partial_title
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
                -> R.string.download_control_check_title
                MutationResultStatus.PERMISSION_DENIED -> R.string.download_control_permission_title
                MutationResultStatus.UNSUPPORTED -> R.string.download_control_unavailable_title
                MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> R.string.download_control_cancelled_title
                MutationResultStatus.CONFIRMED_FAILURE -> R.string.download_control_failed_title
            }
            rule.onNodeWithText(context.getString(expected)).assertIsDisplayed()
        }
    }

    @Test fun 反馈始终显示三个计数() {
        setFeedback(result(MutationResultStatus.PARTIAL_SUCCESS, MutationResultCounts(2, 1, 3)))
        rule.onNodeWithText(context.getString(R.string.download_control_feedback_counts, 2, 1, 3))
            .assertIsDisplayed()
    }

    @Test fun 提交后取消和已提交权限失败要求刷新核对() {
        var currentResult by mutableStateOf(
            result(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION),
        )
        rule.setContent { LanStashTheme { DownloadControlMutationFeedbackCard(
            result = currentResult, failure = null, refreshFailure = null,
            refreshInProgress = false, refreshCompleted = false, mustRefresh = true,
            currentMatches = null,
            deleteFiles = false, onRefresh = {}, onDismiss = {},
        ) } }
        rule.onNodeWithText(context.getString(R.string.download_control_cancel_after_submission))
            .assertIsDisplayed()
        rule.runOnIdle {
            currentResult = result(MutationResultStatus.PERMISSION_DENIED, submitted = true)
        }
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_download_tasks))
            .assertIsEnabled()
    }

    @Test fun 冲突使用目标化反馈且删除文件提示独立核对限制() {
        setFeedback(
            result(MutationResultStatus.CONFIRMED_FAILURE, error = MutationErrorCategory.CONFLICT),
            deleteFiles = true,
        )
        rule.onNodeWithText(context.getString(R.string.download_control_conflict_title))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.download_delete_files_verification_notice))
            .assertIsDisplayed()
    }

    @Test fun 删除任务及文件部分成功使用单任务准确说明() {
        setFeedback(
            result(MutationResultStatus.PARTIAL_SUCCESS),
            deleteFiles = true,
        )
        rule.onNodeWithText(context.getString(R.string.download_delete_files_partial_title))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.download_delete_files_partial_message))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.download_action_partial_persistent))
            .assertDoesNotExist()
    }

    @Test fun 刷新失败禁止关闭并允许重试() {
        setFeedback(
            result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
            refreshFailure = DsmFailure(null, "Refresh failed", "Try again"),
        )
        rule.onNodeWithText(context.getString(R.string.close_checked_download_feedback))
            .assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_download_tasks))
            .assertIsEnabled()
    }

    @Test fun 异常反馈显示可恢复说明且禁止未核对关闭() {
        val failure = DsmFailure(null, "Task action failed", "Refresh and try again")
        rule.setContent { LanStashTheme { DownloadControlMutationFeedbackCard(
            result = null, failure = failure, refreshFailure = null,
            refreshInProgress = false, refreshCompleted = false, mustRefresh = true,
            currentMatches = null,
            deleteFiles = false, onRefresh = {}, onDismiss = {},
        ) } }
        rule.onNodeWithText(context.getString(R.string.operation_not_completed), substring = true)
            .assertExists()
        rule.onNodeWithText(context.getString(R.string.close_checked_download_feedback))
            .assertIsNotEnabled()
    }

    @Test fun 提交前取消和未提交不支持可直接关闭() {
        var currentResult by mutableStateOf(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION))
        rule.setContent { LanStashTheme { DownloadControlMutationFeedbackCard(
            result = currentResult, failure = null, refreshFailure = null,
            refreshInProgress = false, refreshCompleted = false, mustRefresh = false,
            currentMatches = null, deleteFiles = false, onRefresh = {}, onDismiss = {},
        ) } }
        rule.onNodeWithText(context.getString(R.string.close_checked_download_feedback))
            .assertIsEnabled()
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_download_tasks))
            .assertDoesNotExist()
        rule.runOnIdle { currentResult = result(MutationResultStatus.UNSUPPORTED) }
        rule.onNodeWithText(context.getString(R.string.close_checked_download_feedback))
            .assertIsEnabled()
    }

    @Test fun 已提交删除在可信刷新前禁止关闭() {
        rule.setContent { LanStashTheme { DownloadControlMutationFeedbackCard(
            result = result(MutationResultStatus.CONFIRMED_SUCCESS),
            failure = null, refreshFailure = null, refreshInProgress = false,
            refreshCompleted = false, mustRefresh = true, currentMatches = null,
            deleteFiles = false, onRefresh = {}, onDismiss = {},
        ) } }
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_download_tasks))
            .assertIsEnabled()
        rule.onNodeWithText(context.getString(R.string.close_checked_download_feedback))
            .assertIsNotEnabled()
    }

    @Test fun 刷新后明确显示一致不一致和无法判断() {
        var currentMatches by mutableStateOf<Boolean?>(true)
        rule.setContent { LanStashTheme { DownloadControlMutationFeedbackCard(
            result = result(MutationResultStatus.CONFIRMED_SUCCESS),
            failure = null, refreshFailure = null, refreshInProgress = false,
            refreshCompleted = true, mustRefresh = true,
            currentMatches = currentMatches, deleteFiles = false,
            onRefresh = {}, onDismiss = {},
        ) } }
        listOf(
            true to R.string.download_control_refresh_matches,
            false to R.string.download_control_refresh_differs,
            null to R.string.download_control_refresh_unavailable,
        ).forEach { (matches, text) ->
            rule.runOnIdle { currentMatches = matches }
            rule.onNodeWithText(context.getString(text)).assertIsDisplayed()
            rule.onNodeWithText(context.getString(R.string.close_checked_download_feedback))
                .assertIsEnabled()
        }
    }

    @Test fun 删除任务及文件刷新匹配仍要求到目标文件夹核对() {
        setFeedback(
            result = result(MutationResultStatus.CONFIRMED_SUCCESS),
            refreshCompleted = true,
            matches = true,
            deleteFiles = true,
        )
        rule.onNodeWithText(context.getString(R.string.download_delete_files_refresh_matches))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.download_control_refresh_matches))
            .assertDoesNotExist()
    }

    @Test fun 两倍字体窄屏反馈仍可滚动到关闭按钮() {
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                LanStashTheme {
                    Box(Modifier.width(220.dp).height(220.dp)) {
                        DownloadControlMutationFeedbackCard(
                            result = result(MutationResultStatus.PARTIAL_SUCCESS),
                            failure = null,
                            refreshFailure = null,
                            refreshInProgress = false,
                            refreshCompleted = false,
                            mustRefresh = false,
                            currentMatches = null,
                            deleteFiles = true,
                            onRefresh = {},
                            onDismiss = {},
                        )
                    }
                }
            }
        }
        rule.onNodeWithText(context.getString(R.string.close_checked_download_feedback))
            .performScrollTo().assertIsDisplayed().assertIsEnabled()
    }

    @Test fun 两倍字体窄屏仍可滚动到危险动作() {
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                Box(Modifier.width(220.dp).height(260.dp)) {
                    DownloadTaskActionsDialog(
                        "Ubuntu ISO", ResourceState.RUNNING, true, {}, {}, {}, {}, {}, {},
                    )
                }
            }
        }
        rule.onNodeWithText(context.getString(R.string.remove_task_and_files))
            .performScrollTo().assertIsDisplayed()
    }

    private fun setActions(state: ResourceState, enabled: Boolean = true) {
        rule.setContent { LanStashTheme { DownloadTaskActionsDialog(
            "Ubuntu ISO", state, enabled, {}, {}, {}, {}, {}, {},
        ) } }
    }

    private fun setDeletion(deleteFiles: Boolean, onConfirm: () -> Boolean = { true }) {
        rule.setContent { LanStashTheme { DownloadDeletionConfirmationDialog(
            taskTitle = "Ubuntu ISO",
            deleteFiles = deleteFiles,
            onConfirm = onConfirm,
            onDismiss = {},
        ) } }
    }

    private fun setFeedback(
        result: MutationResult,
        refreshCompleted: Boolean = false,
        matches: Boolean? = null,
        refreshFailure: DsmFailure? = null,
        deleteFiles: Boolean = false,
    ) {
        rule.setContent { LanStashTheme { DownloadControlMutationFeedbackCard(
            result = result,
            failure = null,
            refreshFailure = refreshFailure,
            refreshInProgress = false,
            refreshCompleted = refreshCompleted,
            mustRefresh = true,
            currentMatches = matches,
            deleteFiles = deleteFiles,
            onRefresh = {},
            onDismiss = {},
        ) } }
    }

    private fun result(
        status: MutationResultStatus,
        counts: MutationResultCounts? = null,
        submitted: Boolean? = null,
        error: MutationErrorCategory? = null,
    ): MutationResult {
        val isSubmitted = submitted ?: status !in setOf(
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            MutationResultStatus.CONFIRMED_FAILURE,
        )
        val defaultCounts = when (status) {
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
            operation = "downloadControl",
            submitted = isSubmitted,
            requiresRefresh = isSubmitted && status != MutationResultStatus.CONFIRMED_SUCCESS,
            counts = counts ?: defaultCounts,
            errorCategory = error,
        )
    }
}
