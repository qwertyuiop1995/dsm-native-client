package io.github.qwertyuiop1995.dsmnativeclient.ui.downloads

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.annotation.StringRes
import io.github.qwertyuiop1995.dsmnativeclient.AppViewModel
import io.github.qwertyuiop1995.dsmnativeclient.DownloadRssRefreshVerification
import io.github.qwertyuiop1995.dsmnativeclient.DownloadRssRefreshWorkspaceState
import io.github.qwertyuiop1995.dsmnativeclient.DownloadCreationSourceKind
import io.github.qwertyuiop1995.dsmnativeclient.Loadable
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.WorkspaceState
import io.github.qwertyuiop1995.dsmnativeclient.canSubmitDownloadBtSearch
import io.github.qwertyuiop1995.dsmnativeclient.canDismissDownloadRssRefreshMutation
import io.github.qwertyuiop1995.dsmnativeclient.downloadRssRefreshRequiresReadback
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchCatalog
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchDirection
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchModuleScope
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchOptions
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchSort
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadDiscoveryTab
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadRssFeed
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadRssSite
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.localization.localize
import io.github.qwertyuiop1995.dsmnativeclient.ui.EmptyState
import io.github.qwertyuiop1995.dsmnativeclient.ui.LoadableContent
import io.github.qwertyuiop1995.dsmnativeclient.ui.formatBytes
import java.text.DateFormat
import java.util.Date

internal data class DownloadRssRefreshFeedbackPolicy(
    @StringRes val title: Int,
    @StringRes val message: Int,
)

internal fun downloadRssRefreshFeedbackPolicy(
    result: MutationResult,
): DownloadRssRefreshFeedbackPolicy = when (result.status) {
    MutationResultStatus.CONFIRMED_SUCCESS -> DownloadRssRefreshFeedbackPolicy(
        R.string.download_rss_refresh_confirmed_title,
        R.string.download_rss_refresh_confirmed_message,
    )
    MutationResultStatus.PARTIAL_SUCCESS -> DownloadRssRefreshFeedbackPolicy(
        R.string.download_rss_refresh_partial_title,
        R.string.download_rss_refresh_partial_message,
    )
    MutationResultStatus.SUBMITTED_BUT_UNVERIFIED -> DownloadRssRefreshFeedbackPolicy(
        R.string.download_rss_refresh_check_title,
        R.string.download_rss_refresh_unverified_message,
    )
    MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION -> DownloadRssRefreshFeedbackPolicy(
        R.string.download_rss_refresh_check_title,
        R.string.download_rss_refresh_cancel_after_submission_message,
    )
    MutationResultStatus.PERMISSION_DENIED -> DownloadRssRefreshFeedbackPolicy(
        R.string.download_rss_refresh_permission_title,
        R.string.download_rss_refresh_permission_message,
    )
    MutationResultStatus.UNSUPPORTED -> DownloadRssRefreshFeedbackPolicy(
        R.string.download_rss_refresh_unavailable_title,
        R.string.download_rss_refresh_unsupported_message,
    )
    MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> DownloadRssRefreshFeedbackPolicy(
        R.string.download_rss_refresh_cancelled_title,
        R.string.download_rss_refresh_cancelled_message,
    )
    MutationResultStatus.CONFIRMED_FAILURE -> DownloadRssRefreshFeedbackPolicy(
        if (result.errorCategory == MutationErrorCategory.CONFLICT) {
            R.string.download_rss_refresh_conflict_title
        } else R.string.download_rss_refresh_failed_title,
        if (result.errorCategory == MutationErrorCategory.CONFLICT) {
            R.string.download_rss_refresh_conflict_message
        } else R.string.download_rss_refresh_failed_message,
    )
}

@StringRes
internal fun DownloadRssRefreshVerification.messageResource(): Int = when (this) {
    DownloadRssRefreshVerification.MATCHES -> R.string.download_rss_refresh_verification_matches
    DownloadRssRefreshVerification.DIFFERS -> R.string.download_rss_refresh_verification_differs
    DownloadRssRefreshVerification.DISAPPEARED -> R.string.download_rss_refresh_verification_disappeared
    DownloadRssRefreshVerification.UNAVAILABLE -> R.string.download_rss_refresh_verification_unavailable
}

