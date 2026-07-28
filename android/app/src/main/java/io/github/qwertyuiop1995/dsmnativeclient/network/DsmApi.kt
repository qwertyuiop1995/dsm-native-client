package io.github.qwertyuiop1995.dsmnativeclient.network

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import java.io.IOException
import java.net.URI
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Call
import okhttp3.Callback
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response

/**
 * DSM WebAPI 的统一传输层。请求正文、SID、令牌和用户数据不会写入日志。
 */
class DsmApiClient(
    private val http: OkHttpClient = OkHttpClient.Builder()
        .followRedirects(false)
        .followSslRedirects(false)
        .retryOnConnectionFailure(true)
        .build(),
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    fun endpoint(profile: NasProfile): String {
        val raw = profile.address.trim()
        if (raw.endsWith("://")) {
            throw DsmFailure(null, "NAS 地址缺少主机名", "请输入完整的 NAS 地址。")
        }
        val uri = runCatching {
            URI(if ("://" in raw) raw else "https://$raw")
        }.getOrElse {
            throw DsmFailure(null, "NAS 地址格式不正确", "请检查地址后重试。")
        }
        val scheme = uri.scheme?.lowercase()
        if (scheme != "https" && !(BuildPolicy.allowCleartext && scheme == "http")) {
            throw DsmFailure(null, "正式连接仅支持 HTTPS", "请改用 NAS 的 HTTPS 地址。")
        }
        val host = uri.host?.takeIf { it.isNotBlank() }
            ?: throw DsmFailure(null, "NAS 地址缺少主机名", "请输入完整的 NAS 地址。")
        val port = profile.port ?: if (uri.port > 0) uri.port else -1
        val authority = if (port > 0) "$host:$port" else host
        val basePath = uri.path?.trimEnd('/').orEmpty()
        return "$scheme://$authority$basePath"
    }

    suspend fun discover(profile: NasProfile): Map<String, ApiCapability> {
        val result = post(
            profile = profile,
            path = "/webapi/query.cgi",
            parameters = mapOf(
                "api" to "SYNO.API.Info",
                "version" to "1",
                "method" to "query",
                "query" to "all",
            ),
        )
        val data = requireSuccess(result)
        return data.entries.mapNotNull { (name, element) ->
            val value = element as? JsonObject ?: return@mapNotNull null
            val path = value.string("path") ?: return@mapNotNull null
            val min = value.int("minVersion") ?: 1
            val max = value.int("maxVersion") ?: min
            name to ApiCapability(name, path, min, max)
        }.toMap()
    }

    suspend fun login(
        profile: NasProfile,
        password: String,
        otp: String? = null,
        deviceName: String = "岚仓 Android",
        deviceId: String? = null,
    ): DsmSession {
        val parameters = buildMap {
            put("api", "SYNO.API.Auth")
            put("version", "7")
            put("method", "login")
            put("account", profile.username)
            put("passwd", password)
            put("session", "FileStation")
            put("format", "sid")
            put("enable_syno_token", "yes")
            put("enable_device_token", "yes")
            put("device_name", deviceName)
            otp?.takeIf { it.isNotBlank() }?.let { put("otp_code", it) }
            deviceId?.takeIf { it.isNotBlank() }?.let { put("device_id", it) }
        }
        val result = post(profile, "/webapi/auth.cgi", parameters)
        val data = requireSuccess(result)
        val sid = data.string("sid")
            ?: throw DsmFailure(null, "NAS 没有返回登录会话", "请重新登录。", true)
        return DsmSession(
            profileId = profile.id,
            sid = sid,
            synoToken = data.string("synotoken"),
            deviceId = data.string("did") ?: deviceId,
        )
    }

    suspend fun logout(profile: NasProfile, session: DsmSession) {
        runCatching {
            post(
                profile,
                "/webapi/auth.cgi",
                mapOf(
                    "api" to "SYNO.API.Auth",
                    "version" to "7",
                    "method" to "logout",
                    "session" to "FileStation",
                ),
                session,
            )
        }
    }

    suspend fun call(
        profile: NasProfile,
        session: DsmSession,
        capability: ApiCapability,
        method: String,
        parameters: Map<String, String> = emptyMap(),
    ): JsonObject {
        val requestParameters = buildMap {
            put("api", capability.name)
            put("version", capability.maxVersion.toString())
            put("method", method)
            putAll(parameters)
        }
        val path = if (capability.path.startsWith("/")) capability.path else "/webapi/${capability.path}"
        return requireSuccess(post(profile, path, requestParameters, session))
    }

    suspend fun call(
        profile: NasProfile,
        session: DsmSession,
        api: String,
        version: Int,
        method: String,
        parameters: Map<String, String> = emptyMap(),
        path: String = "/webapi/entry.cgi",
    ): JsonObject {
        val requestParameters = buildMap {
            put("api", api)
            put("version", version.toString())
            put("method", method)
            putAll(parameters)
        }
        return requireSuccess(post(profile, path, requestParameters, session))
    }

    private suspend fun post(
        profile: NasProfile,
        path: String,
        parameters: Map<String, String>,
        session: DsmSession? = null,
    ): JsonObject = withContext(Dispatchers.IO) {
        val body = FormBody.Builder().apply {
            parameters.forEach { (key, value) -> add(key, value) }
            session?.sid?.let { add("_sid", it) }
        }.build()
        val request = Request.Builder()
            .url("${endpoint(profile)}$path")
            .post(body)
            .header("Accept", "application/json")
            .header("User-Agent", "LanStash-Android/0.1")
            .apply {
                session?.sid?.let { header("Cookie", "id=$it") }
                session?.synoToken?.takeIf { it.isNotBlank() }?.let {
                    header("X-SYNO-TOKEN", it)
                }
            }
            .build()
        val response = http.newCall(request).await()
        response.use {
            val text = it.body?.string().orEmpty()
            if (!it.isSuccessful) {
                throw DsmFailure(
                    it.code,
                    "无法连接到 NAS",
                    "请检查网络、地址和证书后重试。",
                    it.code == 401 || it.code == 403,
                )
            }
            runCatching { json.parseToJsonElement(text).jsonObject }
                .getOrElse {
                    throw DsmFailure(null, "NAS 返回了无法识别的内容", "请确认地址指向 DSM 后重试。")
                }
        }
    }

    private fun requireSuccess(envelope: JsonObject): JsonObject {
        if (envelope["success"]?.jsonPrimitive?.booleanOrNull == true) {
            return envelope["data"] as? JsonObject ?: JsonObject(emptyMap())
        }
        val code = (envelope["error"] as? JsonObject)?.int("code")
        throw mapFailure(code)
    }

    private fun mapFailure(code: Int?): DsmFailure = when (code) {
        101 -> DsmFailure(code, "DSM 没有完成这次请求", "请刷新后重试。")
        102 -> DsmFailure(code, "当前 NAS 不支持这项功能", "请更新 DSM 或相关套件。")
        103 -> DsmFailure(code, "当前套件版本不支持这项操作", "请更新套件后重试。")
        104 -> DsmFailure(code, "登录会话已失效", "请重新登录。", true)
        105 -> DsmFailure(code, "当前账号没有权限", "请使用具备相应权限的账号。")
        106, 107 -> DsmFailure(code, "请求过于频繁", "请稍后再试。")
        400, 401, 402, 403, 404 -> DsmFailure(code, "账号或登录信息不正确", "请核对账号、密码和验证码。", true)
        406 -> DsmFailure(code, "需要输入双重验证代码", "请输入验证器中的当前代码。", true)
        407 -> DsmFailure(code, "双重验证代码不正确", "请使用最新代码重试。", true)
        408, 409 -> DsmFailure(code, "需要确认登录设备", "请在 DSM 中完成设备确认后重试。", true)
        else -> DsmFailure(code, "NAS 没有完成这次操作", "请刷新后重试。")
    }

    private suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation { cancel() }
        enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (continuation.isCancelled) return
                continuation.resumeWithException(
                    DsmFailure(null, "无法连接到 NAS", "请检查网络连接和 NAS 地址后重试。")
                )
            }

            override fun onResponse(call: Call, response: Response) {
                continuation.resume(response)
            }
        })
    }

    private object BuildPolicy {
        // Debug 也保持 HTTPS，避免测试配置意外进入正式行为。
        const val allowCleartext = false
    }
}

internal fun JsonObject.string(key: String): String? =
    this[key]?.jsonPrimitive?.contentOrNull

internal fun JsonObject.int(key: String): Int? =
    this[key]?.jsonPrimitive?.intOrNull

internal fun JsonObject.long(key: String): Long? =
    this[key]?.jsonPrimitive?.contentOrNull?.toLongOrNull()

internal fun JsonObject.objectValue(key: String): JsonObject? =
    this[key] as? JsonObject

internal fun JsonObject.arrayValue(key: String): List<JsonElement> =
    (this[key] as? kotlinx.serialization.json.JsonArray)?.toList().orEmpty()
