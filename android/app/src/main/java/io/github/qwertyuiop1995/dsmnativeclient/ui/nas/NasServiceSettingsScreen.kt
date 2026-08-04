package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.FolderShared
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.AppViewModel
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasFileServiceSettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProxySettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasTerminalSettings
import io.github.qwertyuiop1995.dsmnativeclient.ui.ConfirmDialog
import io.github.qwertyuiop1995.dsmnativeclient.localization.localize

@Composable
internal fun NasServiceSettingsScreen(
    snapshot: NasSettingsSnapshot,
    savedDraft: NasFileServiceSettings?,
    mutationResult: MutationResult?,
    mutationFailure: DsmFailure?,
    mutationInProgress: Boolean,
    mutationRefreshCompleted: Boolean,
    savedTerminalDraft: NasTerminalSettings?,
    terminalMutationResult: MutationResult?,
    terminalMutationFailure: DsmFailure?,
    terminalMutationInProgress: Boolean,
    terminalMutationRefreshCompleted: Boolean,
    savedProxyDraft: NasProxySettings?,
    proxyMutationResult: MutationResult?,
    proxyMutationFailure: DsmFailure?,
    proxyMutationInProgress: Boolean,
    proxyMutationRefreshCompleted: Boolean,
    isPerformingAction: Boolean,
    model: AppViewModel,
) {
    var editFiles by rememberSaveable { mutableStateOf(false) }
    var confirmFiles by rememberSaveable { mutableStateOf(false) }
    var fileSaveRequested by rememberSaveable { mutableStateOf(false) }
    var editTerminal by rememberSaveable { mutableStateOf(false) }
    var confirmTerminal by rememberSaveable { mutableStateOf(false) }
    var terminalSaveRequested by rememberSaveable { mutableStateOf(false) }
    var editProxy by rememberSaveable { mutableStateOf(false) }
    var confirmProxy by rememberSaveable { mutableStateOf(false) }
    var proxySaveRequested by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(mutationInProgress, mutationResult, mutationFailure) {
        when {
            mutationInProgress -> fileSaveRequested = true
            shouldReopenFileServiceEditor(
                saveRequested = fileSaveRequested,
                mutationInProgress = mutationInProgress,
                mutationResult = mutationResult,
                mutationFailure = mutationFailure,
            ) -> {
                fileSaveRequested = false
                editFiles = true
            }
            fileSaveRequested -> fileSaveRequested = false
        }
    }
    LaunchedEffect(
        terminalMutationInProgress,
        terminalMutationResult,
        terminalMutationFailure,
    ) {
        when {
            terminalMutationInProgress -> terminalSaveRequested = true
            shouldReopenTerminalEditor(
                saveRequested = terminalSaveRequested,
                mutationInProgress = terminalMutationInProgress,
                mutationResult = terminalMutationResult,
                mutationFailure = terminalMutationFailure,
            ) -> {
                terminalSaveRequested = false
                editTerminal = true
            }
            terminalSaveRequested -> terminalSaveRequested = false
        }
    }
    LaunchedEffect(proxyMutationInProgress, proxyMutationResult, proxyMutationFailure) {
        when {
            proxyMutationInProgress -> proxySaveRequested = true
            shouldReopenProxyEditor(
                saveRequested = proxySaveRequested,
                mutationInProgress = proxyMutationInProgress,
                mutationResult = proxyMutationResult,
                mutationFailure = proxyMutationFailure,
            ) -> {
                proxySaveRequested = false
                editProxy = true
            }
            proxySaveRequested -> proxySaveRequested = false
        }
    }
    LazyColumn {
        if (fileSaveRequested || mutationInProgress) {
            item {
                FileServiceSavingCard()
            }
        } else {
            mutationResult?.let { result ->
                item {
                    val policy = fileServiceFeedbackPolicy(result)
                    FileServiceMutationFeedbackCard(
                        result = result,
                        refreshCompleted = mutationRefreshCompleted,
                        canContinueEditing = savedDraft != null &&
                            (!policy.mustRefreshBeforeEditing || mutationRefreshCompleted),
                        onRefresh = { model.load(io.github.qwertyuiop1995.dsmnativeclient.domain.Module.NAS_SETTINGS) },
                        onContinueEditing = {
                            editFiles = savedDraft != null
                            model.dismissFileServiceMutationResult()
                        },
                        onDismiss = { model.dismissFileServiceMutationResult(discardDraft = true) },
                    )
                }
            }
            mutationFailure?.let { failure ->
                item {
                    FileServiceMutationFailureCard(
                        failure = failure,
                        canContinueEditing = savedDraft != null,
                        onContinueEditing = {
                            editFiles = savedDraft != null
                            model.dismissFileServiceMutationResult()
                        },
                        onDismiss = { model.dismissFileServiceMutationResult(discardDraft = true) },
                    )
                }
            }
        }
        if (terminalSaveRequested || terminalMutationInProgress) {
            item {
                TerminalSavingCard()
            }
        } else {
            terminalMutationResult?.let { result ->
                item {
                    val policy = terminalFeedbackPolicy(result)
                    TerminalMutationFeedbackCard(
                        result = result,
                        refreshCompleted = terminalMutationRefreshCompleted,
                        canContinueEditing = savedTerminalDraft != null &&
                            (!policy.mustRefreshBeforeEditing || terminalMutationRefreshCompleted),
                        onRefresh = {
                            model.load(io.github.qwertyuiop1995.dsmnativeclient.domain.Module.NAS_SETTINGS)
                        },
                        onContinueEditing = {
                            editTerminal = savedTerminalDraft != null
                            model.dismissTerminalMutationResult()
                        },
                        onDismiss = { model.dismissTerminalMutationResult(discardDraft = true) },
                    )
                }
            }
            terminalMutationFailure?.let { failure ->
                item {
                    TerminalMutationFailureCard(
                        failure = failure,
                        canContinueEditing = savedTerminalDraft != null,
                        onContinueEditing = {
                            editTerminal = savedTerminalDraft != null
                            model.dismissTerminalMutationResult()
                        },
                        onDismiss = { model.dismissTerminalMutationResult(discardDraft = true) },
                    )
                }
            }
        }
        if (proxySaveRequested || proxyMutationInProgress) {
            item {
                ProxySavingCard()
            }
        } else {
            proxyMutationResult?.let { result ->
                item {
                    val policy = proxyFeedbackPolicy(result)
                    ProxyMutationFeedbackCard(
                        result = result,
                        refreshCompleted = proxyMutationRefreshCompleted,
                        canContinueEditing = savedProxyDraft != null &&
                            (!policy.mustRefreshBeforeEditing || proxyMutationRefreshCompleted),
                        onRefresh = {
                            model.load(io.github.qwertyuiop1995.dsmnativeclient.domain.Module.NAS_SETTINGS)
                        },
                        onContinueEditing = {
                            editProxy = savedProxyDraft != null
                            model.dismissProxyMutationResult()
                        },
                        onDismiss = { model.dismissProxyMutationResult(discardDraft = true) },
                    )
                }
            }
            proxyMutationFailure?.let { failure ->
                item {
                    ProxyMutationFailureCard(
                        failure = failure,
                        canContinueEditing = savedProxyDraft != null,
                        onContinueEditing = {
                            editProxy = savedProxyDraft != null
                            model.dismissProxyMutationResult()
                        },
                        onDismiss = { model.dismissProxyMutationResult(discardDraft = true) },
                    )
                }
            }
        }
        snapshot.fileServiceSettings?.let { settings ->
            item {
                SettingsSummaryRow(
                    title = stringResource(R.string.file_services),
                    detail = fileServiceSummary(settings),
                    icon = { Icon(Icons.Outlined.FolderShared, null) },
                    onEdit = {
                        model.updateFileServiceSettingsDraft(settings)
                        editFiles = true
                    },
                    enabled = !isPerformingAction && mutationResult == null && mutationFailure == null,
                )
            }
        }
        snapshot.terminalSettings?.let { settings ->
            item {
                SettingsSummaryRow(
                    title = stringResource(R.string.remote_terminal),
                    detail = terminalSummary(settings),
                    icon = { Icon(Icons.Outlined.Terminal, null) },
                    onEdit = {
                        model.updateTerminalSettingsDraft(settings)
                        editTerminal = true
                    },
                    enabled = !isPerformingAction && terminalMutationResult == null &&
                        terminalMutationFailure == null,
                )
            }
        } ?: run {
            if (snapshot.fileServiceSettings != null || snapshot.proxySettings != null) {
                item {
                    SettingsUnavailableRow(
                        title = stringResource(R.string.remote_terminal),
                        detail = stringResource(R.string.terminal_settings_unavailable_hint),
                        icon = { Icon(Icons.Outlined.Terminal, null) },
                    )
                }
            }
        }
        snapshot.proxySettings?.let { settings ->
            item {
                SettingsSummaryRow(
                    title = stringResource(R.string.internet_proxy),
                    detail = if (settings.isEnabled) settings.host else stringResource(R.string.service_disabled),
                    icon = { Icon(Icons.Outlined.Public, null) },
                    onEdit = {
                        model.updateProxySettingsDraft(settings)
                        editProxy = true
                    },
                    enabled = !isPerformingAction && !proxyMutationInProgress &&
                        proxyMutationResult == null && proxyMutationFailure == null,
                )
            }
        } ?: run {
            if (snapshot.fileServiceSettings != null || snapshot.terminalSettings != null) {
                item {
                    SettingsUnavailableRow(
                        title = stringResource(R.string.internet_proxy),
                        detail = stringResource(R.string.proxy_settings_unavailable_hint),
                        icon = { Icon(Icons.Outlined.Public, null) },
                    )
                }
            }
        }
        if (
            snapshot.fileServiceSettings == null && snapshot.terminalSettings == null &&
            snapshot.proxySettings == null
        ) {
            item {
                Column(Modifier.fillMaxWidth().padding(24.dp)) {
                    Text(stringResource(R.string.no_service_settings), style = MaterialTheme.typography.titleMedium)
                    Text(
                        stringResource(R.string.no_service_settings_hint),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
    if (editFiles) snapshot.fileServiceSettings?.let { baseline ->
        FileServiceDialog(
            baseline = baseline,
            restoredDraft = savedDraft,
            onDraftChange = model::updateFileServiceSettingsDraft,
            onSave = {
                model.updateFileServiceSettingsDraft(it)
                confirmFiles = true
                editFiles = false
            },
            onDismiss = {
                model.updateFileServiceSettingsDraft(null)
                editFiles = false
            },
        )
    }
    if (editTerminal) snapshot.terminalSettings?.let { baseline ->
        TerminalSettingsDialog(
            baseline = baseline,
            restoredDraft = savedTerminalDraft,
            onDraftChange = model::updateTerminalSettingsDraft,
            onSave = {
                model.updateTerminalSettingsDraft(it)
                confirmTerminal = true
                editTerminal = false
            },
            onDismiss = {
                model.updateTerminalSettingsDraft(null)
                editTerminal = false
            },
        )
    }
    if (editProxy) snapshot.proxySettings?.let { baseline ->
        ProxySettingsDialog(
            baseline = baseline,
            restoredDraft = savedProxyDraft,
            onDraftChange = model::updateProxySettingsDraft,
            onSave = {
                model.updateProxySettingsDraft(it)
                confirmProxy = true
                editProxy = false
            },
            onDismiss = {
                model.updateProxySettingsDraft(null)
                editProxy = false
            },
        )
    }
    if (confirmFiles) savedDraft?.let { value ->
        ConfirmDialog(
            title = stringResource(R.string.save_file_services_title),
            message = stringResource(R.string.save_file_services_message),
            confirm = stringResource(R.string.save),
            destructive = true,
            onConfirm = {
                if (model.saveFileServiceSettings(value)) {
                    fileSaveRequested = true
                    confirmFiles = false
                }
            },
            onDismiss = {
                confirmFiles = false
                editFiles = true
            },
        )
    }
    if (confirmTerminal) savedTerminalDraft?.let { value ->
        ConfirmDialog(
            title = stringResource(R.string.save_terminal_title),
            message = stringResource(R.string.save_terminal_message),
            confirm = stringResource(R.string.save),
            destructive = true,
            onConfirm = {
                if (model.saveTerminalSettings(value)) {
                    terminalSaveRequested = true
                    confirmTerminal = false
                }
            },
            onDismiss = {
                confirmTerminal = false
                editTerminal = true
            },
        )
    }
    if (confirmProxy) savedProxyDraft?.let { value ->
        ConfirmDialog(
            title = stringResource(R.string.save_proxy_title),
            message = stringResource(R.string.save_proxy_message),
            confirm = stringResource(R.string.save),
            destructive = true,
            onConfirm = {
                if (model.saveProxySettings(value)) {
                    proxySaveRequested = true
                    confirmProxy = false
                }
            },
            onDismiss = {
                confirmProxy = false
                editProxy = true
            },
        )
    }
}

internal fun shouldReopenFileServiceEditor(
    saveRequested: Boolean,
    mutationInProgress: Boolean,
    mutationResult: MutationResult?,
    mutationFailure: DsmFailure?,
): Boolean = saveRequested && !mutationInProgress && mutationResult == null && mutationFailure == null

internal fun shouldReopenTerminalEditor(
    saveRequested: Boolean,
    mutationInProgress: Boolean,
    mutationResult: MutationResult?,
    mutationFailure: DsmFailure?,
): Boolean = saveRequested && !mutationInProgress && mutationResult == null && mutationFailure == null

internal fun shouldReopenProxyEditor(
    saveRequested: Boolean,
    mutationInProgress: Boolean,
    mutationResult: MutationResult?,
    mutationFailure: DsmFailure?,
): Boolean = saveRequested && !mutationInProgress && mutationResult == null && mutationFailure == null

internal data class FileServiceFeedbackPolicy(
    @StringRes val title: Int,
    @StringRes val message: Int,
    val canRefresh: Boolean,
    val mustRefreshBeforeEditing: Boolean,
    val isAssertive: Boolean,
)

internal fun fileServiceFeedbackPolicy(result: MutationResult): FileServiceFeedbackPolicy {
    require(result.operation == "fileServiceSettingsUpdate") { "file-services.unexpected-operation" }
    val canRefresh = result.submitted || result.requiresRefresh ||
        result.errorCategory == MutationErrorCategory.CONFLICT
    return when (result.status) {
        MutationResultStatus.CONFIRMED_SUCCESS -> FileServiceFeedbackPolicy(
            R.string.file_service_feedback_saved_title,
            R.string.file_service_settings_saved,
            canRefresh = false,
            mustRefreshBeforeEditing = false,
            isAssertive = false,
        )
        MutationResultStatus.PARTIAL_SUCCESS -> FileServiceFeedbackPolicy(
            R.string.file_service_feedback_partial_title,
            R.string.file_service_feedback_partial_message,
            canRefresh = true,
            mustRefreshBeforeEditing = true,
            isAssertive = true,
        )
        MutationResultStatus.SUBMITTED_BUT_UNVERIFIED -> FileServiceFeedbackPolicy(
            R.string.file_service_feedback_check_title,
            R.string.file_service_feedback_unverified_message,
            canRefresh = true,
            mustRefreshBeforeEditing = true,
            isAssertive = true,
        )
        MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION -> FileServiceFeedbackPolicy(
            R.string.file_service_feedback_check_title,
            R.string.file_service_cancel_after_submission,
            canRefresh = true,
            mustRefreshBeforeEditing = true,
            isAssertive = true,
        )
        MutationResultStatus.PERMISSION_DENIED -> FileServiceFeedbackPolicy(
            R.string.file_service_feedback_permission_title,
            R.string.file_service_feedback_permission_message,
            canRefresh = canRefresh,
            mustRefreshBeforeEditing = canRefresh,
            isAssertive = true,
        )
        MutationResultStatus.UNSUPPORTED -> FileServiceFeedbackPolicy(
            R.string.file_service_feedback_unavailable_title,
            R.string.file_service_feedback_unsupported_message,
            canRefresh = canRefresh,
            mustRefreshBeforeEditing = canRefresh,
            isAssertive = true,
        )
        MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> FileServiceFeedbackPolicy(
            R.string.file_service_feedback_cancelled_title,
            R.string.file_service_feedback_cancelled_message,
            canRefresh = false,
            mustRefreshBeforeEditing = false,
            isAssertive = false,
        )
        MutationResultStatus.CONFIRMED_FAILURE -> FileServiceFeedbackPolicy(
            if (result.errorCategory == MutationErrorCategory.CONFLICT) {
                R.string.file_service_feedback_conflict_title
            } else {
                R.string.file_service_feedback_failed_title
            },
            if (result.errorCategory == MutationErrorCategory.CONFLICT) {
                R.string.file_service_feedback_conflict_message
            } else {
                R.string.file_service_feedback_failed_message
            },
            canRefresh = canRefresh,
            mustRefreshBeforeEditing = canRefresh,
            isAssertive = true,
        )
    }
}

internal data class TerminalFeedbackPolicy(
    @StringRes val title: Int,
    @StringRes val message: Int,
    val canRefresh: Boolean,
    val mustRefreshBeforeEditing: Boolean,
    val isAssertive: Boolean,
)

internal fun terminalFeedbackPolicy(result: MutationResult): TerminalFeedbackPolicy {
    require(result.operation == "terminalSettingsUpdate") { "terminal.unexpected-operation" }
    val canRefresh = result.submitted || result.requiresRefresh ||
        result.errorCategory == MutationErrorCategory.CONFLICT
    return when (result.status) {
        MutationResultStatus.CONFIRMED_SUCCESS -> TerminalFeedbackPolicy(
            R.string.file_service_feedback_saved_title,
            R.string.terminal_settings_saved,
            canRefresh = false,
            mustRefreshBeforeEditing = false,
            isAssertive = false,
        )
        MutationResultStatus.PARTIAL_SUCCESS -> TerminalFeedbackPolicy(
            R.string.file_service_feedback_partial_title,
            R.string.terminal_feedback_partial_message,
            canRefresh = true,
            mustRefreshBeforeEditing = true,
            isAssertive = true,
        )
        MutationResultStatus.SUBMITTED_BUT_UNVERIFIED -> TerminalFeedbackPolicy(
            R.string.file_service_feedback_check_title,
            R.string.terminal_feedback_unverified_message,
            canRefresh = true,
            mustRefreshBeforeEditing = true,
            isAssertive = true,
        )
        MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION -> TerminalFeedbackPolicy(
            R.string.file_service_feedback_check_title,
            R.string.terminal_cancel_after_submission,
            canRefresh = true,
            mustRefreshBeforeEditing = true,
            isAssertive = true,
        )
        MutationResultStatus.PERMISSION_DENIED -> TerminalFeedbackPolicy(
            R.string.file_service_feedback_permission_title,
            R.string.terminal_feedback_permission_message,
            canRefresh = canRefresh,
            mustRefreshBeforeEditing = canRefresh,
            isAssertive = true,
        )
        MutationResultStatus.UNSUPPORTED -> TerminalFeedbackPolicy(
            R.string.file_service_feedback_unavailable_title,
            R.string.terminal_feedback_unsupported_message,
            canRefresh = canRefresh,
            mustRefreshBeforeEditing = canRefresh,
            isAssertive = true,
        )
        MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> TerminalFeedbackPolicy(
            R.string.file_service_feedback_cancelled_title,
            R.string.terminal_feedback_cancelled_message,
            canRefresh = false,
            mustRefreshBeforeEditing = false,
            isAssertive = false,
        )
        MutationResultStatus.CONFIRMED_FAILURE -> TerminalFeedbackPolicy(
            if (result.errorCategory == MutationErrorCategory.CONFLICT) {
                R.string.file_service_feedback_conflict_title
            } else {
                R.string.file_service_feedback_failed_title
            },
            if (result.errorCategory == MutationErrorCategory.CONFLICT) {
                R.string.terminal_feedback_conflict_message
            } else {
                R.string.terminal_feedback_failed_message
            },
            canRefresh = canRefresh,
            mustRefreshBeforeEditing = canRefresh,
            isAssertive = true,
        )
    }
}

internal data class ProxyFeedbackPolicy(
    @StringRes val title: Int,
    @StringRes val message: Int,
    val canRefresh: Boolean,
    val mustRefreshBeforeEditing: Boolean,
    val isAssertive: Boolean,
)

internal fun proxyFeedbackPolicy(result: MutationResult): ProxyFeedbackPolicy {
    require(result.operation == "proxySettingsUpdate") { "proxy.unexpected-operation" }
    val canRefresh = result.submitted || result.requiresRefresh ||
        result.errorCategory == MutationErrorCategory.CONFLICT
    return when (result.status) {
        MutationResultStatus.CONFIRMED_SUCCESS -> ProxyFeedbackPolicy(
            R.string.file_service_feedback_saved_title,
            R.string.proxy_settings_saved,
            canRefresh = false,
            mustRefreshBeforeEditing = false,
            isAssertive = false,
        )
        MutationResultStatus.PARTIAL_SUCCESS -> ProxyFeedbackPolicy(
            R.string.file_service_feedback_partial_title,
            R.string.proxy_feedback_partial_message,
            canRefresh = true,
            mustRefreshBeforeEditing = true,
            isAssertive = true,
        )
        MutationResultStatus.SUBMITTED_BUT_UNVERIFIED -> ProxyFeedbackPolicy(
            R.string.file_service_feedback_check_title,
            R.string.proxy_feedback_unverified_message,
            canRefresh = true,
            mustRefreshBeforeEditing = true,
            isAssertive = true,
        )
        MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION -> ProxyFeedbackPolicy(
            R.string.file_service_feedback_check_title,
            R.string.proxy_cancel_after_submission,
            canRefresh = true,
            mustRefreshBeforeEditing = true,
            isAssertive = true,
        )
        MutationResultStatus.PERMISSION_DENIED -> ProxyFeedbackPolicy(
            R.string.file_service_feedback_permission_title,
            R.string.proxy_feedback_permission_message,
            canRefresh = canRefresh,
            mustRefreshBeforeEditing = canRefresh,
            isAssertive = true,
        )
        MutationResultStatus.UNSUPPORTED -> ProxyFeedbackPolicy(
            R.string.file_service_feedback_unavailable_title,
            R.string.proxy_feedback_unsupported_message,
            canRefresh = canRefresh,
            mustRefreshBeforeEditing = canRefresh,
            isAssertive = true,
        )
        MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> ProxyFeedbackPolicy(
            R.string.file_service_feedback_cancelled_title,
            R.string.proxy_feedback_cancelled_message,
            canRefresh = false,
            mustRefreshBeforeEditing = false,
            isAssertive = false,
        )
        MutationResultStatus.CONFIRMED_FAILURE -> ProxyFeedbackPolicy(
            if (result.errorCategory == MutationErrorCategory.CONFLICT) {
                R.string.file_service_feedback_conflict_title
            } else {
                R.string.file_service_feedback_failed_title
            },
            if (result.errorCategory == MutationErrorCategory.CONFLICT) {
                R.string.proxy_feedback_conflict_message
            } else {
                R.string.proxy_feedback_failed_message
            },
            canRefresh = canRefresh,
            mustRefreshBeforeEditing = canRefresh,
            isAssertive = true,
        )
    }
}

@Composable
internal fun FileServiceSavingCard() = SettingsSavingCard(
    title = R.string.file_service_saving_title,
    message = R.string.file_service_saving_message,
)

@Composable
internal fun TerminalSavingCard() = SettingsSavingCard(
    title = R.string.terminal_saving_title,
    message = R.string.terminal_saving_message,
)

@Composable
internal fun ProxySavingCard() = SettingsSavingCard(
    title = R.string.proxy_saving_title,
    message = R.string.proxy_saving_message,
)

@Composable
private fun SettingsSavingCard(@StringRes title: Int, @StringRes message: Int) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
            .semantics { liveRegion = LiveRegionMode.Polite },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                stringResource(title),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(stringResource(message))
            LinearProgressIndicator(Modifier.fillMaxWidth())
        }
    }
}

@Composable
internal fun FileServiceMutationFeedbackCard(
    result: MutationResult,
    refreshCompleted: Boolean,
    canContinueEditing: Boolean,
    onRefresh: () -> Unit,
    onContinueEditing: () -> Unit,
    onDismiss: () -> Unit,
) {
    val policy = fileServiceFeedbackPolicy(result)
    SettingsMutationFeedbackCard(
        result = result,
        title = policy.title,
        message = policy.message,
        canRefresh = policy.canRefresh,
        mustRefreshBeforeEditing = policy.mustRefreshBeforeEditing,
        isAssertive = policy.isAssertive,
        counts = R.string.file_service_feedback_counts,
        refreshCompletedMessage = R.string.file_service_refresh_completed,
        refreshAction = R.string.refresh_and_check_settings,
        discardAction = R.string.discard_file_service_draft,
        refreshCompleted = refreshCompleted,
        canContinueEditing = canContinueEditing,
        onRefresh = onRefresh,
        onContinueEditing = onContinueEditing,
        onDismiss = onDismiss,
    )
}

@Composable
internal fun TerminalMutationFeedbackCard(
    result: MutationResult,
    refreshCompleted: Boolean,
    canContinueEditing: Boolean,
    onRefresh: () -> Unit,
    onContinueEditing: () -> Unit,
    onDismiss: () -> Unit,
) {
    val policy = terminalFeedbackPolicy(result)
    SettingsMutationFeedbackCard(
        result = result,
        title = policy.title,
        message = policy.message,
        canRefresh = policy.canRefresh,
        mustRefreshBeforeEditing = policy.mustRefreshBeforeEditing,
        isAssertive = policy.isAssertive,
        counts = R.string.terminal_feedback_counts,
        refreshCompletedMessage = R.string.terminal_refresh_completed,
        refreshAction = R.string.refresh_and_check_terminal_settings,
        discardAction = R.string.discard_terminal_draft,
        refreshCompleted = refreshCompleted,
        canContinueEditing = canContinueEditing,
        onRefresh = onRefresh,
        onContinueEditing = onContinueEditing,
        onDismiss = onDismiss,
    )
}

@Composable
internal fun ProxyMutationFeedbackCard(
    result: MutationResult,
    refreshCompleted: Boolean,
    canContinueEditing: Boolean,
    onRefresh: () -> Unit,
    onContinueEditing: () -> Unit,
    onDismiss: () -> Unit,
) {
    val policy = proxyFeedbackPolicy(result)
    SettingsMutationFeedbackCard(
        result = result,
        title = policy.title,
        message = policy.message,
        canRefresh = policy.canRefresh,
        mustRefreshBeforeEditing = policy.mustRefreshBeforeEditing,
        isAssertive = policy.isAssertive,
        counts = R.string.proxy_feedback_counts,
        refreshCompletedMessage = R.string.proxy_refresh_completed,
        refreshAction = R.string.refresh_and_check_proxy_settings,
        discardAction = R.string.discard_proxy_draft,
        refreshCompleted = refreshCompleted,
        canContinueEditing = canContinueEditing,
        onRefresh = onRefresh,
        onContinueEditing = onContinueEditing,
        onDismiss = onDismiss,
    )
}

@Composable
private fun SettingsMutationFeedbackCard(
    result: MutationResult,
    @StringRes title: Int,
    @StringRes message: Int,
    canRefresh: Boolean,
    mustRefreshBeforeEditing: Boolean,
    isAssertive: Boolean,
    @StringRes counts: Int,
    @StringRes refreshCompletedMessage: Int,
    @StringRes refreshAction: Int,
    @StringRes discardAction: Int,
    refreshCompleted: Boolean,
    canContinueEditing: Boolean,
    onRefresh: () -> Unit,
    onContinueEditing: () -> Unit,
    onDismiss: () -> Unit,
) {
    val success = result.status == MutationResultStatus.CONFIRMED_SUCCESS
    val error = result.status == MutationResultStatus.PERMISSION_DENIED ||
        result.status == MutationResultStatus.CONFIRMED_FAILURE
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
            .semantics {
                liveRegion = if (isAssertive) LiveRegionMode.Assertive else LiveRegionMode.Polite
            },
        colors = CardDefaults.cardColors(
            containerColor = if (success) {
                MaterialTheme.colorScheme.secondaryContainer
            } else if (error) {
                MaterialTheme.colorScheme.errorContainer
            } else {
                MaterialTheme.colorScheme.tertiaryContainer
            },
        ),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(stringResource(title), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(message))
            val resultCounts = result.counts
            if (resultCounts.succeeded + resultCounts.failed + resultCounts.unknown > 0) {
                Text(
                    stringResource(
                        counts,
                        resultCounts.succeeded,
                        resultCounts.failed,
                        resultCounts.unknown,
                    ),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (canRefresh) {
                TextButton(onClick = onRefresh, modifier = Modifier.align(Alignment.End)) {
                    Text(stringResource(refreshAction))
                }
            }
            if (refreshCompleted && mustRefreshBeforeEditing) {
                Text(
                    stringResource(refreshCompletedMessage),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (!success && canContinueEditing) {
                TextButton(onClick = onContinueEditing, modifier = Modifier.align(Alignment.End)) {
                    Text(stringResource(R.string.continue_editing))
                }
            }
            TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
                Text(
                    stringResource(
                        if (success) R.string.done else discardAction,
                    ),
                )
            }
        }
    }
}

@Composable
internal fun FileServiceMutationFailureCard(
    failure: DsmFailure,
    canContinueEditing: Boolean,
    onContinueEditing: () -> Unit,
    onDismiss: () -> Unit,
) {
    SettingsMutationFailureCard(
        failure = failure,
        title = R.string.file_service_feedback_failed_title,
        discardAction = R.string.discard_file_service_draft,
        canContinueEditing = canContinueEditing,
        onContinueEditing = onContinueEditing,
        onDismiss = onDismiss,
    )
}

@Composable
internal fun TerminalMutationFailureCard(
    failure: DsmFailure,
    canContinueEditing: Boolean,
    onContinueEditing: () -> Unit,
    onDismiss: () -> Unit,
) {
    SettingsMutationFailureCard(
        failure = failure,
        title = R.string.file_service_feedback_failed_title,
        discardAction = R.string.discard_terminal_draft,
        canContinueEditing = canContinueEditing,
        onContinueEditing = onContinueEditing,
        onDismiss = onDismiss,
    )
}

@Composable
internal fun ProxyMutationFailureCard(
    failure: DsmFailure,
    canContinueEditing: Boolean,
    onContinueEditing: () -> Unit,
    onDismiss: () -> Unit,
) {
    SettingsMutationFailureCard(
        failure = failure,
        title = R.string.file_service_feedback_failed_title,
        discardAction = R.string.discard_proxy_draft,
        canContinueEditing = canContinueEditing,
        onContinueEditing = onContinueEditing,
        onDismiss = onDismiss,
    )
}

@Composable
private fun SettingsMutationFailureCard(
    failure: DsmFailure,
    @StringRes title: Int,
    @StringRes discardAction: Int,
    canContinueEditing: Boolean,
    onContinueEditing: () -> Unit,
    onDismiss: () -> Unit,
) {
    val localized = failure.localize(LocalContext.current)
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
            .semantics { liveRegion = LiveRegionMode.Assertive },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                stringResource(title),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(localized.combined)
            if (canContinueEditing) {
                TextButton(onClick = onContinueEditing, modifier = Modifier.align(Alignment.End)) {
                    Text(stringResource(R.string.continue_editing))
                }
            }
            TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
                Text(stringResource(discardAction))
            }
        }
    }
}

