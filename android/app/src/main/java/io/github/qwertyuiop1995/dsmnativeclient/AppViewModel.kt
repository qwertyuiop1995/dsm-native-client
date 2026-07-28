package io.github.qwertyuiop1995.dsmnativeclient

import android.app.Application
import androidx.annotation.StringRes
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import io.github.qwertyuiop1995.dsmnativeclient.data.DsmRepository
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation
import io.github.qwertyuiop1995.dsmnativeclient.domain.ContainerOverview
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePage
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.ModuleAvailability
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineOverview
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmConnectionResolver
import io.github.qwertyuiop1995.dsmnativeclient.network.ConnectionStatus
import io.github.qwertyuiop1995.dsmnativeclient.localization.localize
import io.github.qwertyuiop1995.dsmnativeclient.storage.SecureProfileStore
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class LoginState(
    val profiles: List<NasProfile> = emptyList(),
    val selectedProfileId: String? = null,
    val savedPassword: String = "",
    val rememberPassword: Boolean = false,
    val autoLoginEnabled: Boolean = false,
    val isConnecting: Boolean = false,
    val connectionStatus: ConnectionStatus? = null,
    val error: DsmFailure? = null,
    val needsOtp: Boolean = false,
)

sealed interface Loadable<out T> {
    data object Idle : Loadable<Nothing>
    data object Loading : Loadable<Nothing>
    data class Ready<T>(val value: T) : Loadable<T>
    data class Failed(val error: DsmFailure) : Loadable<Nothing>
}

