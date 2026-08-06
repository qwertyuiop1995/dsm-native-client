package io.github.qwertyuiop1995.dsmnativeclient.ui

import android.animation.ValueAnimator
import androidx.activity.BackEventCompat
import androidx.activity.compose.PredictiveBackHandler
import androidx.annotation.StringRes
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.PermanentDrawerSheet
import androidx.compose.material3.PermanentNavigationDrawer
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.WorkspaceState
import io.github.qwertyuiop1995.dsmnativeclient.chatUnreadCount
import io.github.qwertyuiop1995.dsmnativeclient.workspaceRouteStack
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.ModuleAvailability
import io.github.qwertyuiop1995.dsmnativeclient.domain.WorkspaceRouteStack
import io.github.qwertyuiop1995.dsmnativeclient.localization.messageResource
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal enum class WorkspaceBackAction {
    CLOSE_DRAWER,
    NAVIGATE_UP,
    EXIT,
}

internal fun workspaceBackAction(
    isExpanded: Boolean,
    isDrawerOpen: Boolean,
    routeStack: WorkspaceRouteStack,
): WorkspaceBackAction = when {
    !isExpanded && isDrawerOpen -> WorkspaceBackAction.CLOSE_DRAWER
    routeStack.entries.size > 1 -> WorkspaceBackAction.NAVIGATE_UP
    else -> WorkspaceBackAction.EXIT
}

internal fun predictiveBackVisualProgress(
    progress: Float,
    animationsEnabled: Boolean,
): Float = if (animationsEnabled) progress.coerceIn(0f, 1f) else 0f