@Composable
private fun SettingsSummaryRow(
    title: String,
    detail: String,
    icon: @Composable () -> Unit,
    onEdit: () -> Unit,
    enabled: Boolean = true,
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(detail) },
        leadingContent = icon,
        trailingContent = {
            TextButton(onClick = onEdit, enabled = enabled) {
                Icon(Icons.Outlined.Edit, null)
                Text(stringResource(R.string.edit))
            }
        },
    )
    HorizontalDivider(Modifier.padding(start = 72.dp))
}

@Composable
private fun SettingsUnavailableRow(
    title: String,
    detail: String,
    icon: @Composable () -> Unit,
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(detail) },
        leadingContent = icon,
    )
    HorizontalDivider(Modifier.padding(start = 72.dp))
}

@Composable
private fun fileServiceSummary(value: NasFileServiceSettings): String {
    val enabled = listOfNotNull(
        stringResource(R.string.smb_short_name).takeIf { value.isSmbEnabled == true },
        stringResource(R.string.nfs_short_name).takeIf { value.isNfsEnabled == true },
        stringResource(R.string.ftp_short_name).takeIf { value.isFtpEnabled == true },
        stringResource(R.string.ftps_short_name).takeIf { value.isFtpsEnabled == true },
        stringResource(R.string.sftp_short_name).takeIf { value.isSftpEnabled == true },
    )
    return enabled.joinToString(" · ").ifBlank { stringResource(R.string.all_file_services_disabled) }
}

