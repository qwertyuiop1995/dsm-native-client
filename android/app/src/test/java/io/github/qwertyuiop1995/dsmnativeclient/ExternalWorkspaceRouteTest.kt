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
            assertEquals(
                ExternalWorkspaceRoute.ModuleRoot(module),
                route.externalWorkspaceRoute(),
            )
        }
        assertEquals(Module.entries.size, Module.entries.map(Module::externalWorkspaceSlug).toSet().size)
    }

    @Test
    fun `外部入口只允许无载荷的固定深页`() {
        listOf(
            "lanstash://open/containers/registry" to ExternalWorkspaceRoute.ContainerRegistry,
            "lanstash://open/virtual-machines/tasks" to ExternalWorkspaceRoute.VirtualMachineTasks,
            "lanstash://open/nas-settings/performance" to
                ExternalWorkspaceRoute.NasSettingsPerformance,
        ).forEach { (route, expected) ->
            assertEquals(expected, route.externalWorkspaceRoute())
            assertNull(route.externalWorkspaceModule())
        }
    }

    @Test
    fun `外部入口拒绝查询片段用户信息端口编码和未白名单层级`() {
        listOf(
            "lanstash://open/files?path=/private",
            "lanstash://open/files#private",
            "lanstash://user@open/files",
            "lanstash://open:443/files",
            "lanstash://open/files/private",
            "lanstash://open/files/",
            "lanstash://open/%66iles",
            "lanstash://open/containers/registry?image=private",
            "lanstash://open/containers/registry#private",
            "lanstash://open/containers/registry/object-id",
            "lanstash://open/containers/registry/",
            "lanstash://open/containers/%72egistry",
            "lanstash://open/virtual-machines/tasks?task=private",
            "lanstash://open/virtual-machines/tasks#private",
            "lanstash://open/virtual-machines/tasks/object-id",
            "lanstash://open/virtual-machines/tasks/",
            "lanstash://open/virtual-machines/%74asks",
            "lanstash://open/nas-settings/performance?history=private",
            "lanstash://open/nas-settings/performance#private",
            "lanstash://open/nas-settings/performance/object-id",
            "lanstash://open/nas-settings/performance/",
            "lanstash://open/nas-settings/%70erformance",
        ).forEach { route -> assertNull(route.externalWorkspaceRoute()) }
    }

    @Test
    fun `外部入口拒绝未知协议主机页面和畸形输入`() {
        listOf(
            null,
            "",
            "https://open/files",
            "LaNsTaSh://open/files",
            "lanstash://OPEN/files",
            "lanstash://other/files",
            "lanstash://open/unknown",
            "lanstash:files",
            "not a uri",
        ).forEach { route -> assertNull(route.externalWorkspaceRoute()) }
    }
}
