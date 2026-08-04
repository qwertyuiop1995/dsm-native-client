package io.github.qwertyuiop1995.dsmnativeclient.data

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * 只保存恢复传输所需的非凭据状态；SID、令牌、账号和 NAS 地址不进入此存储。
 */
class TransferStore(
    context: Context,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()
    private val preferences = EncryptedSharedPreferences.create(
        context,
        PREFERENCES_NAME,
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    @Synchronized
    fun downloads(profileId: String): List<PersistedDownload> = all().filter { it.profileId == profileId }

    @Synchronized
    fun download(id: String): PersistedDownload? = all().firstOrNull { it.id == id }

    @Synchronized
    fun uploads(profileId: String): List<PersistedUpload> = allUploads().filter { it.profileId == profileId }

    @Synchronized
    fun upload(id: String): PersistedUpload? = allUploads().firstOrNull { it.id == id }

    @Synchronized
    fun photoBackupSource(profileId: String): PersistedPhotoBackupSource? =
        allBackupSources().firstOrNull { it.profileId == profileId }

    @Synchronized
    fun upsert(download: PersistedDownload) {
        val next = all().filterNot { it.id == download.id } + download
        save(next)
    }

    @Synchronized
    fun update(id: String, transform: (PersistedDownload) -> PersistedDownload): PersistedDownload? {
        var updated: PersistedDownload? = null
        val next = all().map { current ->
            if (current.id == id) transform(current).also { updated = it } else current
        }
        if (updated != null) save(next)
        return updated
    }

    @Synchronized
    fun upsert(upload: PersistedUpload) {
        saveUploads(allUploads().filterNot { it.id == upload.id } + upload)
    }

    @Synchronized
    fun updateUpload(id: String, transform: (PersistedUpload) -> PersistedUpload): PersistedUpload? {
        var updated: PersistedUpload? = null
        val next = allUploads().map { current ->
            if (current.id == id) transform(current).also { updated = it } else current
        }
        if (updated != null) saveUploads(next)
        return updated
    }

    @Synchronized
    fun upsertPhotoBackupSource(source: PersistedPhotoBackupSource) {
        saveBackupSources(allBackupSources().filterNot { it.profileId == source.profileId } + source)
    }

    @Synchronized
    fun removePhotoBackupSource(profileId: String) {
        saveBackupSources(allBackupSources().filterNot { it.profileId == profileId })
    }

    @Synchronized
    fun removeTerminal(profileId: String) {
        save(
            all().filterNot {
                it.profileId == profileId && it.state in TERMINAL_STATES
            },
        )
        saveUploads(
            allUploads().filterNot {
                it.profileId == profileId && it.state in TERMINAL_STATES
            },
        )
    }

    @Synchronized
    fun remove(id: String) {
        save(all().filterNot { it.id == id })
    }

    @Synchronized
    fun removeProfile(profileId: String) {
        save(all().filterNot { it.profileId == profileId })
        saveUploads(allUploads().filterNot { it.profileId == profileId })
        saveBackupSources(allBackupSources().filterNot { it.profileId == profileId })
    }

    private fun all(): List<PersistedDownload> {
        val value = preferences.getString(KEY_DOWNLOADS, null) ?: return emptyList()
        return runCatching {
            json.decodeFromString(ListSerializer(PersistedDownload.serializer()), value)
        }.getOrDefault(emptyList())
    }

    private fun save(downloads: List<PersistedDownload>) {
        preferences.edit()
            .putString(KEY_DOWNLOADS, json.encodeToString(ListSerializer(PersistedDownload.serializer()), downloads))
            .apply()
    }

    private fun allUploads(): List<PersistedUpload> {
        val value = preferences.getString(KEY_UPLOADS, null) ?: return emptyList()
        return runCatching {
            json.decodeFromString(ListSerializer(PersistedUpload.serializer()), value)
        }.getOrDefault(emptyList())
    }

    private fun saveUploads(uploads: List<PersistedUpload>) {
        preferences.edit()
            .putString(KEY_UPLOADS, json.encodeToString(ListSerializer(PersistedUpload.serializer()), uploads))
            .apply()
    }

    private fun allBackupSources(): List<PersistedPhotoBackupSource> {
        val value = preferences.getString(KEY_BACKUP_SOURCES, null) ?: return emptyList()
        return runCatching {
            json.decodeFromString(ListSerializer(PersistedPhotoBackupSource.serializer()), value)
        }.getOrDefault(emptyList())
    }

    private fun saveBackupSources(sources: List<PersistedPhotoBackupSource>) {
        preferences.edit()
            .putString(
                KEY_BACKUP_SOURCES,
                json.encodeToString(ListSerializer(PersistedPhotoBackupSource.serializer()), sources),
            )
            .apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "lanstash_transfer_tasks"
        const val KEY_DOWNLOADS = "downloads"
        const val KEY_UPLOADS = "uploads"
        const val KEY_BACKUP_SOURCES = "photo_backup_sources"
        val TERMINAL_STATES = setOf(
            TransferState.SUCCEEDED,
            TransferState.FAILED,
            TransferState.CANCELLED,
        )
    }
}

@Serializable
data class PersistedDownload(
    val id: String,
    val profileId: String,
    val sourcePath: String,
    val title: String,
    val destinationUri: String,
    val isDirectory: Boolean,
    val expectedBytes: Long? = null,
    val state: TransferState = TransferState.WAITING,
    val completedBytes: Long = 0,
    val totalBytes: Long? = expectedBytes,
    val errorKind: String? = null,
    val workId: String? = null,
    val backgroundCapable: Boolean = false,
    val startedAtEpochMillis: Long? = null,
)

@Serializable
data class PersistedUpload(
    val id: String,
    val profileId: String,
    val sourceUri: String,
    val title: String,
    val contentType: String? = null,
    val expectedBytes: Long,
    val destinationPath: String,
    val destinationRootPath: String = destinationPath,
    val state: TransferState = TransferState.WAITING,
    val completedBytes: Long = 0,
    val errorKind: String? = null,
    val workId: String? = null,
    val skippedExisting: Boolean = false,
    val ownsPersistedReadGrant: Boolean = true,
    val sourceTreeUri: String? = null,
    val backupMode: Boolean = true,
    val overwrite: Boolean = false,
    val requiresRefresh: Boolean = false,
    val mirrorDirectories: Boolean = false,
    val startedAtEpochMillis: Long? = null,
)

@Serializable
data class PersistedPhotoBackupSource(
    val profileId: String,
    val treeUri: String,
    val destinationPath: String,
    val workId: String? = null,
    val enabled: Boolean = true,
)

internal fun TransferState.hasIncompleteDownloadDestination(): Boolean = this !in setOf(
    TransferState.SUCCEEDED,
    TransferState.FAILED,
    TransferState.CANCELLED,
)
