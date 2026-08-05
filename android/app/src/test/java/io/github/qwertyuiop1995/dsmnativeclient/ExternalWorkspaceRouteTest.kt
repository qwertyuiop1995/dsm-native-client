package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ExternalWorkspaceRouteTest {
    @Test
    fun `每个模块都有唯一且可逆的无载荷外部入口`() {
        Module.entries.forEach { module ->
            val route = "lanstash://open/${module.externalWorkspaceSlug()}"
            assertEquals(module, route.externalWorkspaceModule())
        }
        assertEquals(Module.entries.size, Module.entries.map(Module::externalWorkspaceSlug).toSet().size)
    }

    @Test
    fun `外部入口拒绝查询片段用户信息端口和额外路径`() {
        listOf(
            "lanstash://open/files?path=/private",
            "lanstash://open/files#private",
            "lanstash://user@open/files",
            "lanstash://open:443/files",
            "lanstash://open/files/private",
            "lanstash://open/files/",
            "lanstash://open/%66iles",
        ).forEach { route -> assertNull(route.externalWorkspaceModule()) }
    }

    @Test
    fun `外部入口拒绝未知协议主机页面和畸形输入`() {
        listOf(
            null,
            "",
            "https://open/files",
            "lanstash://other/files",
            "lanstash://open/unknown",
            "lanstash:files",
            "not a uri",
        ).forEach { route -> assertNull(route.externalWorkspaceModule()) }
    }
}