data class WorkspaceState(
    val profile: NasProfile,
    val selectedModule: Module = Module.FILES,
    val availability: List<ModuleAvailability> = emptyList(),
    val files: Loadable<FilePage> = Loadable.Idle,
    val path: String = "",
    val pathHistory: List<String> = emptyList(),
    val downloads: Loadable<List<DownloadTask>> = Loadable.Idle,
    val containers: Loadable<ContainerOverview> = Loadable.Idle,
    val virtualMachines: Loadable<VirtualMachineOverview> = Loadable.Idle,
    val conversations: Loadable<List<ChatConversation>> = Loadable.Idle,
    val nasSettings: Loadable<NasSettingsSnapshot> = Loadable.Idle,
    val transfers: List<TransferTask> = emptyList(),
    val isPerformingAction: Boolean = false,
    val message: String? = null,
)

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val api = DsmApiClient()
    private val connectionResolver = DsmConnectionResolver(api)
    private val store = SecureProfileStore(application)
    private var repository: DsmRepository? = null

    private val initialProfiles = store.profiles()
    private val initialProfile = initialProfiles.firstOrNull { it.id == store.lastProfileId() }
        ?: initialProfiles.firstOrNull()
    private val initialPassword = initialProfile?.let { store.password(it.id) }.orEmpty()
    private val _login = MutableStateFlow(
        LoginState(
            profiles = initialProfiles,
            selectedProfileId = initialProfile?.id,
            savedPassword = initialPassword,
            rememberPassword = initialPassword.isNotEmpty(),
            autoLoginEnabled = initialPassword.isNotEmpty() &&
                initialProfile?.let { store.isAutoLoginEnabled(it.id) } == true,
        )
    )
    val login: StateFlow<LoginState> = _login.asStateFlow()

    private val _workspace = MutableStateFlow<WorkspaceState?>(null)
    val workspace: StateFlow<WorkspaceState?> = _workspace.asStateFlow()

    init {
        if (initialProfile != null &&
            store.isAutoLoginEnabled(initialProfile.id) &&
            initialPassword.isNotEmpty()
        ) {
            restore(initialProfile, initialPassword)
        }
    }

    fun selectProfile(profile: NasProfile) {
        store.setLastProfileId(profile.id)
        val storedPassword = store.password(profile.id).orEmpty()
        _login.update {
            it.copy(
                selectedProfileId = profile.id,
                savedPassword = storedPassword,
                rememberPassword = storedPassword.isNotEmpty(),
                autoLoginEnabled = storedPassword.isNotEmpty() &&
                    store.isAutoLoginEnabled(profile.id),
                error = null,
                needsOtp = false,
            )
        }
    }

    fun newProfile() {
        store.setLastProfileId(null)
        _login.update {
            it.copy(
                selectedProfileId = null,
                savedPassword = "",
                rememberPassword = false,
                autoLoginEnabled = false,
                error = null,
                needsOtp = false,
            )
        }
    }

    fun connect(
        profileId: String?,
        name: String,
        address: String,
        portText: String,
        username: String,
        password: String,
        otp: String,
        rememberPassword: Boolean,
        autoLoginEnabled: Boolean,
    ) {
        if (_login.value.isConnecting) return
        val existing = profileId?.let { id -> _login.value.profiles.firstOrNull { it.id == id } }
        val profile = NasProfile(
            id = existing?.id ?: UUID.randomUUID().toString(),
            name = name.trim().ifBlank { "NAS" },
            address = address.trim(),
            username = username.trim(),
            port = portText.toIntOrNull(),
            rememberSession = rememberPassword,
        )
        if (profile.address.isBlank() || profile.username.isBlank() || password.isBlank()) {
            _login.update {
                it.copy(
                    error = DsmFailure(
                        null,
                        "NAS address, account, and password are required",
                        "Complete the sign-in information and connect again.",
                        kind = DsmErrorKind.MISSING_LOGIN_FIELDS,
                    )
                )
            }
            return
        }
        viewModelScope.launch {
            _login.update {
                it.copy(
                    isConnecting = true,
                    connectionStatus = ConnectionStatus.PREPARING,
                    error = null,
                )
            }
            runCatching {
                val discovered = connectionResolver.discover(profile) { status ->
                    _login.update { it.copy(connectionStatus = status) }
                }
                val previousSession = store.session(profile.id)
                val session = api.login(
                    profile = discovered.profile,
                    password = password,
                    otp = otp.ifBlank { null },
                    deviceId = previousSession?.deviceId,
                )
                store.saveProfile(profile)
                store.setLastProfileId(profile.id)
                if (rememberPassword) {
                    store.savePassword(profile.id, password)
                    store.saveSession(session)
                    store.setAutoLoginEnabled(profile.id, autoLoginEnabled)
                } else {
                    store.clearPassword(profile.id)
                    store.clearSession(profile.id)
                }
                DsmRepository(discovered.profile, session, api, discovered.capabilities)
            }.onSuccess { repo ->
                repository = repo
                _login.value = LoginState(
                    profiles = store.profiles(),
                    selectedProfileId = profile.id,
                    savedPassword = if (rememberPassword) password else "",
                    rememberPassword = rememberPassword,
                    autoLoginEnabled = rememberPassword && autoLoginEnabled,
                )
                _workspace.value = WorkspaceState(
                    profile = profile,
                    availability = repo.availability(),
                )
                load(Module.FILES)
            }.onFailure { error ->
                val failure = error.asDsmFailure()
                _login.update {
                    it.copy(
                        isConnecting = false,
                        connectionStatus = null,
                        error = failure,
                        needsOtp = failure.code in setOf(406, 407),
                    )
                }
            }
        }
    }

    fun restore(profile: NasProfile, fallbackPassword: String? = null) {
        store.setLastProfileId(profile.id)
        val session = store.session(profile.id)
        if (session == null) {
            if (!fallbackPassword.isNullOrEmpty()) {
                connect(
                    profile.id,
                    profile.name,
                    profile.address,
                    profile.port?.toString().orEmpty(),
                    profile.username,
                    fallbackPassword,
                    "",
                    rememberPassword = true,
                    autoLoginEnabled = store.isAutoLoginEnabled(profile.id),
                )
            } else {
                selectProfile(profile)
                _login.update {
                    it.copy(
                        error = DsmFailure(
                            null,
                            "No saved session is available",
                            "Enter the password and connect again.",
                            true,
                            DsmErrorKind.NO_SAVED_SESSION,
                        )
                    )
                }
            }
            return
        }
        if (_login.value.isConnecting) return
        viewModelScope.launch {
            _login.update {
                it.copy(
                    isConnecting = true,
                    connectionStatus = ConnectionStatus.RESTORING_SESSION,
                    error = null,
                )
            }
            runCatching {
                val discovered = connectionResolver.discover(profile) { status ->
                    _login.update { it.copy(connectionStatus = status) }
                }
                val repo = DsmRepository(
                    discovered.profile,
                    session,
                    api,
                    discovered.capabilities,
                )
                repo.listShares()
                repo
            }.onSuccess { repo ->
                repository = repo
                _login.update { it.copy(isConnecting = false, connectionStatus = null) }
                _workspace.value = WorkspaceState(
                    profile = profile,
                    availability = repo.availability(),
                )
                load(Module.FILES)
            }.onFailure {
                store.clearSession(profile.id)
                val savedPassword = fallbackPassword ?: store.password(profile.id)
                _login.update { it.copy(isConnecting = false, connectionStatus = null) }
                if (!savedPassword.isNullOrEmpty() && store.isAutoLoginEnabled(profile.id)) {
                    connect(
                        profile.id,
                        profile.name,
                        profile.address,
                        profile.port?.toString().orEmpty(),
                        profile.username,
                        savedPassword,
                        "",
                        rememberPassword = true,
                        autoLoginEnabled = true,
                    )
                } else {
                    selectProfile(profile)
                    _login.update {
                        it.copy(
                            error = DsmFailure(
                                null,
                                "The saved session expired",
                                "The saved password is filled in. Connect again.",
                                true,
                                DsmErrorKind.SAVED_SESSION_EXPIRED,
                            ),
                        )
                    }
                }
            }
        }
    }

    fun removeProfile(profile: NasProfile) {
        val previousSelection = _login.value.selectedProfileId
        store.removeProfile(profile.id)
        val profiles = store.profiles()
        val selected = profiles.firstOrNull { it.id == previousSelection }
            ?: profiles.firstOrNull()
        if (selected == null) {
            newProfile()
            _login.update { it.copy(profiles = profiles) }
        } else {
            _login.update { it.copy(profiles = profiles) }
            selectProfile(selected)
        }
    }

    fun select(module: Module) {
        val state = _workspace.value ?: return
        if (state.availability.firstOrNull { it.module == module }?.isAvailable == false) {
            _workspace.update {
                it?.copy(
                    message = state.availability
                        .first { item -> item.module == module }
                        .reason
                        ?.localize(getApplication<Application>())
                )
            }
            return
        }
        _workspace.update { it?.copy(selectedModule = module, message = null) }
        load(module)
    }

    fun load(module: Module? = null) {
        val targetModule = module ?: _workspace.value?.selectedModule ?: return
        val repo = repository ?: return
        viewModelScope.launch {
            when (targetModule) {
                Module.FILES, Module.PHOTOS -> loadFiles(repo, _workspace.value?.path.orEmpty())
                Module.DOWNLOADS -> {
                    _workspace.update { it?.copy(downloads = Loadable.Loading) }
                    capture(
                        block = { repo.listDownloads() },
                        update = { value -> _workspace.update { it?.copy(downloads = value) } },
                    )
                }
                Module.CONTAINERS -> {
                    _workspace.update { it?.copy(containers = Loadable.Loading) }
                    capture(
                        block = { repo.containerOverview() },
                        update = { value -> _workspace.update { it?.copy(containers = value) } },
                    )
                }
                Module.VIRTUAL_MACHINES -> {
                    _workspace.update { it?.copy(virtualMachines = Loadable.Loading) }
                    capture(
                        block = { repo.virtualMachineOverview() },
                        update = { value -> _workspace.update { it?.copy(virtualMachines = value) } },
                    )
                }
                Module.CHAT -> {
                    _workspace.update { it?.copy(conversations = Loadable.Loading) }
                    capture(
                        block = { repo.chatConversations() },
                        update = { value -> _workspace.update { it?.copy(conversations = value) } },
                    )
                }
                Module.NAS_SETTINGS -> {
                    _workspace.update { it?.copy(nasSettings = Loadable.Loading) }
                    capture(
                        block = { repo.nasSettings() },
                        update = { value -> _workspace.update { it?.copy(nasSettings = value) } },
                    )
                }
                Module.TRANSFERS, Module.SETTINGS -> Unit
            }
        }
    }

    fun openDirectory(item: FileItem) {
        if (!item.isDirectory) return
        val current = _workspace.value ?: return
        _workspace.update {
            it?.copy(
                path = item.path,
                pathHistory = current.pathHistory + current.path,
            )
        }
        repository?.let { repo ->
            viewModelScope.launch { loadFiles(repo, item.path) }
        }
    }

    fun goBackDirectory() {
        val state = _workspace.value ?: return
        val previous = state.pathHistory.lastOrNull() ?: return
        _workspace.update {
            it?.copy(path = previous, pathHistory = state.pathHistory.dropLast(1))
        }
        repository?.let { repo ->
            viewModelScope.launch { loadFiles(repo, previous) }
        }
    }

    fun searchFiles(keyword: String) {
        val repo = repository ?: return
        val path = _workspace.value?.path.orEmpty()
        if (keyword.isBlank()) {
            load(Module.FILES)
            return
        }
        viewModelScope.launch {
            _workspace.update { it?.copy(files = Loadable.Loading) }
            capture(
                block = { repo.search(path, keyword.trim()) },
                update = { value -> _workspace.update { it?.copy(files = value) } },
            )
        }
    }

    fun createFolder(name: String) = action(R.string.folder_created) { repo ->
        repo.createFolder(_workspace.value?.path.orEmpty(), name)
        loadFiles(repo, _workspace.value?.path.orEmpty())
    }

    fun renameFile(item: FileItem, newName: String) = action(R.string.name_changed) { repo ->
        repo.rename(item.path, newName)
        loadFiles(repo, _workspace.value?.path.orEmpty())
    }

    fun deleteFiles(items: List<FileItem>) = action(R.string.delete_submitted) { repo ->
        repo.delete(items.map(FileItem::path))
        loadFiles(repo, _workspace.value?.path.orEmpty())
    }

    fun createDownload(uri: String, destination: String?) = action(R.string.download_task_created) { repo ->
        repo.createDownload(uri, destination)
        _workspace.update { it?.copy(downloads = Loadable.Ready(repo.listDownloads())) }
    }

    fun controlDownloads(ids: List<String>, action: String, deleteFiles: Boolean = false) =
        action(R.string.download_task_updated) { repo ->
            repo.controlDownloads(ids, action, deleteFiles)
            _workspace.update { it?.copy(downloads = Loadable.Ready(repo.listDownloads())) }
        }

    fun controlContainer(id: String, command: String) = action(R.string.container_state_updated) { repo ->
        repo.controlContainer(id, command)
        _workspace.update { it?.copy(containers = Loadable.Ready(repo.containerOverview())) }
    }

    fun deleteContainer(id: String) = action(R.string.container_deleted) { repo ->
        repo.deleteContainer(id)
        _workspace.update { it?.copy(containers = Loadable.Ready(repo.containerOverview())) }
    }

    fun deleteContainerImage(id: String) = action(R.string.image_deleted) { repo ->
        repo.deleteContainerImage(id)
        _workspace.update { it?.copy(containers = Loadable.Ready(repo.containerOverview())) }
    }

    fun createContainerNetwork(name: String, driver: String) = action(R.string.network_created) { repo ->
        repo.createContainerNetwork(name, driver)
        _workspace.update { it?.copy(containers = Loadable.Ready(repo.containerOverview())) }
    }

    fun deleteContainerNetwork(id: String) = action(R.string.network_deleted) { repo ->
        repo.deleteContainerNetwork(id)
        _workspace.update { it?.copy(containers = Loadable.Ready(repo.containerOverview())) }
    }

    fun controlVirtualMachine(id: String, command: String) = action(R.string.virtual_machine_state_updated) { repo ->
        repo.controlVirtualMachine(id, command)
        _workspace.update { it?.copy(virtualMachines = Loadable.Ready(repo.virtualMachineOverview())) }
    }

    fun deleteVirtualMachine(id: String) = action(R.string.virtual_machine_deleted) { repo ->
        repo.deleteVirtualMachine(id)
        _workspace.update { it?.copy(virtualMachines = Loadable.Ready(repo.virtualMachineOverview())) }
    }

    fun deleteVirtualMachineImage(id: String) = action(R.string.image_deleted) { repo ->
        repo.deleteVirtualMachineImage(id)
        _workspace.update { it?.copy(virtualMachines = Loadable.Ready(repo.virtualMachineOverview())) }
    }

    fun renameVirtualMachineNetwork(id: String, name: String) = action(R.string.network_changed) { repo ->
        repo.renameVirtualMachineNetwork(id, name)
        _workspace.update { it?.copy(virtualMachines = Loadable.Ready(repo.virtualMachineOverview())) }
    }

    fun deleteVirtualMachineNetwork(id: String) = action(R.string.network_deleted) { repo ->
        repo.deleteVirtualMachineNetwork(id)
        _workspace.update { it?.copy(virtualMachines = Loadable.Ready(repo.virtualMachineOverview())) }
    }

    fun clearMessage() {
        _workspace.update { it?.copy(message = null) }
    }

    fun logout() {
        val state = _workspace.value ?: return
        val repoProfile = state.profile
        store.clearSession(repoProfile.id)
        store.setAutoLoginEnabled(repoProfile.id, false)
        val savedPassword = store.password(repoProfile.id).orEmpty()
        repository = null
        _workspace.value = null
        _login.update {
            it.copy(
                profiles = store.profiles(),
                selectedProfileId = repoProfile.id,
                savedPassword = savedPassword,
                rememberPassword = savedPassword.isNotEmpty(),
                autoLoginEnabled = false,
                connectionStatus = null,
                error = null,
                needsOtp = false,
            )
        }
    }

    private suspend fun loadFiles(repo: DsmRepository, path: String) {
        _workspace.update { it?.copy(files = Loadable.Loading) }
        capture(
            block = { if (path.isBlank()) repo.listShares() else repo.listDirectory(path) },
            update = { value -> _workspace.update { it?.copy(files = value) } },
        )
    }

    private fun action(@StringRes success: Int, block: suspend (DsmRepository) -> Unit) {
        val repo = repository ?: return
        if (_workspace.value?.isPerformingAction == true) return
        viewModelScope.launch {
            _workspace.update { it?.copy(isPerformingAction = true, message = null) }
            runCatching { block(repo) }
                .onSuccess {
                    _workspace.update {
                        it?.copy(
                            isPerformingAction = false,
                            message = getApplication<Application>().getString(success),
                        )
                    }
                }
                .onFailure { error ->
                    val localized = error.asDsmFailure()
                        .localize(getApplication<Application>())
                        .combined
                    _workspace.update {
                        it?.copy(
                            isPerformingAction = false,
                            message = localized,
                        )
                    }
                }
        }
    }

    private suspend fun <T> capture(
        block: suspend () -> T,
        update: (Loadable<T>) -> Unit,
    ) {
        runCatching { block() }
            .onSuccess { update(Loadable.Ready(it)) }
            .onFailure { update(Loadable.Failed(it.asDsmFailure())) }
    }
}

private fun Throwable.asDsmFailure(): DsmFailure =
    this as? DsmFailure
        ?: DsmFailure(
            null,
            "The operation was not completed",
            "Try again later.",
            kind = DsmErrorKind.REQUEST_FAILED,
        )
