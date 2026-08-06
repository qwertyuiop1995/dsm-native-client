package io.github.qwertyuiop1995.dsmnativeclient.storage

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.OpaqueWorkspaceRouteRecord
import io.github.qwertyuiop1995.dsmnativeclient.domain.OpaqueWorkspaceTarget
import io.github.qwertyuiop1995.dsmnativeclient.domain.OPAQUE_WORKSPACE_ROUTE_SCHEMA_VERSION
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.nio.charset.StandardCharsets
import java.security.SecureRandom
import java.util.Base64

/**
 * 保存 NAS 配置，以及受 Android Keystore 保护的会话和用户主动选择保存的密码。
 */
class SecureProfileStore(
    context: Context,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val preferences = EncryptedSharedPreferences.create(
        context,
        "lanstash_secure_profiles",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun profiles(): List<NasProfile> {
        val value = preferences.getString(KEY_PROFILES, null) ?: return emptyList()
        return runCatching {
            json.decodeFromString(ListSerializer(NasProfile.serializer()), value)
        }.getOrDefault(emptyList())
    }

    fun saveProfile(profile: NasProfile) {
        val profiles = profiles().filterNot { it.id == profile.id } + profile
        preferences.edit()
            .putString(KEY_PROFILES, json.encodeToString(ListSerializer(NasProfile.serializer()), profiles))
            .apply()
    }

    @Synchronized
    fun removeProfile(profileId: String) {
        val profiles = profiles().filterNot { it.id == profileId }
        val editor = preferences.edit()
            .putString(KEY_PROFILES, json.encodeToString(ListSerializer(NasProfile.serializer()), profiles))
            .remove(sessionKey(profileId))
            .remove(passwordKey(profileId))
            .remove(autoLoginKey(profileId))
            .remove(recentDirectoriesKey(profileId))
            .remove(workspaceUiStateKey(profileId))
        opaqueWorkspaceRouteKeys(profileId).forEach(editor::remove)
        editor.apply()
        if (lastProfileId() == profileId) {
            preferences.edit().remove(KEY_LAST_PROFILE_ID).apply()
        }
    }

    fun session(profileId: String): DsmSession? =
        preferences.getString(sessionKey(profileId), null)?.let {
            runCatching { json.decodeFromString<DsmSession>(it) }.getOrNull()
        }

    fun saveSession(session: DsmSession) {
        preferences.edit()
            .putString(sessionKey(session.profileId), json.encodeToString(session))
            .apply()
    }

    fun clearSession(profileId: String) {
        preferences.edit().remove(sessionKey(profileId)).apply()
    }

    fun password(profileId: String): String? =
        preferences.getString(passwordKey(profileId), null)

    fun savePassword(profileId: String, password: String) {
        preferences.edit().putString(passwordKey(profileId), password).apply()
    }

    fun clearPassword(profileId: String) {
        preferences.edit()
            .remove(passwordKey(profileId))
            .putBoolean(autoLoginKey(profileId), false)
            .apply()
    }

    fun isAutoLoginEnabled(profileId: String): Boolean =
        preferences.getBoolean(autoLoginKey(profileId), false)

    fun setAutoLoginEnabled(profileId: String, enabled: Boolean) {
        preferences.edit().putBoolean(autoLoginKey(profileId), enabled).apply()
    }

    fun lastProfileId(): String? = preferences.getString(KEY_LAST_PROFILE_ID, null)

    fun setLastProfileId(profileId: String?) {
        preferences.edit().apply {
            if (profileId == null) remove(KEY_LAST_PROFILE_ID)
            else putString(KEY_LAST_PROFILE_ID, profileId)
        }.apply()
    }

    fun recentDirectories(profileId: String): List<String> =
        preferences.getString(recentDirectoriesKey(profileId), null)?.let { value ->
            runCatching {
                json.decodeFromString(ListSerializer(String.serializer()), value)
            }.getOrDefault(emptyList())
        }.orEmpty()

    fun recordRecentDirectory(profileId: String, path: String) {
        if (!path.startsWith('/') || path.split('/').contains("#recycle")) return
        val recent = updateRecentDirectories(recentDirectories(profileId), path)
        preferences.edit().putString(
            recentDirectoriesKey(profileId),
            json.encodeToString(ListSerializer(String.serializer()), recent),
        ).apply()
    }

    fun workspaceUiState(profileId: String): PersistedWorkspaceUiState? =
        preferences.getString(workspaceUiStateKey(profileId), null)?.let { value ->
            runCatching { json.decodeFromString<PersistedWorkspaceUiState>(value) }.getOrNull()
        }

    fun saveWorkspaceUiState(profileId: String, state: PersistedWorkspaceUiState) {
        preferences.edit()
            .putString(workspaceUiStateKey(profileId), json.encodeToString(state))
            .apply()
    }

    /**
     * 同步写入本机加密的业务目标映射；成功后才返回可放进外部 URI 的不透明令牌。
     *
     * 同一资料、同一目标会复用既有令牌。令牌不包含 NAS、会话、路径或对象 ID，且不会过期，
     * 直到资料被删除、存储被清空或调用方显式删除该令牌。
     */
    @Synchronized
    fun issueOpaqueWorkspaceTarget(
        profileId: String,
        target: OpaqueWorkspaceTarget,
        createdAtEpochMillis: Long = System.currentTimeMillis(),
    ): String? {
        if (profiles().none { it.id == profileId }) return null
        val current = opaqueWorkspaceRoutes(profileId)
        val existing = current.firstOrNull { it.target == target }
        if (existing != null) return existing.token

        var token: String
        do {
            token = createOpaqueWorkspaceToken(secureRandom)
        } while (opaqueWorkspaceRoute(token) != null)

        val candidate = OpaqueWorkspaceRouteRecord(
            token = token,
            profileId = profileId,
            target = target,
            createdAtEpochMillis = createdAtEpochMillis,
        )
        val mutation = planOpaqueWorkspaceRouteIssue(current, candidate)
        val editor = preferences.edit()
        mutation.removedTokens.forEach { removedToken ->
            editor.remove(opaqueWorkspaceRouteKey(profileId, removedToken))
        }
        editor.putString(
            opaqueWorkspaceRouteKey(profileId, token),
            json.encodeToString(candidate),
        )
        return token.takeIf { editor.commit() }
    }

    /**
     * 读取令牌对应的加密记录。资料已删除、记录损坏或 schema 不受支持时一律返回 null。
     */
    @Synchronized
    fun opaqueWorkspaceRoute(token: String): OpaqueWorkspaceRouteRecord? {
        if (!token.isOpaqueWorkspaceToken()) return null
        return profiles().asSequence()
            .mapNotNull { profile ->
                decodeOpaqueWorkspaceRoute(
                    profileId = profile.id,
                    value = preferences.getString(opaqueWorkspaceRouteKey(profile.id, token), null),
                )
            }
            .firstOrNull()
    }

    /** 删除令牌映射并同步确认写入结果；不存在的令牌不会写入。 */
    @Synchronized
    fun removeOpaqueWorkspaceRoute(token: String): Boolean {
        if (!token.isOpaqueWorkspaceToken()) return false
        val editor = preferences.edit()
        var removed = false
        profiles().forEach { profile ->
            val key = opaqueWorkspaceRouteKey(profile.id, token)
            if (preferences.contains(key)) {
                editor.remove(key)
                removed = true
            }
        }
        return removed && editor.commit()
    }

    @Synchronized
    fun clearAll() {
        preferences.edit().clear().apply()
    }

    private fun sessionKey(profileId: String) = "session_$profileId"
    private fun passwordKey(profileId: String) = "password_$profileId"
    private fun autoLoginKey(profileId: String) = "auto_login_$profileId"
    private fun recentDirectoriesKey(profileId: String) = "recent_directories_$profileId"
    private fun workspaceUiStateKey(profileId: String) = "workspace_ui_state_$profileId"

    private fun opaqueWorkspaceRoutes(profileId: String): List<OpaqueWorkspaceRouteRecord> {
        val prefix = opaqueWorkspaceRouteKeyPrefix(profileId)
        return runCatching { preferences.all }
            .getOrDefault(emptyMap())
            .asSequence()
            .filter { (key, _) -> key.startsWith(prefix) }
            .mapNotNull { (_, value) ->
                decodeOpaqueWorkspaceRouteRecord(json, profileId, value as? String)
            }
            .sortedBy(OpaqueWorkspaceRouteRecord::createdAtEpochMillis)
            .toList()
    }

    private fun opaqueWorkspaceRouteKeys(profileId: String): List<String> {
        val prefix = opaqueWorkspaceRouteKeyPrefix(profileId)
        return runCatching { preferences.all.keys }
            .getOrDefault(emptySet())
            .filter { it.startsWith(prefix) }
    }

    private fun decodeOpaqueWorkspaceRoute(
        profileId: String,
        value: String?,
    ): OpaqueWorkspaceRouteRecord? = decodeOpaqueWorkspaceRouteRecord(json, profileId, value)

    private fun opaqueWorkspaceRouteKey(profileId: String, token: String): String =
        "${opaqueWorkspaceRouteKeyPrefix(profileId)}$token"

    private fun opaqueWorkspaceRouteKeyPrefix(profileId: String): String =
        "opaque_workspace_route_${encodeProfileId(profileId)}_"

    private fun encodeProfileId(profileId: String): String = Base64.getUrlEncoder()
        .withoutPadding()
        .encodeToString(profileId.toByteArray(StandardCharsets.UTF_8))

    private companion object {
        const val KEY_PROFILES = "profiles"
        const val KEY_LAST_PROFILE_ID = "last_profile_id"
        const val MAX_RECENT_DIRECTORIES = 20
    }

    private val secureRandom = SecureRandom()
}

@kotlinx.serialization.Serializable
data class PersistedWorkspaceUiState(
    val selectedModule: String = "FILES",
    val filePath: String = "",
    val filePathHistory: List<String> = emptyList(),
    val fileSearchQuery: String = "",
    val fileActiveSearchQuery: String? = null,
    val fileSortOption: String = "NAME",
    val fileSortAscending: Boolean = true,
    val fileTypeFilter: String = "ALL",
    val fileViewMode: String = "LIST",
    val chatPinnedConversationIds: List<String> = emptyList(),
)

internal fun updateRecentDirectories(current: List<String>, path: String): List<String> {
    if (!path.startsWith('/') || path.split('/').contains("#recycle")) return current
    return (listOf(path) + current.filterNot { it == path }).take(20)
}

internal const val MAX_OPAQUE_WORKSPACE_ROUTES_PER_PROFILE = 256
internal const val OPAQUE_WORKSPACE_TOKEN_BYTE_COUNT = 32
internal const val OPAQUE_WORKSPACE_TOKEN_LENGTH = 43

internal data class OpaqueWorkspaceRouteIssue(
    val token: String,
    val removedTokens: Set<String>,
)

/** 规划单资料内的去重和有界淘汰；实际加密写入由 [SecureProfileStore] 负责。 */
internal fun planOpaqueWorkspaceRouteIssue(
    current: List<OpaqueWorkspaceRouteRecord>,
    candidate: OpaqueWorkspaceRouteRecord,
): OpaqueWorkspaceRouteIssue {
    require(current.all { it.profileId == candidate.profileId }) {
        "Opaque workspace routes must belong to one profile"
    }
    current.firstOrNull { it.target == candidate.target }?.let { existing ->
        return OpaqueWorkspaceRouteIssue(existing.token, emptySet())
    }
    val overflow = (current.size + 1 - MAX_OPAQUE_WORKSPACE_ROUTES_PER_PROFILE)
        .coerceAtLeast(0)
    val removed = current
        .mapIndexed { index, route -> IndexedValue(index, route) }
        .sortedWith(
            compareBy<IndexedValue<OpaqueWorkspaceRouteRecord>> { it.value.createdAtEpochMillis }
                .thenBy(IndexedValue<OpaqueWorkspaceRouteRecord>::index),
        )
        .take(overflow)
        .map { it.value.token }
        .toSet()
    return OpaqueWorkspaceRouteIssue(candidate.token, removed)
}

internal fun createOpaqueWorkspaceToken(random: SecureRandom = SecureRandom()): String {
    val bytes = ByteArray(OPAQUE_WORKSPACE_TOKEN_BYTE_COUNT)
    random.nextBytes(bytes)
    return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
}

internal fun String.isOpaqueWorkspaceToken(): Boolean =
    length == OPAQUE_WORKSPACE_TOKEN_LENGTH &&
        all { character -> character.isAsciiLetterOrDigit() || character == '-' || character == '_' } &&
        runCatching {
            val bytes = Base64.getUrlDecoder().decode(this)
            bytes.size == OPAQUE_WORKSPACE_TOKEN_BYTE_COUNT &&
                Base64.getUrlEncoder().withoutPadding().encodeToString(bytes) == this
        }.getOrDefault(false)

internal fun decodeOpaqueWorkspaceRouteRecord(
    json: Json,
    profileId: String,
    value: String?,
): OpaqueWorkspaceRouteRecord? = value?.let {
    runCatching { json.decodeFromString<OpaqueWorkspaceRouteRecord>(it) }.getOrNull()
}?.takeIf { record ->
    record.schemaVersion == OPAQUE_WORKSPACE_ROUTE_SCHEMA_VERSION &&
        record.profileId == profileId &&
        record.token.isOpaqueWorkspaceToken()
}

private fun Char.isAsciiLetterOrDigit(): Boolean =
    this in 'a'..'z' || this in 'A'..'Z' || this in '0'..'9'