@Composable
private fun terminalSummary(value: NasTerminalSettings): String = listOfNotNull(
    stringResource(R.string.ssh_short_name).takeIf { value.isSshEnabled },
    stringResource(R.string.telnet_short_name).takeIf { value.isTelnetEnabled },
).joinToString(" · ").ifBlank { stringResource(R.string.service_disabled) }

@Composable
private fun FileServiceDialog(
    baseline: NasFileServiceSettings,
    restoredDraft: NasFileServiceSettings?,
    onDraftChange: (NasFileServiceSettings) -> Unit,
    onSave: (NasFileServiceSettings) -> Unit,
    onDismiss: () -> Unit,
) {
    var draft by remember(baseline, restoredDraft) { mutableStateOf(restoredDraft ?: baseline) }
    LaunchedEffect(draft) { onDraftChange(draft) }
    val validation = fileServiceValidation(draft)
    SettingsDialog(
        title = stringResource(R.string.file_services),
        valid = validation == null,
        changed = draft != baseline,
        onSave = { onSave(draft) },
        onDismiss = onDismiss,
    ) {
        NullableSettingsSwitch(R.string.smb_service, draft.isSmbEnabled) {
            draft = draft.copy(isSmbEnabled = it)
        }
        NullableSettingsSwitch(R.string.nfs_service, draft.isNfsEnabled) {
            draft = draft.copy(isNfsEnabled = it)
        }
        NullableSettingsSwitch(R.string.ftp_service, draft.isFtpEnabled) {
            draft = draft.copy(isFtpEnabled = it)
        }
        NullableSettingsSwitch(R.string.ftps_service, draft.isFtpsEnabled) {
            draft = draft.copy(isFtpsEnabled = it)
        }
        draft.ftpPort?.let { port ->
            PortField(port, R.string.ftp_port, validation == ServiceValidation.FTP_PORT) {
                draft = draft.copy(ftpPort = it)
            }
        }
        NullableSettingsSwitch(R.string.sftp_service, draft.isSftpEnabled) {
            draft = draft.copy(isSftpEnabled = it)
        }
        draft.sftpPort?.let { port ->
            PortField(port, R.string.sftp_port, validation == ServiceValidation.SFTP_PORT) {
                draft = draft.copy(sftpPort = it)
            }
        }
        NullableSettingsSwitch(R.string.ssdp_discovery, draft.isSsdpEnabled) {
            draft = draft.copy(isSsdpEnabled = it)
        }
        NullableSettingsSwitch(R.string.bonjour_discovery, draft.isBonjourEnabled) {
            draft = draft.copy(isBonjourEnabled = it)
        }
        NullableSettingsSwitch(R.string.smb_time_machine, draft.isSmbTimeMachineEnabled) {
            draft = draft.copy(isSmbTimeMachineEnabled = it)
        }
        validation?.let {
            Text(
                stringResource(
                    if (it == ServiceValidation.PORT_CONFLICT) R.string.file_service_port_conflict
                    else if (it == ServiceValidation.TIME_MACHINE) R.string.time_machine_requires_smb
                    else R.string.invalid_port,
                ),
                color = MaterialTheme.colorScheme.error,
            )
        }
        Text(
            stringResource(R.string.file_services_impact_hint),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
internal fun TerminalSettingsDialog(
    baseline: NasTerminalSettings,
    restoredDraft: NasTerminalSettings?,
    onDraftChange: (NasTerminalSettings) -> Unit,
    onSave: (NasTerminalSettings) -> Unit,
    onDismiss: () -> Unit,
) {
    var draft by remember(baseline, restoredDraft) { mutableStateOf(restoredDraft ?: baseline) }
    LaunchedEffect(draft) { onDraftChange(draft) }
    val invalidPort = draft.sshPort?.let { it !in 1..65_535 } == true
    SettingsDialog(
        title = stringResource(R.string.remote_terminal),
        valid = !invalidPort,
        changed = draft != baseline,
        onSave = { onSave(draft) },
        onDismiss = onDismiss,
    ) {
        SettingsSwitch(R.string.ssh_service, draft.isSshEnabled) {
            draft = draft.copy(isSshEnabled = it)
        }
        SettingsSwitch(R.string.telnet_service, draft.isTelnetEnabled) {
            draft = draft.copy(isTelnetEnabled = it)
        }
        draft.sshPort?.let { port ->
            PortField(port, R.string.ssh_port, invalidPort) { draft = draft.copy(sshPort = it) }
        }
        Text(
            stringResource(R.string.terminal_security_hint),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
internal fun ProxySettingsDialog(
    baseline: NasProxySettings,
    restoredDraft: NasProxySettings?,
    onDraftChange: (NasProxySettings) -> Unit,
    onSave: (NasProxySettings) -> Unit,
    onDismiss: () -> Unit,
) {
    val initial = restoredDraft ?: baseline
    var enabled by rememberSaveable(baseline, restoredDraft) { mutableStateOf(initial.isEnabled) }
    var host by rememberSaveable(baseline, restoredDraft) { mutableStateOf(initial.host) }
    var portText by rememberSaveable(baseline, restoredDraft) {
        mutableStateOf(initial.port?.toString().orEmpty())
    }
    val port = portText.toIntOrNull()
    val hostInvalid = enabled && !isValidProxyHost(host.trim())
    val portInvalid = enabled && (port == null || port !in 1..65_535)
    val draft = NasProxySettings(enabled, host.trim(), port)
    val changed = enabled != baseline.isEnabled || enabled &&
        (draft.host != baseline.host.trim() || draft.port != baseline.port)
    LaunchedEffect(draft) { onDraftChange(draft) }
    SettingsDialog(
        title = stringResource(R.string.internet_proxy),
        valid = !hostInvalid && !portInvalid,
        changed = changed,
        onSave = { onSave(draft) },
        onDismiss = onDismiss,
    ) {
        SettingsSwitch(R.string.use_internet_proxy, enabled) { enabled = it }
        if (enabled) {
            OutlinedTextField(
                value = host,
                onValueChange = { host = it },
                label = { Text(stringResource(R.string.proxy_host)) },
                isError = hostInvalid,
                supportingText = if (hostInvalid) {
                    { Text(stringResource(R.string.invalid_proxy_host)) }
                } else null,
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = portText,
                onValueChange = { portText = it.filter(Char::isDigit).take(5) },
                label = { Text(stringResource(R.string.proxy_port)) },
                isError = portInvalid,
                supportingText = if (portInvalid) { { Text(stringResource(R.string.invalid_port)) } } else null,
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Text(
            stringResource(R.string.proxy_impact_hint),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun SettingsDialog(
    title: String,
    valid: Boolean,
    changed: Boolean,
    onSave: () -> Unit,
    onDismiss: () -> Unit,
    content: @Composable () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(
                modifier = Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) { content() }
        },
        confirmButton = {
            TextButton(enabled = valid && changed, onClick = onSave) { Text(stringResource(R.string.continue_action)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        },
    )
}

@Composable
private fun NullableSettingsSwitch(label: Int, value: Boolean?, onChange: (Boolean) -> Unit) {
    value?.let { SettingsSwitch(label, it, onChange) }
}

@Composable
private fun SettingsSwitch(label: Int, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .toggleable(value = value, role = Role.Switch, onValueChange = onChange)
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(stringResource(label), modifier = Modifier.weight(1f))
        Switch(checked = value, onCheckedChange = null)
    }
}

@Composable
private fun PortField(value: Int, label: Int, isError: Boolean, onChange: (Int) -> Unit) {
    var text by remember(value) { mutableStateOf(value.toString()) }
    OutlinedTextField(
        value = text,
        onValueChange = {
            text = it.filter(Char::isDigit).take(5)
            onChange(text.toIntOrNull() ?: 0)
        },
        label = { Text(stringResource(label)) },
        isError = isError,
        supportingText = if (isError) { { Text(stringResource(R.string.invalid_port)) } } else null,
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        modifier = Modifier.fillMaxWidth(),
    )
}

private enum class ServiceValidation { FTP_PORT, SFTP_PORT, PORT_CONFLICT, TIME_MACHINE }

private fun fileServiceValidation(value: NasFileServiceSettings): ServiceValidation? = when {
    value.ftpPort?.let { it !in 1..65_535 } == true -> ServiceValidation.FTP_PORT
    value.sftpPort?.let { it !in 1..65_535 } == true -> ServiceValidation.SFTP_PORT
    value.isSmbTimeMachineEnabled == true && value.isSmbEnabled == false -> ServiceValidation.TIME_MACHINE
    (value.isFtpEnabled == true || value.isFtpsEnabled == true) && value.isSftpEnabled == true &&
        value.ftpPort != null && value.ftpPort == value.sftpPort -> ServiceValidation.PORT_CONFLICT
    else -> null
}

private fun isValidProxyHost(value: String): Boolean =
    value.isNotBlank() && value.length <= 255 && "://" !in value &&
        value.none { it.isWhitespace() || it in "/?#@" }
