package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.Loadable
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSystemUpdateInfo
import io.github.qwertyuiop1995.dsmnativeclient.localization.localize

@Composable
internal fun NasSystemUpdateCard(
    state: Loadable<NasSystemUpdateInfo>,
    onCheck: () -> Unit,
) {
    val context = LocalContext.current
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(18.dp).then(
                when (state) {
                    is Loadable.Failed -> Modifier.semantics {
                        liveRegion = LiveRegionMode.Assertive
                    }
                    is Loadable.Ready -> Modifier.semantics {
                        liveRegion = LiveRegionMode.Polite
                    }
                    else -> Modifier
                },
            ),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    stringResource(R.string.system_update),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
                when (state) {
                    Loadable.Idle -> Text(
                        stringResource(R.string.system_update_description),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Loadable.Loading -> Text(
                        stringResource(R.string.checking_system_update),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    is Loadable.Ready -> SystemUpdateResult(state.value)
                    is Loadable.Failed -> {
                        val failure = state.error.localize(context)
                        Text(failure.message, color = MaterialTheme.colorScheme.error)
                        Text(failure.recovery, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                Text(
                    stringResource(R.string.system_update_manage_in_dsm),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    OutlinedButton(
                        onClick = onCheck,
                        enabled = state !is Loadable.Loading,
                    ) {
                        if (state is Loadable.Loading) {
                            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.system_update_checking_button))
                        } else {
                            Text(stringResource(if (state is Loadable.Failed) R.string.retry else R.string.check_for_updates))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SystemUpdateResult(info: NasSystemUpdateInfo) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (info.isUpdateAvailable) {
            Text(
                stringResource(R.string.system_update_available),
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold,
            )
            info.latestVersion?.let {
                Text(stringResource(R.string.system_update_available_version, it))
            }
            info.releaseNotes?.let {
                Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            Text(
                stringResource(R.string.system_update_none),
                fontWeight = FontWeight.SemiBold,
            )
        }
        info.currentVersion?.let {
            Text(
                stringResource(R.string.system_update_current_version, it),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
