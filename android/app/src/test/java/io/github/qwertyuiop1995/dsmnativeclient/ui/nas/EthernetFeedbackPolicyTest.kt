package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasEthernetInterface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class EthernetFeedbackPolicyTest {
    @Test
    fun `网卡八类结果均有持久反馈和正确刷新门禁`() {
        val expected = mapOf(
            MutationResultStatus.CONFIRMED_SUCCESS to false,
            MutationResultStatus.PARTIAL_SUCCESS to true,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED to true,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION to true,
            MutationResultStatus.PERMISSION_DENIED to false,
            MutationResultStatus.UNSUPPORTED to false,
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION to false,
            MutationResultStatus.CONFIRMED_FAILURE to false,
        )

        expected.forEach { (status, mustRefresh) ->
            val policy = ethernetFeedbackPolicy(result(status))
            assertEquals(status.name, mustRefresh, policy.canRefresh)
            assertEquals(status.name, mustRefresh, policy.mustRefreshBeforeDismiss)
            assertEquals(
                status !in setOf(
                    MutationResultStatus.CONFIRMED_SUCCESS,
                    MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
                ),
                policy.isAssertive,
            )
        }
    }

    @Test
    fun `冲突和已提交拒绝必须专项刷新`() {
        val conflict = ethernetFeedbackPolicy(
            result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
        )
        assertEquals(R.string.ethernet_feedback_conflict_title, conflict.title)
        assertTrue(conflict.canRefresh)
        assertTrue(conflict.mustRefreshBeforeDismiss)

        listOf(
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            MutationResultStatus.CONFIRMED_FAILURE,
        ).forEach { status ->
            assertTrue(ethernetFeedbackPolicy(result(status, submitted = true)).canRefresh)
        }
        assertFalse(ethernetFeedbackPolicy(result(MutationResultStatus.UNSUPPORTED)).canRefresh)
    }

    @Test
    fun `反馈拒绝其他操作类型`() {
        assertThrows(IllegalArgumentException::class.java) {
            ethernetFeedbackPolicy(
                result(MutationResultStatus.CONFIRMED_SUCCESS).copy(operation = "other"),
            )
        }
    }

    @Test
    fun `逐字段匹配遵循 DHCP 与 VLAN 语义`() {
        val expected = ethernet().copy(usesDhcp = true, isVlanEnabled = false)
        assertTrue(
            ethernetMatchesDraft(
                expected.copy(address = "198.51.100.9", subnetMask = "255.0.0.0", vlanId = 99),
                expected,
            ),
        )
        assertFalse(ethernetMatchesDraft(expected.copy(mtu = 1_400), expected))
        assertFalse(ethernetMatchesDraft(expected.copy(isDefaultGateway = true), expected))
    }

    @Test
    fun `地址默认路由与 VLAN 变化使用高风险确认`() {
        val baseline = ethernet()
        assertTrue(ethernetHasConnectionRisk(baseline, baseline.copy(address = "192.0.2.20")))
        assertTrue(ethernetHasConnectionRisk(baseline, baseline.copy(isDefaultGateway = true)))
        assertTrue(ethernetHasConnectionRisk(baseline, baseline.copy(isVlanEnabled = true, vlanId = 20)))
        assertFalse(ethernetHasConnectionRisk(baseline, baseline.copy(mtu = 1_400)))
    }

    private fun result(
        status: MutationResultStatus,
        category: MutationErrorCategory? = null,
        submitted: Boolean = status in setOf(
            MutationResultStatus.CONFIRMED_SUCCESS,
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
    ) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "ethernetUpdate",
        submitted = submitted,
        requiresRefresh = status in setOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
        counts = MutationResultCounts(
            succeeded = if (
                status == MutationResultStatus.CONFIRMED_SUCCESS ||
                status == MutationResultStatus.PARTIAL_SUCCESS
            ) 1 else 0,
            failed = if (status == MutationResultStatus.CONFIRMED_FAILURE) 1 else 0,
            unknown = if (
                status == MutationResultStatus.PARTIAL_SUCCESS ||
                status == MutationResultStatus.SUBMITTED_BUT_UNVERIFIED ||
                status == MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION
            ) 1 else 0,
        ),
        errorCategory = category,
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
}
