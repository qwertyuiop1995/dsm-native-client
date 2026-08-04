package io.github.qwertyuiop1995.dsmnativeclient.data

import java.io.InputStream
import java.util.UUID

/**
 * 由系统文件选择器提供的只读上传来源，不保存本地真实路径。
 * `requestToken` 只用于当前进程内的重复提交保护，不包含 URI、路径或文件内容。
 */
data class UploadSource(
    val displayName: String,
    val contentType: String?,
    val contentLength: Long,
    val openInputStream: () -> InputStream,
    val requestToken: String = UUID.randomUUID().toString(),
)
