package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.EditCalendar
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.AppViewModel
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasManualDateTime
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasRegionSettings
import io.github.qwertyuiop1995.dsmnativeclient.localization.localize
import io.github.qwertyuiop1995.dsmnativeclient.ui.ConfirmDialog
import java.util.GregorianCalendar

@Composable
internal fun NasRegionSettingsScreen(
    settings: NasRegionSettings?,
    savedDraft: NasRegionSettings?,
    mutationResult: MutationResult?,
    mutationFailure: DsmFailure?,
    mutationInProgress: Boolean,
    mutationRefreshCompleted: Boolean,
    isPerformingAction: Boolean,
    model: AppViewModel,
) {
    var editing by rememberSaveable { mutableStateOf(false) }
    var confirming by rememberSaveable { mutableStateOf(false) }
    var saveRequested by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(mutationInProgress, mutationResult, mutationFailure) {
        when {
            mutationInProgress -> saveRequested = true
            shouldReopenRegionEditor(
                saveRequested,
                mutationInProgress,
                mutationResult,
                mutationFailure,
            ) -> {
                saveRequested = false
                editing = true
            }
            saveRequested -> saveRequested = false
        }
    }

    LazyColumn {
        if (saveRequested || mutationInProgress) {
            item { RegionSavingCard() }
        } else {
            mutationResult?.let { result ->
                item {
                    val policy = regionFeedbackPolicy(result)
                    RegionMutationFeedbackCard(
                        result = result,
                        refreshCompleted = mutationRefreshCompleted,
                        canContinueEditing = savedDraft != null &&
                            (!policy.mustRefreshBeforeEditing || mutationRefreshCompleted),
                        onRefresh = { model.load(Module.NAS_SETTINGS) },
                        onContinueEditing = {
                            editing = savedDraft != null
                            model.dismissRegionMutationResult()
                        },
                        onDismiss = { model.dismissRegionMutationResult(discardDraft = true) },
                    )
                }
            }
            mutationFailure?.let { failure ->
                item {
                    RegionMutationFailureCard(
                        failure = failure,
                        canContinueEditing = savedDraft != null,
                        onContinueEditing = {
                            editing = savedDraft != null
                            model.dismissRegionMutationResult()
                        },
                        onDismiss = { model.dismissRegionMutationResult(discardDraft = true) },
                    )
                }
            }
        }
        if (settings == null) {
            item {
                Column(
                    Modifier.fillMaxWidth().padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        stringResource(R.string.region_settings_unavailable),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        stringResource(R.string.region_settings_unavailable_hint),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    TextButton(
                        onClick = { model.load(Module.NAS_SETTINGS) },
                        enabled = !isPerformingAction,
                    ) {
                        Text(stringResource(R.string.refresh_and_check_region_settings))
                    }
                }
            }
        } else {
            item {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.region_and_time)) },
                    supportingContent = {
                        val zone = settings.timeZones.firstOrNull { it.id == settings.timeZone }
                        Text(
                            stringResource(
                                if (settings.isNetworkTimeEnabled) R.string.network_time_summary
                                else R.string.manual_time_summary,
                                zone?.displayName ?: settings.timeZone,
                            ),
                        )
                    },
                    leadingContent = { Icon(Icons.Outlined.EditCalendar, null) },
                    trailingContent = {
                        TextButton(
                            onClick = {
                                model.updateRegionSettingsDraft(settings)
                                editing = true
                            },
                            enabled = !isPerformingAction && !mutationInProgress &&
                                mutationResult == null && mutationFailure == null,
                        ) {
                            Text(stringResource(R.string.edit))
                        }
                    },
                )
            }
        }
    }

    if (editing && settings != null) {
        RegionSettingsDialog(
            baseline = settings,
            restoredDraft = savedDraft,
            onDraftChange = model::updateRegionSettingsDraft,
            onSave = {
                model.updateRegionSettingsDraft(it)
                confirming = true
                editing = false
            },
            onDismiss = {
                model.updateRegionSettingsDraft(null)
                editing = false
            },
        )
    }
    if (confirming) savedDraft?.let { value ->
        ConfirmDialog(
            title = stringResource(R.string.save_region_settings_title),
            message = stringResource(
                if (regionSettingsNeedsImmediateTimeSync(settings, value)) {
                    R.string.save_region_settings_with_sync_message
                } else {
                    R.string.save_region_settings_message
                },
            ),
            confirm = stringResource(R.string.save),
            destructive = true,
            onConfirm = {
                if (model.saveRegionSettings(value)) {
                    saveRequested = true
                    confirming = false
                }
            },
            onDismiss = {
                confirming = false
                editing = true
            },
        )
    }
}

