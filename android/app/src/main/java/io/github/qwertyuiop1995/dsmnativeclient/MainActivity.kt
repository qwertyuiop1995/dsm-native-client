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
            InternalNavigationState().receive(InternalRouteRequest.OpenTransfers)
        } else {
            InternalNavigationState()
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
        super.onSaveInstanceState(outState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val request = intent.internalRouteRequest()
        internalNavigation = internalNavigation.receive(request)
        if (request != null) {
            pendingNavigationIntent = intent
        }
        if (internalNavigation.pendingRequest == null || internalNavigationJob?.isActive == true) return
        val job = lifecycleScope.launch {
            model.workspace.filterNotNull().first()
            val pending = internalNavigation.pendingRequest ?: return@launch
            val result = when (pending) {
                InternalRouteRequest.OpenTransfers ->
                    model.navigateTo(WorkspaceRoute.ModuleRoot(Module.TRANSFERS))
            }
            if (result != WorkspaceNavigationResult.DEFERRED) {
                internalNavigation = internalNavigation.consume(pending)
                pendingNavigationIntent?.removeExtra(TransferNotifications.EXTRA_OPEN_TRANSFERS)
                this@MainActivity.intent.removeExtra(TransferNotifications.EXTRA_OPEN_TRANSFERS)
                pendingNavigationIntent = null
            }
        }
        internalNavigationJob = job
        job.invokeOnCompletion {
            if (internalNavigationJob === job) internalNavigationJob = null
        }
    }

    private companion object {
        const val STATE_PENDING_OPEN_TRANSFERS = "pending_open_transfers"
    }
}

internal sealed interface InternalRouteRequest {
    data object OpenTransfers : InternalRouteRequest
}

internal data class InternalNavigationState(
    val pendingRequest: InternalRouteRequest? = null,
) {
    val pendingOpenTransfers: Boolean
        get() = pendingRequest == InternalRouteRequest.OpenTransfers

    fun receive(request: InternalRouteRequest?): InternalNavigationState =
        if (request != null) copy(pendingRequest = request) else this

    fun consume(request: InternalRouteRequest): InternalNavigationState =
        if (pendingRequest == request) copy(pendingRequest = null) else this
}

internal fun Intent?.internalRouteRequest(): InternalRouteRequest? = when {
    this?.getBooleanExtra(TransferNotifications.EXTRA_OPEN_TRANSFERS, false) == true ->
        InternalRouteRequest.OpenTransfers
    else -> null
}
