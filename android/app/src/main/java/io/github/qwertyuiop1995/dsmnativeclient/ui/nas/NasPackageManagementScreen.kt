package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.SettingsApplications
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.AppViewModel
import io.github.qwertyuiop1995.dsmnativeclient.PackageMutationOperation
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.WorkspaceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import io.github.qwertyuiop1995.dsmnativeclient.domain.PackageInfo
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.ui.displayName

@Composable
internal fun NasPackageManagementScreen(
    snapshot: NasSettingsSnapshot,
    state: WorkspaceState,
    model: AppViewModel,
) {
    val target = state.packageMutationTarget
    val operation = state.packageMutationOperation
    val enabled = !state.isPerformingAction && !state.packageMutationInProgress &&
        !state.packageMutationRefreshInProgress && state.packageMutationResult == null &&
        state.packageMutationFailure == null && !state.packageMutationConfirmationRequested
    PackageManagementContent(
        packages = snapshot.packages,
        packagesAvailable = snapshot.packagesAvailable,
        target = target,
        operation = operation,
        mutationInProgress = state.packageMutationInProgress,
        result = state.packageMutationResult,
        failure = state.packageMutationFailure,
        refreshFailure = state.packageMutationRefreshFailure,
        refreshInProgress = state.packageMutationRefreshInProgress,
        refreshCompleted = state.packageMutationRefreshCompleted,
        enabled = enabled,
        onRequest = model::requestPackageMutation,
        onRefresh = model::refreshPackageMutation,
        onContinue = { model.dismissPackageMutationResult() },
        onCloseResult = { model.dismissPackageMutationResult() },
    )
    if (state.packageMutationConfirmationRequested && target != null && operation != null) {
        PackageMutationConfirmationDialog(
            target = target,
            operation = operation,
            onConfirm = model::confirmPackageMutation,
            onDismiss = model::cancelPackageMutationConfirmation,
        )
    }
}

@Composable
internal fun PackageManagementContent(
    packages: List<PackageInfo>,
    packagesAvailable: Boolean,
    target: PackageInfo?,
    operation: PackageMutationOperation?,
    mutationInProgress: Boolean,
    result: MutationResult?,
    failure: DsmFailure?,
    refreshFailure: DsmFailure?,
    refreshInProgress: Boolean,
    refreshCompleted: Boolean,
    enabled: Boolean,
    onRequest: (PackageInfo, PackageMutationOperation) -> Unit,
    onRefresh: () -> Unit,
    onContinue: () -> Unit,
    onCloseResult: () -> Unit,
) {
    val targetState = if (target != null && operation != null) {
        packageTargetState(target, operation, packages, packagesAvailable, refreshCompleted)
    } else ManagementTargetState.UNAVAILABLE
    LazyColumn {
        item {
            when {
                mutationInProgress && target != null -> ManagementSavingCard(
                    R.string.package_action_in_progress,
                    target.name,
                    R.string.package_action_in_progress_message,
                )
                (result != null || failure != null) && target != null -> ManagementMutationFeedbackCard(
                    targetName = target.name,
                    result = result,
                    failure = failure,
                    refreshFailure = refreshFailure,
                    refreshInProgress = refreshInProgress,
                    refreshCompleted = refreshCompleted,
                    targetState = targetState,
                    countsLabel = R.string.package_feedback_counts,
                    refreshLabel = R.string.refresh_and_check_packages,
                    onRefresh = onRefresh,
                    onContinue = onContinue,
                    onCloseResult = onCloseResult,
                )
            }
        }
        when {
            !packagesAvailable -> item { PackageStateMessage(R.string.packages_unavailable, R.string.packages_unavailable_hint) }
            packages.isEmpty() -> item { PackageStateMessage(R.string.packages_empty, R.string.packages_empty_hint) }
            else -> items(packages, key = PackageInfo::id) { packageInfo ->
                PackageManagementRow(packageInfo, enabled, onRequest)
            }
        }
    }
}

@Composable
internal fun PackageManagementRow(
    packageInfo: PackageInfo,
    enabled: Boolean,
    onRequest: (PackageInfo, PackageMutationOperation) -> Unit,
) {
    ListItem(
        headlineContent = { Text(packageInfo.name) },
        supportingContent = {
            Column {
                Text(stringResource(R.string.package_version_and_status, packageInfo.version, packageInfo.status.displayName()))
                packageInfo.description?.takeIf(String::isNotBlank)?.let { Text(it) }
            }
        },
        leadingContent = { Icon(Icons.Outlined.SettingsApplications, null) },
        trailingContent = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (packageInfo.canStart) PackageActionButton(
                    enabled,
                    stringResource(R.string.start_package_description, packageInfo.name),
                    PackageMutationOperation.START,
                ) { onRequest(packageInfo, PackageMutationOperation.START) }
                if (packageInfo.canStop) PackageActionButton(
                    enabled,
                    stringResource(R.string.stop_package_description, packageInfo.name),
                    PackageMutationOperation.STOP,
                ) { onRequest(packageInfo, PackageMutationOperation.STOP) }
                if (packageInfo.canUninstall) PackageActionButton(
                    enabled,
                    stringResource(R.string.uninstall_package_description, packageInfo.name),
                    PackageMutationOperation.UNINSTALL,
                ) { onRequest(packageInfo, PackageMutationOperation.UNINSTALL) }
            }
        },
    )
    HorizontalDivider(Modifier.padding(start = 72.dp))
}

