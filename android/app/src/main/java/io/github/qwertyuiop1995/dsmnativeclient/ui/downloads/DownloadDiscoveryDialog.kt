package io.github.qwertyuiop1995.dsmnativeclient.ui.downloads

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.AppViewModel
import io.github.qwertyuiop1995.dsmnativeclient.DownloadCreationSourceKind
import io.github.qwertyuiop1995.dsmnativeclient.Loadable
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.WorkspaceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadRssFeed
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadRssSite
import io.github.qwertyuiop1995.dsmnativeclient.ui.EmptyState
import io.github.qwertyuiop1995.dsmnativeclient.ui.LoadableContent
import io.github.qwertyuiop1995.dsmnativeclient.ui.formatBytes
import java.text.DateFormat
import java.util.Date

private enum class DiscoveryTab { RSS, BT_SEARCH }

@Composable
internal fun DownloadDiscoveryDialog(
    state: WorkspaceState,
    model: AppViewModel,
    canCreateTask: Boolean,
    onCreateTask: (title: String, uri: String, sourceKind: DownloadCreationSourceKind) -> Unit,
    onDismiss: () -> Unit,
) {
    val tabs = buildList {
        if (state.supportsDownloadRss) add(DiscoveryTab.RSS)
        if (state.supportsDownloadBtSearch) add(DiscoveryTab.BT_SEARCH)
    }
    var selectedTab by rememberSaveable { mutableIntStateOf(0) }
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
                            onClick = { selectedTab = index },
                            text = {
                                Text(
                                    stringResource(
                                        if (tab == DiscoveryTab.RSS) {
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
                    DiscoveryTab.RSS -> DownloadRssContent(
                        state = state,
                        model = model,
                        canCreateTask = canCreateTask,
                        onCreateTask = onCreateTask,
                    )
                    DiscoveryTab.BT_SEARCH -> DownloadBtSearchContent(
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
    val refreshing = state.downloadRssRefreshInProgressSiteId == selected.id || selected.isUpdating
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
                enabled = !refreshing,
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
        state.downloadRssRefreshFeedback?.let { feedback ->
            Text(
                feedback,
                modifier = Modifier
                    .padding(horizontal = 16.dp, vertical = 4.dp)
                    .semantics { liveRegion = LiveRegionMode.Polite },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
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
                modifier = Modifier.clickable { onSelect(site) },
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
    var keyword by rememberSaveable { mutableStateOf("") }
    Column {
        Row(Modifier.fillMaxWidth().padding(12.dp)) {
            OutlinedTextField(
                value = keyword,
                onValueChange = { if (it.length <= 200) keyword = it },
                label = { Text(stringResource(R.string.download_bt_keyword)) },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(8.dp))
            Button(
                onClick = { model.searchDownloadBt(keyword) },
                enabled = keyword.isNotBlank() && state.downloadBtSearchResults !is Loadable.Loading,
            ) {
                Icon(Icons.Outlined.Search, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.download_bt_search_action))
            }
        }
        when (state.downloadBtSearchResults) {
            Loadable.Idle -> EmptyState(
                stringResource(R.string.download_discovery_bt_search),
                stringResource(R.string.download_bt_search_hint),
                Icons.Outlined.Search,
            )
            else -> LoadableContent(
                value = state.downloadBtSearchResults,
                emptyTitle = stringResource(R.string.download_bt_search_empty),
                emptyMessage = stringResource(R.string.download_bt_search_empty_description),
                onRetry = { model.searchDownloadBt(keyword) },
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