internal fun predictiveBackDirection(swipeEdge: Int): Float =
    if (swipeEdge == BackEventCompat.EDGE_RIGHT) -1f else 1f

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun WorkspaceShell(
    state: WorkspaceState,
    onModuleSelected: (Module) -> Unit,
    onRefresh: () -> Unit,
    onNavigateUp: () -> Unit,
    onSwitchNas: () -> Unit = {},
    onLogout: () -> Unit,
    onMessageShown: () -> Unit,
    canCopyPageLink: Boolean = false,
    onCopyPageLink: () -> Unit = {},
    content: @Composable () -> Unit,
) {
    val drawerState = rememberDrawerState(DrawerValue.Closed)
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    val predictiveBackProgress = remember { Animatable(0f) }
    var predictiveBackSwipeEdge by remember { mutableIntStateOf(BackEventCompat.EDGE_LEFT) }

    LaunchedEffect(state.message) {
        state.message?.let {
            snackbar.showSnackbar(it)
            onMessageShown()
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val navigationType = AdaptiveLayoutPolicy.navigationType(maxWidth.value)
        val expanded = navigationType == AdaptiveNavigationType.PERMANENT_DRAWER
        val usesNavigationRail = navigationType == AdaptiveNavigationType.RAIL

        LaunchedEffect(navigationType) {
            if (expanded) {
                drawerState.snapTo(DrawerValue.Closed)
            }
        }
        val routeStack = state.workspaceRouteStack()
        val backAction = workspaceBackAction(
            isExpanded = expanded,
            isDrawerOpen = drawerState.isOpen,
            routeStack = routeStack,
        )

        PredictiveBackHandler(enabled = backAction != WorkspaceBackAction.EXIT) { backEvents ->
            try {
                backEvents.collect { event ->
                    predictiveBackSwipeEdge = event.swipeEdge
                    predictiveBackProgress.snapTo(
                        predictiveBackVisualProgress(
                            progress = event.progress,
                            animationsEnabled = ValueAnimator.areAnimatorsEnabled(),
                        ),
                    )
                }
                when (backAction) {
                    WorkspaceBackAction.CLOSE_DRAWER -> scope.launch { drawerState.close() }
                    WorkspaceBackAction.NAVIGATE_UP -> onNavigateUp()
                    WorkspaceBackAction.EXIT -> Unit
                }
                predictiveBackProgress.snapTo(0f)
            } catch (_: CancellationException) {
                withContext(NonCancellable) {
                    if (ValueAnimator.areAnimatorsEnabled()) {
                        predictiveBackProgress.animateTo(0f, animationSpec = tween(150))
                    } else {
                        predictiveBackProgress.snapTo(0f)
                    }
                }
            }
        }

        val workspaceContent: @Composable () -> Unit = {
            val processingDescription = stringResource(R.string.processing_action)
            Scaffold(
                contentWindowInsets = WindowInsets(0),
                topBar = {
                    TopAppBar(
                        title = {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Text(
                                    stringResource(state.selectedModule.titleResource()),
                                    style = MaterialTheme.typography.titleLarge,
                                    fontWeight = FontWeight.Bold,
                                )
                                Box(
                                    modifier = Modifier
                                        .clip(MaterialTheme.shapes.extraSmall)
                                        .background(MaterialTheme.colorScheme.primaryContainer)
                                        .padding(horizontal = 8.dp, vertical = 2.dp),
                                ) {
                                    Text(
                                        state.profile.name,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                                        fontWeight = FontWeight.Medium,
                                    )
                                }
                            }
                        },
                        navigationIcon = {
                            if (navigationType == AdaptiveNavigationType.BOTTOM_BAR) {
                                IconButton(onClick = { scope.launch { drawerState.open() } }) {
                                    Icon(
                                        Icons.Outlined.Menu,
                                        contentDescription = stringResource(R.string.open_navigation),
                                    )
                                }
                            }
                        },
                        actions = {
                            if (canCopyPageLink) {
                                IconButton(
                                    onClick = onCopyPageLink,
                                    modifier = Modifier.size(48.dp),
                                ) {
                                    Icon(
                                        Icons.Outlined.Link,
                                        contentDescription = stringResource(R.string.copy_page_link),
                                    )
                                }
                            }
                            IconButton(onClick = onRefresh) {
                                Icon(
                                    Icons.Outlined.Refresh,
                                    contentDescription = stringResource(R.string.refresh),
                                )
                            }
                        },
                        colors = TopAppBarDefaults.topAppBarColors(
                            containerColor = MaterialTheme.colorScheme.surfaceContainer,
                        ),
                        modifier = Modifier.statusBarsPadding(),
                    )
                },
                snackbarHost = {
                    SnackbarHost(
                        snackbar,
                        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                    )
                },
                bottomBar = {
                    if (navigationType == AdaptiveNavigationType.BOTTOM_BAR) {
                        NavigationBar(
                            modifier = Modifier.testTag(WORKSPACE_BOTTOM_NAVIGATION_TEST_TAG),
                        ) {
                            PRIMARY_MOBILE_MODULES.forEach { module ->
                                val unreadCount = if (module == Module.CHAT) {
                                    chatUnreadCount(state.conversations)
                                } else 0
                                val unavailableResource = state.availability
                                    .firstOrNull { it.module == module }
                                    .navigationStatusResource()
                                val navigationStateDescription = unavailableResource?.let {
                                    stringResource(it)
                                } ?: unreadCount.takeIf { it > 0 }?.let {
                                    pluralStringResource(R.plurals.unread_count, it, it)
                                }
                                NavigationBarItem(
                                    selected = state.selectedModule == module,
                                    onClick = { onModuleSelected(module) },
                                    icon = {
                                        BadgedBox(
                                            badge = {
                                                if (unreadCount > 0) Badge {
                                                    Text(unreadCount.coerceAtMost(99).toString())
                                                }
                                            },
                                        ) {
                                            Icon(module.icon(), contentDescription = null)
                                        }
                                    },
                                    label = {
                                        Text(stringResource(module.titleResource()))
                                    },
                                    modifier = Modifier.semantics {
                                        navigationStateDescription?.let { description ->
                                            stateDescription = description
                                        }
                                    },
                                )
                            }
                        }
                    }
                },
            ) { padding ->
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .navigationBarsPadding()
                        .graphicsLayer {
                            val progress = if (backAction == WorkspaceBackAction.NAVIGATE_UP) {
                                predictiveBackProgress.value
                            } else {
                                0f
                            }
                            translationX = progress *
                                predictiveBackDirection(predictiveBackSwipeEdge) *
                                32.dp.toPx()
                            alpha = 1f - (progress * 0.08f)
                        },
                ) {
                    content()
                    if (state.isPerformingAction) {
                        LinearProgressIndicator(
                            modifier = Modifier
                                .fillMaxWidth()
                                .align(Alignment.TopCenter)
                                .semantics { contentDescription = processingDescription },
                        )
                    }
                }
            }
        }

        val adaptiveWorkspaceContent: @Composable () -> Unit = {
            if (usesNavigationRail) {
                Row(Modifier.fillMaxSize()) {
                    WorkspaceNavigationRail(
                        state = state,
                        onOpenDrawer = { scope.launch { drawerState.open() } },
                        onModuleSelected = onModuleSelected,
                    )
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight(),
                    ) {
                        workspaceContent()
                    }
                }
            } else {
                workspaceContent()
            }
        }

        if (expanded) {
            PermanentNavigationDrawer(
                drawerContent = {
                    PermanentDrawerSheet(
                        drawerContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                        modifier = Modifier.width(280.dp),
                    ) {
                        WorkspaceDrawer(
                            state = state,
                            onModuleSelected = onModuleSelected,
                            onSwitchNas = onSwitchNas,
                            onLogout = onLogout,
                        )
                    }
                },
                content = adaptiveWorkspaceContent,
            )
        } else {
            ModalNavigationDrawer(
                drawerState = drawerState,
                drawerContent = {
                    ModalDrawerSheet(
                        drawerContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                        modifier = Modifier.testTag(WORKSPACE_MODAL_DRAWER_TEST_TAG),
                    ) {
                        WorkspaceDrawer(
                            state = state,
                            onModuleSelected = {
                                onModuleSelected(it)
                                scope.launch { drawerState.close() }
                            },
                            onSwitchNas = onSwitchNas,
                            onLogout = onLogout,
                        )
                    }
                },
                content = adaptiveWorkspaceContent,
            )
        }
    }
}

