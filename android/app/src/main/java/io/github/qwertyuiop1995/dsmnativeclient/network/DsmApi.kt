package io.github.qwertyuiop1995.dsmnativeclient.network

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
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
            throw DsmFailure(
                null,
                "NAS host is missing",
                "Enter a complete NAS address.",
                kind = DsmErrorKind.INVALID_ADDRESS,
            )
        }
        val uri = runCatching {
            URI(if ("://" in raw) raw else "https://$raw")
        }.getOrElse {
            throw DsmFailure(
                null,
                "NAS address is invalid",
                "Check the address and try again.",
                kind = DsmErrorKind.INVALID_ADDRESS,
            )
        }
        val scheme = uri.scheme?.lowercase()
        if (scheme != "https" && !(BuildPolicy.allowCleartext && scheme == "http")) {
            throw DsmFailure(
                null,
                "Only HTTPS connections are supported",
                "Use the HTTPS address of the NAS.",
                kind = DsmErrorKind.INSECURE_ADDRESS,
            )
        }
        val host = uri.host?.takeIf { it.isNotBlank() }
            ?: throw DsmFailure(
                null,
                "NAS host is missing",
                "Enter a complete NAS address.",
                kind = DsmErrorKind.INVALID_ADDRESS,
            )
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
        deviceName: String = "LanStash Android",
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
            ?: throw DsmFailure(
                null,
                "The NAS did not return a session",
                "Sign in again.",
                true,
                DsmErrorKind.SESSION_EXPIRED,
            )
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
                    "Could not connect to the NAS",
                    "Check the network, address, and certificate.",
                    it.code == 401 || it.code == 403,
                    DsmErrorKind.CONNECTION_FAILED,
                )
            }
            runCatching { json.parseToJsonElement(text).jsonObject }
                .getOrElse {
                    throw DsmFailure(
                        null,
                        "The NAS returned an unrecognized response",
                        "Make sure the address points to DSM and try again.",
                        kind = DsmErrorKind.INVALID_RESPONSE,
                    )
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
        101 -> DsmFailure(code, "DSM request failed", "Refresh and try again.", kind = DsmErrorKind.REQUEST_FAILED)
        102 -> DsmFailure(code, "Feature unsupported", "Update DSM or the related package.", kind = DsmErrorKind.FEATURE_UNSUPPORTED)
        103 -> DsmFailure(code, "Package version unsupported", "Update the package and try again.", kind = DsmErrorKind.PACKAGE_VERSION_UNSUPPORTED)
        104 -> DsmFailure(code, "Session expired", "Sign in again.", true, DsmErrorKind.SESSION_EXPIRED)
        105 -> DsmFailure(code, "Permission denied", "Use an account with the required permission.", kind = DsmErrorKind.PERMISSION_DENIED)
        106, 107 -> DsmFailure(code, "Too many requests", "Try again later.", kind = DsmErrorKind.RATE_LIMITED)
        400, 401, 402, 403, 404 -> DsmFailure(code, "Sign-in information is incorrect", "Check the account, password, and verification code.", true, DsmErrorKind.AUTHENTICATION_FAILED)
        406 -> DsmFailure(code, "Two-factor code required", "Enter the current code from your authenticator.", true, DsmErrorKind.OTP_REQUIRED)
        407 -> DsmFailure(code, "Two-factor code is incorrect", "Use the latest code and try again.", true, DsmErrorKind.OTP_INVALID)
        408, 409 -> DsmFailure(code, "Device confirmation required", "Confirm the device in DSM and try again.", true, DsmErrorKind.DEVICE_CONFIRMATION_REQUIRED)
        else -> DsmFailure(code, "NAS operation failed", "Refresh and try again.", kind = DsmErrorKind.REQUEST_FAILED)
    }

    private suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation { cancel() }
        enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (continuation.isCancelled) return
                continuation.resumeWithException(
                    DsmFailure(
                        null,
                        "Could not connect to the NAS",
                        "Check the network connection and NAS address.",
                        kind = DsmErrorKind.CONNECTION_FAILED,
                    )
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
