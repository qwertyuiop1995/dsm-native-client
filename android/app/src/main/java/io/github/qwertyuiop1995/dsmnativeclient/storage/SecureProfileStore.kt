package io.github.qwertyuiop1995.dsmnativeclient.storage

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

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

    fun removeProfile(profileId: String) {
        val profiles = profiles().filterNot { it.id == profileId }
        preferences.edit()
            .putString(KEY_PROFILES, json.encodeToString(ListSerializer(NasProfile.serializer()), profiles))
            .remove(sessionKey(profileId))
            .remove(passwordKey(profileId))
            .remove(autoLoginKey(profileId))
            .apply()
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

    fun clearAll() {
        preferences.edit().clear().apply()
    }

    private fun sessionKey(profileId: String) = "session_$profileId"
    private fun passwordKey(profileId: String) = "password_$profileId"
    private fun autoLoginKey(profileId: String) = "auto_login_$profileId"

    private companion object {
        const val KEY_PROFILES = "profiles"
        const val KEY_LAST_PROFILE_ID = "last_profile_id"
    }
}