internal fun shouldReopenRegionEditor(
    saveRequested: Boolean,
    mutationInProgress: Boolean,
    mutationResult: MutationResult?,
    mutationFailure: DsmFailure?,
): Boolean = saveRequested && !mutationInProgress && mutationResult == null && mutationFailure == null

internal fun regionSettingsNeedsImmediateTimeSync(
    baseline: NasRegionSettings?,
    draft: NasRegionSettings,
): Boolean = baseline != null && draft.isNetworkTimeEnabled &&
    (!baseline.isNetworkTimeEnabled || baseline.timeServers != draft.timeServers)

internal data class RegionFeedbackPolicy(
    @StringRes val title: Int,
    @StringRes val message: Int,
    val canRefresh: Boolean,
    val mustRefreshBeforeEditing: Boolean,
    val isAssertive: Boolean,
)

internal fun regionFeedbackPolicy(result: MutationResult): RegionFeedbackPolicy {
    require(result.operation == "regionSettingsUpdate") { "region.unexpected-operation" }
    val canRefresh = result.submitted || result.requiresRefresh ||
        result.errorCategory == MutationErrorCategory.CONFLICT
    return when (result.status) {
        MutationResultStatus.CONFIRMED_SUCCESS -> RegionFeedbackPolicy(
            R.string.region_feedback_saved_title,
            R.string.region_feedback_sync_accepted_message,
            canRefresh = false,
            mustRefreshBeforeEditing = false,
            isAssertive = false,
        )
        MutationResultStatus.PARTIAL_SUCCESS -> RegionFeedbackPolicy(
            R.string.region_feedback_partial_title,
            R.string.region_feedback_partial_message,
            canRefresh = true,
            mustRefreshBeforeEditing = true,
            isAssertive = true,
        )
        MutationResultStatus.SUBMITTED_BUT_UNVERIFIED -> RegionFeedbackPolicy(
            R.string.region_feedback_check_title,
            R.string.region_feedback_unverified_message,
            canRefresh = true,
            mustRefreshBeforeEditing = true,
            isAssertive = true,
        )
        MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION -> RegionFeedbackPolicy(
            R.string.region_feedback_check_title,
            R.string.region_cancel_after_submission,
            canRefresh = true,
            mustRefreshBeforeEditing = true,
            isAssertive = true,
        )
        MutationResultStatus.PERMISSION_DENIED -> RegionFeedbackPolicy(
            R.string.file_service_feedback_permission_title,
            R.string.region_feedback_permission_message,
            canRefresh = canRefresh,
            mustRefreshBeforeEditing = canRefresh,
            isAssertive = true,
        )
        MutationResultStatus.UNSUPPORTED -> RegionFeedbackPolicy(
            R.string.file_service_feedback_unavailable_title,
            R.string.region_feedback_unsupported_message,
            canRefresh = canRefresh,
            mustRefreshBeforeEditing = canRefresh,
            isAssertive = true,
        )
        MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> RegionFeedbackPolicy(
            R.string.file_service_feedback_cancelled_title,
            R.string.region_feedback_cancelled_message,
            canRefresh = false,
            mustRefreshBeforeEditing = false,
            isAssertive = false,
        )
        MutationResultStatus.CONFIRMED_FAILURE -> RegionFeedbackPolicy(
            if (result.errorCategory == MutationErrorCategory.CONFLICT) {
                R.string.file_service_feedback_conflict_title
            } else {
                R.string.file_service_feedback_failed_title
            },
            if (result.errorCategory == MutationErrorCategory.CONFLICT) {
                R.string.region_feedback_conflict_message
            } else {
                R.string.region_feedback_failed_message
            },
            canRefresh = canRefresh,
            mustRefreshBeforeEditing = canRefresh,
            isAssertive = true,
        )
    }
}

