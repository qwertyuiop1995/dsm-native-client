package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasFileServiceSettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProxySettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasRegionSettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasTimeZoneOption
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDoSProtectionSetting
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSecuritySettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasPowerAction
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasHardwareSettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasUpsSettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasTerminalSettings
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import okhttp3.FormBody
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NasServiceSettingsMutationTest {
    @Test
    fun `文件服务六组契约均使用固定参数与版本`() = runBlocking {
        val transport = SettingsInterceptor(
            json(SMB_OFF), json(NFS_OFF), json(FTP_OFF), json(SFTP_OFF), json(WEB_OFF), json(DISCOVERY_OFF),
            json(SUCCESS), json(SUCCESS), json(SUCCESS), json(SUCCESS), json(SUCCESS), json(SUCCESS),
            json(SMB_ON), json(NFS_ON), json(FTP_ALL_ON), json(SFTP_ON), json(WEB_SSDP_ON), json(DISCOVERY_ON),
        )
        val expected = NasFileServiceSettings(
            true, true, true, true, 2_121, true, 2_222, true, false, true,
        )

        val result = repository(
            transport,
            SMB to 3, NFS to 3, FTP to 1, SFTP to 1, WEB to 3, DISCOVERY to 1,
        ).saveFileServiceSettingsResult(expected)

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(6, result.counts.succeeded)
        assertEquals(listOf("3", "3", "1", "1", "2", "1"), transport.versions().take(6))
        val writes = transport.requests.filter { it.fields()["method"] == "set" }
        assertEquals(6, writes.size)
        listOf(
            "file-services/set-smb/synthetic-settings/request.json",
            "file-services/set-nfs/synthetic-settings/request.json",
            "file-services/set-ftp/synthetic-settings/request.json",
            "file-services/set-sftp/synthetic-settings/request.json",
            "file-services/set-web-discovery/synthetic-settings/request.json",
            "file-services/set-time-machine/synthetic-settings/request.json",
        ).forEachIndexed { index, fixture ->
            RequestFixtureAssertions.assertRequest(writes[index], fixture)
        }
        assertEquals("true", writes[0].fields()["enable_samba"])
        assertEquals("true", writes[1].fields()["enable_nfs"])
        assertEquals("true", writes[2].fields()["enable_ftps"])
        assertEquals("2222", writes[3].fields()["portnum"])
        assertEquals("false", writes[4].fields()["enable_avahi"])
        assertEquals("true", writes[5].fields()["enable_smb_time_machine"])
    }

    @Test
    fun `文件服务只提交变化 API 组并整体回读`() = runBlocking {
        val transport = SettingsInterceptor(
            json(SMB_OFF), json(FTP_OFF), json(SUCCESS), json(SUCCESS), json(SMB_ON), json(FTP_ON),
        )
        val current = fileSettings()
        val expected = current.copy(isSmbEnabled = true, isFtpEnabled = true, ftpPort = 2_121)

        val result = repository(transport, SMB to 3, FTP to 1)
            .saveFileServiceSettingsResult(expected)

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("get", "get", "set", "set", "get", "get"), transport.methods())
        assertEquals(listOf(SMB, FTP, SMB, FTP, SMB, FTP), transport.apis())
        assertEquals("true", transport.requests[2].fields()["enable_samba"])
        assertEquals("2121", transport.requests[3].fields()["portnum"])
    }

    @Test
    fun `文件服务后续能力缺失时一次性预检且零写请求`() = runBlocking {
        val transport = SettingsInterceptor(json(SMB_OFF))
        val expected = fileSettings().copy(isSmbEnabled = true, isSftpEnabled = true, sftpPort = 2_222)

        val result = repository(transport, SMB to 3).saveFileServiceSettingsResult(expected)

        assertEquals(MutationResultStatus.UNSUPPORTED, result.status)
        assertFalse(result.submitted)
        assertEquals(listOf("get"), transport.methods())
    }

    @Test
    fun `文件服务前序生效后后续失败返回部分成功且不重放`() = runBlocking {
        val transport = SettingsInterceptor(
            json(SMB_OFF), json(FTP_OFF), json(SUCCESS), failure(IOException("synthetic FTP disconnect")),
            json(SMB_ON), json(FTP_OFF),
        )
        val expected = fileSettings().copy(isSmbEnabled = true, isFtpEnabled = true, ftpPort = 2_121)

        val result = repository(transport, SMB to 3, FTP to 1)
            .saveFileServiceSettingsResult(expected)

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertEquals(1, result.counts.succeeded)
        assertEquals(1, result.counts.unknown)
        assertEquals(1, transport.methods().zip(transport.apis()).count { it == "set" to SMB })
        assertEquals(2, transport.methods().count { it == "set" })
    }

    @Test
    fun `文件服务提交与回读均断线返回未确认而不误报失败`() = runBlocking {
        val transport = SettingsInterceptor(
            json(SMB_OFF), json(FTP_OFF),
            failure(IOException("synthetic submit disconnect")),
            failure(IOException("synthetic readback disconnect")),
        )
        val expected = fileSettings().copy(isSmbEnabled = true, isFtpEnabled = true, ftpPort = 2_121)

        val result = repository(transport, SMB to 3, FTP to 1)
            .saveFileServiceSettingsResult(expected)

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertTrue(result.submitted)
        assertTrue(result.requiresRefresh)
        assertEquals(0, result.counts.succeeded)
        assertEquals(0, result.counts.failed)
        assertEquals(2, result.counts.unknown)
    }

    @Test
    fun `文件服务写请求在途取消仍执行不可取消回读`() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = SettingsInterceptor(
            json(SMB_OFF), blockingJson(SUCCESS, entered, release), json(SMB_OFF),
        )
        var result: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) {
            result = repository(transport, SMB to 3).saveFileServiceSettingsResult(
                NasFileServiceSettings(
                    true, null, null, null, null, null, null, null, null, null,
                ),
            )
        }

        assertTrue(entered.await(5, TimeUnit.SECONDS))
        job.cancel()
        release.countDown()
        job.join()

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, result?.status)
        assertTrue(result?.submitted == true)
        assertTrue(result?.requiresRefresh == true)
        assertEquals(listOf("get", "set", "get"), transport.methods())
    }

    @Test
    fun `文件服务提交权限失败保留已提交语义与权限类别`() = runBlocking {
        val transport = SettingsInterceptor(
            json(SMB_OFF), json(FTP_OFF), json(PERMISSION), json(SMB_OFF), json(FTP_OFF),
        )
        val expected = fileSettings().copy(isSmbEnabled = true, isFtpEnabled = true, ftpPort = 2_121)

        val result = repository(transport, SMB to 3, FTP to 1)
            .saveFileServiceSettingsResult(expected)

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertTrue(result.submitted)
        assertFalse(result.requiresRefresh)
        assertEquals(MutationErrorCategory.PERMISSION, result.errorCategory)
        assertEquals(0, result.counts.succeeded)
        assertEquals(2, result.counts.failed)
        assertEquals(0, result.counts.unknown)
    }

    @Test
    fun `文件服务写入响应成功但回读全不匹配返回确认失败`() = runBlocking {
        val transport = SettingsInterceptor(
            json(SMB_OFF), json(FTP_OFF), json(SUCCESS), json(SUCCESS), json(SMB_OFF), json(FTP_OFF),
        )
        val expected = fileSettings().copy(isSmbEnabled = true, isFtpEnabled = true, ftpPort = 2_121)

        val result = repository(transport, SMB to 3, FTP to 1)
            .saveFileServiceSettingsResult(expected)

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertTrue(result.submitted)
        assertFalse(result.requiresRefresh)
        assertEquals(MutationErrorCategory.CONFLICT, result.errorCategory)
        assertEquals(0, result.counts.succeeded)
        assertEquals(2, result.counts.failed)
        assertEquals(0, result.counts.unknown)
    }

    @Test
    fun `文件服务无变化返回冲突且零写入`() = runBlocking {
        val transport = SettingsInterceptor(json(SMB_OFF), json(FTP_OFF))

        val result = repository(transport, SMB to 3, FTP to 1)
            .saveFileServiceSettingsResult(fileSettings())

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertFalse(result.submitted)
        assertEquals(MutationErrorCategory.CONFLICT, result.errorCategory)
        assertEquals(0, transport.methods().count { it == "set" })
    }

    @Test
    fun `文件服务冲突端口与 Time Machine 依赖在请求前拒绝`() = runBlocking {
        val invalid = listOf(
            fileSettings().copy(isFtpEnabled = true, isSftpEnabled = true, ftpPort = 22, sftpPort = 22),
            fileSettings().copy(isSmbEnabled = false, isSmbTimeMachineEnabled = true),
        )
        invalid.forEach { value ->
            val transport = SettingsInterceptor()
            val result = repository(transport, SMB to 3).saveFileServiceSettingsResult(value)
            assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
            assertEquals(MutationErrorCategory.VALIDATION, result.errorCategory)
            assertTrue(transport.requests.isEmpty())
        }
    }

    @Test
    fun `终端设置提交完整字段并回读确认`() = runBlocking {
        val transport = SettingsInterceptor(json(TERMINAL_OFF), json(SUCCESS), json(TERMINAL_ON))

        val result = repository(transport, TERMINAL to 3).saveTerminalSettingsResult(
            NasTerminalSettings(true, true, 2_222),
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        RequestFixtureAssertions.assertRequest(
            transport.requests[1],
            "terminal/set-settings/synthetic-settings/request.json",
        )
        val fields = transport.requests[1].fields()
        assertEquals("true", fields["enable_ssh"])
        assertEquals("true", fields["enable_telnet"])
        assertEquals("2222", fields["ssh_port"])
        assertEquals(3, result.counts.succeeded)
    }

    @Test
    fun `终端提交响应丢失后部分字段匹配返回部分成功`() = runBlocking {
        val transport = SettingsInterceptor(
            json(TERMINAL_OFF), failure(IOException("synthetic terminal disconnect")),
            json(TERMINAL_PARTIAL),
        )

        val result = repository(transport, TERMINAL to 3).saveTerminalSettingsResult(
            NasTerminalSettings(true, true, 2_222),
        )

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertEquals(2, result.counts.succeeded)
        assertEquals(1, result.counts.unknown)
        assertEquals(1, transport.methods().count { it == "set" })
    }

    @Test
    fun `终端非法端口与无变化均不写入`() = runBlocking {
        val invalidTransport = SettingsInterceptor()
        val invalid = repository(invalidTransport, TERMINAL to 3).saveTerminalSettingsResult(
            NasTerminalSettings(true, false, 0),
        )
        assertEquals(MutationErrorCategory.VALIDATION, invalid.errorCategory)
        assertTrue(invalidTransport.requests.isEmpty())

        val sameTransport = SettingsInterceptor(json(TERMINAL_OFF))
        val same = repository(sameTransport, TERMINAL to 3).saveTerminalSettingsResult(
            NasTerminalSettings(false, false, 22),
        )
        assertEquals(MutationErrorCategory.CONFLICT, same.errorCategory)
        assertEquals(listOf("get"), sameTransport.methods())
    }

    @Test
    fun `终端权限拒绝后只回读且不重放`() = runBlocking {
        val transport = SettingsInterceptor(json(TERMINAL_OFF), json(PERMISSION), json(TERMINAL_OFF))

        val result = repository(transport, TERMINAL to 3).saveTerminalSettingsResult(
            NasTerminalSettings(true, false, 22),
        )

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertTrue(result.submitted)
        assertFalse(result.requiresRefresh)
        assertEquals(MutationErrorCategory.PERMISSION, result.errorCategory)
        assertEquals(0, result.counts.succeeded)
        assertEquals(1, result.counts.failed)
        assertEquals(0, result.counts.unknown)
        assertEquals(listOf("get", "set", "get"), transport.methods())
        assertEquals(1, transport.methods().count { it == "set" })
    }

    @Test
    fun `终端预检在途取消不会进入写请求`() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = SettingsInterceptor(blockingJson(TERMINAL_OFF, entered, release))
        var result: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) {
            result = repository(transport, TERMINAL to 3).saveTerminalSettingsResult(
                NasTerminalSettings(true, true, 2_222),
            )
        }

        assertTrue(entered.await(5, TimeUnit.SECONDS))
        job.cancel()
        release.countDown()
        job.join()

        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, result?.status)
        assertFalse(result?.submitted ?: true)
        assertFalse(result?.requiresRefresh ?: true)
        assertEquals(0, result?.counts?.succeeded)
        assertEquals(0, result?.counts?.failed)
        assertEquals(0, result?.counts?.unknown)
        assertEquals(listOf("get"), transport.methods())
    }

    @Test
    fun `终端写请求在途取消仍执行不可取消回读`() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = SettingsInterceptor(
            json(TERMINAL_OFF), blockingJson(SUCCESS, entered, release), json(TERMINAL_OFF),
        )
        var result: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) {
            result = repository(transport, TERMINAL to 3).saveTerminalSettingsResult(
                NasTerminalSettings(true, true, 2_222),
            )
        }

        assertTrue(entered.await(5, TimeUnit.SECONDS))
        job.cancel()
        release.countDown()
        job.join()

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, result?.status)
        assertTrue(result?.submitted == true)
        assertTrue(result?.requiresRefresh == true)
        assertEquals(0, result?.counts?.succeeded)
        assertEquals(0, result?.counts?.failed)
        assertEquals(3, result?.counts?.unknown)
        assertEquals(listOf("get", "set", "get"), transport.methods())
    }

    @Test
    fun `终端在途取消但部分字段生效保留未知计数`() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = SettingsInterceptor(
            json(TERMINAL_OFF), blockingJson(SUCCESS, entered, release), json(TERMINAL_PARTIAL),
        )
        var result: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) {
            result = repository(transport, TERMINAL to 3).saveTerminalSettingsResult(
                NasTerminalSettings(true, true, 2_222),
            )
        }

        assertTrue(entered.await(5, TimeUnit.SECONDS))
        job.cancel()
        release.countDown()
        job.join()

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result?.status)
        assertEquals(2, result?.counts?.succeeded)
        assertEquals(0, result?.counts?.failed)
        assertEquals(1, result?.counts?.unknown)
        assertTrue(result?.requiresRefresh == true)
        assertEquals(1, transport.methods().count { it == "set" })
    }

    @Test
    fun `终端提交成功但回读失败返回未确认且不重放`() = runBlocking {
        val transport = SettingsInterceptor(
            json(TERMINAL_OFF), json(SUCCESS), failure(IOException("synthetic readback disconnect")),
        )

        val result = repository(transport, TERMINAL to 3).saveTerminalSettingsResult(
            NasTerminalSettings(true, true, 2_222),
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertTrue(result.submitted)
        assertTrue(result.requiresRefresh)
        assertEquals(0, result.counts.succeeded)
        assertEquals(0, result.counts.failed)
        assertEquals(3, result.counts.unknown)
        assertEquals(listOf("get", "set", "get"), transport.methods())
    }

    @Test
    fun `终端重复保存被目标锁拒绝且不产生额外写入`() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = SettingsInterceptor(
            json(TERMINAL_OFF), blockingJson(SUCCESS, entered, release), json(TERMINAL_ON),
        )
        val repo = repository(transport, TERMINAL to 3)
        var first: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) {
            first = repo.saveTerminalSettingsResult(NasTerminalSettings(true, true, 2_222))
        }

        assertTrue(entered.await(5, TimeUnit.SECONDS))
        val duplicate = repo.saveTerminalSettingsResult(NasTerminalSettings(true, true, 2_222))
        release.countDown()
        job.join()

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.errorCategory)
        assertFalse(duplicate.submitted)
        assertFalse(duplicate.requiresRefresh)
        assertEquals(0, duplicate.counts.succeeded)
        assertEquals(1, duplicate.counts.failed)
        assertEquals(0, duplicate.counts.unknown)
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first?.status)
        assertEquals(1, transport.methods().count { it == "set" })
    }

    @Test
    fun `终端无变化和单字段变化使用实际变化数量`() = runBlocking {
        val sameTransport = SettingsInterceptor(json(TERMINAL_OFF))
        val same = repository(sameTransport, TERMINAL to 3).saveTerminalSettingsResult(
            NasTerminalSettings(false, false, 22),
        )
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, same.status)
        assertEquals(MutationErrorCategory.CONFLICT, same.errorCategory)
        assertFalse(same.submitted)
        assertFalse(same.requiresRefresh)
        assertEquals(0, same.counts.succeeded)
        assertEquals(1, same.counts.failed)
        assertEquals(0, same.counts.unknown)
        assertEquals(listOf("get"), sameTransport.methods())

        val sshOnlyTransport = SettingsInterceptor(
            json(TERMINAL_OFF), json(SUCCESS),
            json("""{"success":true,"data":{"enable_ssh":true,"enable_telnet":false,"ssh_port":22}}"""),
        )
        val sshOnly = repository(sshOnlyTransport, TERMINAL to 3).saveTerminalSettingsResult(
            NasTerminalSettings(true, false, 22),
        )
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, sshOnly.status)
        assertEquals(1, sshOnly.counts.succeeded)
        assertEquals(0, sshOnly.counts.failed)
        assertEquals(0, sshOnly.counts.unknown)
    }

    @Test
    fun `代理启用请求与 Fixture 字段一致并回读确认`() = runBlocking {
        val transport = SettingsInterceptor(json(PROXY_OFF), json(SUCCESS), json(PROXY_ON))

        val result = repository(transport, PROXY to 1).saveProxySettingsResult(
            NasProxySettings(true, " proxy.example.invalid ", 3_128),
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        RequestFixtureAssertions.assertRequest(
            transport.requests[1],
            "network/set-proxy/synthetic-settings/request.json",
        )
        val fields = transport.requests[1].fields()
        assertEquals("true", fields["enable"])
        assertEquals("proxy.example.invalid", fields["http_host"])
        assertEquals("3128", fields["http_port"])
        assertEquals(listOf("1", "1", "1"), transport.versions())
        assertTrue(result.submitted)
        assertFalse(result.requiresRefresh)
        assertEquals(3, result.counts.succeeded)
        assertEquals(0, result.counts.failed)
        assertEquals(0, result.counts.unknown)
        assertEquals(listOf("get", "set", "get"), transport.methods())
    }

    @Test
    fun `停用代理只提交开关且不比较旧地址`() = runBlocking {
        val transport = SettingsInterceptor(json(PROXY_ON), json(SUCCESS), json(PROXY_OFF_WITH_OLD))

        val result = repository(transport, PROXY to 1).saveProxySettingsResult(
            NasProxySettings(false, "", null),
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(setOf("api", "version", "method", "enable", "_sid", "SynoToken"),
            transport.requests[1].fields().keys)
        assertEquals("false", transport.requests[1].fields()["enable"])
        assertEquals(1, result.counts.succeeded)
        assertEquals(0, result.counts.failed)
        assertEquals(0, result.counts.unknown)
        assertEquals(listOf("1", "1", "1"), transport.versions())
    }

    @Test
    fun `代理非法地址与端口零请求拒绝`() = runBlocking {
        listOf(
            NasProxySettings(true, "https://proxy.example.invalid/path", 3_128),
            NasProxySettings(true, "proxy.example.invalid", 0),
        ).forEach { value ->
            val transport = SettingsInterceptor()
            val result = repository(transport, PROXY to 1).saveProxySettingsResult(value)
            assertEquals(MutationErrorCategory.VALIDATION, result.errorCategory)
            assertTrue(transport.requests.isEmpty())
        }
    }

    @Test
    fun `代理提交断线且回读失败返回未确认不重放`() = runBlocking {
        val transport = SettingsInterceptor(
            json(PROXY_OFF), failure(IOException("synthetic proxy submit disconnect")),
            failure(IOException("synthetic proxy readback disconnect")),
        )

        val result = repository(transport, PROXY to 1).saveProxySettingsResult(
            NasProxySettings(true, "proxy.example.invalid", 3_128),
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertTrue(result.submitted)
        assertTrue(result.requiresRefresh)
        assertEquals(MutationErrorCategory.NETWORK, result.errorCategory)
        assertEquals(0, result.counts.succeeded)
        assertEquals(0, result.counts.failed)
        assertEquals(3, result.counts.unknown)
        assertEquals(listOf("get", "set", "get"), transport.methods())
        assertEquals(1, transport.methods().count { it == "set" })
    }

    @Test
    fun `代理固定版本不在能力范围时零请求关闭`() = runBlocking {
        val transport = SettingsInterceptor()
        val repo = DsmRepository(
            NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
            DsmSession("test", "test-session", "test-token"),
            DsmApiClient(OkHttpClient.Builder().addInterceptor(transport).build()),
            mapOf(PROXY to ApiCapability(PROXY, "entry.cgi", 2, 2)),
        )

        val result = repo.saveProxySettingsResult(
            NasProxySettings(true, "proxy.example.invalid", 3_128),
        )

        assertEquals(MutationResultStatus.UNSUPPORTED, result.status)
        assertFalse(result.submitted)
        assertFalse(result.requiresRefresh)
        assertEquals(0, result.counts.succeeded)
        assertEquals(1, result.counts.failed)
        assertEquals(0, result.counts.unknown)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `代理三字段权限拒绝保留字段失败计数`() = runBlocking {
        val transport = SettingsInterceptor(json(PROXY_OFF), json(PERMISSION), json(PROXY_OFF))

        val result = repository(transport, PROXY to 1).saveProxySettingsResult(
            NasProxySettings(true, "proxy.example.invalid", 3_128),
        )

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertTrue(result.submitted)
        assertFalse(result.requiresRefresh)
        assertEquals(MutationErrorCategory.PERMISSION, result.errorCategory)
        assertEquals(0, result.counts.succeeded)
        assertEquals(3, result.counts.failed)
        assertEquals(0, result.counts.unknown)
        assertEquals(listOf("get", "set", "get"), transport.methods())
        assertEquals(1, transport.methods().count { it == "set" })
    }

    @Test
    fun `代理预检在途取消不会进入写请求`() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = SettingsInterceptor(blockingJson(PROXY_OFF, entered, release))
        var result: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) {
            result = repository(transport, PROXY to 1).saveProxySettingsResult(
                NasProxySettings(true, "proxy.example.invalid", 3_128),
            )
        }

        assertTrue(entered.await(5, TimeUnit.SECONDS))
        job.cancel()
        release.countDown()
        job.join()

        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, result?.status)
        assertFalse(result?.submitted ?: true)
        assertFalse(result?.requiresRefresh ?: true)
        assertEquals(0, result?.counts?.succeeded)
        assertEquals(0, result?.counts?.failed)
        assertEquals(0, result?.counts?.unknown)
        assertEquals(listOf("get"), transport.methods())
    }

    @Test
    fun `代理写请求在途取消回读三字段且不重放`() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = SettingsInterceptor(
            json(PROXY_OFF), blockingJson(SUCCESS, entered, release), json(PROXY_OFF),
        )
        var result: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) {
            result = repository(transport, PROXY to 1).saveProxySettingsResult(
                NasProxySettings(true, "proxy.example.invalid", 3_128),
            )
        }

        assertTrue(entered.await(5, TimeUnit.SECONDS))
        job.cancel()
        release.countDown()
        job.join()

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, result?.status)
        assertTrue(result?.submitted == true)
        assertTrue(result?.requiresRefresh == true)
        assertEquals(0, result?.counts?.succeeded)
        assertEquals(0, result?.counts?.failed)
        assertEquals(3, result?.counts?.unknown)
        assertEquals(listOf("get", "set", "get"), transport.methods())
        assertEquals(1, transport.methods().count { it == "set" })
    }

    @Test
    fun `代理提交响应丢失后部分生效保留未知字段`() = runBlocking {
        val transport = SettingsInterceptor(
            json(PROXY_OFF), failure(IOException("synthetic proxy submit disconnect")),
            json(PROXY_PARTIAL),
        )

        val result = repository(transport, PROXY to 1).saveProxySettingsResult(
            NasProxySettings(true, "proxy.example.invalid", 3_128),
        )

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertTrue(result.submitted)
        assertTrue(result.requiresRefresh)
        assertEquals(1, result.counts.succeeded)
        assertEquals(0, result.counts.failed)
        assertEquals(2, result.counts.unknown)
        assertEquals(1, transport.methods().count { it == "set" })
    }

    @Test
    fun `代理重复保存被目标锁拒绝且不产生额外写入`() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = SettingsInterceptor(
            json(PROXY_OFF), blockingJson(SUCCESS, entered, release), json(PROXY_ON),
        )
        val repo = repository(transport, PROXY to 1)
        var first: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) {
            first = repo.saveProxySettingsResult(
                NasProxySettings(true, "proxy.example.invalid", 3_128),
            )
        }

        assertTrue(entered.await(5, TimeUnit.SECONDS))
        val duplicate = repo.saveProxySettingsResult(
            NasProxySettings(true, "proxy.example.invalid", 3_128),
        )
        release.countDown()
        job.join()

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.errorCategory)
        assertFalse(duplicate.submitted)
        assertEquals(1, duplicate.counts.failed)
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first?.status)
        assertEquals(1, transport.methods().count { it == "set" })
    }

    @Test
    fun `代理停用无变化忽略未提交地址并返回冲突`() = runBlocking {
        val transport = SettingsInterceptor(json(PROXY_OFF_WITH_OLD))

        val result = repository(transport, PROXY to 1).saveProxySettingsResult(
            NasProxySettings(false, "different.example.invalid", 8_080),
        )

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertEquals(MutationErrorCategory.CONFLICT, result.errorCategory)
        assertFalse(result.submitted)
        assertFalse(result.requiresRefresh)
        assertEquals(0, result.counts.succeeded)
        assertEquals(1, result.counts.failed)
        assertEquals(0, result.counts.unknown)
        assertEquals(listOf("get"), transport.methods())
    }

    @Test
    fun `区域设置按固定版本保存回读并在确认后校时`() = runBlocking {
        val transport = SettingsInterceptor(
            json(REGION_MANUAL), json(REGION_ZONES), json(SUCCESS),
            json(REGION_NTP), json(REGION_ZONES), json(SUCCESS),
            json(REGION_NTP), json(REGION_ZONES),
        )

        val result = repository(transport, REGION to 3).saveRegionSettingsResult(regionNtpDraft())

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(5, result.counts.succeeded)
        assertEquals(listOf("3", "1", "3", "3", "1", "2", "3", "1"), transport.versions())
        RequestFixtureAssertions.assertRequest(
            transport.requests[2],
            "region/set-settings/synthetic-settings/request.json",
        )
        RequestFixtureAssertions.assertRequest(
            transport.requests[5],
            "region/synchronize-time/synthetic-servers/request.json",
        )
        val set = transport.requests[2].fields()
        assertEquals("Y/m/d", set["date_format"])
        assertEquals("UTC", set["timezone"])
        assertEquals("ntp", set["enable_ntp"])
        assertEquals("time.example.invalid", set["server"])
        assertEquals("[\"time.example.invalid\"]", transport.requests[5].fields()["servers"])
    }

    @Test
    fun `未编辑手动时间时使用预检刚读取的 NAS 时间`() = runBlocking {
        val after = REGION_MANUAL.replace("Y-m-d", "Y/m/d").replace("\"second\":10", "\"second\":11")
        val transport = SettingsInterceptor(
            json(REGION_MANUAL), json(REGION_ZONES), json(SUCCESS), json(after), json(REGION_ZONES),
        )
        val draft = NasRegionSettings(
            "Y/m/d", "H:i", "Asia/Shanghai", false, emptyList(), null,
            listOf(NasTimeZoneOption("Asia/Shanghai", "北京、上海")),
        )

        val result = repository(transport, REGION to 3).saveRegionSettingsResult(draft)

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        val set = transport.requests[2].fields()
        assertEquals("2026/7/26", set["date"])
        assertEquals("18", set["hour"])
        assertEquals("30", set["minute"])
        assertEquals("10", set["second"])
        assertFalse(transport.methods().contains("sync"))
    }

    @Test
    fun `区域配置提交超时只回读且不继续校时`() = runBlocking {
        val partial = REGION_MANUAL.replace("Y-m-d", "Y/m/d")
        val transport = SettingsInterceptor(
            json(REGION_MANUAL), json(REGION_ZONES), failure(IOException("synthetic region timeout")),
            json(partial), json(REGION_ZONES),
        )

        val result = repository(transport, REGION to 3).saveRegionSettingsResult(regionNtpDraft())

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertEquals(1, result.counts.succeeded)
        assertEquals(4, result.counts.unknown)
        assertEquals(1, transport.methods().count { it == "set" })
        assertFalse(transport.methods().contains("sync"))
    }

    @Test
    fun `区域配置确认后校时超时返回部分成功且不重放`() = runBlocking {
        val transport = SettingsInterceptor(
            json(REGION_MANUAL), json(REGION_ZONES), json(SUCCESS),
            json(REGION_NTP), json(REGION_ZONES), failure(IOException("synthetic sync timeout")),
        )

        val result = repository(transport, REGION to 3).saveRegionSettingsResult(regionNtpDraft())

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertEquals(4, result.counts.succeeded)
        assertEquals(1, result.counts.unknown)
        assertEquals(1, transport.methods().count { it == "sync" })
    }

    @Test
    fun `区域设置拒绝非法服务器和未返回的时区`() = runBlocking {
        val invalidTransport = SettingsInterceptor()
        val invalid = repository(invalidTransport, REGION to 3).saveRegionSettingsResult(
            regionNtpDraft().copy(timeServers = listOf("https://time.example.invalid/path")),
        )
        assertEquals(MutationErrorCategory.VALIDATION, invalid.errorCategory)
        assertTrue(invalidTransport.requests.isEmpty())

        val zoneTransport = SettingsInterceptor(json(REGION_MANUAL), json(REGION_ZONES))
        val unknownZone = repository(zoneTransport, REGION to 3).saveRegionSettingsResult(
            regionNtpDraft().copy(timeZone = "Mars/Olympus"),
        )
        assertEquals(MutationErrorCategory.VALIDATION, unknownZone.errorCategory)
        assertEquals(listOf("get", "listzone"), zoneTransport.methods())
    }

    @Test
    fun `区域预检拒绝未知自动校时模式且零写请求`() = runBlocking {
        val unknownMode = REGION_MANUAL.replace(
            "\"enable_ntp\":\"manual\"",
            "\"enable_ntp\":\"synthetic-unknown\"",
        )
        val transport = SettingsInterceptor(json(unknownMode), json(REGION_ZONES))

        val result = repository(transport, REGION to 3).saveRegionSettingsResult(regionNtpDraft())

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertFalse(result.submitted)
        assertEquals(0, result.counts.succeeded)
        assertEquals(1, result.counts.failed)
        assertEquals(0, result.counts.unknown)
        assertEquals(listOf("get", "listzone"), transport.methods())
        assertFalse(transport.methods().contains("set"))
        assertFalse(transport.methods().contains("sync"))
    }

    @Test
    fun `区域固定版本范围不完整时零请求关闭`() = runBlocking {
        listOf(1 to 1, 3 to 3).forEach { (min, max) ->
            val transport = SettingsInterceptor()

            val result = repositoryRange(transport, REGION, min, max)
                .saveRegionSettingsResult(regionNtpDraft())

            assertEquals("$min-$max", MutationResultStatus.UNSUPPORTED, result.status)
            assertFalse(result.submitted)
            assertFalse(result.requiresRefresh)
            assertEquals(0, result.counts.succeeded)
            assertEquals(1, result.counts.failed)
            assertEquals(0, result.counts.unknown)
            assertTrue(transport.requests.isEmpty())
        }
    }

    @Test
    fun `区域预检在途取消不会进入配置或校时请求`() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = SettingsInterceptor(blockingJson(REGION_MANUAL, entered, release))
        var result: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) {
            result = repository(transport, REGION to 3).saveRegionSettingsResult(regionNtpDraft())
        }

        assertTrue(entered.await(5, TimeUnit.SECONDS))
        job.cancel()
        release.countDown()
        job.join()

        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, result?.status)
        assertFalse(result?.submitted ?: true)
        assertFalse(result?.requiresRefresh ?: true)
        assertEquals(0, result?.counts?.succeeded)
        assertEquals(0, result?.counts?.failed)
        assertEquals(0, result?.counts?.unknown)
        assertEquals(listOf("get"), transport.methods())
    }

    @Test
    fun `区域配置写请求在途取消回读且绝不继续校时`() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = SettingsInterceptor(
            json(REGION_MANUAL), json(REGION_ZONES), blockingJson(SUCCESS, entered, release),
            json(REGION_MANUAL), json(REGION_ZONES),
        )
        var result: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) {
            result = repository(transport, REGION to 3).saveRegionSettingsResult(regionNtpDraft())
        }

        assertTrue(entered.await(5, TimeUnit.SECONDS))
        job.cancel()
        release.countDown()
        job.join()

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, result?.status)
        assertTrue(result?.submitted == true)
        assertTrue(result?.requiresRefresh == true)
        assertEquals(0, result?.counts?.succeeded)
        assertEquals(0, result?.counts?.failed)
        assertEquals(5, result?.counts?.unknown)
        assertEquals(listOf("get", "listzone", "set", "get", "listzone"), transport.methods())
        assertFalse(transport.methods().contains("sync"))
    }

    @Test
    fun `区域配置权限失败与回读失败保留多字段计数且不校时`() = runBlocking {
        val transport = SettingsInterceptor(
            json(REGION_MANUAL), json(REGION_ZONES), json(PERMISSION),
            failure(IOException("synthetic region readback disconnect")),
        )

        val result = repository(transport, REGION to 3).saveRegionSettingsResult(regionNtpDraft())

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertEquals(MutationErrorCategory.PERMISSION, result.errorCategory)
        assertTrue(result.submitted)
        assertEquals(0, result.counts.succeeded)
        assertEquals(4, result.counts.failed)
        assertEquals(0, result.counts.unknown)
        assertEquals(1, transport.methods().count { it == "set" })
        assertFalse(transport.methods().contains("sync"))
    }

    @Test
    fun `区域配置响应未知但回读确认时仍不自动校时`() = runBlocking {
        val transport = SettingsInterceptor(
            json(REGION_MANUAL), json(REGION_ZONES),
            failure(IOException("synthetic region response lost")),
            json(REGION_NTP), json(REGION_ZONES),
        )

        val result = repository(transport, REGION to 3).saveRegionSettingsResult(regionNtpDraft())

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertEquals(4, result.counts.succeeded)
        assertEquals(0, result.counts.failed)
        assertEquals(1, result.counts.unknown)
        assertEquals("region.configuration-not-fully-confirmed", result.diagnosticTag)
        assertFalse(transport.methods().contains("sync"))
    }

    @Test
    fun `区域立即校时在途取消只提交一次并保留待核对结果`() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = SettingsInterceptor(
            json(REGION_MANUAL), json(REGION_ZONES), json(SUCCESS),
            json(REGION_NTP), json(REGION_ZONES), blockingJson(SUCCESS, entered, release),
        )
        var result: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) {
            result = repository(transport, REGION to 3).saveRegionSettingsResult(regionNtpDraft())
        }

        assertTrue(entered.await(5, TimeUnit.SECONDS))
        job.cancel()
        release.countDown()
        job.join()

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result?.status)
        assertEquals(4, result?.counts?.succeeded)
        assertEquals(0, result?.counts?.failed)
        assertEquals(1, result?.counts?.unknown)
        assertEquals(1, transport.methods().count { it == "sync" })
    }

    @Test
    fun `区域立即校时成功但最终读取失败返回部分成功且不重放`() = runBlocking {
        val transport = SettingsInterceptor(
            json(REGION_MANUAL), json(REGION_ZONES), json(SUCCESS),
            json(REGION_NTP), json(REGION_ZONES), json(SUCCESS),
            failure(IOException("synthetic final region readback disconnect")),
        )

        val result = repository(transport, REGION to 3).saveRegionSettingsResult(regionNtpDraft())

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertEquals(4, result.counts.succeeded)
        assertEquals(0, result.counts.failed)
        assertEquals(1, result.counts.unknown)
        assertEquals("region.sync-readback-unverified", result.diagnosticTag)
        assertEquals(1, transport.methods().count { it == "sync" })
    }

    @Test
    fun `区域重复保存被目标锁拒绝且无变化只读取不写入`() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val transport = SettingsInterceptor(
            json(REGION_MANUAL), json(REGION_ZONES), blockingJson(SUCCESS, entered, release),
            json(REGION_NTP), json(REGION_ZONES), json(SUCCESS), json(REGION_NTP), json(REGION_ZONES),
        )
        val repo = repository(transport, REGION to 3)
        var first: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) { first = repo.saveRegionSettingsResult(regionNtpDraft()) }

        assertTrue(entered.await(5, TimeUnit.SECONDS))
        val duplicate = repo.saveRegionSettingsResult(regionNtpDraft())
        release.countDown()
        job.join()

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.errorCategory)
        assertFalse(duplicate.submitted)
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first?.status)
        assertEquals(1, transport.methods().count { it == "set" })
        assertEquals(1, transport.methods().count { it == "sync" })

        val noChangeTransport = SettingsInterceptor(json(REGION_MANUAL), json(REGION_ZONES))
        val noChange = repository(noChangeTransport, REGION to 3).saveRegionSettingsResult(
            NasRegionSettings(
                "Y-m-d", "H:i", "Asia/Shanghai", false, emptyList(), null,
                listOf(NasTimeZoneOption("Asia/Shanghai", "北京、上海")),
            ),
        )
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, noChange.status)
        assertEquals(MutationErrorCategory.CONFLICT, noChange.errorCategory)
        assertFalse(noChange.submitted)
        assertEquals(listOf("get", "listzone"), noChangeTransport.methods())
    }

    @Test
    fun `安全设置四个子操作使用固定契约并整体回读`() = runBlocking {
        val transport = SettingsInterceptor(
            json(AUTO_BLOCK_OFF), json(FIREWALL_ON), json(PORT_SCAN_OFF), json(ETHERNET), json(DOS_OFF),
            json(SUCCESS), json(SUCCESS), json(SUCCESS), json(SUCCESS),
            json(AUTO_BLOCK_ON), json(FIREWALL_OFF), json(PORT_SCAN_ON), json(ETHERNET), json(DOS_ON),
        )

        val result = securityRepository(transport).saveSecuritySettingsResult(securityUpdate())

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(4, result.counts.succeeded)
        assertEquals(listOf("set", "set", "set", "set"), transport.methods().subList(5, 9))
        listOf(
            "security/set-auto-block/synthetic-settings/request.json",
            "security/set-dos/synthetic-interface/request.json",
            "security/set-port-scan/synthetic-settings/request.json",
            "security/disable-firewall/synthetic-settings/request.json",
        ).forEachIndexed { index, fixture ->
            RequestFixtureAssertions.assertRequest(transport.requests[index + 5], fixture)
        }
        assertEquals("true", transport.requests[5].fields()["enable"])
        assertEquals("[{\"adapter\":\"eth-synthetic\",\"dos_protect_enable\":true}]",
            transport.requests[6].fields()["configs"])
        assertEquals("2", transport.requests[6].fields()["version"])
        assertEquals("true", transport.requests[7].fields()["enable_port_check"])
        assertEquals("disable", transport.requests[8].fields()["set_type"])
    }

    @Test
    fun `安全设置中途断线后停止后续提交并整体回读`() = runBlocking {
        val transport = SettingsInterceptor(
            json(AUTO_BLOCK_OFF), json(PORT_SCAN_OFF), json(SUCCESS),
            failure(IOException("synthetic port scan timeout")),
            json(AUTO_BLOCK_ON), json(PORT_SCAN_OFF),
        )
        val expected = securityUpdate().copy(
            dosProtection = emptyList(), isFirewallEnabled = null, firewallProfileName = null,
        )

        val result = repository(transport, AUTO_BLOCK to 1, FIREWALL_CONF to 1)
            .saveSecuritySettingsResult(expected)

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertEquals(1, result.counts.succeeded)
        assertEquals(2, transport.methods().count { it == "set" })
    }

    @Test
    fun `安全设置提交断网且回读失败不自动重放`() = runBlocking {
        val transport = SettingsInterceptor(
            json(AUTO_BLOCK_OFF), failure(IOException("synthetic submit disconnect")),
            failure(IOException("synthetic readback disconnect")),
        )
        val expected = securityUpdate().copy(
            dosProtection = emptyList(), isFirewallEnabled = null,
            firewallProfileName = null, isPortScanProtectionEnabled = null,
        )

        val result = repository(transport, AUTO_BLOCK to 1).saveSecuritySettingsResult(expected)

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertEquals(1, result.counts.unknown)
        assertEquals(1, transport.methods().count { it == "set" })
    }

    @Test
    fun `开启防火墙只应用预检返回的配置档并清理任务`() = runBlocking {
        val transport = SettingsInterceptor(
            json(AUTO_BLOCK_ON), json(FIREWALL_OFF_PROFILE),
            json("""{"success":true,"data":{"task_id":"synthetic-task"}}"""),
            json("""{"success":true,"data":{"success":true}}"""), json(SUCCESS),
            json(AUTO_BLOCK_ON), json(FIREWALL_ON_PROFILE),
        )
        val expected = securityUpdate().copy(
            dosProtection = emptyList(), isFirewallEnabled = true,
            firewallProfileName = "user-must-not-control-this", isPortScanProtectionEnabled = null,
        )

        val result = repository(
            transport, AUTO_BLOCK to 1, FIREWALL to 1, FIREWALL_APPLY to 1,
        ).saveSecuritySettingsResult(expected)

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        RequestFixtureAssertions.assertRequest(
            transport.requests[2],
            "security/apply-firewall-profile/synthetic-profile/request.json",
        )
        assertEquals("synthetic-profile", transport.requests[2].fields()["name"])
        assertEquals("synthetic-task", transport.requests[3].fields()["task_id"])
        assertEquals("stop", transport.requests[4].fields()["method"])
    }

    @Test
    fun `安全设置非法阈值与伪造网卡标识零请求拒绝`() = runBlocking {
        listOf(
            securityUpdate().copy(failedAttempts = 0),
            securityUpdate().copy(
                dosProtection = listOf(NasDoSProtectionSetting("eth/unsafe", "Unsafe", true)),
            ),
        ).forEach { expected ->
            val transport = SettingsInterceptor()
            val result = securityRepository(transport).saveSecuritySettingsResult(expected)
            assertEquals(MutationErrorCategory.VALIDATION, result.errorCategory)
            assertTrue(transport.requests.isEmpty())
        }
    }

    @Test
    fun `关机与重启均先预检且只提交一次无参数动作`() = runBlocking {
        NasPowerAction.entries.forEach { action ->
            val transport = SettingsInterceptor(json(SUCCESS), json(SUCCESS))
            val result = repository(transport, SYSTEM to 3).performPowerActionResult(action)
            assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
            assertTrue(result.submitted)
            assertEquals(
                listOf("info", if (action == NasPowerAction.SHUTDOWN) "shutdown" else "reboot"),
                transport.methods(),
            )
            RequestFixtureAssertions.assertRequest(
                transport.requests[1],
                if (action == NasPowerAction.SHUTDOWN) {
                    "system-power/shutdown/synthetic-nas/request.json"
                } else {
                    "system-power/reboot/synthetic-nas/request.json"
                },
            )
            assertEquals(setOf("api", "version", "method", "_sid", "SynoToken"),
                transport.requests[1].fields().keys)
        }
    }

    @Test
    fun `电源动作能力缺失与预检拒绝均零写入`() = runBlocking {
        val unsupportedTransport = SettingsInterceptor()
        val unsupported = repository(unsupportedTransport).performPowerActionResult(NasPowerAction.SHUTDOWN)
        assertEquals(MutationResultStatus.UNSUPPORTED, unsupported.status)
        assertTrue(unsupportedTransport.requests.isEmpty())

        val deniedTransport = SettingsInterceptor(json(PERMISSION))
        val denied = repository(deniedTransport, SYSTEM to 3)
            .performPowerActionResult(NasPowerAction.REBOOT)
        assertEquals(MutationResultStatus.PERMISSION_DENIED, denied.status)
        assertFalse(denied.submitted)
        assertEquals(listOf("info"), deniedTransport.methods())
    }

    @Test
    fun `电源请求提交断线报告未确认且禁止重放`() = runBlocking {
        val transport = SettingsInterceptor(
            json(SUCCESS), failure(IOException("synthetic power disconnect")),
        )

        val result = repository(transport, SYSTEM to 3)
            .performPowerActionResult(NasPowerAction.SHUTDOWN)

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertTrue(result.requiresRefresh)
        assertEquals(1, result.counts.unknown)
        assertEquals(1, transport.methods().count { it == "shutdown" })
    }

    @Test
    fun `硬件六组设置按契约提交并整体回读`() = runBlocking {
        val transport = SettingsInterceptor(
            json(POWER_OFF), json(LED_LOW), json(LED_RANGE), json(FAN_QUIET), json(BEEP_OFF),
            json(HIBERNATION_OFF), json(UPS_OFF),
            json(SUCCESS), json(SUCCESS), json(SUCCESS), json(SUCCESS), json(SUCCESS), json(SUCCESS), json(SUCCESS),
            json(POWER_ON), json(LED_HIGH), json(LED_RANGE), json(FAN_COOL), json(BEEP_ON),
            json(HIBERNATION_ON), json(UPS_ON),
        )

        val result = hardwareRepository(transport).saveHardwareSettingsResult(
            hardwareBaseline(), hardwareUpdate(),
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(6, result.counts.succeeded)
        RequestFixtureAssertions.assertRequest(
            transport.requests[7],
            "hardware/set-power-recovery/synthetic-settings/request.json",
        )
        RequestFixtureAssertions.assertRequest(
            transport.requests[8],
            "hardware/set-led-brightness/synthetic-settings/request.json",
        )
        RequestFixtureAssertions.assertRequest(
            transport.requests[10],
            "hardware/set-fan-mode/synthetic-settings/request.json",
        )
        assertEquals("true", transport.requests[7].fields()["rc_power_config"])
        assertEquals("5", transport.requests[8].fields()["led_brightness"])
        assertEquals("update", transport.requests[9].fields()["method"])
        assertEquals("coolfan", transport.requests[10].fields()["dual_fan_speed"])
        assertEquals("true", transport.requests[11].fields()["volume_or_cache_crash"])
        assertEquals("true", transport.requests[12].fields()["ignore_netbios_broadcast"])
        assertEquals("SLAVE", transport.requests[13].fields()["mode"])
        assertEquals("ups.example.invalid", transport.requests[13].fields()["net_server_ip"])
    }

    @Test
    fun `硬件设置中途断线停止后续写入并回读部分成功`() = runBlocking {
        val transport = SettingsInterceptor(
            json(POWER_OFF), json(FAN_QUIET), json(SUCCESS),
            failure(IOException("synthetic fan timeout")), json(POWER_ON), json(FAN_QUIET),
        )
        val expected = emptyHardware().copy(restartsAfterPowerFailure = true, fanMode = "coolfan")

        val result = repository(transport, POWER to 1, FAN to 1).saveHardwareSettingsResult(expected)

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertEquals(1, result.counts.succeeded)
        assertEquals(2, transport.methods().count { it == "set" })
    }

    @Test
    fun `蜂鸣休眠与UPS独立变更符合公共 Fixture`() = runBlocking {
        val beepTransport = SettingsInterceptor(
            json(BEEP_OFF), json(SUCCESS), json(BEEP_POWER_ON),
        )
        val hibernationTransport = SettingsInterceptor(
            json(HIBERNATION_OFF), json(SUCCESS), json(HIBERNATION_SELECTED_ON),
        )
        val upsTransport = SettingsInterceptor(
            json(UPS_OFF), json(SUCCESS), json(UPS_ON),
        )
        val beepOriginal = emptyHardware().copy(
            isFanFailureAlertEnabled = false,
            isVolumeFailureAlertEnabled = false,
            isPowerOnSoundEnabled = false,
            isPowerOffSoundEnabled = false,
            isResetSoundEnabled = false,
        )
        val hibernationOriginal = emptyHardware().copy(
            isExternalDriveDeepSleepEnabled = false,
            isWakeUpLogEnabled = false,
            isSataSleepEnabled = false,
            ignoresNetworkDiscoveryDuringSleep = false,
            isAutomaticPowerOffEnabled = false,
        )
        val upsOriginal = emptyHardware().copy(ups = upsBaseline())

        assertEquals(
            MutationResultStatus.CONFIRMED_SUCCESS,
            repository(beepTransport, BEEP to 1).saveHardwareSettingsResult(
                beepOriginal,
                beepOriginal.copy(isPowerOnSoundEnabled = true),
            ).status,
        )
        assertEquals(
            MutationResultStatus.CONFIRMED_SUCCESS,
            repository(hibernationTransport, HIBERNATION to 1).saveHardwareSettingsResult(
                hibernationOriginal,
                hibernationOriginal.copy(
                    isExternalDriveDeepSleepEnabled = true,
                    ignoresNetworkDiscoveryDuringSleep = true,
                ),
            ).status,
        )
        assertEquals(
            MutationResultStatus.CONFIRMED_SUCCESS,
            repository(upsTransport, UPS to 1).saveHardwareSettingsResult(
                upsOriginal,
                upsOriginal.copy(
                    ups = upsBaseline().copy(
                        isEnabled = true,
                        mode = "SLAVE",
                        safeModeDelaySeconds = 120,
                        shutsDownUpsAfterSafeMode = true,
                        networkServerAddress = "ups.example.invalid",
                    ),
                ),
            ).status,
        )
        RequestFixtureAssertions.assertRequest(
            beepTransport.requests[1],
            "hardware/set-beep/synthetic-settings/request.json",
        )
        RequestFixtureAssertions.assertRequest(
            hibernationTransport.requests[1],
            "hardware/set-hibernation/synthetic-settings/request.json",
        )
        RequestFixtureAssertions.assertRequest(
            upsTransport.requests[1],
            "hardware/set-ups/synthetic-settings/request.json",
        )
    }

    @Test
    fun `硬件设置拒绝范围外亮度和非法 UPS 地址且零写入`() = runBlocking {
        val ledTransport = SettingsInterceptor(json(LED_LOW), json(LED_RANGE))
        val ledResult = repository(ledTransport, LED to 1).saveHardwareSettingsResult(
            emptyHardware().copy(ledBrightness = 99, ledBrightnessMinimum = 1, ledBrightnessMaximum = 5),
        )
        assertEquals(MutationErrorCategory.VALIDATION, ledResult.errorCategory)
        assertFalse(ledTransport.methods().any { it.startsWith("set") })

        val upsTransport = SettingsInterceptor(json(UPS_OFF))
        val upsResult = repository(upsTransport, UPS to 1).saveHardwareSettingsResult(
            emptyHardware().copy(
                ups = NasUpsSettings(true, "SLAVE", 120, false, true,
                    "https://ups.example.invalid/path", ""),
            ),
        )
        assertEquals(MutationErrorCategory.VALIDATION, upsResult.errorCategory)
        assertEquals(listOf("get"), upsTransport.methods())
    }

    @Test
    fun `蜂鸣器沿用设备返回的旧音量故障字段`() = runBlocking {
        val legacyOff = BEEP_OFF.replace("volume_or_cache_crash", "volume_crash")
        val legacyOn = BEEP_ON.replace("volume_or_cache_crash", "volume_crash")
        val transport = SettingsInterceptor(json(legacyOff), json(SUCCESS), json(legacyOn))

        val result = repository(transport, BEEP to 1).saveHardwareSettingsResult(
            emptyHardware().copy(isVolumeFailureAlertEnabled = true),
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals("true", transport.requests[1].fields()["volume_crash"])
        assertFalse(transport.requests[1].fields().containsKey("volume_or_cache_crash"))
    }

    private fun regionNtpDraft() = NasRegionSettings(
        "Y/m/d", "H:i", "UTC", true, listOf("time.example.invalid"), null,
        listOf(
            NasTimeZoneOption("Asia/Shanghai", "北京、上海"),
            NasTimeZoneOption("UTC", "协调世界时"),
        ),
    )

    private fun securityRepository(interceptor: Interceptor) = repository(
        interceptor, AUTO_BLOCK to 1, FIREWALL to 1, FIREWALL_CONF to 1,
        ETHERNET_API_TEST to 2, DOS to 2,
    )

    private fun securityUpdate() = NasSecuritySettings(
        true, 5, 10, 7,
        listOf(NasDoSProtectionSetting("eth-synthetic", "LAN 1", true)),
        false, "synthetic-profile", true,
    )

    private fun hardwareRepository(interceptor: Interceptor) = repository(
        interceptor, POWER to 1, LED to 1, FAN to 1, BEEP to 1, HIBERNATION to 1, UPS to 1,
    )

    private fun emptyHardware() = NasHardwareSettings(
        null, null, null, null, null, null, null, null, null, null,
        null, null, null, null, null, null,
    )

    private fun upsBaseline() = NasUpsSettings(
        false, "USB", 60, false, false, "", "",
    )

    private fun hardwareBaseline() = NasHardwareSettings(
        false, 1, 1, 5, "quietfan", false, false, false, false, false,
        false, false, false, false, false, upsBaseline(),
    )

    private fun hardwareUpdate() = NasHardwareSettings(
        true, 5, 1, 5, "coolfan", true, true, true, true, true,
        true, true, true, true, true,
        NasUpsSettings(true, "SLAVE", 120, false, true, "ups.example.invalid", ""),
    )

    private fun repository(interceptor: Interceptor, vararg versions: Pair<String, Int>) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "test-session", "test-token"),
        DsmApiClient(OkHttpClient.Builder().addInterceptor(interceptor).build()),
        versions.associate { (name, max) -> name to ApiCapability(name, "entry.cgi", 1, max) },
    )

    private fun repositoryRange(
        interceptor: Interceptor,
        name: String,
        min: Int,
        max: Int,
    ) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "test-session", "test-token"),
        DsmApiClient(OkHttpClient.Builder().addInterceptor(interceptor).build()),
        mapOf(name to ApiCapability(name, "entry.cgi", min, max)),
    )

    private fun fileSettings() = NasFileServiceSettings(
        isSmbEnabled = false,
        isNfsEnabled = null,
        isFtpEnabled = false,
        isFtpsEnabled = false,
        ftpPort = 21,
        isSftpEnabled = null,
        sftpPort = null,
        isSsdpEnabled = null,
        isBonjourEnabled = null,
        isSmbTimeMachineEnabled = null,
    )

    companion object {
        const val SMB = "SYNO.Core.FileServ.SMB"
        const val FTP = "SYNO.Core.FileServ.FTP"
        const val NFS = "SYNO.Core.FileServ.NFS"
        const val SFTP = "SYNO.Core.FileServ.FTP.SFTP"
        const val WEB = "SYNO.Core.Web.DSM"
        const val DISCOVERY = "SYNO.Core.FileServ.ServiceDiscovery"
        const val TERMINAL = "SYNO.Core.Terminal"
        const val PROXY = "SYNO.Core.Network.Proxy"
        const val REGION = "SYNO.Core.Region.NTP"
        const val AUTO_BLOCK = "SYNO.Core.Security.AutoBlock"
        const val DOS = "SYNO.Core.Security.DoS"
        const val FIREWALL = "SYNO.Core.Security.Firewall"
        const val FIREWALL_CONF = "SYNO.Core.Security.Firewall.Conf"
        const val FIREWALL_APPLY = "SYNO.Core.Security.Firewall.Profile.Apply"
        const val ETHERNET_API_TEST = "SYNO.Core.Network.Ethernet"
        const val SYSTEM = "SYNO.Core.System"
        const val POWER = "SYNO.Core.Hardware.PowerRecovery"
        const val LED = "SYNO.Core.Hardware.Led.Brightness"
        const val FAN = "SYNO.Core.Hardware.FanSpeed"
        const val BEEP = "SYNO.Core.Hardware.BeepControl"
        const val HIBERNATION = "SYNO.Core.Hardware.Hibernation"
        const val UPS = "SYNO.Core.ExternalDevice.UPS"
        const val SUCCESS = """{"success":true,"data":{}}"""
        const val PERMISSION = """{"success":false,"error":{"code":105}}"""
        const val SMB_OFF = """{"success":true,"data":{"enable_samba":false}}"""
        const val SMB_ON = """{"success":true,"data":{"enable_samba":true}}"""
        const val NFS_OFF = """{"success":true,"data":{"enable_nfs":false}}"""
        const val NFS_ON = """{"success":true,"data":{"enable_nfs":true}}"""
        const val FTP_OFF =
            """{"success":true,"data":{"enable_ftp":false,"enable_ftps":false,"portnum":21}}"""
        const val FTP_ON =
            """{"success":true,"data":{"enable_ftp":true,"enable_ftps":false,"portnum":2121}}"""
        const val FTP_ALL_ON =
            """{"success":true,"data":{"enable_ftp":true,"enable_ftps":true,"portnum":2121}}"""
        const val SFTP_OFF = """{"success":true,"data":{"enable":false,"portnum":22}}"""
        const val SFTP_ON = """{"success":true,"data":{"enable":true,"portnum":2222}}"""
        const val WEB_OFF =
            """{"success":true,"data":{"enable_ssdp":false,"enable_avahi":false}}"""
        const val WEB_ON =
            """{"success":true,"data":{"enable_ssdp":true,"enable_avahi":true}}"""
        const val WEB_SSDP_ON =
            """{"success":true,"data":{"enable_ssdp":true,"enable_avahi":false}}"""
        const val DISCOVERY_OFF =
            """{"success":true,"data":{"enable_smb_time_machine":false}}"""
        const val DISCOVERY_ON =
            """{"success":true,"data":{"enable_smb_time_machine":true}}"""
        const val TERMINAL_OFF =
            """{"success":true,"data":{"enable_ssh":false,"enable_telnet":false,"ssh_port":22}}"""
        const val TERMINAL_ON =
            """{"success":true,"data":{"enable_ssh":true,"enable_telnet":true,"ssh_port":2222}}"""
        const val TERMINAL_PARTIAL =
            """{"success":true,"data":{"enable_ssh":true,"enable_telnet":false,"ssh_port":2222}}"""
        const val PROXY_OFF =
            """{"success":true,"data":{"enable":false,"http_host":"","http_port":0}}"""
        const val PROXY_ON =
            """{"success":true,"data":{"enable":true,"http_host":"proxy.example.invalid","http_port":3128}}"""
        const val PROXY_PARTIAL =
            """{"success":true,"data":{"enable":true,"http_host":"","http_port":0}}"""
        const val PROXY_OFF_WITH_OLD =
            """{"success":true,"data":{"enable":false,"http_host":"proxy.example.invalid","http_port":3128}}"""
        const val REGION_MANUAL =
            """{"success":true,"data":{"date_format":"Y-m-d","time_format":"H:i","timezone":"Asia/Shanghai","enable_ntp":"manual","server":"","date":"2026/7/26","hour":18,"minute":30,"second":10}}"""
        const val REGION_NTP =
            """{"success":true,"data":{"date_format":"Y/m/d","time_format":"H:i","timezone":"UTC","enable_ntp":"ntp","server":"time.example.invalid","date":"2026/7/26","hour":18,"minute":30,"second":10}}"""
        const val REGION_ZONES =
            """{"success":true,"data":{"zonedata":[{"value":"Asia/Shanghai","display":"北京、上海"},{"value":"UTC","display":"协调世界时"}]}}"""
        const val AUTO_BLOCK_OFF =
            """{"success":true,"data":{"enable":false,"attempts":10,"within_mins":5,"expire_day":0}}"""
        const val AUTO_BLOCK_ON =
            """{"success":true,"data":{"enable":true,"attempts":5,"within_mins":10,"expire_day":7}}"""
        const val FIREWALL_ON =
            """{"success":true,"data":{"enable_firewall":true,"profile_name":"synthetic-profile"}}"""
        const val FIREWALL_OFF =
            """{"success":true,"data":{"enable_firewall":false,"profile_name":"synthetic-profile"}}"""
        const val FIREWALL_OFF_PROFILE = FIREWALL_OFF
        const val FIREWALL_ON_PROFILE = FIREWALL_ON
        const val PORT_SCAN_OFF = """{"success":true,"data":{"enable_port_check":false}}"""
        const val PORT_SCAN_ON = """{"success":true,"data":{"enable_port_check":true}}"""
        const val ETHERNET =
            """{"success":true,"data":{"interfaces":[{"id":"eth-synthetic","display":"LAN 1"}]}}"""
        const val DOS_OFF =
            """{"success":true,"data":[{"adapter":"eth-synthetic","dos_protect_enable":false}]}"""
        const val DOS_ON =
            """{"success":true,"data":[{"adapter":"eth-synthetic","dos_protect_enable":true}]}"""
        const val POWER_OFF = """{"success":true,"data":{"rc_power_config":false}}"""
        const val POWER_ON = """{"success":true,"data":{"rc_power_config":true}}"""
        const val LED_LOW = """{"success":true,"data":{"led_brightness":1}}"""
        const val LED_HIGH = """{"success":true,"data":{"led_brightness":5}}"""
        const val LED_RANGE = """{"success":true,"data":{"min":1,"max":5}}"""
        const val FAN_QUIET = """{"success":true,"data":{"dual_fan_speed":"quietfan"}}"""
        const val FAN_COOL = """{"success":true,"data":{"dual_fan_speed":"coolfan"}}"""
        const val BEEP_OFF =
            """{"success":true,"data":{"fan_fail":false,"volume_or_cache_crash":false,"poweron_beep":false,"poweroff_beep":false,"reset_beep":false}}"""
        const val BEEP_ON =
            """{"success":true,"data":{"fan_fail":true,"volume_or_cache_crash":true,"poweron_beep":true,"poweroff_beep":true,"reset_beep":true}}"""
        const val BEEP_POWER_ON =
            """{"success":true,"data":{"fan_fail":false,"volume_or_cache_crash":false,"poweron_beep":true,"poweroff_beep":false,"reset_beep":false}}"""
        const val HIBERNATION_OFF =
            """{"success":true,"data":{"eunit_deep_sleep":false,"enable_log":false,"sata_deep_sleep":false,"ignore_netbios_broadcast":false,"auto_poweroff_enable":false}}"""
        const val HIBERNATION_ON =
            """{"success":true,"data":{"eunit_deep_sleep":true,"enable_log":true,"sata_deep_sleep":true,"ignore_netbios_broadcast":true,"auto_poweroff_enable":true}}"""
        const val HIBERNATION_SELECTED_ON =
            """{"success":true,"data":{"eunit_deep_sleep":true,"enable_log":false,"sata_deep_sleep":false,"ignore_netbios_broadcast":true,"auto_poweroff_enable":false}}"""
        const val UPS_OFF =
            """{"success":true,"data":{"enable":false,"mode":"USB","delay_time":60,"ups_set_safemode_until_lowbatt":false,"shutdown_device":false,"net_server_ip":"","snmp_server_ip":""}}"""
        const val UPS_ON =
            """{"success":true,"data":{"enable":true,"mode":"SLAVE","delay_time":120,"ups_set_safemode_until_lowbatt":false,"shutdown_device":true,"net_server_ip":"ups.example.invalid","snmp_server_ip":""}}"""
    }
}

