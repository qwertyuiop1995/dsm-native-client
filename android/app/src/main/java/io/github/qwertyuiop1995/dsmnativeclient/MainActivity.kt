package io.github.qwertyuiop1995.dsmnativeclient

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.WorkspaceRoute
import io.github.qwertyuiop1995.dsmnativeclient.ui.LanStashApp
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {
    private val model: AppViewModel by viewModels()
    private var internalNavigation = InternalNavigationState()
    private var pendingNavigationIntent: Intent? = null
    private var internalNavigationJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        internalNavigation = savedInstanceState?.pendingInternalRouteRequest()
            ?.let { request -> InternalNavigationState().receive(request) }
            ?: InternalNavigationState()
        enableEdgeToEdge()
        setContent {
            LanStashTheme {
                LanStashApp(model)
            }
        }
        handleIntent(intent)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString(STATE_PENDING_ROUTE, internalNavigation.pendingRequest?.name)
        super.onSaveInstanceState(outState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val request = intent.internalRouteRequest()
        if (request == null && intent?.action == Intent.ACTION_VIEW) {
            intent.data = null
        }
        if (request != null && pendingNavigationIntent !== intent) {
            clearNavigationPayload(pendingNavigationIntent)
        }
        internalNavigation = internalNavigation.receive(request)
        if (request != null) {
            pendingNavigationIntent = intent
        }
        val pending = internalNavigation.pendingRequest ?: return
        internalNavigationJob?.cancel()
        val job = lifecycleScope.launch {
            model.workspace.filterNotNull().first {
                if (internalNavigation.pendingRequest != pending) return@first true
                navigatePendingRequest(pending) != WorkspaceNavigationResult.DEFERRED
            }
            if (internalNavigation.pendingRequest == pending) {
                internalNavigation = internalNavigation.consume(pending)
                clearConsumedNavigationIntent(pendingNavigationIntent, pending)
                clearConsumedNavigationIntent(this@MainActivity.intent, pending)
                pendingNavigationIntent = null
            }
        }
        internalNavigationJob = job
        job.invokeOnCompletion {
            if (internalNavigationJob === job) internalNavigationJob = null
        }
    }

    private fun navigatePendingRequest(request: InternalRouteRequest): WorkspaceNavigationResult {
        if (request == InternalRouteRequest.OPEN_CONTAINER_REGISTRY) {
            return model.navigateToContainerRegistry()
        }
        val moduleResult = model.navigateTo(WorkspaceRoute.ModuleRoot(request.module))
        if (moduleResult == WorkspaceNavigationResult.DEFERRED ||
            moduleResult == WorkspaceNavigationResult.REJECTED
        ) {
            return moduleResult
        }
        if (request == InternalRouteRequest.OPEN_CONTAINERS) {
            model.closeContainerRegistry()
        }
        return moduleResult
    }

    private fun clearConsumedNavigationIntent(
        intent: Intent?,
        request: InternalRouteRequest,
    ) {
        if (intent.internalRouteRequest() != request) return
        clearNavigationPayload(intent)
    }

    private fun clearNavigationPayload(intent: Intent?) {
        intent?.removeExtra(TransferNotifications.EXTRA_OPEN_TRANSFERS)
        if (intent?.action == Intent.ACTION_VIEW) intent.data = null
    }

    private companion object {
        const val STATE_PENDING_ROUTE = "pending_route"
    }
}

/** 兼容第 81 批 Activity 已保存但尚未消费的固定模块状态。 */
internal fun Bundle.pendingInternalRouteRequest(): InternalRouteRequest? =
    getString("pending_route")
        ?.let { value -> runCatching { InternalRouteRequest.valueOf(value) }.getOrNull() }
        ?: if (getBoolean("pending_open_transfers")) {
            InternalRouteRequest.OPEN_TRANSFERS
        } else {
            getString("pending_module")
                ?.let { value -> runCatching { Module.valueOf(value) }.getOrNull() }
                ?.let(InternalRouteRequest::openModule)
        }

/** 只保存固定目标枚举，不能携带 URI、NAS、路径或业务对象标识。 */
internal enum class InternalRouteRequest(
    val module: Module,
) {
    OPEN_FILES(Module.FILES),
    OPEN_PHOTOS(Module.PHOTOS),
    OPEN_CHAT(Module.CHAT),
    OPEN_DOWNLOADS(Module.DOWNLOADS),
    OPEN_CONTAINERS(Module.CONTAINERS),
    OPEN_VIRTUAL_MACHINES(Module.VIRTUAL_MACHINES),
    OPEN_NAS_SETTINGS(Module.NAS_SETTINGS),
    OPEN_TRANSFERS(Module.TRANSFERS),
    OPEN_SETTINGS(Module.SETTINGS),
    OPEN_CONTAINER_REGISTRY(Module.CONTAINERS),
    ;

    companion object {
        fun openModule(module: Module): InternalRouteRequest = when (module) {
            Module.FILES -> OPEN_FILES
            Module.PHOTOS -> OPEN_PHOTOS
            Module.CHAT -> OPEN_CHAT
            Module.DOWNLOADS -> OPEN_DOWNLOADS
            Module.CONTAINERS -> OPEN_CONTAINERS
            Module.VIRTUAL_MACHINES -> OPEN_VIRTUAL_MACHINES
            Module.NAS_SETTINGS -> OPEN_NAS_SETTINGS
            Module.TRANSFERS -> OPEN_TRANSFERS
            Module.SETTINGS -> OPEN_SETTINGS
        }
    }
}

internal data class InternalNavigationState(
    val pendingRequest: InternalRouteRequest? = null,
) {
    val pendingOpenTransfers: Boolean
        get() = pendingRequest == InternalRouteRequest.OPEN_TRANSFERS

    val pendingModule: Module?
        get() = pendingRequest?.module

    fun receive(request: InternalRouteRequest?): InternalNavigationState =
        if (request != null) copy(pendingRequest = request) else this

    fun consume(request: InternalRouteRequest): InternalNavigationState =
        if (pendingRequest == request) copy(pendingRequest = null) else this
}

internal fun Intent?.internalRouteRequest(): InternalRouteRequest? = when {
    this?.action == Intent.ACTION_VIEW ->
        when (val route = dataString.externalWorkspaceRoute()) {
            is ExternalWorkspaceRoute.ModuleRoot -> InternalRouteRequest.openModule(route.module)
            ExternalWorkspaceRoute.ContainerRegistry -> InternalRouteRequest.OPEN_CONTAINER_REGISTRY
            null -> null
        }
    this?.getBooleanExtra(TransferNotifications.EXTRA_OPEN_TRANSFERS, false) == true ->
        InternalRouteRequest.OPEN_TRANSFERS
    else -> null
}