@Composable
internal fun RegionSavingCard() {
    Card(
        modifier = Modifier.fillMaxWidth().padding(16.dp)
            .semantics { liveRegion = LiveRegionMode.Polite },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.region_saving_title), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.region_saving_message))
            LinearProgressIndicator(Modifier.fillMaxWidth())
        }
    }
}

@Composable
internal fun RegionMutationFeedbackCard(
    result: MutationResult,
    refreshCompleted: Boolean,
    canContinueEditing: Boolean,
    onRefresh: () -> Unit,
    onContinueEditing: () -> Unit,
    onDismiss: () -> Unit,
) {
    val policy = regionFeedbackPolicy(result)
    val success = result.status == MutationResultStatus.CONFIRMED_SUCCESS
    val error = result.status == MutationResultStatus.PERMISSION_DENIED ||
        result.status == MutationResultStatus.CONFIRMED_FAILURE
    Card(
        modifier = Modifier.fillMaxWidth().padding(16.dp).semantics {
            liveRegion = if (policy.isAssertive) LiveRegionMode.Assertive else LiveRegionMode.Polite
        },
        colors = CardDefaults.cardColors(
            containerColor = if (success) MaterialTheme.colorScheme.secondaryContainer
            else if (error) MaterialTheme.colorScheme.errorContainer
            else MaterialTheme.colorScheme.tertiaryContainer,
        ),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(stringResource(policy.title), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(policy.message))
            val counts = result.counts
            if (counts.succeeded + counts.failed + counts.unknown > 0) {
                Text(
                    stringResource(
                        R.string.region_feedback_counts,
                        counts.succeeded,
                        counts.failed,
                        counts.unknown,
                    ),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (policy.canRefresh) {
                TextButton(onClick = onRefresh, modifier = Modifier.align(Alignment.End)) {
                    Text(stringResource(R.string.refresh_and_check_region_settings))
                }
            }
            if (refreshCompleted && policy.mustRefreshBeforeEditing) {
                Text(
                    stringResource(R.string.region_refresh_completed),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (!success && canContinueEditing) {
                TextButton(onClick = onContinueEditing, modifier = Modifier.align(Alignment.End)) {
                    Text(stringResource(R.string.continue_editing))
                }
            }
            TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
                Text(stringResource(if (success) R.string.done else R.string.discard_region_draft))
            }
        }
    }
}

@Composable
internal fun RegionMutationFailureCard(
    failure: DsmFailure,
    canContinueEditing: Boolean,
    onContinueEditing: () -> Unit,
    onDismiss: () -> Unit,
) {
    val localized = failure.localize(LocalContext.current)
    Card(
        modifier = Modifier.fillMaxWidth().padding(16.dp)
            .semantics { liveRegion = LiveRegionMode.Assertive },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                stringResource(R.string.file_service_feedback_failed_title),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(localized.combined)
            if (canContinueEditing) {
                TextButton(onClick = onContinueEditing, modifier = Modifier.align(Alignment.End)) {
                    Text(stringResource(R.string.continue_editing))
                }
            }
            TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
                Text(stringResource(R.string.discard_region_draft))
            }
        }
    }
}

