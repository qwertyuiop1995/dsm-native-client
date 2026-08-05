package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import java.net.URI

/**
 * 外部入口只允许打开固定模块根页面或白名单中的无载荷固定页面，
 * 不接受 NAS、路径、会话、任务、查询或凭据。
 *
 * 公共形式固定为 `lanstash://open/<module>` 与
 * `lanstash://open/containers/registry`、`lanstash://open/virtual-machines/tasks` 与
 * `lanstash://open/nas-settings/performance`；任何未白名单的路径、查询、片段、端口、用户信息
 * 或编码后的路径变体都会被拒绝，避免把业务载荷引入导航状态。
 */
internal sealed interface ExternalWorkspaceRoute {
    val module: Module

    data class ModuleRoot(override val module: Module) : ExternalWorkspaceRoute

    data object ContainerRegistry : ExternalWorkspaceRoute {
        override val module: Module = Module.CONTAINERS
    }

    data object VirtualMachineTasks : ExternalWorkspaceRoute {
        override val module: Module = Module.VIRTUAL_MACHINES
    }

    data object NasSettingsPerformance : ExternalWorkspaceRoute {
        override val module: Module = Module.NAS_SETTINGS
    }
}

internal fun String?.externalWorkspaceRoute(): ExternalWorkspaceRoute? {
    val uri = this?.let { runCatching { URI(it) }.getOrNull() } ?: return null
    if (uri.isOpaque || uri.scheme != EXTERNAL_ROUTE_SCHEME ||
        uri.host != EXTERNAL_ROUTE_HOST || uri.rawAuthority != EXTERNAL_ROUTE_HOST ||
        uri.userInfo != null || uri.port != -1 || uri.rawQuery != null || uri.rawFragment != null
    ) return null
    val rawPath = uri.rawPath ?: return null
    if ('%' in rawPath) return null
    when (rawPath) {
        CONTAINER_REGISTRY_PATH -> return ExternalWorkspaceRoute.ContainerRegistry
        VIRTUAL_MACHINE_TASKS_PATH -> return ExternalWorkspaceRoute.VirtualMachineTasks
        NAS_SETTINGS_PERFORMANCE_PATH -> return ExternalWorkspaceRoute.NasSettingsPerformance
    }
    val slug = rawPath.removePrefix("/")
        .takeIf { it.isNotEmpty() && '/' !in it && '%' !in it }
        ?: return null
    return EXTERNAL_MODULES[slug]?.let(ExternalWorkspaceRoute::ModuleRoot)
}

/** 保持模块根页调用方的既有语义；固定子页面不会降级为模块根页。 */
internal fun String?.externalWorkspaceModule(): Module? =
    (externalWorkspaceRoute() as? ExternalWorkspaceRoute.ModuleRoot)?.module

internal fun Module.externalWorkspaceSlug(): String = when (this) {
    Module.FILES -> "files"
    Module.PHOTOS -> "photos"
    Module.CHAT -> "chat"
    Module.DOWNLOADS -> "downloads"
    Module.CONTAINERS -> "containers"
    Module.VIRTUAL_MACHINES -> "virtual-machines"
    Module.NAS_SETTINGS -> "nas-settings"
    Module.TRANSFERS -> "transfers"
    Module.SETTINGS -> "settings"
}

private const val EXTERNAL_ROUTE_SCHEME = "lanstash"
private const val EXTERNAL_ROUTE_HOST = "open"
private const val CONTAINER_REGISTRY_PATH = "/containers/registry"
private const val VIRTUAL_MACHINE_TASKS_PATH = "/virtual-machines/tasks"
private const val NAS_SETTINGS_PERFORMANCE_PATH = "/nas-settings/performance"

private val EXTERNAL_MODULES: Map<String, Module> =
    Module.entries.associateBy(Module::externalWorkspaceSlug)
