package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import java.net.URI

/**
 * 外部入口只允许打开固定模块根页面，不接受 NAS、路径、会话、任务、查询或凭据。
 *
 * 公共形式固定为 `lanstash://open/<module>`；任何查询、片段、端口、用户信息、额外层级
 * 或编码后的路径变体都会被拒绝，避免把业务载荷引入导航状态。
 */
internal fun String?.externalWorkspaceModule(): Module? {
    val uri = this?.let { runCatching { URI(it) }.getOrNull() } ?: return null
    if (uri.isOpaque || !uri.scheme.equals(EXTERNAL_ROUTE_SCHEME, ignoreCase = true) ||
        !uri.host.equals(EXTERNAL_ROUTE_HOST, ignoreCase = true) ||
        uri.rawAuthority?.equals(EXTERNAL_ROUTE_HOST, ignoreCase = true) != true ||
        uri.userInfo != null || uri.port != -1 || uri.rawQuery != null || uri.rawFragment != null
    ) return null
    val slug = uri.rawPath?.removePrefix("/")
        ?.takeIf { it.isNotEmpty() && '/' !in it && '%' !in it }
        ?: return null
    return EXTERNAL_MODULES[slug]
}

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

private val EXTERNAL_MODULES: Map<String, Module> =
    Module.entries.associateBy(Module::externalWorkspaceSlug)