@Composable
internal fun RegionSettingsDialog(
    baseline: NasRegionSettings,
    restoredDraft: NasRegionSettings?,
    onDraftChange: (NasRegionSettings) -> Unit,
    onSave: (NasRegionSettings) -> Unit,
    onDismiss: () -> Unit,
) {
    val initial = restoredDraft ?: baseline
    var dateFormat by rememberSaveable(baseline) { mutableStateOf(initial.dateFormat) }
    var timeFormat by rememberSaveable(baseline) { mutableStateOf(initial.timeFormat) }
    var timeZone by rememberSaveable(baseline) { mutableStateOf(initial.timeZone) }
    var networkTime by rememberSaveable(baseline) {
        mutableStateOf(initial.isNetworkTimeEnabled)
    }
    var servers by rememberSaveable(baseline) {
        mutableStateOf(initial.timeServers.joinToString("\n"))
    }
    val initialManual = initial.manualDateTime ?: baseline.manualDateTime
    var manualDate by rememberSaveable(baseline) {
        mutableStateOf(initialManual?.dateText().orEmpty())
    }
    var manualTime by rememberSaveable(baseline) {
        mutableStateOf(initialManual?.timeText().orEmpty())
    }
    var zonesExpanded by rememberSaveable { mutableStateOf(false) }
    val normalizedServers = servers.lines().map(String::trim).filter(String::isNotEmpty)
    val baselineManual = baseline.manualDateTime
    val manualWasEdited = manualDate != baselineManual?.dateText() ||
        manualTime != baselineManual?.timeText()
    val parsedManual = parseManualDateTime(manualDate, manualTime)
    val editedManual = if (!networkTime && manualWasEdited) parsedManual else null
    val manualValid = networkTime || !manualWasEdited || parsedManual != null
    val serversValid = !networkTime || normalizedServers.isNotEmpty() &&
        normalizedServers.size <= 3 && normalizedServers.distinct().size == normalizedServers.size &&
        normalizedServers.all(::isValidTimeServer)
    val dateFormatInvalid = dateFormat.isBlank()
    val timeFormatInvalid = timeFormat.isBlank()
    val draft = NasRegionSettings(
        dateFormat.trim(),
        timeFormat.trim(),
        timeZone,
        networkTime,
        normalizedServers,
        editedManual,
        baseline.timeZones,
    )
    val changed = draft.dateFormat != baseline.dateFormat ||
        draft.timeFormat != baseline.timeFormat || draft.timeZone != baseline.timeZone ||
        draft.isNetworkTimeEnabled != baseline.isNetworkTimeEnabled ||
        draft.timeServers != baseline.timeServers || editedManual != null
    val valid = !dateFormatInvalid && !timeFormatInvalid &&
        baseline.timeZones.any { it.id == timeZone } && serversValid && manualValid
    LaunchedEffect(draft) { onDraftChange(draft) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.region_and_time)) },
        text = {
            Column(
                Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedTextField(
                    dateFormat,
                    { dateFormat = it },
                    label = { Text(stringResource(R.string.date_format)) },
                    isError = dateFormatInvalid,
                    supportingText = if (dateFormatInvalid) {
                        { Text(stringResource(R.string.region_format_required)) }
                    } else null,
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    timeFormat,
                    { timeFormat = it },
                    label = { Text(stringResource(R.string.time_format)) },
                    isError = timeFormatInvalid,
                    supportingText = if (timeFormatInvalid) {
                        { Text(stringResource(R.string.region_format_required)) }
                    } else null,
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Box(Modifier.fillMaxWidth()) {
                    TextButton(
                        onClick = { zonesExpanded = true },
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    ) {
                        val selected = baseline.timeZones.firstOrNull { it.id == timeZone }
                        Text(stringResource(R.string.time_zone_value, selected?.displayName ?: timeZone))
                    }
                    DropdownMenu(
                        expanded = zonesExpanded,
                        onDismissRequest = { zonesExpanded = false },
                    ) {
                        baseline.timeZones.forEach { zone ->
                            DropdownMenuItem(
                                text = { Text(zone.displayName) },
                                onClick = {
                                    timeZone = zone.id
                                    zonesExpanded = false
                                },
                            )
                        }
                    }
                }
                RegionSettingsSwitch(R.string.use_network_time, networkTime) { networkTime = it }
                if (networkTime) {
                    OutlinedTextField(
                        servers,
                        { servers = it },
                        label = { Text(stringResource(R.string.time_servers)) },
                        supportingText = {
                            Text(
                                stringResource(
                                    if (serversValid) R.string.time_servers_hint
                                    else R.string.invalid_time_servers,
                                ),
                            )
                        },
                        isError = !serversValid,
                        minLines = 2,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                        modifier = Modifier.fillMaxWidth(),
                    )
                } else {
                    OutlinedTextField(
                        manualDate,
                        {
                            manualDate = it.filter { char -> char.isDigit() || char == '-' }.take(10)
                        },
                        label = { Text(stringResource(R.string.manual_date)) },
                        placeholder = { Text(stringResource(R.string.manual_date_placeholder)) },
                        isError = !manualValid,
                        supportingText = if (!manualValid) {
                            { Text(stringResource(R.string.invalid_manual_time)) }
                        } else null,
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        manualTime,
                        {
                            manualTime = it.filter { char -> char.isDigit() || char == ':' }.take(8)
                        },
                        label = { Text(stringResource(R.string.manual_time)) },
                        placeholder = { Text(stringResource(R.string.manual_time_placeholder)) },
                        isError = !manualValid,
                        supportingText = if (!manualValid) {
                            { Text(stringResource(R.string.invalid_manual_time)) }
                        } else null,
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                Text(
                    stringResource(R.string.region_time_impact_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = {
            TextButton(enabled = valid && changed, onClick = { onSave(draft) }) {
                Text(stringResource(R.string.continue_action))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        },
    )
}

@Composable
private fun RegionSettingsSwitch(@StringRes label: Int, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
            .toggleable(value = value, role = Role.Switch, onValueChange = onChange)
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(stringResource(label), modifier = Modifier.weight(1f))
        Switch(checked = value, onCheckedChange = null)
    }
}

private fun NasManualDateTime.dateText() = "%04d-%02d-%02d".format(year, month, day)
private fun NasManualDateTime.timeText() = "%02d:%02d:%02d".format(hour, minute, second)

private fun parseManualDateTime(date: String, time: String): NasManualDateTime? {
    if (!MANUAL_DATE_PATTERN.matches(date) || !MANUAL_TIME_PATTERN.matches(time)) return null
    val dateParts = date.split('-').mapNotNull(String::toIntOrNull)
    val timeParts = time.split(':').mapNotNull(String::toIntOrNull)
    if (dateParts.size != 3 || timeParts.size !in 2..3) return null
    val value = NasManualDateTime(
        dateParts[0],
        dateParts[1],
        dateParts[2],
        timeParts[0],
        timeParts[1],
        timeParts.getOrElse(2) { 0 },
    )
    if (value.hour !in 0..23 || value.minute !in 0..59 || value.second !in 0..59) return null
    return runCatching {
        GregorianCalendar().apply {
            clear()
            isLenient = false
            set(value.year, value.month - 1, value.day, value.hour, value.minute, value.second)
            time
        }
    }.getOrNull()?.let { value }
}

private fun isValidTimeServer(value: String): Boolean = value.isNotEmpty() && value.length <= 253 &&
    value.all { it.isLetterOrDigit() || it in ".-:" } &&
    !value.startsWith('.') && !value.endsWith('.') && ".." !in value

private val MANUAL_DATE_PATTERN = Regex("\\d{4}-\\d{2}-\\d{2}")
private val MANUAL_TIME_PATTERN = Regex("\\d{2}:\\d{2}(?::\\d{2})?")
