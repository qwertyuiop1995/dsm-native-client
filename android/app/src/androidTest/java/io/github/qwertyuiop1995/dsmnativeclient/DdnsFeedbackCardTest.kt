package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDdnsDirectory
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDdnsDraft
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDdnsProvider
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDdnsRecord
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.DdnsConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.DdnsEditorDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.DdnsEmptyState
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.DdnsMutationFailureCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.DdnsMutationFeedbackCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.DdnsMutationStatusContent
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.DdnsRecordRow
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DdnsFeedbackCardTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 不可用和可信空内容给出不同原因() {
        val context = context()
        var available by mutableStateOf(false)
        rule.setContent { LanStashTheme { DdnsEmptyState(directoryAvailable = available, canAdd = available) } }
        rule.onNodeWithText(context.getString(R.string.ddns_unavailable_title)).assertIsDisplayed()

        rule.runOnIdle { available = true }
        rule.onNodeWithText(context.getString(R.string.ddns_empty_title)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.ddns_empty_message)).assertIsDisplayed()
    }

    @Test
    fun 记录动作带目标语义且编辑器开关整行可点击并达到48dp() {
        val context = context()
        val record = record()
        rule.setContent {
            LanStashTheme {
                DdnsRecordRow(record = record, enabled = true, onEdit = {}, onDelete = {})
            }
        }
        rule.onNodeWithContentDescription(
            context.getString(R.string.edit_ddns_record_description, record.providerName, record.hostname),
        ).assertHeightIsAtLeast(48.dp)
        rule.onNodeWithContentDescription(
            context.getString(R.string.delete_ddns_record_description, record.providerName, record.hostname),
        ).assertHeightIsAtLeast(48.dp)
    }

    @Test
    fun 编辑器开关整行可点击并达到48dp() {
        val draft = draft()
        rule.setContent {
            LanStashTheme {
                DdnsEditorDialog(
                    initial = draft,
                    draft = draft,
                    providers = providers,
                    enabled = true,
                    onDraftChange = {},
                    onTest = { true },
                    onSave = { true },
                    onDismiss = {},
                )
            }
        }
        rule.onAllNodes(
            SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch) and hasClickAction(),
            useUnmergedTree = true,
        ).onFirst().assertHeightIsAtLeast(48.dp).performClick()
    }

    @Test
    fun 四类确认显示目标且confirm拒绝时留框() {
        val context = context()
        val target = record()
        var operation by mutableStateOf(DdnsMutationOperation.TEST)
        var calls = 0
        rule.setContent {
            LanStashTheme {
                DdnsConfirmationDialog(
                    operation = operation,
                    draft = draft(),
                    deleteTarget = target,
                    addressTargets = listOf(target),
                    providers = providers,
                    onConfirm = { calls += 1; false },
                    onDismiss = {},
                )
            }
        }
        DdnsMutationOperation.entries.forEach { currentOperation ->
            rule.runOnIdle { operation = currentOperation; calls = 0 }
            rule.onNodeWithText(target.providerName, substring = true).assertIsDisplayed()
            rule.onNodeWithText(target.hostname, substring = true).assertIsDisplayed()
            val action = when (currentOperation) {
                DdnsMutationOperation.TEST -> R.string.test_connection
                DdnsMutationOperation.SAVE -> R.string.save
                DdnsMutationOperation.DELETE -> R.string.delete
                DdnsMutationOperation.ADDRESS_REFRESH -> R.string.update_now
            }
            rule.onNodeWithText(context.getString(action)).performClick()
            rule.runOnIdle { check(calls == 1) }
            rule.onNodeWithText(target.hostname, substring = true).assertIsDisplayed()
        }
    }

    @Test
    fun 测试成功明确未保存并显示计数和礼貌播报() {
        val context = context()
        rule.setContent {
            LanStashTheme {
                DdnsMutationFeedbackCard(
                    operation = DdnsMutationOperation.TEST,
                    draft = draft(),
                    deleteTarget = null,
                    addressTargets = emptyList(),
                    providers = providers,
                    currentRecord = record(),
                    result = result(DdnsMutationOperation.TEST, MutationResultStatus.CONFIRMED_SUCCESS),
                    refreshFailure = null,
                    refreshInProgress = false,
                    refreshCompleted = false,
                    onRefresh = {},
                    onContinueEditing = {},
                    onDismiss = {},
                )
            }
        }
        rule.onNodeWithText(context.getString(R.string.ddns_test_succeeded)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.ddns_feedback_counts, 1, 0, 0)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.continue_editing)).assertIsEnabled()
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite),
        ).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.ddns_record_saved)).assertDoesNotExist()
    }

    @Test
    fun 立即更新专项刷新区分部分变化和全部消失() {
        val context = context()
        val first = record()
        val second = record().copy(providerId = "other", providerName = "Other", hostname = "other.example.test")
        var currentIds by mutableStateOf(setOf(first.providerId))
        rule.setContent {
            LanStashTheme {
                DdnsMutationFeedbackCard(
                    operation = DdnsMutationOperation.ADDRESS_REFRESH,
                    draft = null,
                    deleteTarget = null,
                    addressTargets = listOf(first, second),
                    addressTargetIds = setOf(first.providerId, second.providerId),
                    currentAddressRecordIds = currentIds,
                    providers = providers,
                    currentRecord = null,
                    result = result(
                        DdnsMutationOperation.ADDRESS_REFRESH,
                        MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                    ),
                    refreshFailure = null,
                    refreshInProgress = false,
                    refreshCompleted = true,
                    onRefresh = {},
                    onContinueEditing = {},
                    onDismiss = {},
                )
            }
        }
        rule.onNodeWithText(context.getString(R.string.ddns_refresh_address_targets_changed))
            .assertIsDisplayed()

        rule.runOnIdle { currentIds = emptySet() }
        rule.onNodeWithText(context.getString(R.string.ddns_refresh_address_targets_missing))
            .assertIsDisplayed()
    }

    @Test
    fun 未确认结果刷新前门禁且目标消失后不能继续编辑() {
        val context = context()
        rule.setContent {
            LanStashTheme {
                DdnsMutationFeedbackCard(
                    operation = DdnsMutationOperation.SAVE,
                    draft = draft(),
                    deleteTarget = null,
                    addressTargets = emptyList(),
                    providers = providers,
                    currentRecord = null,
                    result = result(DdnsMutationOperation.SAVE, MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
                    refreshFailure = null,
                    refreshInProgress = false,
                    refreshCompleted = true,
                    onRefresh = {},
                    onContinueEditing = {},
                    onDismiss = {},
                )
            }
        }
        rule.onNodeWithText(context.getString(R.string.ddns_refresh_target_missing)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.continue_editing)).assertDoesNotExist()
        rule.onNodeWithText(context.getString(R.string.discard_changes)).assertIsEnabled()
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive),
        ).assertIsDisplayed()
    }

    @Test
    fun 异常和专项刷新失败保持强提醒与门禁() {
        val context = context()
        val failure = DsmFailure(
            null,
            "Synthetic DDNS failure",
            "Synthetic DDNS recovery",
            kind = DsmErrorKind.CONNECTION_FAILED,
        )
        rule.setContent {
            LanStashTheme {
                DdnsMutationFailureCard(
                    operation = DdnsMutationOperation.DELETE,
                    draft = null,
                    deleteTarget = record(),
                    addressTargets = emptyList(),
                    providers = providers,
                    currentRecord = record(),
                    failure = failure,
                    refreshFailure = failure,
                    refreshInProgress = false,
                    refreshCompleted = false,
                    onRefresh = {},
                    onContinueEditing = {},
                    onDismiss = {},
                )
            }
        }
        rule.onAllNodesWithText(
            context.getString(R.string.error_connection_failed),
            substring = true,
        ).onFirst().assertIsDisplayed()
        rule.onAllNodesWithText(
            context.getString(R.string.error_connection_failed_recovery),
            substring = true,
        ).onFirst().assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_ddns)).assertIsEnabled()
        rule.onNodeWithText(context.getString(R.string.discard_changes)).assertIsNotEnabled()
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive),
        ).assertIsDisplayed()
    }

    @Test
    fun 深色两倍字体和键盘表单仍可滚动到隐私提示() {
        val context = context()
        var draft by mutableStateOf(draft())
        rule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, 2f)) {
                LanStashTheme(darkTheme = true) {
                    DdnsEditorDialog(
                        initial = draft,
                        draft = draft,
                        providers = providers,
                        enabled = true,
                        onDraftChange = { draft = it },
                        onTest = { true },
                        onSave = { true },
                        onDismiss = {},
                    )
                }
            }
        }
        rule.onNodeWithText(context.getString(R.string.ddns_hostname)).performClick()
        rule.onNodeWithText(context.getString(R.string.ddns_credential_privacy_hint))
            .performScrollTo().assertIsDisplayed()
    }

    @Test
    fun 非秘密草稿和确认阶段恢复而密码不会进入恢复状态() {
        val context = context()
        val restoration = StateRestorationTester(rule)
        restoration.setContent {
            var hostname by rememberSaveable { mutableStateOf("before.example.test") }
            var confirmation by rememberSaveable { mutableStateOf(false) }
            var password by remember { mutableStateOf("temporary-secret") }
            val draft = draft().copy(hostname = hostname, password = password)
            LanStashTheme {
                if (confirmation) {
                    DdnsConfirmationDialog(
                        operation = DdnsMutationOperation.SAVE,
                        draft = draft.copy(password = ""),
                        deleteTarget = null,
                        addressTargets = emptyList(),
                        providers = providers,
                        onConfirm = { false },
                        onDismiss = { confirmation = false },
                    )
                } else {
                    DdnsEditorDialog(
                        initial = draft().copy(hostname = ""),
                        draft = draft,
                        providers = providers,
                        enabled = true,
                        onDraftChange = { hostname = it.hostname; password = it.password },
                        onTest = { true },
                        onSave = { confirmation = true; true },
                        onDismiss = {},
                    )
                }
            }
        }
        rule.onNodeWithText("before.example.test").performTextReplacement("after.example.test")
        rule.onNodeWithText(context.getString(R.string.continue_action)).performClick()
        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText("after.example.test", substring = true).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.ddns_password_not_reentered)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.save)).performClick()
        rule.onNodeWithText("after.example.test", substring = true).assertIsDisplayed()
    }

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext

    private val providers = listOf(NasDdnsProvider("synthetic-provider", "Synthetic Provider"))

    private fun draft() = NasDdnsDraft(
        originalProviderId = "synthetic-provider",
        providerId = "synthetic-provider",
        hostname = "host.example.test",
        username = "synthetic-user",
        password = "",
        isEnabled = true,
        heartbeat = false,
    )

    private fun record() = NasDdnsRecord(
        providerId = "synthetic-provider",
        providerName = "Synthetic Provider",
        hostname = "host.example.test",
        address = "192.0.2.10",
        status = "normal",
        lastUpdated = null,
        isEnabled = true,
        username = "synthetic-user",
        networkType = "auto",
        ipv4 = "0.0.0.0",
        ipv6 = "0:0:0:0:0:0:0:0",
        interfaceV4 = "",
        interfaceV6 = "",
        heartbeat = false,
    )

    private fun result(
        operation: DdnsMutationOperation,
        status: MutationResultStatus,
    ) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = when (operation) {
            DdnsMutationOperation.TEST -> "ddnsProviderTest"
            DdnsMutationOperation.SAVE -> "ddnsRecordSave"
            DdnsMutationOperation.DELETE -> "ddnsRecordDelete"
            DdnsMutationOperation.ADDRESS_REFRESH -> "ddnsAddressRefresh"
        },
        submitted = status != MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
        requiresRefresh = status == MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
        counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            else -> MutationResultCounts(0, 0, 1)
        },
    )
}