internal const val WORKSPACE_NAVIGATION_RAIL_TEST_TAG = "workspace_navigation_rail"
internal const val WORKSPACE_BOTTOM_NAVIGATION_TEST_TAG = "workspace_bottom_navigation"
internal const val WORKSPACE_MODAL_DRAWER_TEST_TAG = "workspace_modal_drawer"

private val PRIMARY_MOBILE_MODULES = listOf(
    Module.FILES,
    Module.PHOTOS,
    Module.CHAT,
    Module.DOWNLOADS,
    Module.TRANSFERS,
)

@Composable
private fun WorkspaceNavigationRail(
    state: WorkspaceState,
    onOpenDrawer: () -> Unit,
    onModuleSelected: (Module) -> Unit,
) {
    NavigationRail(
        header = {
            IconButton(onClick = onOpenDrawer) {
                Icon(
                    Icons.Outlined.Menu,
                    contentDescription = stringResource(R.string.open_navigation),
                )
            }
        },
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
        modifier = Modifier
            .fillMaxHeight()
            .statusBarsPadding()
            .navigationBarsPadding()
            .testTag(WORKSPACE_NAVIGATION_RAIL_TEST_TAG),
    ) {
        PRIMARY_MOBILE_MODULES.forEach { module ->
            val unreadCount = if (module == Module.CHAT) {
                chatUnreadCount(state.conversations)
            } else 0
            val unavailableResource = state.availability
                .firstOrNull { it.module == module }
                .navigationStatusResource()
            val navigationStateDescription = unavailableResource?.let {
                stringResource(it)
            } ?: unreadCount.takeIf { it > 0 }?.let {
                pluralStringResource(R.plurals.unread_count, it, it)
            }
            NavigationRailItem(
                selected = state.selectedModule == module,
                onClick = { onModuleSelected(module) },
                icon = {
                    BadgedBox(
                        badge = {
                            if (unreadCount > 0) Badge {
                                Text(unreadCount.coerceAtMost(99).toString())
                            }
                        },
                    ) {
                        if (unavailableResource != null) {
                            Icon(
                                module.icon(),
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.outline,
                            )
                        } else {
                            Icon(module.icon(), contentDescription = null)
                        }
                    }
                },
                label = { Text(stringResource(module.titleResource())) },
                alwaysShowLabel = true,
                modifier = Modifier.semantics {
                    navigationStateDescription?.let { description ->
                        stateDescription = description
                    }
                },
            )
        }
    }
}

