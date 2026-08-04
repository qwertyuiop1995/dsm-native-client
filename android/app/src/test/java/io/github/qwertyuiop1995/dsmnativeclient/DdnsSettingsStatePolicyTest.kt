package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDdnsDirectory
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDdnsDraft
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDdnsProvider
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDdnsRecord
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DdnsSettingsStatePolicyTest {
    @Test
    fun `四类操作八类结果使用各自刷新门禁`() {
        DdnsMutationOperation.entries.forEach { operation ->
            MutationResultStatus.entries.forEach { status ->
                val result = result(status)
                val expected = operation != DdnsMutationOperation.TEST && when (status) {
                    MutationResultStatus.PARTIAL_SUCCESS,
                    MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                    MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
                    -> true
                    MutationResultStatus.PERMISSION_DENIED,
                    MutationResultStatus.UNSUPPORTED,
                    MutationResultStatus.CONFIRMED_FAILURE,
                    -> result.submitted || result.requiresRefresh ||
                        result.errorCategory == MutationErrorCategory.CONFLICT
                    MutationResultStatus.CONFIRMED_SUCCESS,
                    MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
                    -> false
                }

                assertEquals(
                    "$operation/$status",
                    expected,
                    ddnsMutationRequiresRefreshBeforeDismiss(operation, result),
                )
            }
        }
        assertTrue(
            ddnsMutationRequiresRefreshBeforeDismiss(
                DdnsMutationOperation.DELETE,
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    category = MutationErrorCategory.CONFLICT,
                ),
            ),
        )
        assertFalse(
            ddnsMutationRequiresRefreshBeforeDismiss(
                DdnsMutationOperation.TEST,
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    category = MutationErrorCategory.CONFLICT,
                ),
            ),
        )
    }

    @Test
    fun `测试或保存 claim 后密码从状态草稿清除`() {
        val draft = draft(password = "synthetic-secret")

        val scrubbed = scrubDdnsPassword(draft)

        assertEquals("", scrubbed.password)
        assertEquals(draft.copy(password = ""), scrubbed)
        assertEquals("synthetic-secret", draft.password)
        assertFalse(scrubbed.toString().contains("synthetic-secret"))
    }

    @Test
    fun `保存成功回退只覆盖真实核对字段并保留运行状态字段`() {
        val cached = record().copy(
            providerName = "缓存服务商",
            address = "192.0.2.10",
            status = "normal",
            lastUpdated = "cached-time",
            networkType = "cached-net",
            ipv4 = "192.0.2.10",
            ipv6 = "2001:db8::10",
            interfaceV4 = "eth0",
            interfaceV6 = "eth1",
        )
        val expected = draft().copy(
            hostname = " UPDATED.EXAMPLE.INVALID ",
            username = " updated-user ",
            isEnabled = false,
            heartbeat = true,
            networkType = "draft-net",
            ipv4 = "198.51.100.20",
            ipv6 = "2001:db8::20",
            interfaceV4 = "bond0",
            interfaceV6 = "bond1",
        )

        val value = confirmedDdnsSaveFallback(snapshot(records = listOf(cached)), expected)
            ?.ddnsDirectory?.records?.single()

        assertEquals("updated.example.invalid", value?.hostname)
        assertEquals("updated-user", value?.username)
        assertFalse(value?.isEnabled ?: true)
        assertTrue(value?.heartbeat == true)
        assertEquals("缓存服务商", value?.providerName)
        assertEquals("192.0.2.10", value?.address)
        assertEquals("normal", value?.status)
        assertEquals("cached-time", value?.lastUpdated)
        assertEquals("cached-net", value?.networkType)
        assertEquals("192.0.2.10", value?.ipv4)
        assertEquals("2001:db8::10", value?.ipv6)
        assertEquals("eth0", value?.interfaceV4)
        assertEquals("eth1", value?.interfaceV6)
    }

    @Test
    fun `保存回退不伪造新记录且删除回退只移除目标`() {
        val target = record(providerId = "Example")
        val other = record(providerId = "Other").copy(providerName = "Other Provider")

        assertNull(confirmedDdnsSaveFallback(snapshot(records = emptyList()), draft()))
        val deleted = confirmedDdnsDeleteFallback(
            snapshot(providers = listOf("Example", "Other"), records = listOf(target, other)),
            "Example",
        )?.ddnsDirectory?.records
        assertEquals(listOf(other), deleted)
        assertNull(confirmedDdnsDeleteFallback(snapshot(records = listOf(other)), "Example"))
    }

    @Test
    fun `刷新后继续编辑使用最新基线保留非秘密草稿并处理目标消失`() {
        val old = record().copy(hostname = "old.example.invalid", status = "old")
        val edited = draft(originalProviderId = "Example").copy(
            hostname = "edited.example.invalid",
            password = "synthetic-secret",
            heartbeat = true,
        )
        val current = old.copy(hostname = "current.example.invalid", status = "current")

        val rebased = checkNotNull(
            rebasedDdnsSettingsDraft(snapshot(records = listOf(current)), edited, true),
        )

        assertEquals(current, rebased.baseline)
        assertEquals("edited.example.invalid", rebased.draft.hostname)
        assertTrue(rebased.draft.heartbeat)
        assertEquals("", rebased.draft.password)
        assertNull(rebasedDdnsSettingsDraft(snapshot(records = emptyList()), edited, true))
    }

    @Test
    fun `新建草稿仅在保存后明确采用已出现的目标`() {
        val creating = draft(originalProviderId = null, password = "synthetic-secret")
        val empty = snapshot(records = emptyList())
        val created = snapshot(records = listOf(record()))

        val stillCreating = checkNotNull(rebasedDdnsSettingsDraft(empty, creating, false))
        assertNull(stillCreating.baseline)
        assertNull(stillCreating.draft.originalProviderId)
        assertNull(rebasedDdnsSettingsDraft(created, creating, false))
        val adopted = checkNotNull(rebasedDdnsSettingsDraft(created, creating, true))
        assertEquals(record(), adopted.baseline)
        assertEquals("Example", adopted.draft.originalProviderId)
        assertEquals("", adopted.draft.password)
    }

    private fun draft(
        originalProviderId: String? = null,
        password: String = "",
    ) = NasDdnsDraft(
        originalProviderId = originalProviderId,
        providerId = "Example",
        hostname = "nas.example.invalid",
        username = "synthetic-user",
        password = password,
        networkType = "auto",
        ipv4 = "0.0.0.0",
        ipv6 = "0:0:0:0:0:0:0:0",
        interfaceV4 = "eth0",
        interfaceV6 = "eth0",
    )

    private fun record(providerId: String = "Example") = NasDdnsRecord(
        providerId = providerId,
        providerName = "$providerId Provider",
        hostname = "nas.example.invalid",
        address = null,
        status = null,
        lastUpdated = null,
        isEnabled = true,
        username = "synthetic-user",
        networkType = "auto",
        ipv4 = "0.0.0.0",
        ipv6 = "0:0:0:0:0:0:0:0",
        interfaceV4 = "eth0",
        interfaceV6 = "eth0",
        heartbeat = false,
    )

    private fun snapshot(
        providers: List<String> = listOf("Example"),
        records: List<NasDdnsRecord>,
    ) = NasSettingsSnapshot(
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
        networkInterfaces = emptyList(),
        networkInterfacesAvailable = true,
        ddnsDirectory = NasDdnsDirectory(
            providers.map { NasDdnsProvider(it, "$it Provider") },
            records,
        ),
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
        operation = "ddnsRecordSave",
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