@Composable
private fun PackageActionButton(
    enabled: Boolean,
    description: String,
    operation: PackageMutationOperation,
    onClick: () -> Unit,
) {
    val destructive = operation != PackageMutationOperation.START
    TextButton(
        enabled = enabled,
        onClick = onClick,
        modifier = Modifier.heightIn(min = 48.dp).semantics {
            contentDescription = description
            role = Role.Button
        },
    ) {
        Icon(when (operation) {
            PackageMutationOperation.START -> Icons.Outlined.PlayArrow
            PackageMutationOperation.STOP -> Icons.Outlined.Pause
            PackageMutationOperation.UNINSTALL -> Icons.Outlined.DeleteOutline
        }, null)
        Text(
            stringResource(when (operation) {
                PackageMutationOperation.START -> R.string.start
                PackageMutationOperation.STOP -> R.string.stop
                PackageMutationOperation.UNINSTALL -> R.string.uninstall
            }),
            color = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
        )
    }
}

@Composable
internal fun PackageMutationConfirmationDialog(
    target: PackageInfo,
    operation: PackageMutationOperation,
    onConfirm: () -> Boolean,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(packageConfirmationTitle(operation), target.name)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(packageConfirmationMessage(operation)))
                Text(stringResource(R.string.package_target_summary, target.name, target.version))
                Text(
                    stringResource(packageImpactMessage(operation)),
                    color = if (operation == PackageMutationOperation.START) {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    } else MaterialTheme.colorScheme.error,
                )
            }
        },
        confirmButton = { TextButton(onClick = { onConfirm() }) { Text(stringResource(packageActionLabel(operation))) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

internal fun packageTargetState(
    target: PackageInfo,
    operation: PackageMutationOperation,
    packages: List<PackageInfo>,
    packagesAvailable: Boolean,
    refreshCompleted: Boolean,
): ManagementTargetState {
    if (!refreshCompleted || !packagesAvailable) return ManagementTargetState.UNAVAILABLE
    val current = packages.firstOrNull { it.id == target.id }
    if (operation == PackageMutationOperation.UNINSTALL) {
        return if (current == null) ManagementTargetState.MATCHES else ManagementTargetState.DIFFERS
    }
    current ?: return ManagementTargetState.MISSING
    val expected = if (operation == PackageMutationOperation.START) ResourceState.RUNNING else ResourceState.STOPPED
    return if (current.status == expected) ManagementTargetState.MATCHES else ManagementTargetState.DIFFERS
}

@StringRes
private fun packageConfirmationTitle(operation: PackageMutationOperation) = when (operation) {
    PackageMutationOperation.START -> R.string.start_package_title
    PackageMutationOperation.STOP -> R.string.stop_package_title
    PackageMutationOperation.UNINSTALL -> R.string.uninstall_package_title
}

@StringRes
private fun packageConfirmationMessage(operation: PackageMutationOperation) = when (operation) {
    PackageMutationOperation.START -> R.string.start_package_message
    PackageMutationOperation.STOP -> R.string.stop_package_message
    PackageMutationOperation.UNINSTALL -> R.string.uninstall_package_message
}

@StringRes
private fun packageImpactMessage(operation: PackageMutationOperation) = when (operation) {
    PackageMutationOperation.START -> R.string.start_package_impact
    PackageMutationOperation.STOP -> R.string.stop_package_impact
    PackageMutationOperation.UNINSTALL -> R.string.uninstall_package_impact
}

@StringRes
private fun packageActionLabel(operation: PackageMutationOperation) = when (operation) {
    PackageMutationOperation.START -> R.string.start
    PackageMutationOperation.STOP -> R.string.stop
    PackageMutationOperation.UNINSTALL -> R.string.uninstall
}

@Composable
private fun PackageStateMessage(@StringRes title: Int, @StringRes message: Int) {
    Column(Modifier.fillMaxWidth().padding(24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(title), style = MaterialTheme.typography.titleMedium)
        Text(stringResource(message), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