@Composable
private fun WorkspaceDrawer(
    state: WorkspaceState,
    onModuleSelected: (Module) -> Unit,
    onSwitchNas: () -> Unit,
    onLogout: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxHeight()
            .width(280.dp)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 14.dp, vertical = 12.dp),
    ) {
        Card(
            shape = MaterialTheme.shapes.medium,
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.6f),
            ),
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 12.dp),
        ) {
            Row(
                modifier = Modifier.padding(14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(MaterialTheme.colorScheme.primary),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Outlined.Storage,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onPrimary,
                        modifier = Modifier.size(24.dp),
                    )
                }
                Column {
                    Text(
                        stringResource(R.string.app_name),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                    Text(
                        state.profile.name,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f),
                    )
                }
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
        Spacer(Modifier.height(10.dp))
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.weight(1f),
        ) {
            items(Module.entries, key = Module::name) { module ->
                val availability = state.availability.firstOrNull { it.module == module }
                val unavailableReasonResource = availability.navigationStatusResource()
                val isSelected = state.selectedModule == module
                val unreadCount = if (module == Module.CHAT) {
                    chatUnreadCount(state.conversations)
                } else 0
                val navigationStateDescription = unavailableReasonResource?.let {
                    stringResource(it)
                } ?: unreadCount.takeIf { it > 0 }?.let {
                    pluralStringResource(R.plurals.unread_count, it, it)
                }
                NavigationDrawerItem(
                    label = {
                        Row(
                            verticalAlignment = Alignment.Top,
                            horizontalArrangement = Arrangement.SpaceBetween,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Column(
                                verticalArrangement = Arrangement.spacedBy(2.dp),
                                modifier = Modifier.weight(1f),
                            ) {
                                Text(
                                    stringResource(module.titleResource()),
                                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
                                )
                                unavailableReasonResource?.let { reasonResource ->
                                    Text(
                                        stringResource(reasonResource),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                            if (unavailableReasonResource == null && unreadCount > 0) {
                                Badge {
                                    Text(unreadCount.coerceAtMost(99).toString())
                                }
                            }
                        }
                    },
                    icon = {
                        Icon(
                            module.icon(),
                            contentDescription = null,
                            tint = if (unavailableReasonResource != null) {
                                MaterialTheme.colorScheme.outline
                            } else if (isSelected) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                    },
                    selected = isSelected,
                    onClick = { onModuleSelected(module) },
                    shape = MaterialTheme.shapes.medium,
                    colors = NavigationDrawerItemDefaults.colors(
                        selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                        selectedIconColor = MaterialTheme.colorScheme.primary,
                        selectedTextColor = MaterialTheme.colorScheme.onPrimaryContainer,
                        unselectedContainerColor = Color.Transparent,
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics {
                            navigationStateDescription?.let { description ->
                                stateDescription = description
                            }
                        },
                )
            }
        }
        HorizontalDivider(
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
            modifier = Modifier.padding(vertical = 8.dp),
        )
        Text(
            stringResource(R.string.switch_nas_description),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
        )
        OutlinedButton(
            onClick = onSwitchNas,
            enabled = !state.isPerformingAction,
            shape = MaterialTheme.shapes.medium,
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp),
        ) {
            Icon(
                Icons.Outlined.Storage,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(8.dp))
            Text(
                stringResource(R.string.switch_nas),
                fontWeight = FontWeight.Medium,
            )
        }
        HorizontalDivider(
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
            modifier = Modifier.padding(vertical = 8.dp),
        )
        OutlinedButton(
            onClick = onLogout,
            enabled = !state.isPerformingAction,
            shape = MaterialTheme.shapes.medium,
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp),
        ) {
            Icon(
                Icons.AutoMirrored.Outlined.Logout,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.error,
            )
            Spacer(Modifier.width(8.dp))
            Text(
                stringResource(R.string.sign_out_description),
                color = MaterialTheme.colorScheme.error,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

@StringRes
internal fun ModuleAvailability?.navigationStatusResource(): Int? = when {
    this?.isAvailable != false -> null
    reason != null -> reason.messageResource()
    else -> R.string.unavailable
}

@StringRes
internal fun Module.titleResource(): Int = when (this) {
    Module.FILES -> R.string.module_files
    Module.PHOTOS -> R.string.module_photos
    Module.CHAT -> R.string.module_chat
    Module.DOWNLOADS -> R.string.module_downloads
    Module.CONTAINERS -> R.string.module_containers
    Module.VIRTUAL_MACHINES -> R.string.module_virtual_machines
    Module.NAS_SETTINGS -> R.string.module_nas_settings
    Module.TRANSFERS -> R.string.module_transfers
    Module.SETTINGS -> R.string.module_settings
}

internal fun Module.icon(): ImageVector = when (this) {
    Module.FILES -> Icons.Outlined.Folder
    Module.PHOTOS -> Icons.Outlined.PhotoLibrary
    Module.CHAT -> Icons.Outlined.ChatBubbleOutline
    Module.DOWNLOADS -> Icons.Outlined.CloudDownload
    Module.CONTAINERS -> Icons.Outlined.Dns
    Module.VIRTUAL_MACHINES -> Icons.Outlined.Computer
    Module.NAS_SETTINGS -> Icons.Outlined.Storage
    Module.TRANSFERS -> Icons.Outlined.SwapVert
    Module.SETTINGS -> Icons.Outlined.Settings
}
