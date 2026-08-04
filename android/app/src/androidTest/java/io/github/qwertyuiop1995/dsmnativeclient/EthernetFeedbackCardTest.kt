package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasEthernetInterface
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.EthernetEditDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.EthernetMutationFeedbackCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.EthernetMutationFailureCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.EthernetSettingsContent
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.EthernetSavingCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class EthernetFeedbackCardTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 整屏区分不可用与可信空列表() {
        val context = context()
        var available by mutableStateOf(false)
        rule.setContent {
            LanStashTheme {
                content(interfaces = emptyList(), available = available)
            }
        }

        rule.onNodeWithText(context.getString(R.string.network_interfaces_unavailable)).assertIsDisplayed()
        rule.runOnIdle { available = true }
        rule.onNodeWithText(context.getString(R.string.no_physical_network_interfaces)).assertIsDisplayed()
    }

    @Test
    fun 正常列表显示关键摘要且编辑按钮目标化并达到48dp() {
        val context = context()
        val ethernet = ethernet().copy(isDefaultGateway = true, isVlanEnabled = true, vlanId = 20)
        rule.setContent { LanStashTheme { content(interfaces = listOf(ethernet)) } }

        rule.onNodeWithText(ethernet.displayName).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.default_route), substring = true).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.vlan_value, 20), substring = true).assertIsDisplayed()
        val description = context.getString(R.string.edit_network_interface_accessibility, ethernet.displayName)
        val node = rule.onNodeWithContentDescription(description)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .fetchSemanticsNode()
        val density = context.resources.displayMetrics.density
        check(node.boundsInRoot.height >= 48f * density)
    }

    @Test
    fun 编辑器整行开关可点击且带开关角色() {
        val context = context()
        var draft by mutableStateOf(ethernet())
        rule.setContent {
            LanStashTheme {
                EthernetEditDialog(
                    initial = ethernet(),
                    draft = draft,
                    enabled = true,
                    onDraftChange = { draft = it },
                    onContinue = { true },
                    onDismiss = {},
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.obtain_ipv4_automatically))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch))
            .performClick()
        rule.runOnIdle { check(draft.usesDhcp) }
    }

    @Test
    fun 保存中保留目标并礼貌播报() {
        val context = context()
        rule.setContent { LanStashTheme { EthernetSavingCard(ethernet()) } }

        rule.onNodeWithText(context.getString(R.string.ethernet_saving_title)).assertIsDisplayed()
        rule.onNodeWithText("Synthetic LAN", substring = true).assertIsDisplayed()
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite),
        ).assertExists()
    }

    @Test
    fun 未确认结果显示计数并在刷新前禁止继续和放弃() {
        val context = context()
        setFeedback(
            result = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, MutationResultCounts(0, 0, 1)),
        )

        rule.onNodeWithText(context.getString(R.string.ethernet_feedback_unverified_message)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.ethernet_feedback_counts, 0, 0, 1)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.continue_editing)).assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.discard_changes)).assertIsNotEnabled()
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive),
        ).assertExists()
    }

    @Test
    fun 专项刷新明确区分匹配不一致与目标消失() {
        val context = context()
        var current by mutableStateOf<NasEthernetInterface?>(ethernet().copy(mtu = 1_400))
        rule.setContent {
            LanStashTheme {
                feedback(
                    current = current,
                    refreshCompleted = true,
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.ethernet_refresh_differs)).assertIsDisplayed()
        rule.runOnIdle { current = ethernet() }
        rule.onNodeWithText(context.getString(R.string.ethernet_refresh_matches)).assertIsDisplayed()
        rule.runOnIdle { current = null }
        rule.onNodeWithText(context.getString(R.string.ethernet_refresh_target_missing)).assertIsDisplayed()
    }

    @Test
    fun 刷新中禁用操作且刷新失败保持强提醒() {
        val context = context()
        val failure = DsmFailure(
            null,
            "Synthetic refresh failure",
            "Synthetic refresh recovery",
            kind = DsmErrorKind.CONNECTION_FAILED,
        )
        rule.setContent {
            LanStashTheme {
                EthernetMutationFailureCard(
                    draft = ethernet(),
                    currentTarget = ethernet(),
                    failure = failure,
                    refreshFailure = failure,
                    refreshInProgress = true,
                    refreshCompleted = false,
                    onRefresh = {},
                    onContinueEditing = {},
                    onDismiss = {},
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.refreshing_network_interface)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_network_interface)).assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.continue_editing)).assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.discard_changes)).assertIsNotEnabled()
    }

    @Test
    fun 异常反馈刷新后目标消失时不能继续编辑() {
        val context = context()
        val failure = DsmFailure(
            null,
            "Synthetic failure",
            "Synthetic recovery",
            kind = DsmErrorKind.CONNECTION_FAILED,
        )
        rule.setContent {
            LanStashTheme {
                EthernetMutationFailureCard(
                    draft = ethernet(),
                    currentTarget = null,
                    failure = failure,
                    refreshFailure = null,
                    refreshInProgress = false,
                    refreshCompleted = true,
                    onRefresh = {},
                    onContinueEditing = {},
                    onDismiss = {},
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.ethernet_refresh_target_missing))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.continue_editing)).assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.discard_changes)).assertIsEnabled()
    }

    @Test
    fun 深色两倍字体下恢复动作仍可滚动到() {
        val context = context()
        rule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, 2f)) {
                LanStashTheme(darkTheme = true) {
                    Column(Modifier.verticalScroll(rememberScrollState())) {
                        feedback(current = ethernet(), refreshCompleted = false)
                    }
                }
            }
        }

        rule.onNodeWithText(context.getString(R.string.refresh_and_check_network_interface))
            .performScrollTo().assertIsDisplayed()
    }

    @androidx.compose.runtime.Composable
    private fun content(
        interfaces: List<NasEthernetInterface>,
        available: Boolean = true,
    ) = EthernetSettingsContent(
        interfaces = interfaces,
        interfacesAvailable = available,
        baseline = null,
        draft = null,
        mutationResult = null,
        mutationFailure = null,
        refreshFailure = null,
        mutationInProgress = false,
        refreshInProgress = false,
        refreshCompleted = false,
        isPerformingAction = false,
        currentTarget = null,
        onEdit = {},
        onRefresh = {},
        onContinueEditing = {},
        onDismissResult = {},
        onRefreshList = {},
    )

    private fun setFeedback(result: MutationResult) {
        rule.setContent { LanStashTheme { feedback(result = result) } }
    }

    @androidx.compose.runtime.Composable
    private fun feedback(
        result: MutationResult = result(
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultCounts(0, 0, 1),
        ),
        current: NasEthernetInterface? = null,
        refreshCompleted: Boolean = false,
    ) = EthernetMutationFeedbackCard(
        baseline = ethernet().copy(mtu = 1_400),
        draft = ethernet(),
        currentTarget = current,
        result = result,
        refreshFailure = null,
        refreshInProgress = false,
        refreshCompleted = refreshCompleted,
        onRefresh = {},
        onContinueEditing = {},
        onDismiss = {},
    )

    private fun result(status: MutationResultStatus, counts: MutationResultCounts) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "ethernetUpdate",
        submitted = status != MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
        requiresRefresh = status in setOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
        counts = counts,
    )

    private fun ethernet() = NasEthernetInterface(
        id = "eth0",
        displayName = "Synthetic LAN",
        status = "connected",
        usesDhcp = false,
        address = "192.0.2.10",
        subnetMask = "255.255.255.0",
        gateway = "192.0.2.1",
        dnsServers = "192.0.2.1",
        isDefaultGateway = false,
        mtu = 1_500,
        isVlanEnabled = false,
        vlanId = null,
    )

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
}