@Composable
internal fun DownloadDiscoveryDialog(
    state: WorkspaceState,
    model: AppViewModel,
    canCreateTask: Boolean,
    onCreateTask: (title: String, uri: String, sourceKind: DownloadCreationSourceKind) -> Unit,
    onDismiss: () -> Unit,
    onSelectTab: (DownloadDiscoveryTab) -> Unit = model::selectDownloadDiscoveryTab,
) {
    val tabs = buildList {
        if (state.supportsDownloadRss) add(DownloadDiscoveryTab.RSS)
        if (state.supportsDownloadBtSearch) add(DownloadDiscoveryTab.BT_SEARCH)
    }
    val selectedTab = tabs.indexOf(state.downloadAdvancedRead.discoveryTab).takeIf { it >= 0 } ?: 0
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.download_discovery)) },
        text = {
            Column(Modifier.fillMaxWidth().height(520.dp)) {
                if (tabs.isEmpty()) {
                    EmptyState(
                        stringResource(R.string.download_discovery),
                        stringResource(R.string.download_discovery_unavailable),
                        Icons.Outlined.Info,
                    )
                    return@Column
                }
                ScrollableTabRow(selectedTabIndex = selectedTab, edgePadding = 0.dp) {
                    tabs.forEachIndexed { index, tab ->
                        Tab(
                            selected = selectedTab == index,
                            onClick = { onSelectTab(tab) },
                            text = {
                                Text(
                                    stringResource(
                                        if (tab == DownloadDiscoveryTab.RSS) {
                                            R.string.download_discovery_rss
                                        } else {
                                            R.string.download_discovery_bt_search
                                        },
                                    ),
                                )
                            },
                        )
                    }
                }
                when (tabs[selectedTab.coerceIn(0, tabs.lastIndex)]) {
                    DownloadDiscoveryTab.RSS -> DownloadRssContent(
                        state = state,
                        model = model,
                        canCreateTask = canCreateTask,
                        onCreateTask = onCreateTask,
                    )
                    DownloadDiscoveryTab.BT_SEARCH -> DownloadBtSearchContent(
                        state = state,
                        model = model,
                        canCreateTask = canCreateTask,
                        onCreateTask = onCreateTask,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.close)) }
        },
    )
}

@Composable
private fun DownloadRssContent(
    state: WorkspaceState,
    model: AppViewModel,
    canCreateTask: Boolean,
    onCreateTask: (String, String, DownloadCreationSourceKind) -> Unit,
) {
    val selected = state.selectedDownloadRssSite
    if (selected == null) {
        LoadableContent(
            value = state.downloadRssSites,
            emptyTitle = stringResource(R.string.download_rss_sites_empty),
            emptyMessage = stringResource(R.string.download_rss_sites_empty_description),
            onRetry = model::loadDownloadRssSites,
        ) { sites -> DownloadRssSiteList(sites, model::selectDownloadRssSite) }
        return
    }
    val refreshState = state.downloadRssRefreshState
    val ownsRefreshResult = refreshState.target?.siteId == selected.id
    val refreshing = ownsRefreshResult &&
        (refreshState.mutationInProgress || refreshState.mutationRefreshInProgress) || selected.isUpdating
    Column {
        TextButton(onClick = model::loadDownloadRssSites) {
            Text(stringResource(R.string.download_rss_back_to_sites))
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                selected.title,
                modifier = Modifier.weight(1f),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.width(8.dp))
            TextButton(
                onClick = model::refreshSelectedDownloadRssSite,
                enabled = !refreshing && !ownsRefreshResult,
                modifier = Modifier.heightIn(min = 48.dp),
            ) {
                if (refreshing) {
                    CircularProgressIndicator(Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                }
                Text(
                    stringResource(
                        if (refreshing) R.string.download_rss_updating
                        else R.string.download_rss_refresh,
                    ),
                )
            }
        }
        if (refreshState.target?.siteId == selected.id) {
            DownloadRssRefreshMutationFeedback(
                state = refreshState,
                onRecheck = model::recheckDownloadRssRefresh,
                onDismiss = { model.dismissDownloadRssRefreshMutation() },
            )
        }
        LoadableContent(
            value = state.downloadRssFeeds,
            emptyTitle = stringResource(R.string.download_rss_feeds_empty),
            emptyMessage = stringResource(R.string.download_rss_feeds_empty_description),
            onRetry = { model.selectDownloadRssSite(selected) },
        ) { feeds ->
            DownloadRssFeedList(
                feeds = feeds,
                canCreateTask = canCreateTask,
                onCreateTask = onCreateTask,
            )
        }
    }
}

