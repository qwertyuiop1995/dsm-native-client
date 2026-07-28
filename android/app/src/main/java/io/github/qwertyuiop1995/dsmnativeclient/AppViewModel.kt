package io.github.qwertyuiop1995.dsmnativeclient

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import io.github.qwertyuiop1995.dsmnativeclient.data.DsmRepository
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation
import io.github.qwertyuiop1995.dsmnativeclient.domain.ContainerOverview
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
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
    val connectionStatus: String? = null,
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
                        "请填写 NAS 地址、账号和密码",
                        "补充登录信息后重新连接。",
                    )
                )
            }
            return
        }
        viewModelScope.launch {
            _login.update {
                it.copy(
                    isConnecting = true,
                    connectionStatus = "正在准备连接…",
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
                            "没有可恢复的登录",
                            "请输入密码后重新连接。",
                            true,
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
                    connectionStatus = "正在恢复登录…",
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
                                "保存的登录已失效",
                                "密码已为你填好，请重新连接。",
                                true,
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
                    message = state.availability.first { item -> item.module == module }.reason
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

    fun createFolder(name: String) = action("文件夹已创建") { repo ->
        repo.createFolder(_workspace.value?.path.orEmpty(), name)
        loadFiles(repo, _workspace.value?.path.orEmpty())
    }

    fun renameFile(item: FileItem, newName: String) = action("名称已修改") { repo ->
        repo.rename(item.path, newName)
        loadFiles(repo, _workspace.value?.path.orEmpty())
    }

    fun deleteFiles(items: List<FileItem>) = action("已提交删除") { repo ->
        repo.delete(items.map(FileItem::path))
        loadFiles(repo, _workspace.value?.path.orEmpty())
    }

    fun createDownload(uri: String, destination: String?) = action("下载任务已创建") { repo ->
        repo.createDownload(uri, destination)
        _workspace.update { it?.copy(downloads = Loadable.Ready(repo.listDownloads())) }
    }

    fun controlDownloads(ids: List<String>, action: String, deleteFiles: Boolean = false) =
        action("下载任务已更新") { repo ->
            repo.controlDownloads(ids, action, deleteFiles)
            _workspace.update { it?.copy(downloads = Loadable.Ready(repo.listDownloads())) }
        }

    fun controlContainer(id: String, command: String) = action("容器状态已更新") { repo ->
        repo.controlContainer(id, command)
        _workspace.update { it?.copy(containers = Loadable.Ready(repo.containerOverview())) }
    }

    fun deleteContainer(id: String) = action("容器已删除") { repo ->
        repo.deleteContainer(id)
        _workspace.update { it?.copy(containers = Loadable.Ready(repo.containerOverview())) }
    }

    fun deleteContainerImage(id: String) = action("映像已删除") { repo ->
        repo.deleteContainerImage(id)
        _workspace.update { it?.copy(containers = Loadable.Ready(repo.containerOverview())) }
    }

    fun createContainerNetwork(name: String, driver: String) = action("网络已创建") { repo ->
        repo.createContainerNetwork(name, driver)
        _workspace.update { it?.copy(containers = Loadable.Ready(repo.containerOverview())) }
    }

    fun deleteContainerNetwork(id: String) = action("网络已删除") { repo ->
        repo.deleteContainerNetwork(id)
        _workspace.update { it?.copy(containers = Loadable.Ready(repo.containerOverview())) }
    }

    fun controlVirtualMachine(id: String, command: String) = action("虚拟机状态已更新") { repo ->
        repo.controlVirtualMachine(id, command)
        _workspace.update { it?.copy(virtualMachines = Loadable.Ready(repo.virtualMachineOverview())) }
    }

    fun deleteVirtualMachine(id: String) = action("虚拟机已删除") { repo ->
        repo.deleteVirtualMachine(id)
        _workspace.update { it?.copy(virtualMachines = Loadable.Ready(repo.virtualMachineOverview())) }
    }

    fun deleteVirtualMachineImage(id: String) = action("映像已删除") { repo ->
        repo.deleteVirtualMachineImage(id)
        _workspace.update { it?.copy(virtualMachines = Loadable.Ready(repo.virtualMachineOverview())) }
    }

    fun renameVirtualMachineNetwork(id: String, name: String) = action("网络已修改") { repo ->
        repo.renameVirtualMachineNetwork(id, name)
        _workspace.update { it?.copy(virtualMachines = Loadable.Ready(repo.virtualMachineOverview())) }
    }

    fun deleteVirtualMachineNetwork(id: String) = action("网络已删除") { repo ->
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

    private fun action(success: String, block: suspend (DsmRepository) -> Unit) {
        val repo = repository ?: return
        if (_workspace.value?.isPerformingAction == true) return
        viewModelScope.launch {
            _workspace.update { it?.copy(isPerformingAction = true, message = null) }
            runCatching { block(repo) }
                .onSuccess {
                    _workspace.update { it?.copy(isPerformingAction = false, message = success) }
                }
                .onFailure { error ->
                    _workspace.update {
                        it?.copy(
                            isPerformingAction = false,
                            message = "${error.asDsmFailure().message} ${error.asDsmFailure().recovery}",
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
        ?: DsmFailure(null, "没有完成这次操作", "请稍后重试。")
