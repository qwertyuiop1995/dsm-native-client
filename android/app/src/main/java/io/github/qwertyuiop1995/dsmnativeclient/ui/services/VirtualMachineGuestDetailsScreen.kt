package io.github.qwertyuiop1995.dsmnativeclient.ui.services

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.Loadable
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineGuestDetails
import io.github.qwertyuiop1995.dsmnativeclient.ui.displayName

/** 独立虚拟机详情页只展示公开只读投影，不承载任何写操作。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun VirtualMachineGuestDetailsScreen(
    guest: Loadable<VirtualMachineGuestDetails>,
    onRetry: () -> Unit,
    onNavigateUp: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val title = (guest as? Loadable.Ready)?.value?.resource?.name
        ?: stringResource(R.string.virtual_machines)
    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = title,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.semantics { heading() },
                    )
                },
                navigationIcon = {
                    IconButton(
                        onClick = onNavigateUp,
                        modifier = Modifier.size(48.dp),
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Outlined.ArrowBack,
                            contentDescription = stringResource(R.string.go_up),
                        )
                    }
                },
                actions = {
                    IconButton(
                        onClick = onRetry,
                        modifier = Modifier.size(48.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Refresh,
                            contentDescription = stringResource(R.string.refresh),
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainer,
                ),
            )
        },
    ) { contentPadding ->
        Box(
            modifier = Modifier.fillMaxSize().padding(contentPadding),
            contentAlignment = Alignment.Center,
        ) {
            when (guest) {
                Loadable.Idle, Loadable.Loading -> VirtualMachineGuestDetailsLoadingContent()
                is Loadable.Failed -> VirtualMachineGuestDetailsErrorContent(onRetry)
                is Loadable.Ready -> Box(
                    modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
                ) {
                    VirtualMachineReadOnlyDetailContent(
                        stateLabel = guest.value.resource.state.displayName(),
                        hardware = guest.value.hardware,
                        hardwareAvailable = true,
                        onRetry = onRetry,
                        actions = {},
                    )
                }
            }
        }
    }
}

@Composable
private fun VirtualMachineGuestDetailsLoadingContent() {
    val description = stringResource(R.string.loading)
    CircularProgressIndicator(
        modifier = Modifier.semantics {
            contentDescription = description
            liveRegion = LiveRegionMode.Polite
        },
    )
}

@Composable
private fun VirtualMachineGuestDetailsErrorContent(onRetry: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
            .semantics { liveRegion = LiveRegionMode.Assertive },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = Icons.Outlined.ErrorOutline,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.error,
        )
        Text(
            text = stringResource(R.string.service_section_unavailable_title),
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 16.dp).semantics { heading() },
        )
        Text(
            text = stringResource(R.string.service_section_unavailable_message),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 8.dp),
        )
        FilledTonalButton(
            onClick = onRetry,
            modifier = Modifier.padding(top = 16.dp).heightIn(min = 48.dp),
        ) {
            Text(stringResource(R.string.refresh))
        }
    }
}