@Composable
internal fun DownloadRssRefreshMutationFeedback(
    state: DownloadRssRefreshWorkspaceState,
    onRecheck: () -> Unit,
    onDismiss: () -> Unit,
) {
    val result = state.mutationResult
    val policy = result?.let(::downloadRssRefreshFeedbackPolicy)
    val busy = state.mutationInProgress || state.mutationRefreshInProgress
    val canDismiss = canDismissDownloadRssRefreshMutation(state)
    val canRecheck = !busy && downloadRssRefreshRequiresReadback(state)
    val context = LocalContext.current
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
        ) {
            if (busy) {
                Text(
                    stringResource(
                        if (state.mutationInProgress) {
                            R.string.download_rss_refresh_in_progress_title
                        } else R.string.download_rss_refresh_checking_title,
                    ),
                    style = MaterialTheme.typography.titleMedium,
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(
                        if (state.mutationInProgress) {
                            R.string.download_rss_refresh_in_progress_message
                        } else R.string.download_rss_refresh_checking_message,
                    ),
                )
                Spacer(Modifier.height(8.dp))
                LinearProgressIndicator(Modifier.fillMaxWidth())
            } else {
                Column(Modifier.semantics { liveRegion = LiveRegionMode.Assertive }) {
                    Text(
                        when {
                            state.mutationFailure != null -> stringResource(R.string.download_rss_refresh_failed_title)
                            state.mutationRefreshFailure != null -> stringResource(R.string.download_rss_refresh_check_failed_title)
                            else -> stringResource(checkNotNull(policy).title)
                        },
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Spacer(Modifier.height(8.dp))
                    when {
                        state.mutationFailure != null -> Text(state.mutationFailure.localize(context).combined)
                        state.mutationRefreshFailure != null -> Text(
                            state.mutationRefreshFailure.localize(context).combined,
                        )
                        policy != null -> Text(stringResource(policy.message))
                    }
                    result?.counts?.let { counts ->
                        Spacer(Modifier.height(8.dp))
                        Text(
                            stringResource(
                                R.string.download_rss_refresh_counts,
                                counts.succeeded,
                                counts.failed,
                                counts.unknown,
                            ),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    state.mutationVerification?.let { verification ->
                        Spacer(Modifier.height(8.dp))
                        Text(
                            stringResource(verification.messageResource()),
                        )
                    }
                }
            }
            if (canRecheck || canDismiss) {
                Spacer(Modifier.height(8.dp))
                Column(Modifier.fillMaxWidth()) {
                    if (canRecheck) {
                        TextButton(
                            onClick = onRecheck,
                            modifier = Modifier.heightIn(min = 48.dp),
                        ) { Text(stringResource(R.string.download_rss_refresh_recheck)) }
                    }
                    if (canRecheck && canDismiss) Spacer(Modifier.height(4.dp))
                    if (canDismiss) {
                        Button(
                            onClick = onDismiss,
                            modifier = Modifier.heightIn(min = 48.dp),
                        ) { Text(stringResource(R.string.download_rss_refresh_close_checked)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun DownloadRssSiteList(
    sites: List<DownloadRssSite>,
    onSelect: (DownloadRssSite) -> Unit,
) {
    LazyColumn {
        itemsIndexed(sites, key = { index, site -> "$index:${site.id}" }) { _, site ->
            ListItem(
                headlineContent = {
                    Text(site.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                },
                supportingContent = {
                    Text(
                        when {
                            site.isUpdating -> stringResource(R.string.download_rss_updating)
                            site.lastUpdatedAtEpochSeconds != null -> stringResource(
                                R.string.download_rss_last_updated,
                                DateFormat.getDateTimeInstance().format(
                                    Date(site.lastUpdatedAtEpochSeconds * 1_000),
                                ),
                            )
                            else -> stringResource(R.string.download_rss_choose_site)
                        },
                    )
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .clickable { onSelect(site) },
            )
            HorizontalDivider()
        }
    }
}

@Composable
private fun DownloadRssFeedList(
    feeds: List<DownloadRssFeed>,
    canCreateTask: Boolean,
    onCreateTask: (String, String, DownloadCreationSourceKind) -> Unit,
) {
    LazyColumn {
        itemsIndexed(feeds, key = { index, _ -> index }) { _, feed ->
            ListItem(
                headlineContent = {
                    Text(feed.title, maxLines = 2, overflow = TextOverflow.Ellipsis)
                },
                supportingContent = {
                    Text(
                        listOfNotNull(
                            feed.size?.let(::formatBytes),
                            feed.publishedAtEpochSeconds?.let {
                                DateFormat.getDateTimeInstance().format(Date(it * 1_000))
                            },
                        ).joinToString(" · "),
                    )
                },
                trailingContent = {
                    DiscoveryDownloadButton(
                        enabled = canCreateTask,
                        onClick = {
                            onCreateTask(
                                feed.title,
                                feed.downloadUri,
                                DownloadCreationSourceKind.RSS,
                            )
                        },
                    )
                },
            )
            HorizontalDivider()
        }
    }
}

@Composable
private fun DownloadBtSearchContent(
    state: WorkspaceState,
    model: AppViewModel,
    canCreateTask: Boolean,
    onCreateTask: (String, String, DownloadCreationSourceKind) -> Unit,
) {
    val options = state.downloadAdvancedRead.btSearchOptions
    val catalog = state.downloadAdvancedRead.btSearchCatalog
    val canSearch = canSubmitDownloadBtSearch(
        catalog,
        options,
        state.downloadAdvancedRead.btSearchResults,
    )
    Column {
        Row(Modifier.fillMaxWidth().padding(12.dp)) {
            OutlinedTextField(
                value = options.keyword,
                onValueChange = {
                    if (it.length <= 200) {
                        model.updateDownloadBtSearchOptions(options.copy(keyword = it))
                    }
                },
                label = { Text(stringResource(R.string.download_bt_keyword)) },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(8.dp))
            Button(
                onClick = model::searchDownloadBt,
                enabled = canSearch,
                modifier = Modifier.heightIn(min = 48.dp),
            ) {
                Icon(Icons.Outlined.Search, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.download_bt_search_action))
            }
        }
        DownloadBtSearchOptionsContent(
            catalog = catalog,
            options = options,
            expanded = state.downloadAdvancedRead.btAdvancedOptionsVisible,
            onToggleExpanded = model::toggleDownloadBtAdvancedOptions,
            onRetry = model::loadDownloadBtSearchCatalog,
            onOptionsChanged = model::updateDownloadBtSearchOptions,
        )
        when (state.downloadAdvancedRead.btSearchResults) {
            Loadable.Idle -> EmptyState(
                stringResource(R.string.download_discovery_bt_search),
                stringResource(R.string.download_bt_search_hint),
                Icons.Outlined.Search,
            )
            else -> LoadableContent(
                value = state.downloadAdvancedRead.btSearchResults,
                emptyTitle = stringResource(R.string.download_bt_search_empty),
                emptyMessage = stringResource(R.string.download_bt_search_empty_description),
                onRetry = model::searchDownloadBt,
            ) { results ->
                DownloadBtResultList(
                    results = results,
                    canCreateTask = canCreateTask,
                    onCreateTask = onCreateTask,
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DownloadBtSearchOptionsContent(
    catalog: Loadable<DownloadBtSearchCatalog>,
    options: DownloadBtSearchOptions,
    expanded: Boolean,
    onToggleExpanded: () -> Unit,
    onRetry: () -> Unit,
    onOptionsChanged: (DownloadBtSearchOptions) -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp)) {
        TextButton(
            onClick = onToggleExpanded,
            enabled = catalog is Loadable.Ready,
            modifier = Modifier.heightIn(min = 48.dp),
        ) {
            Text(
                stringResource(
                    if (expanded) R.string.download_bt_hide_options
                    else R.string.download_bt_show_options,
                ),
            )
        }
        when (catalog) {
            Loadable.Idle, Loadable.Loading -> {
                Text(stringResource(R.string.download_bt_options_loading))
                LinearProgressIndicator(Modifier.fillMaxWidth().padding(vertical = 8.dp))
            }
            is Loadable.Failed -> Column(
                Modifier.semantics { liveRegion = LiveRegionMode.Assertive },
            ) {
                Text(stringResource(R.string.download_bt_options_failed))
                TextButton(
                    onClick = onRetry,
                    modifier = Modifier.heightIn(min = 48.dp),
                ) { Text(stringResource(R.string.retry)) }
            }
            is Loadable.Ready -> {
                if (catalog.value.modules.isEmpty()) {
                    Text(stringResource(R.string.download_bt_options_empty))
                } else if (expanded) {
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(max = 240.dp)
                            .verticalScroll(rememberScrollState()),
                    ) {
                        DownloadBtOptionLabel(R.string.download_bt_provider_scope)
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            DownloadBtSearchModuleScope.entries.forEach { scope ->
                                FilterChip(
                                    selected = options.moduleScope == scope,
                                    onClick = {
                                        onOptionsChanged(
                                            options.copy(
                                                moduleScope = scope,
                                                selectedModuleIds = if (
                                                    scope == DownloadBtSearchModuleScope.SELECTED
                                                ) options.selectedModuleIds else emptySet(),
                                            ),
                                        )
                                    },
                                    label = { Text(stringResource(scope.labelResource())) },
                                    modifier = Modifier.heightIn(min = 48.dp),
                                )
                            }
                        }
                        if (options.moduleScope == DownloadBtSearchModuleScope.SELECTED) {
                            DownloadBtOptionLabel(R.string.download_bt_specific_providers)
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                catalog.value.modules.forEach { module ->
                                    val selected = module.id in options.selectedModuleIds
                                    FilterChip(
                                        selected = selected,
                                        onClick = {
                                            onOptionsChanged(
                                                options.copy(
                                                    selectedModuleIds = if (selected) {
                                                        options.selectedModuleIds - module.id
                                                    } else {
                                                        options.selectedModuleIds + module.id
                                                    },
                                                ),
                                            )
                                        },
                                        label = {
                                            Text(
                                                if (module.enabled) module.title else stringResource(
                                                    R.string.download_bt_provider_disabled,
                                                    module.title,
                                                ),
                                            )
                                        },
                                        modifier = Modifier.heightIn(min = 48.dp),
                                    )
                                }
                            }
                        }
                        DownloadBtOptionLabel(R.string.download_bt_category)
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            FilterChip(
                                selected = options.categoryId == null,
                                onClick = { onOptionsChanged(options.copy(categoryId = null)) },
                                label = { Text(stringResource(R.string.download_bt_all_categories)) },
                                modifier = Modifier.heightIn(min = 48.dp),
                            )
                            catalog.value.categories
                                .filterNot { it.id == "_allcat_" }
                                .forEach { category ->
                                    FilterChip(
                                        selected = options.categoryId == category.id,
                                        onClick = {
                                            onOptionsChanged(options.copy(categoryId = category.id))
                                        },
                                        label = { Text(category.title) },
                                        modifier = Modifier.heightIn(min = 48.dp),
                                    )
                                }
                        }
                        DownloadBtOptionLabel(R.string.download_bt_sort)
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            DownloadBtSearchSort.entries.forEach { sort ->
                                FilterChip(
                                    selected = options.sort == sort,
                                    onClick = { onOptionsChanged(options.copy(sort = sort)) },
                                    label = { Text(stringResource(sort.labelResource())) },
                                    modifier = Modifier.heightIn(min = 48.dp),
                                )
                            }
                        }
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            DownloadBtSearchDirection.entries.forEach { direction ->
                                FilterChip(
                                    selected = options.direction == direction,
                                    onClick = {
                                        onOptionsChanged(options.copy(direction = direction))
                                    },
                                    label = { Text(stringResource(direction.labelResource())) },
                                    modifier = Modifier.heightIn(min = 48.dp),
                                )
                            }
                        }
                        OutlinedTextField(
                            value = options.titleFilter,
                            onValueChange = {
                                if (it.length <= 200) {
                                    onOptionsChanged(options.copy(titleFilter = it))
                                }
                            },
                            label = { Text(stringResource(R.string.download_bt_title_filter)) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DownloadBtOptionLabel(@StringRes resource: Int) {
    Text(
        stringResource(resource),
        style = MaterialTheme.typography.labelLarge,
        modifier = Modifier.padding(top = 8.dp),
    )
}

@StringRes
private fun DownloadBtSearchModuleScope.labelResource(): Int = when (this) {
    DownloadBtSearchModuleScope.ALL -> R.string.download_bt_scope_all
    DownloadBtSearchModuleScope.ENABLED -> R.string.download_bt_scope_enabled
    DownloadBtSearchModuleScope.SELECTED -> R.string.download_bt_scope_selected
}

@StringRes
private fun DownloadBtSearchSort.labelResource(): Int = when (this) {
    DownloadBtSearchSort.TITLE -> R.string.download_bt_sort_title
    DownloadBtSearchSort.SIZE -> R.string.download_bt_sort_size
    DownloadBtSearchSort.DATE -> R.string.download_bt_sort_date
    DownloadBtSearchSort.PEERS -> R.string.download_bt_sort_peers
    DownloadBtSearchSort.PROVIDER -> R.string.download_bt_sort_provider
    DownloadBtSearchSort.SEEDS -> R.string.download_bt_sort_seeds
    DownloadBtSearchSort.LEECHES -> R.string.download_bt_sort_leeches
}

@StringRes
private fun DownloadBtSearchDirection.labelResource(): Int = when (this) {
    DownloadBtSearchDirection.ASCENDING -> R.string.download_bt_sort_ascending
    DownloadBtSearchDirection.DESCENDING -> R.string.download_bt_sort_descending
}

@Composable
private fun DownloadBtResultList(
    results: List<DownloadBtSearchResult>,
    canCreateTask: Boolean,
    onCreateTask: (String, String, DownloadCreationSourceKind) -> Unit,
) {
    LazyColumn {
        itemsIndexed(results, key = { index, _ -> index }) { _, result ->
            ListItem(
                headlineContent = {
                    Text(result.title, maxLines = 2, overflow = TextOverflow.Ellipsis)
                },
                supportingContent = {
                    Column {
                        result.provider?.takeIf(String::isNotBlank)?.let {
                            Text(stringResource(R.string.download_bt_provider, it))
                        }
                        Text(
                            listOfNotNull(
                                result.size?.let(::formatBytes),
                                if (result.seeds != null && result.peers != null) {
                                    stringResource(
                                        R.string.download_bt_seeds_peers,
                                        result.seeds,
                                        result.peers,
                                    )
                                } else {
                                    null
                                },
                                result.listedAt,
                            ).joinToString(" · "),
                        )
                    }
                },
                trailingContent = {
                    DiscoveryDownloadButton(
                        enabled = canCreateTask,
                        onClick = {
                            onCreateTask(
                                result.title,
                                result.downloadUri,
                                DownloadCreationSourceKind.BT_SEARCH,
                            )
                        },
                    )
                },
            )
            HorizontalDivider()
        }
    }
}

@Composable
private fun DiscoveryDownloadButton(enabled: Boolean, onClick: () -> Unit) {
    IconButton(onClick = onClick, enabled = enabled) {
        Icon(
            Icons.Outlined.Download,
            contentDescription = stringResource(R.string.download_discovery_create_task),
        )
    }
}