private sealed interface SettingsStep {
    data class Json(val body: String) : SettingsStep
    data class Failure(val error: IOException) : SettingsStep
    data class BlockingJson(
        val body: String,
        val entered: CountDownLatch,
        val release: CountDownLatch,
    ) : SettingsStep
}

private fun json(value: String): SettingsStep = SettingsStep.Json(value)
private fun failure(value: IOException): SettingsStep = SettingsStep.Failure(value)
private fun blockingJson(
    value: String,
    entered: CountDownLatch,
    release: CountDownLatch,
): SettingsStep = SettingsStep.BlockingJson(value, entered, release)

private class SettingsInterceptor(vararg steps: SettingsStep) : Interceptor {
    private val pending = ArrayDeque(steps.toList())
    val requests = mutableListOf<Request>()
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return when (val step = pending.removeFirstOrNull() ?: error("缺少合成设置响应")) {
            is SettingsStep.Json -> settingsResponse(request, step.body)
            is SettingsStep.Failure -> throw step.error
            is SettingsStep.BlockingJson -> {
                step.entered.countDown()
                check(step.release.await(5, TimeUnit.SECONDS)) { "合成设置请求等待取消超时" }
                settingsResponse(request, step.body)
            }
        }
    }
    fun methods() = requests.map { it.fields()["method"].orEmpty() }
    fun apis() = requests.map { it.fields()["api"].orEmpty() }
    fun versions() = requests.map { it.fields()["version"].orEmpty() }
}

private fun settingsResponse(request: Request, body: String): Response = Response.Builder()
    .request(request)
    .protocol(Protocol.HTTP_1_1)
    .code(200)
    .message("OK")
    .body(body.toResponseBody("application/json".toMediaType()))
    .build()

private fun Request.fields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return (0 until form.size).associate { form.name(it) to form.value(it) }
}
