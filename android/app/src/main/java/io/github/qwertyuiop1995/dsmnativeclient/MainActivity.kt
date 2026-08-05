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
        internalNavigation = if (
            savedInstanceState?.getBoolean(STATE_PENDING_OPEN_TRANSFERS) == true
        ) {
            InternalNavigationState().receive(InternalRouteRequest.OpenModule(Module.TRANSFERS))
        } else {
            savedInstanceState?.getString(STATE_PENDING_MODULE)
                ?.let { value -> runCatching { Module.valueOf(value) }.getOrNull() }
                ?.let { module ->
                    InternalNavigationState().receive(InternalRouteRequest.OpenModule(module))
                }
                ?: InternalNavigationState()
        }
        enableEdgeToEdge()
        setContent {
            LanStashTheme {
                LanStashApp(model)
            }
        }
        handleIntent(intent)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(
            STATE_PENDING_OPEN_TRANSFERS,
            internalNavigation.pendingOpenTransfers,
        )
        outState.putString(STATE_PENDING_MODULE, internalNavigation.pendingModule?.name)
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
                model.navigateTo(WorkspaceRoute.ModuleRoot(pending.module)) !=
                    WorkspaceNavigationResult.DEFERRED
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
        const val STATE_PENDING_OPEN_TRANSFERS = "pending_open_transfers"
        const val STATE_PENDING_MODULE = "pending_module"
    }
}

internal sealed interface InternalRouteRequest {
    val module: Module

    data class OpenModule(override val module: Module) : InternalRouteRequest
}

internal data class InternalNavigationState(
    val pendingRequest: InternalRouteRequest? = null,
) {
    val pendingOpenTransfers: Boolean
        get() = pendingModule == Module.TRANSFERS

    val pendingModule: Module?
        get() = pendingRequest?.module

    fun receive(request: InternalRouteRequest?): InternalNavigationState =
        if (request != null) copy(pendingRequest = request) else this

    fun consume(request: InternalRouteRequest): InternalNavigationState =
        if (pendingRequest == request) copy(pendingRequest = null) else this
}

internal fun Intent?.internalRouteRequest(): InternalRouteRequest? = when {
    this?.getBooleanExtra(TransferNotifications.EXTRA_OPEN_TRANSFERS, false) == true ->
        InternalRouteRequest.OpenModule(Module.TRANSFERS)
    this?.action == Intent.ACTION_VIEW ->
        dataString.externalWorkspaceModule()?.let(InternalRouteRequest::OpenModule)
    else -> null
}
