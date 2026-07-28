package io.github.qwertyuiop1995.dsmnativeclient

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmConnectionResolver
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 可选的真机 QuickConnect 烟雾测试。
 *
 * ID 只能通过 instrumentation 参数传入，不写入源码、测试报告或日志。
 * 测试仅执行不含凭据的能力发现，不会发送账号、密码、验证码或会话。
 */
@RunWith(AndroidJUnit4::class)
class QuickConnectSmokeTest {
    @Test
    fun quickConnectCanDiscoverNasWithoutCredentials() = runBlocking {
        val id = InstrumentationRegistry.getArguments()
            .getString(ARGUMENT_QUICK_CONNECT_ID)
            .orEmpty()
            .trim()
        assumeTrue("未提供 QuickConnect 烟雾测试参数", id.isNotEmpty())

        val api = DsmApiClient()
        val discovered = DsmConnectionResolver(api).discover(
            NasProfile(
                id = "quickconnect-smoke-test",
                name = "测试 NAS",
                address = id,
                username = "not-used",
            )
        )

        assertTrue(discovered.capabilities.containsKey("SYNO.API.Auth"))
        assertTrue(
            discovered.profile.address.endsWith(".quickconnect.to") ||
                discovered.profile.address.endsWith(".quickconnect.cn")
        )
    }

    private companion object {
        const val ARGUMENT_QUICK_CONNECT_ID = "quickConnectId"
    }
}
