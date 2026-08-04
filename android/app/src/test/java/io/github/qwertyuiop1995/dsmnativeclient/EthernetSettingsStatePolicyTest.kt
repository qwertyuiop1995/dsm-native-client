package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasEthernetInterface
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EthernetSettingsStatePolicyTest {
    @Test
    fun `专项刷新后继续编辑使用最新基线并保留可编辑草稿`() {
        val original = ethernet(id = "eth0").copy(displayName = "旧名称", status = "down")
        val draft = original.copy(mtu = 1_400, isDefaultGateway = true)
        val refreshed = original.copy(displayName = "新名称", status = "up", mtu = 1_300)
        val snapshot = snapshot(refreshed)

        val rebased = checkNotNull(rebasedEthernetSettingsDraft(snapshot, draft))

        assertEquals(refreshed, rebased.first)
        assertEquals(1_400, rebased.second.mtu)
        assertTrue(rebased.second.isDefaultGateway)
        assertEquals("新名称", rebased.second.displayName)
        assertEquals("up", rebased.second.status)
        assertNull(rebasedEthernetSettingsDraft(snapshot(), draft))
    }

    @Test
    fun `DHCP 与关闭 VLAN 的成功回退只替换实际提交字段`() {
        val cached = ethernet(
            displayName = "缓存名称",
            status = "connected",
            usesDhcp = false,
            address = "192.0.2.10",
            subnetMask = "255.255.255.0",
            gateway = "192.0.2.1",
            dnsServers = "192.0.2.53",
            isDefaultGateway = false,
            mtu = 1_500,
            isVlanEnabled = true,
            vlanId = 20,
        )
        val draft = cached.copy(
            displayName = "不得覆盖的草稿名称",
            status = "不得覆盖的草稿状态",
            usesDhcp = true,
            address = "198.51.100.10",
            subnetMask = "255.255.0.0",
            gateway = "198.51.100.1",
            dnsServers = "198.51.100.53",
            isDefaultGateway = true,
            mtu = 9_000,
            isVlanEnabled = false,
            vlanId = 99,
        )

        val value = confirmedEthernetSettingsFallback(snapshot(cached), draft)
            ?.networkInterfaces?.single()

        assertEquals("缓存名称", value?.displayName)
        assertEquals("connected", value?.status)
        assertTrue(value?.usesDhcp == true)
        assertEquals("192.0.2.10", value?.address)
        assertEquals("255.255.255.0", value?.subnetMask)
        assertEquals("192.0.2.1", value?.gateway)
        assertEquals("192.0.2.53", value?.dnsServers)
        assertTrue(value?.isDefaultGateway == true)
        assertEquals(9_000, value?.mtu)
        assertFalse(value?.isVlanEnabled ?: true)
        assertEquals(20, value?.vlanId)
    }

    @Test
    fun `静态地址与开启 VLAN 的成功回退规范化并替换全部提交字段`() {
        val cached = ethernet()
        val draft = cached.copy(
            usesDhcp = false,
            address = " 198.51.100.20 ",
            subnetMask = " 255.255.255.0 ",
            gateway = " 198.51.100.1 ",
            dnsServers = " 198.51.100.53 ",
            isDefaultGateway = true,
            mtu = 2_000,
            isVlanEnabled = true,
            vlanId = 40,
        )

        val value = confirmedEthernetSettingsFallback(snapshot(cached), draft)
            ?.networkInterfaces?.single()

        assertFalse(value?.usesDhcp ?: true)
        assertEquals("198.51.100.20", value?.address)
        assertEquals("255.255.255.0", value?.subnetMask)
        assertEquals("198.51.100.1", value?.gateway)
        assertEquals("198.51.100.53", value?.dnsServers)
        assertTrue(value?.isDefaultGateway == true)
        assertEquals(2_000, value?.mtu)
        assertTrue(value?.isVlanEnabled == true)
        assertEquals(40, value?.vlanId)
    }

    @Test
    fun `缓存没有目标网卡时不伪造成功回退`() {
        val cached = ethernet(id = "eth1")

        assertNull(confirmedEthernetSettingsFallback(snapshot(cached), ethernet(id = "eth0")))
    }

    @Test
    fun `成功回退不会改变非目标网卡`() {
        val target = ethernet(id = "eth0")
        val other = ethernet(id = "eth1", displayName = "LAN 2", address = "203.0.113.10")

        val interfaces = confirmedEthernetSettingsFallback(
            snapshot(target, other),
            target.copy(mtu = 2_000),
        )?.networkInterfaces

        assertEquals(2_000, interfaces?.first()?.mtu)
        assertEquals(other, interfaces?.last())
    }

    @Test
    fun `未确认与提交后取消始终要求专项刷新`() {
        assertTrue(
            ethernetMutationRequiresRefreshBeforeDismiss(
                result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
            ),
        )
        assertTrue(
            ethernetMutationRequiresRefreshBeforeDismiss(
                result(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION),
            ),
        )
        assertTrue(
            ethernetMutationRequiresRefreshBeforeDismiss(
                result(MutationResultStatus.PARTIAL_SUCCESS),
            ),
        )
    }

    @Test
    fun `已提交失败与冲突要求专项刷新但提交前取消可直接清除`() {
        assertTrue(
            ethernetMutationRequiresRefreshBeforeDismiss(
                result(MutationResultStatus.CONFIRMED_FAILURE, submitted = true),
            ),
        )
        assertTrue(
            ethernetMutationRequiresRefreshBeforeDismiss(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    category = MutationErrorCategory.CONFLICT,
                ),
            ),
        )
        assertFalse(
            ethernetMutationRequiresRefreshBeforeDismiss(
                result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION),
            ),
        )
        assertFalse(
            ethernetMutationRequiresRefreshBeforeDismiss(
                result(MutationResultStatus.CONFIRMED_SUCCESS),
            ),
        )
        assertTrue(
            ethernetMutationRequiresRefreshBeforeDismiss(
                result(MutationResultStatus.PERMISSION_DENIED, submitted = true),
            ),
        )
        assertFalse(
            ethernetMutationRequiresRefreshBeforeDismiss(
                result(
                    MutationResultStatus.PERMISSION_DENIED,
                    category = MutationErrorCategory.PERMISSION,
                ),
            ),
        )
        assertFalse(
            ethernetMutationRequiresRefreshBeforeDismiss(
                result(
                    MutationResultStatus.UNSUPPORTED,
                    category = MutationErrorCategory.UNSUPPORTED,
                ),
            ),
        )
        assertFalse(
            ethernetMutationRequiresRefreshBeforeDismiss(
                result(MutationResultStatus.CONFIRMED_FAILURE),
            ),
        )
    }

    private fun ethernet(
        id: String = "eth0",
        displayName: String = "LAN 1",
        status: String? = "connected",
        usesDhcp: Boolean = true,
        address: String = "192.0.2.10",
        subnetMask: String = "255.255.255.0",
        gateway: String = "192.0.2.1",
        dnsServers: String = "192.0.2.53",
        isDefaultGateway: Boolean = false,
        mtu: Int = 1_500,
        isVlanEnabled: Boolean = false,
        vlanId: Int? = null,
    ) = NasEthernetInterface(
        id,
        displayName,
        status,
        usesDhcp,
        address,
        subnetMask,
        gateway,
        dnsServers,
        isDefaultGateway,
        mtu,
        isVlanEnabled,
        vlanId,
    )

    private fun snapshot(vararg ethernet: NasEthernetInterface) = NasSettingsSnapshot(
        system = null,
        volumes = emptyList(),
        pools = emptyList(),
        disks = emptyList(),
        storageDisks = emptyList(),
        packages = emptyList(),
        scheduledTasks = emptyList(),
        accounts = emptyList(),
        groups = emptyList(),
        logs = emptyList(),
        connections = emptyList(),
        connectionsAvailable = true,
        networkInterfaces = ethernet.toList(),
        networkInterfacesAvailable = true,
        ddnsDirectory = null,
        ddnsDirectoryAvailable = true,
        fileServiceSettings = null,
        terminalSettings = null,
        proxySettings = null,
        regionSettings = null,
        securitySettings = null,
        hardwareSettings = null,
        security = emptyList(),
    )

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
        counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 0, 1)
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            else -> MutationResultCounts(0, 1, 0)
        },
        errorCategory = category,
    )
}
