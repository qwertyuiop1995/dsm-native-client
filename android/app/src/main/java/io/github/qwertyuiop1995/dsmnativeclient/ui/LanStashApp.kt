package io.github.qwertyuiop1995.dsmnativeclient.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image as FoundationImage
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AdminPanelSettings
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.HourglassTop
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.InsertDriveFile
import androidx.compose.material.icons.outlined.ListAlt
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.NetworkCheck
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.PermanentDrawerSheet
import androidx.compose.material3.PermanentNavigationDrawer
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDrawerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.DrawerValue
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.annotation.StringRes
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import io.github.qwertyuiop1995.dsmnativeclient.AppViewModel
import io.github.qwertyuiop1995.dsmnativeclient.Loadable
import io.github.qwertyuiop1995.dsmnativeclient.LoginState
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.WorkspaceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.ContainerOverview
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.LogEntry
import io.github.qwertyuiop1995.dsmnativeclient.domain.LogLevel
import io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResource
import io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResourceLabel
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineOverview
import io.github.qwertyuiop1995.dsmnativeclient.network.ConnectionStatus
import io.github.qwertyuiop1995.dsmnativeclient.localization.localize
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

@Composable
fun LanStashApp(model: AppViewModel) {
    val login by model.login.collectAsStateWithLifecycle()
    val workspace by model.workspace.collectAsStateWithLifecycle()
    if (workspace == null) {
        LoginScreen(login, model)
    } else {
        WorkspaceScreen(workspace!!, model)
    }
}

@Composable
private fun LoginScreen(state: LoginState, model: AppViewModel) {
    val selectedProfileId = state.selectedProfileId
    val selectedProfile = state.profiles.firstOrNull { it.id == selectedProfileId }
    var name by rememberSaveable(selectedProfileId) { mutableStateOf(selectedProfile?.name.orEmpty()) }
    var address by rememberSaveable(selectedProfileId) { mutableStateOf(selectedProfile?.address.orEmpty()) }
    var port by rememberSaveable(selectedProfileId) {
        mutableStateOf(selectedProfile?.port?.toString().orEmpty())
    }
    var username by rememberSaveable(selectedProfileId) {
        mutableStateOf(selectedProfile?.username.orEmpty())
    }
    var password by rememberSaveable(selectedProfileId) { mutableStateOf(state.savedPassword) }
    var otp by rememberSaveable { mutableStateOf("") }
    var rememberPassword by rememberSaveable(selectedProfileId) {
        mutableStateOf(state.rememberPassword)
    }
    var autoLoginEnabled by rememberSaveable(selectedProfileId) {
        mutableStateOf(state.autoLoginEnabled)
    }
    var profileToRemove by remember { mutableStateOf<NasProfile?>(null) }
    val focusManager = LocalFocusManager.current
    val localizedLoginError = state.error?.localize(LocalContext.current)?.combined

    LaunchedEffect(selectedProfileId, state.savedPassword) {
        password = state.savedPassword
        rememberPassword = state.rememberPassword
        autoLoginEnabled = state.autoLoginEnabled
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val wide = maxWidth >= 768.dp
            val loginWidth = if (wide) 460.dp else maxWidth
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = if (wide) 48.dp else 20.dp, vertical = 24.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (wide) {
                    Column(
                        modifier = Modifier.width(320.dp),
                        verticalArrangement = Arrangement.spacedBy(20.dp),
                    ) {
                        BrandHeader(large = true)
                        if (state.profiles.isNotEmpty()) {
                            Text(
                                stringResource(R.string.saved_nas_devices),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.semantics { heading() },
                            )
                            LazyColumn(
                                verticalArrangement = Arrangement.spacedBy(10.dp),
                                modifier = Modifier.weight(1f, fill = false),
                            ) {
                                items(state.profiles, key = NasProfile::id) { profile ->
                                    SavedProfileCard(
                                        profile = profile,
                                        selected = profile.id == selectedProfileId,
                                        onSelect = { model.selectProfile(profile) },
                                        onConnect = { model.restore(profile) },
                                        onRemove = { profileToRemove = profile },
                                    )
                                }
                            }
                        }
                    }
                    Spacer(Modifier.width(56.dp))
                }
                LoginForm(
                    modifier = Modifier.width(loginWidth),
                    showBrand = !wide,
                    name = name,
                    address = address,
                    port = port,
                    username = username,
                    password = password,
                    otp = otp,
                    rememberPassword = rememberPassword,
                    autoLoginEnabled = autoLoginEnabled,
                    needsOtp = state.needsOtp,
                    isConnecting = state.isConnecting,
                    connectionStatus = state.connectionStatus,
                    error = localizedLoginError,
                    onName = { name = it },
                    onAddress = { address = it },
                    onPort = { port = it.filter(Char::isDigit) },
                    onUsername = { username = it },
                    onPassword = { password = it },
                    onOtp = { otp = it.filter(Char::isDigit) },
                    onRememberPassword = {
                        rememberPassword = it
                        if (!it) autoLoginEnabled = false
                    },
                    onAutoLogin = {
                        autoLoginEnabled = it
                        if (it) rememberPassword = true
                    },
                    onConnect = {
                        focusManager.clearFocus()
                        model.connect(
                            selectedProfileId,
                            name,
                            address,
                            port,
                            username,
                            password,
                            otp,
                            rememberPassword,
                            autoLoginEnabled,
                        )
                    },
                )
            }
        }
        LanguageMenu(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(8.dp),
        )
    }

    profileToRemove?.let { profile ->
        ConfirmDialog(
            title = stringResource(R.string.remove_profile_title, profile.name),
            message = stringResource(R.string.remove_profile_message),
            confirm = stringResource(R.string.remove),
            destructive = true,
            onConfirm = {
                model.removeProfile(profile)
                profileToRemove = null
            },
            onDismiss = { profileToRemove = null },
        )
    }
}

@Composable
private fun BrandHeader(large: Boolean = false) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        FoundationImage(
            painter = painterResource(R.drawable.brand_logo),
            contentDescription = null,
            modifier = Modifier
                .size(if (large) 68.dp else 56.dp)
                .clip(RoundedCornerShape(if (large) 20.dp else 16.dp)),
        )
        Column {
            Text(
                stringResource(R.string.app_name),
                style = if (large) MaterialTheme.typography.headlineLarge else MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Text(
                stringResource(R.string.brand_tagline),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

@Composable
private fun LoginForm(
    modifier: Modifier,
    showBrand: Boolean,
    name: String,
    address: String,
    port: String,
    username: String,
    password: String,
    otp: String,
    rememberPassword: Boolean,
    autoLoginEnabled: Boolean,
    needsOtp: Boolean,
    isConnecting: Boolean,
    connectionStatus: ConnectionStatus?,
    error: String?,
    onName: (String) -> Unit,
    onAddress: (String) -> Unit,
    onPort: (String) -> Unit,
    onUsername: (String) -> Unit,
    onPassword: (String) -> Unit,
    onOtp: (String) -> Unit,
    onRememberPassword: (Boolean) -> Unit,
    onAutoLogin: (Boolean) -> Unit,
    onConnect: () -> Unit,
) {
    var showsAdvancedSettings by rememberSaveable { mutableStateOf(false) }
    Card(
        modifier = modifier,
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .imePadding()
                .padding(horizontal = 24.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (showBrand) {
                BrandHeader()
                Spacer(Modifier.height(4.dp))
            }
            Text(
                stringResource(R.string.connect_synology_nas),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.semantics { heading() },
            )
            OutlinedTextField(
                value = name,
                onValueChange = onName,
                label = { Text(stringResource(R.string.display_name)) },
                singleLine = true,
                shape = MaterialTheme.shapes.small,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = address,
                onValueChange = onAddress,
                label = { Text(stringResource(R.string.nas_address_or_quickconnect)) },
                supportingText = {
                    Text(stringResource(R.string.nas_address_example))
                },
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Uri,
                    imeAction = ImeAction.Next,
                ),
                singleLine = true,
                shape = MaterialTheme.shapes.small,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = username,
                onValueChange = onUsername,
                label = { Text(stringResource(R.string.account)) },
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                singleLine = true,
                shape = MaterialTheme.shapes.small,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = password,
                onValueChange = onPassword,
                label = { Text(stringResource(R.string.password)) },
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = if (needsOtp) ImeAction.Next else ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(onDone = { onConnect() }),
                singleLine = true,
                shape = MaterialTheme.shapes.small,
                modifier = Modifier.fillMaxWidth(),
            )
            if (needsOtp || otp.isNotEmpty()) {
                OutlinedTextField(
                    value = otp,
                    onValueChange = onOtp,
                    label = { Text(stringResource(R.string.two_factor_code)) },
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.NumberPassword,
                        imeAction = ImeAction.Done,
                    ),
                    keyboardActions = KeyboardActions(onDone = { onConnect() }),
                    singleLine = true,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // 封装漂亮的控制开关卡片
            Card(
                shape = MaterialTheme.shapes.medium,
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                ),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(MaterialTheme.shapes.small)
                            .clickable(role = Role.Switch) { onRememberPassword(!rememberPassword) }
                            .padding(horizontal = 8.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Switch(checked = rememberPassword, onCheckedChange = onRememberPassword)
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text(stringResource(R.string.remember_password), fontWeight = FontWeight.Medium)
                            Text(
                                stringResource(R.string.password_keystore_note),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(MaterialTheme.shapes.small)
                            .clickable(role = Role.Switch) { onAutoLogin(!autoLoginEnabled) }
                            .padding(horizontal = 8.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Switch(checked = autoLoginEnabled, onCheckedChange = onAutoLogin)
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text(stringResource(R.string.auto_login), fontWeight = FontWeight.Medium)
                            Text(
                                stringResource(R.string.auto_login_note),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            TextButton(
                onClick = { showsAdvancedSettings = !showsAdvancedSettings },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Outlined.Tune, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(if (showsAdvancedSettings) stringResource(R.string.collapse_advanced_connection_settings) else stringResource(R.string.advanced_connection_settings))
            }
            if (showsAdvancedSettings) {
                OutlinedTextField(
                    value = port,
                    onValueChange = onPort,
                    label = { Text(stringResource(R.string.custom_https_port)) },
                    supportingText = { Text(stringResource(R.string.custom_https_port_note)) },
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Number,
                        imeAction = ImeAction.Next,
                    ),
                    singleLine = true,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            error?.let { ErrorBanner(it) }
            if (isConnecting && connectionStatus != null) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.padding(vertical = 4.dp),
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Text(
                        connectionStatus.displayText(),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.semantics {
                            liveRegion = LiveRegionMode.Polite
                        },
                    )
                }
            }
            Button(
                onClick = onConnect,
                enabled = !isConnecting,
                shape = MaterialTheme.shapes.medium,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
            ) {
                if (isConnecting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                    Spacer(Modifier.width(10.dp))
                }
                Text(
                    if (isConnecting) stringResource(R.string.connecting) else stringResource(R.string.connect),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }
}

@Composable
private fun ConnectionStatus.displayText(): String = stringResource(
    when (this) {
        ConnectionStatus.PREPARING -> R.string.status_preparing_connection
        ConnectionStatus.CONNECTING_DIRECT -> R.string.status_connecting_nas
        ConnectionStatus.LOOKING_UP_QUICK_CONNECT -> R.string.status_looking_up_quickconnect
        ConnectionStatus.TRYING_LOCAL -> R.string.status_trying_local
        ConnectionStatus.TRYING_EXTERNAL -> R.string.status_trying_external
        ConnectionStatus.ESTABLISHING_RELAY -> R.string.status_establishing_relay
        ConnectionStatus.RESTORING_SESSION -> R.string.status_restoring_session
    }
)

@Composable
private fun SavedProfileCard(
    profile: NasProfile,
    selected: Boolean,
    onSelect: () -> Unit,
    onConnect: () -> Unit,
    onRemove: () -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.medium)
            .clickable(onClick = onSelect),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = if (selected) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                MaterialTheme.colorScheme.surfaceContainer
            }
        ),
        border = if (selected) {
            androidx.compose.foundation.BorderStroke(1.5.dp, MaterialTheme.colorScheme.primary)
        } else null,
    ) {
        Row(
            modifier = Modifier.padding(start = 16.dp, top = 12.dp, bottom = 12.dp, end = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(
                        if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                        else MaterialTheme.colorScheme.surfaceContainerHigh
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Outlined.Storage,
                    contentDescription = null,
                    tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(22.dp),
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    profile.name,
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    profile.username,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (selected) MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f) else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = onConnect) {
                Icon(
                    Icons.Outlined.PlayArrow,
                    contentDescription = stringResource(R.string.connect_saved_login),
                    tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = onRemove) {
                Icon(
                    Icons.Outlined.DeleteOutline,
                    contentDescription = stringResource(R.string.remove_saved_nas),
                    tint = MaterialTheme.colorScheme.error.copy(alpha = 0.8f),
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WorkspaceScreen(state: WorkspaceState, model: AppViewModel) {
    val drawerState = rememberDrawerState(DrawerValue.Closed)
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(state.message) {
        state.message?.let {
            snackbar.showSnackbar(it)
            model.clearMessage()
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val expanded = maxWidth >= 840.dp
        val content: @Composable () -> Unit = {
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
                            if (!expanded) {
                                IconButton(onClick = { scope.launch { drawerState.open() } }) {
                                    Icon(Icons.Outlined.Menu, contentDescription = stringResource(R.string.open_navigation))
                                }
                            }
                        },
                        actions = {
                            IconButton(onClick = { model.load() }) {
                                Icon(Icons.Outlined.Refresh, contentDescription = stringResource(R.string.refresh))
                            }
                        },
                        colors = TopAppBarDefaults.topAppBarColors(
                            containerColor = MaterialTheme.colorScheme.surfaceContainer,
                        ),
                        modifier = Modifier.statusBarsPadding(),
                    )
                },
                snackbarHost = { SnackbarHost(snackbar) },
            ) { padding ->
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .navigationBarsPadding(),
                ) {
                    ModuleContent(state, model)
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
        if (expanded) {
            PermanentNavigationDrawer(
                drawerContent = {
                    PermanentDrawerSheet(
                        drawerContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                        modifier = Modifier.width(280.dp),
                    ) {
                        DrawerContent(state, model)
                    }
                },
                content = content,
            )
        } else {
            ModalNavigationDrawer(
                drawerState = drawerState,
                drawerContent = {
                    ModalDrawerSheet(
                        drawerContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                    ) {
                        DrawerContent(
                            state,
                            model,
                            onSelected = { scope.launch { drawerState.close() } },
                        )
                    }
                },
                content = content,
            )
        }
    }
}

@Composable
private fun DrawerContent(
    state: WorkspaceState,
    model: AppViewModel,
    onSelected: () -> Unit = {},
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
                val isSelected = state.selectedModule == module
                NavigationDrawerItem(
                    label = {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(
                                stringResource(module.titleResource()),
                                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
                            )
                            if (availability?.isAvailable == false) {
                                Text(
                                    stringResource(R.string.unavailable),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.outline,
                                )
                            }
                        }
                    },
                    icon = {
                        Icon(
                            module.icon(),
                            contentDescription = null,
                            tint = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    selected = isSelected,
                    onClick = {
                        model.select(module)
                        onSelected()
                    },
                    shape = MaterialTheme.shapes.medium,
                    colors = androidx.compose.material3.NavigationDrawerItemDefaults.colors(
                        selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                        selectedIconColor = MaterialTheme.colorScheme.primary,
                        selectedTextColor = MaterialTheme.colorScheme.onPrimaryContainer,
                        unselectedContainerColor = Color.Transparent,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        HorizontalDivider(
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
            modifier = Modifier.padding(vertical = 8.dp),
        )
        OutlinedButton(
            onClick = model::logout,
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
            Text(stringResource(R.string.sign_out_description), color = MaterialTheme.colorScheme.error, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
private fun ModuleContent(state: WorkspaceState, model: AppViewModel) {
    when (state.selectedModule) {
        Module.FILES -> FileBrowser(state, model)
        Module.PHOTOS -> PhotosScreen(state, model)
        Module.CHAT -> ChatScreen(state, model)
        Module.DOWNLOADS -> DownloadsScreen(state, model)
        Module.CONTAINERS -> ContainersScreen(state, model)
        Module.VIRTUAL_MACHINES -> VirtualMachinesScreen(state, model)
        Module.NAS_SETTINGS -> NasSettingsScreen(state, model)
        Module.TRANSFERS -> TransfersScreen(state)
        Module.SETTINGS -> SettingsScreen(state)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FileBrowser(state: WorkspaceState, model: AppViewModel) {
    var query by rememberSaveable { mutableStateOf("") }
    var showCreate by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<FileItem?>(null) }
    var rename by remember { mutableStateOf<FileItem?>(null) }
    var delete by remember { mutableStateOf<FileItem?>(null) }
    Scaffold(
        contentWindowInsets = WindowInsets(0),
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { showCreate = true },
                icon = { Icon(Icons.Outlined.Add, null) },
                text = { Text(stringResource(R.string.new_folder), fontWeight = FontWeight.SemiBold) },
                shape = MaterialTheme.shapes.medium,
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding)) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (state.pathHistory.isNotEmpty()) {
                    IconButton(
                        onClick = model::goBackDirectory,
                        modifier = Modifier
                            .clip(MaterialTheme.shapes.small)
                            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
                    ) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.go_up))
                    }
                }
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    placeholder = { Text(stringResource(R.string.search_files)) },
                    leadingIcon = { Icon(Icons.Outlined.Search, null, tint = MaterialTheme.colorScheme.primary) },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { model.searchFiles(query) }),
                    singleLine = true,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.weight(1f),
                )
            }
            if (state.path.isNotBlank()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 4.dp)
                        .clip(MaterialTheme.shapes.extraSmall)
                        .background(MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.6f))
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                ) {
                    Text(
                        state.path,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            LoadableContent(
                value = state.files,
                emptyTitle = stringResource(R.string.directory_empty),
                emptyMessage = stringResource(R.string.empty_folder_description),
                onRetry = { model.load(Module.FILES) },
            ) { page ->
                LazyColumn(
                    contentPadding = PaddingValues(bottom = 96.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(page.items, key = FileItem::path) { item ->
                        ListItem(
                            headlineContent = {
                                Text(
                                    item.name,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    fontWeight = FontWeight.Medium,
                                )
                            },
                            supportingContent = {
                                Text(
                                    if (item.isDirectory) stringResource(R.string.folder) else formatBytes(item.size),
                                    maxLines = 1,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            },
                            leadingContent = {
                                Box(
                                    modifier = Modifier
                                        .size(40.dp)
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(
                                            if (item.isDirectory) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.7f)
                                            else MaterialTheme.colorScheme.surfaceContainerHigh
                                        ),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(
                                        if (item.isDirectory) Icons.Outlined.Folder else Icons.Outlined.InsertDriveFile,
                                        contentDescription = null,
                                        tint = if (item.isDirectory) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.size(22.dp),
                                    )
                                }
                            },
                            trailingContent = {
                                IconButton(onClick = { selected = item }) {
                                    Icon(Icons.Outlined.MoreVert, contentDescription = stringResource(R.string.more_actions))
                                }
                            },
                            modifier = Modifier.combinedClickable(
                                onClick = { if (item.isDirectory) model.openDirectory(item) else selected = item },
                                onLongClick = { selected = item },
                            ),
                        )
                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f),
                            modifier = Modifier.padding(start = 72.dp),
                        )
                    }
                }
            }
        }
    }
    selected?.let { item ->
        AlertDialog(
            onDismissRequest = { selected = null },
            title = { Text(item.name) },
            text = {
                Column {
                    if (item.isDirectory) {
                        ActionRow(Icons.Outlined.FolderOpen, stringResource(R.string.open)) {
                            model.openDirectory(item)
                            selected = null
                        }
                    }
                    ActionRow(Icons.Outlined.Edit, stringResource(R.string.rename)) {
                        rename = item
                        selected = null
                    }
                    ActionRow(Icons.Outlined.DeleteOutline, stringResource(R.string.delete), destructive = true) {
                        delete = item
                        selected = null
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { selected = null }) { Text(stringResource(R.string.close)) }
            },
        )
    }
    if (showCreate) {
        TextInputDialog(
            title = stringResource(R.string.new_folder),
            label = stringResource(R.string.folder_name),
            confirm = stringResource(R.string.create),
            onConfirm = {
                model.createFolder(it)
                showCreate = false
            },
            onDismiss = { showCreate = false },
        )
    }
    rename?.let { item ->
        TextInputDialog(
            title = stringResource(R.string.rename),
            label = stringResource(R.string.new_name),
            initial = item.name,
            confirm = stringResource(R.string.save),
            onConfirm = {
                model.renameFile(item, it)
                rename = null
            },
            onDismiss = { rename = null },
        )
    }
    delete?.let { item ->
        ConfirmDialog(
            title = stringResource(R.string.delete_named_item, item.name),
            message = stringResource(R.string.delete_recycle_note),
            confirm = stringResource(R.string.delete),
            destructive = true,
            onConfirm = {
                model.deleteFiles(listOf(item))
                delete = null
            },
            onDismiss = { delete = null },
        )
    }
}

@Composable
private fun PhotosScreen(state: WorkspaceState, model: AppViewModel) {
    LoadableContent(
        value = state.files,
        emptyTitle = stringResource(R.string.no_photos),
        emptyMessage = stringResource(R.string.no_media_in_folder),
        onRetry = { model.load(Module.PHOTOS) },
    ) { page ->
        val media = page.items.filter {
            !it.isDirectory && it.extension in setOf(
                "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "mov", "mp4"
            )
        }
        if (media.isEmpty()) {
            EmptyState(stringResource(R.string.no_photos), stringResource(R.string.no_photos_description), Icons.Outlined.PhotoLibrary)
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(132.dp),
                contentPadding = PaddingValues(12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(media, key = FileItem::path) { item ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(150.dp),
                    ) {
                        Box(Modifier.fillMaxSize()) {
                            Icon(
                                Icons.Outlined.Image,
                                contentDescription = null,
                                modifier = Modifier
                                    .size(48.dp)
                                    .align(Alignment.Center),
                                tint = MaterialTheme.colorScheme.primary,
                            )
                            Text(
                                item.name,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .align(Alignment.BottomCenter)
                                    .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))
                                    .padding(8.dp),
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                style = MaterialTheme.typography.labelMedium,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ChatScreen(state: WorkspaceState, model: AppViewModel) {
    LoadableContent(
        value = state.conversations,
        emptyTitle = stringResource(R.string.no_conversations),
        emptyMessage = stringResource(R.string.no_conversations_description),
        onRetry = { model.load(Module.CHAT) },
    ) { conversations ->
        LazyColumn {
            items(conversations, key = { it.id }) { conversation ->
                ListItem(
                    headlineContent = {
                        Text(conversation.title.ifBlank { stringResource(R.string.unnamed_conversation) })
                    },
                    supportingContent = {
                        Text(
                            conversation.latestPreview ?: pluralStringResource(
                                R.plurals.member_count,
                                conversation.memberCount,
                                conversation.memberCount,
                            ),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    },
                    leadingContent = {
                        Icon(Icons.Outlined.ChatBubbleOutline, contentDescription = null)
                    },
                    trailingContent = {
                        if (conversation.unreadCount > 0) {
                            AssistChip(
                                onClick = {},
                                label = { Text(conversation.unreadCount.toString()) },
                            )
                        }
                    },
                )
                HorizontalDivider(Modifier.padding(start = 72.dp))
            }
        }
    }
}

@Composable
private fun DownloadsScreen(state: WorkspaceState, model: AppViewModel) {
    var create by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<DownloadTask?>(null) }
    Scaffold(
        contentWindowInsets = WindowInsets(0),
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { create = true },
                icon = { Icon(Icons.Outlined.Add, null) },
                text = { Text(stringResource(R.string.add_download)) },
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding)) {
            LoadableContent(
                value = state.downloads,
                emptyTitle = stringResource(R.string.no_download_tasks),
                emptyMessage = stringResource(R.string.add_download_description),
                onRetry = { model.load(Module.DOWNLOADS) },
            ) { tasks ->
                LazyColumn(contentPadding = PaddingValues(bottom = 96.dp)) {
                    items(tasks, key = DownloadTask::id) { task ->
                        ListItem(
                            headlineContent = {
                                Text(
                                    task.title.ifBlank { stringResource(R.string.unnamed_download) },
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            },
                            supportingContent = {
                                Column {
                                    Text(task.status.displayName())
                                    val total = task.size
                                    val transferred = task.transferred
                                    if (total != null && total > 0 && transferred != null) {
                                        LinearProgressIndicator(
                                            progress = {
                                                (transferred.toFloat() / total.toFloat()).coerceIn(0f, 1f)
                                            },
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .padding(top = 6.dp),
                                        )
                                    }
                                }
                            },
                            leadingContent = {
                                StatusIcon(task.status)
                            },
                            trailingContent = {
                                IconButton(onClick = { selected = task }) {
                                    Icon(
                                        Icons.Outlined.MoreVert,
                                        contentDescription = stringResource(R.string.task_actions),
                                    )
                                }
                            },
                        )
                        HorizontalDivider(Modifier.padding(start = 72.dp))
                    }
                }
            }
        }
    }
    if (create) {
        DownloadDialog(
            onConfirm = { uri, destination ->
                model.createDownload(uri, destination)
                create = false
            },
            onDismiss = { create = false },
        )
    }
    selected?.let { task ->
        AlertDialog(
            onDismissRequest = { selected = null },
            title = { Text(task.title) },
            text = {
                Column {
                    ActionRow(Icons.Outlined.Pause, stringResource(R.string.pause)) {
                        model.controlDownloads(listOf(task.id), "pause")
                        selected = null
                    }
                    ActionRow(Icons.Outlined.PlayArrow, stringResource(R.string.resume)) {
                        model.controlDownloads(listOf(task.id), "resume")
                        selected = null
                    }
                    ActionRow(Icons.Outlined.DeleteOutline, stringResource(R.string.remove_task), destructive = true) {
                        model.controlDownloads(listOf(task.id), "delete")
                        selected = null
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { selected = null }) {
                    Text(stringResource(R.string.close))
                }
            },
        )
    }
}

@Composable
private fun ContainersScreen(state: WorkspaceState, model: AppViewModel) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var selected by remember { mutableStateOf<ManagedResource?>(null) }
    var confirmDelete by remember { mutableStateOf<Pair<Int, ManagedResource>?>(null) }
    var createNetwork by remember { mutableStateOf(false) }
    val titles = listOf(stringResource(R.string.containers), stringResource(R.string.images), stringResource(R.string.networks), stringResource(R.string.projects))
    Column {
        ScrollableTabRow(selectedTabIndex = tab, edgePadding = 12.dp) {
            titles.forEachIndexed { index, title ->
                Tab(
                    selected = tab == index,
                    onClick = { tab = index },
                    text = { Text(title) },
                )
            }
        }
        LoadableContent(
            value = state.containers,
            emptyTitle = stringResource(R.string.no_items),
            emptyMessage = stringResource(R.string.no_category_items),
            onRetry = { model.load(Module.CONTAINERS) },
        ) { overview ->
            val resources = when (tab) {
                0 -> overview.containers
                1 -> overview.images
                2 -> overview.networks
                else -> overview.projects
            }
            ResourceList(
                resources = resources,
                emptyTitle = stringResource(R.string.no_named_items, titles[tab]),
                onSelect = { selected = it },
                headerAction = if (tab == 2) {
                    {
                        FilledTonalButton(onClick = { createNetwork = true }) {
                            Icon(Icons.Outlined.Add, null)
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.new_network))
                        }
                    }
                } else null,
            )
        }
    }
    selected?.let { resource ->
        AlertDialog(
            onDismissRequest = { selected = null },
            title = { Text(resource.name) },
            text = {
                Column {
                    if (tab == 0) {
                        ActionRow(Icons.Outlined.PlayArrow, stringResource(R.string.start)) {
                            model.controlContainer(resource.id, "start")
                            selected = null
                        }
                        ActionRow(Icons.Outlined.Pause, stringResource(R.string.stop)) {
                            model.controlContainer(resource.id, "stop")
                            selected = null
                        }
                    }
                    if (tab in 0..2) {
                        ActionRow(Icons.Outlined.DeleteOutline, stringResource(R.string.delete), destructive = true) {
                            confirmDelete = tab to resource
                            selected = null
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { selected = null }) {
                    Text(stringResource(R.string.close))
                }
            },
        )
    }
    confirmDelete?.let { (kind, resource) ->
        ConfirmDialog(
            title = stringResource(R.string.delete_named_item, resource.name),
            message = when (kind) {
                0 -> stringResource(R.string.delete_container_message)
                1 -> stringResource(R.string.image_in_use_message)
                else -> stringResource(R.string.delete_network_confirmation)
            },
            confirm = stringResource(R.string.delete),
            destructive = true,
            onConfirm = {
                when (kind) {
                    0 -> model.deleteContainer(resource.id)
                    1 -> model.deleteContainerImage(resource.id)
                    2 -> model.deleteContainerNetwork(resource.id)
                }
                confirmDelete = null
            },
            onDismiss = { confirmDelete = null },
        )
    }
    if (createNetwork) {
        TextInputDialog(
            title = stringResource(R.string.create_container_network),
            label = stringResource(R.string.network_name),
            confirm = stringResource(R.string.create),
            onConfirm = {
                model.createContainerNetwork(it, "bridge")
                createNetwork = false
            },
            onDismiss = { createNetwork = false },
        )
    }
}

@Composable
private fun VirtualMachinesScreen(state: WorkspaceState, model: AppViewModel) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var protectionTab by rememberSaveable { mutableIntStateOf(0) }
    var selected by remember { mutableStateOf<ManagedResource?>(null) }
    var pendingDelete by remember { mutableStateOf<Pair<Int, ManagedResource>?>(null) }
    var editNetwork by remember { mutableStateOf<ManagedResource?>(null) }
    val titles = listOf(stringResource(R.string.virtual_machines), stringResource(R.string.hosts), stringResource(R.string.storage), stringResource(R.string.networks), stringResource(R.string.images), stringResource(R.string.protection), stringResource(R.string.logs))
    Column {
        ScrollableTabRow(selectedTabIndex = tab, edgePadding = 12.dp) {
            titles.forEachIndexed { index, title ->
                Tab(selected = tab == index, onClick = { tab = index }, text = { Text(title) })
            }
        }
        LoadableContent(
            value = state.virtualMachines,
            emptyTitle = stringResource(R.string.no_items),
            emptyMessage = stringResource(R.string.no_category_items),
            onRetry = { model.load(Module.VIRTUAL_MACHINES) },
        ) { overview ->
            when (tab) {
                5 -> ProtectionContent(overview, protectionTab) { protectionTab = it }
                6 -> LogList(overview.logs)
                else -> {
                    val resources = overview.forTab(tab)
                    ResourceList(
                        resources,
                        stringResource(R.string.no_named_items, titles[tab]),
                        onSelect = { selected = it },
                    )
                }
            }
        }
    }
    selected?.let { resource ->
        AlertDialog(
            onDismissRequest = { selected = null },
            title = { Text(resource.name) },
            text = {
                Column {
                    if (tab == 0) {
                        ActionRow(Icons.Outlined.PlayArrow, stringResource(R.string.start)) {
                            model.controlVirtualMachine(resource.id, "poweron")
                            selected = null
                        }
                        ActionRow(Icons.Outlined.Pause, stringResource(R.string.normal_shutdown)) {
                            model.controlVirtualMachine(resource.id, "shutdown")
                            selected = null
                        }
                    }
                    if (tab == 3) {
                        ActionRow(Icons.Outlined.Edit, stringResource(R.string.edit_name)) {
                            editNetwork = resource
                            selected = null
                        }
                    }
                    if (tab == 0 || tab == 3 || tab == 4) {
                        ActionRow(Icons.Outlined.DeleteOutline, stringResource(R.string.delete), destructive = true) {
                            pendingDelete = tab to resource
                            selected = null
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { selected = null }) {
                    Text(stringResource(R.string.close))
                }
            },
        )
    }
    editNetwork?.let { resource ->
        TextInputDialog(
            title = stringResource(R.string.modify_network),
            label = stringResource(R.string.network_name),
            initial = resource.name,
            confirm = stringResource(R.string.save),
            onConfirm = {
                model.renameVirtualMachineNetwork(resource.id, it)
                editNetwork = null
            },
            onDismiss = { editNetwork = null },
        )
    }
    pendingDelete?.let { (kind, resource) ->
        ConfirmDialog(
            title = stringResource(R.string.delete_named_item, resource.name),
            message = when (kind) {
                0 -> stringResource(R.string.delete_virtual_machine_message)
                3 -> stringResource(R.string.delete_network_message)
                else -> stringResource(R.string.delete_image_message)
            },
            confirm = stringResource(R.string.delete),
            destructive = true,
            onConfirm = {
                when (kind) {
                    0 -> model.deleteVirtualMachine(resource.id)
                    3 -> model.deleteVirtualMachineNetwork(resource.id)
                    4 -> model.deleteVirtualMachineImage(resource.id)
                }
                pendingDelete = null
            },
            onDismiss = { pendingDelete = null },
        )
    }
}

@Composable
private fun ProtectionContent(
    overview: VirtualMachineOverview,
    selected: Int,
    onSelected: (Int) -> Unit,
) {
    val titles = listOf(stringResource(R.string.protection_plans), stringResource(R.string.schedule_policies), stringResource(R.string.retention_policies))
    val items = when (selected) {
        0 -> overview.protectionPlans
        1 -> overview.protectionSchedules
        else -> overview.retentionPolicies
    }
    Column {
        ScrollableTabRow(selectedTabIndex = selected, edgePadding = 12.dp, divider = {}) {
            titles.forEachIndexed { index, title ->
                Tab(selected = index == selected, onClick = { onSelected(index) }, text = { Text(title) })
            }
        }
        ResourceList(
            items,
            stringResource(R.string.no_named_items, titles[selected]),
            onSelect = {},
        )
    }
}

@Composable
private fun LogList(logs: List<LogEntry>) {
    var query by rememberSaveable { mutableStateOf("") }
    var level by rememberSaveable { mutableStateOf<LogLevel?>(null) }
    val filtered = logs.filter { log ->
        (level == null || log.level == level) &&
            (query.isBlank() || log.event.contains(query, true) || log.user.contains(query, true))
    }
    Column {
        LazyRow(
            contentPadding = PaddingValues(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                AssistChip(onClick = { level = null }, label = { Text(stringResource(R.string.all)) })
            }
            items(LogLevel.entries) { value ->
                AssistChip(onClick = { level = value }, label = { Text(value.displayName()) })
            }
        }
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = { Text(stringResource(R.string.search_logs)) },
            leadingIcon = { Icon(Icons.Outlined.Search, null) },
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp),
        )
        if (filtered.isEmpty()) {
            EmptyState(stringResource(R.string.no_log_entries), stringResource(R.string.no_records_for_filter), Icons.Outlined.ListAlt)
        } else {
            LazyColumn {
                items(filtered, key = LogEntry::id) { log ->
                    ListItem(
                        headlineContent = { Text(log.event) },
                        supportingContent = {
                            Text(
                                listOfNotNull(
                                    log.user,
                                    log.timeEpochSeconds?.let(::formatDate),
                                ).joinToString(" · ")
                            )
                        },
                        leadingContent = {
                            Icon(log.level.icon(), contentDescription = log.level.displayName())
                        },
                    )
                    HorizontalDivider(Modifier.padding(start = 72.dp))
                }
            }
        }
    }
}

@Composable
private fun NasSettingsScreen(state: WorkspaceState, model: AppViewModel) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val titles = listOf(stringResource(R.string.overview), stringResource(R.string.storage), stringResource(R.string.packages), stringResource(R.string.account), stringResource(R.string.logs), stringResource(R.string.connect), stringResource(R.string.networks), stringResource(R.string.security))
    Column {
        ScrollableTabRow(selectedTabIndex = tab, edgePadding = 12.dp) {
            titles.forEachIndexed { index, title ->
                Tab(selected = tab == index, onClick = { tab = index }, text = { Text(title) })
            }
        }
        LoadableContent(
            value = state.nasSettings,
            emptyTitle = stringResource(R.string.temporarily_unavailable),
            emptyMessage = stringResource(R.string.admin_permission_recovery),
            onRetry = { model.load(Module.NAS_SETTINGS) },
        ) { snapshot ->
            NasSettingsTab(snapshot, tab)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun NasSettingsTab(snapshot: NasSettingsSnapshot, tab: Int) {
    when (tab) {
        0 -> LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                snapshot.system?.let { system ->
                    SummaryCard(stringResource(R.string.system)) {
                        SummaryLine(stringResource(R.string.device_name), system.serverName)
                        SummaryLine(stringResource(R.string.model), system.model)
                        SummaryLine("DSM", system.dsmVersion)
                        system.uptimeSeconds?.let { SummaryLine(stringResource(R.string.uptime), formatDuration(it)) }
                    }
                }
            }
            item {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    MetricCard(stringResource(R.string.storage_space), snapshot.volumes.size.toString(), Icons.Outlined.Storage)
                    MetricCard(stringResource(R.string.packages), snapshot.packages.size.toString(), Icons.Outlined.Dns)
                    MetricCard(stringResource(R.string.active_connections), snapshot.connections.size.toString(), Icons.Outlined.NetworkCheck)
                    MetricCard(stringResource(R.string.account), snapshot.accounts.size.toString(), Icons.Outlined.AdminPanelSettings)
                }
            }
        }
        1 -> ResourceList(
            snapshot.volumes.map {
                ManagedResource(
                    it.id,
                    it.name,
                    "${formatBytes(it.usedBytes)} / ${formatBytes(it.totalBytes)}",
                    it.status,
                )
            } + snapshot.pools + snapshot.disks,
            stringResource(R.string.no_storage_info),
            onSelect = {},
        )
        2 -> ResourceList(
            snapshot.packages.map {
                ManagedResource(it.id, it.name, "${it.version} · ${it.description.orEmpty()}", it.status)
            },
            stringResource(R.string.no_package_info),
            onSelect = {},
        )
        3 -> LazyColumn {
            items(snapshot.accounts, key = { it.name }) {
                ListItem(
                    headlineContent = { Text(it.name) },
                    supportingContent = { Text(it.description ?: it.email ?: stringResource(R.string.nas_account)) },
                    leadingContent = { Icon(Icons.Outlined.AdminPanelSettings, null) },
                )
            }
            items(snapshot.groups, key = { "group:${it.name}" }) {
                ListItem(
                    headlineContent = { Text(it.name) },
                    supportingContent = { Text(it.description ?: stringResource(R.string.user_group)) },
                    leadingContent = { Icon(Icons.Outlined.Security, null) },
                )
            }
        }
        4 -> LogList(snapshot.logs)
        5 -> LazyColumn {
            items(snapshot.connections, key = { it.id }) {
                ListItem(
                    headlineContent = {
                        Text("${it.user.ifBlank { stringResource(R.string.unknown_account) }} · ${it.service}")
                    },
                    supportingContent = {
                        Text(it.client.ifBlank { stringResource(R.string.unknown_device) })
                    },
                    leadingContent = { Icon(Icons.Outlined.NetworkCheck, null) },
                )
                HorizontalDivider(Modifier.padding(start = 72.dp))
            }
        }
        6 -> ResourceList(
            snapshot.networkInterfaces + snapshot.ddnsRecords,
            stringResource(R.string.no_network_info),
            onSelect = {},
        )
        else -> ResourceList(snapshot.security, stringResource(R.string.no_security_status), onSelect = {})
    }
}

@Composable
private fun TransfersScreen(state: WorkspaceState) {
    if (state.transfers.isEmpty()) {
        EmptyState(stringResource(R.string.no_transfer_tasks), stringResource(R.string.transfers_description), Icons.Outlined.SwapVert)
    } else {
        LazyColumn {
            items(state.transfers, key = { it.id }) { task ->
                ListItem(
                    headlineContent = { Text(task.title) },
                    supportingContent = {
                        Column {
                            Text(task.detail)
                            task.progress?.let {
                                LinearProgressIndicator(progress = { it }, Modifier.fillMaxWidth())
                            }
                        }
                    },
                    leadingContent = { Icon(Icons.Outlined.SwapVert, null) },
                )
            }
        }
    }
}

@Composable
private fun SettingsScreen(state: WorkspaceState) {
    val context = LocalContext.current
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Card {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            stringResource(R.string.language_title),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            stringResource(R.string.language_fallback_note),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    LanguageMenu()
                }
            }
        }
        item {
            Text(
                stringResource(R.string.feature_modules),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.semantics { heading() },
            )
        }
        items(state.availability, key = { it.module.name }) { item ->
            Card {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(item.module.icon(), contentDescription = null)
                    Spacer(Modifier.width(16.dp))
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(item.module.titleResource()), fontWeight = FontWeight.Medium)
                        Text(
                            if (item.isAvailable) {
                                stringResource(R.string.available)
                            } else {
                                item.reason?.localize(context)
                                    ?: stringResource(R.string.unavailable)
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(checked = item.isAvailable, onCheckedChange = null)
                }
            }
        }
        item {
            Text(
                stringResource(R.string.password_feature_note),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@StringRes
private fun Module.titleResource(): Int = when (this) {
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

@Composable
private fun LanguageMenu(modifier: Modifier = Modifier) {
    var expanded by remember { mutableStateOf(false) }
    val currentTags = AppCompatDelegate.getApplicationLocales().toLanguageTags()
    Box(modifier) {
        IconButton(onClick = { expanded = true }) {
            Icon(
                Icons.Outlined.Language,
                contentDescription = stringResource(R.string.language_title),
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            LanguageMenuItem(
                title = stringResource(R.string.language_follow_system),
                selected = currentTags.isEmpty(),
            ) {
                AppCompatDelegate.setApplicationLocales(LocaleListCompat.getEmptyLocaleList())
                expanded = false
            }
            LanguageMenuItem(
                title = stringResource(R.string.language_english),
                selected = currentTags.startsWith("en"),
            ) {
                AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags("en"))
                expanded = false
            }
            LanguageMenuItem(
                title = stringResource(R.string.language_simplified_chinese),
                selected = currentTags.startsWith("zh"),
            ) {
                AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags("zh-CN"))
                expanded = false
            }
        }
    }
}

@Composable
private fun LanguageMenuItem(
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    DropdownMenuItem(
        text = { Text(title) },
        leadingIcon = {
            if (selected) {
                Icon(Icons.Outlined.CheckCircle, contentDescription = null)
            }
        },
        onClick = onClick,
    )
}

@Composable
private fun <T> LoadableContent(
    value: Loadable<T>,
    emptyTitle: String,
    emptyMessage: String,
    onRetry: () -> Unit,
    content: @Composable (T) -> Unit,
) {
    val loadingDescription = stringResource(R.string.loading)
    val context = LocalContext.current
    when (value) {
        Loadable.Idle, Loadable.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(
                Modifier.semantics { contentDescription = loadingDescription },
            )
        }
        is Loadable.Failed -> {
            val error = value.error.localize(context)
            ErrorState(error.message, error.recovery, onRetry)
        }
        is Loadable.Ready -> {
            val data = value.value
            val empty = when (data) {
                is Collection<*> -> data.isEmpty()
                else -> false
            }
            if (empty) EmptyState(emptyTitle, emptyMessage, Icons.Outlined.Info) else content(data)
        }
    }
}

@Composable
private fun ResourceList(
    resources: List<ManagedResource>,
    emptyTitle: String,
    onSelect: (ManagedResource) -> Unit,
    headerAction: (@Composable () -> Unit)? = null,
) {
    if (resources.isEmpty() && headerAction == null) {
        EmptyState(emptyTitle, stringResource(R.string.no_category_items), Icons.Outlined.Info)
        return
    }
    LazyColumn {
        headerAction?.let { action ->
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                    horizontalArrangement = Arrangement.End,
                ) { action() }
            }
        }
        items(resources, key = ManagedResource::id) { resource ->
            ListItem(
                headlineContent = {
                    Text(resource.displayName(), maxLines = 1, overflow = TextOverflow.Ellipsis)
                },
                supportingContent = {
                    Text(
                        resource.detail.ifBlank { resource.state.displayName() },
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                leadingContent = { StatusIcon(resource.state) },
                trailingContent = {
                    IconButton(onClick = { onSelect(resource) }) {
                        Icon(Icons.Outlined.MoreVert, contentDescription = stringResource(R.string.more_actions))
                    }
                },
                modifier = Modifier.clickable { onSelect(resource) },
            )
            HorizontalDivider(Modifier.padding(start = 72.dp))
        }
    }
}

@Composable
private fun ErrorBanner(message: String) {
    Card(
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
        modifier = Modifier.semantics {
            contentDescription = message
            liveRegion = LiveRegionMode.Assertive
        },
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Outlined.ErrorOutline, null, tint = MaterialTheme.colorScheme.error)
            Text(
                message,
                color = MaterialTheme.colorScheme.onErrorContainer,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
private fun ErrorState(message: String, recovery: String, onRetry: () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            modifier = Modifier.padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(64.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(MaterialTheme.colorScheme.errorContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Outlined.ErrorOutline,
                    contentDescription = null,
                    modifier = Modifier.size(36.dp),
                    tint = MaterialTheme.colorScheme.error,
                )
            }
            Text(
                message,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                recovery,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
            Button(
                onClick = onRetry,
                shape = MaterialTheme.shapes.medium,
            ) {
                Text(stringResource(R.string.retry))
            }
        }
    }
}

@Composable
private fun EmptyState(title: String, message: String, icon: ImageVector) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            modifier = Modifier.padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(68.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    icon,
                    contentDescription = null,
                    modifier = Modifier.size(34.dp),
                    tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.8f),
                )
            }
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                message,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
private fun ActionRow(
    icon: ImageVector,
    title: String,
    destructive: Boolean = false,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp)
            .clip(MaterialTheme.shapes.small)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
        )
        Text(
            title,
            fontWeight = FontWeight.Medium,
            color = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun ConfirmDialog(
    title: String,
    message: String,
    confirm: String,
    destructive: Boolean,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        shape = MaterialTheme.shapes.extraLarge,
        title = { Text(title, fontWeight = FontWeight.Bold) },
        text = { Text(message) },
        confirmButton = {
            Button(
                onClick = onConfirm,
                shape = MaterialTheme.shapes.medium,
                colors = if (destructive) {
                    androidx.compose.material3.ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError,
                    )
                } else {
                    androidx.compose.material3.ButtonDefaults.buttonColors()
                },
            ) { Text(confirm, fontWeight = FontWeight.Bold) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun TextInputDialog(
    title: String,
    label: String,
    initial: String = "",
    confirm: String,
    onConfirm: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var value by rememberSaveable { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        shape = MaterialTheme.shapes.extraLarge,
        title = { Text(title, fontWeight = FontWeight.Bold) },
        text = {
            OutlinedTextField(
                value = value,
                onValueChange = { value = it },
                label = { Text(label) },
                singleLine = true,
                shape = MaterialTheme.shapes.small,
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = {
            Button(
                onClick = { onConfirm(value) },
                enabled = value.isNotBlank(),
                shape = MaterialTheme.shapes.medium,
            ) { Text(confirm, fontWeight = FontWeight.Bold) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun DownloadDialog(onConfirm: (String, String?) -> Unit, onDismiss: () -> Unit) {
    var uri by rememberSaveable { mutableStateOf("") }
    var destination by rememberSaveable { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        shape = MaterialTheme.shapes.extraLarge,
        title = { Text(stringResource(R.string.add_download_task), fontWeight = FontWeight.Bold) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                OutlinedTextField(
                    value = uri,
                    onValueChange = { uri = it },
                    label = { Text(stringResource(R.string.url_or_magnet)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    minLines = 2,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = destination,
                    onValueChange = { destination = it },
                    label = { Text(stringResource(R.string.save_to_optional)) },
                    singleLine = true,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            Button(
                onClick = { onConfirm(uri, destination.ifBlank { null }) },
                enabled = uri.isNotBlank(),
                shape = MaterialTheme.shapes.medium,
            ) { Text(stringResource(R.string.create_task), fontWeight = FontWeight.Bold) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun StatusIcon(state: ResourceState) {
    Icon(
        when (state) {
            ResourceState.RUNNING, ResourceState.HEALTHY -> Icons.Outlined.CheckCircle
            ResourceState.WAITING -> Icons.Outlined.HourglassTop
            ResourceState.WARNING -> Icons.Outlined.WarningAmber
            ResourceState.ERROR -> Icons.Outlined.ErrorOutline
            ResourceState.PAUSED -> Icons.Outlined.Pause
            else -> Icons.Outlined.Info
        },
        contentDescription = state.displayName(),
        tint = when (state) {
            ResourceState.RUNNING, ResourceState.HEALTHY -> Color(0xFF10B981)
            ResourceState.WARNING -> Color(0xFFF59E0B)
            ResourceState.ERROR -> MaterialTheme.colorScheme.error
            else -> MaterialTheme.colorScheme.onSurfaceVariant
        },
    )
}

@Composable
private fun SummaryCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            content()
        }
    }
}

@Composable
private fun SummaryLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
        Text(value, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun MetricCard(title: String, value: String, icon: ImageVector) {
    Card(
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
        modifier = Modifier.width(156.dp),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
            }
            Text(value, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.ExtraBold)
            Text(
                title,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private fun Module.icon(): ImageVector = when (this) {
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

private fun VirtualMachineOverview.forTab(tab: Int): List<ManagedResource> = when (tab) {
    0 -> machines
    1 -> hosts
    2 -> storages
    3 -> networks
    4 -> images
    else -> emptyList()
}

@Composable
private fun ManagedResource.displayName(): String = when (localizedLabel) {
    ManagedResourceLabel.SECURITY_AUTO_BLOCK -> stringResource(R.string.security_auto_block)
    ManagedResourceLabel.SECURITY_DOS_PROTECTION -> stringResource(R.string.security_dos_protection)
    ManagedResourceLabel.SECURITY_FIREWALL -> stringResource(R.string.security_firewall)
    null -> name.ifBlank { stringResource(R.string.unnamed_item) }
}

@Composable
private fun ResourceState.displayName(): String = when (this) {
    ResourceState.RUNNING -> stringResource(R.string.running)
    ResourceState.STOPPED -> stringResource(R.string.stopped)
    ResourceState.PAUSED -> stringResource(R.string.paused)
    ResourceState.WAITING -> stringResource(R.string.waiting)
    ResourceState.HEALTHY -> stringResource(R.string.normal)
    ResourceState.WARNING -> stringResource(R.string.needs_attention)
    ResourceState.ERROR -> stringResource(R.string.abnormal)
    ResourceState.UNKNOWN -> stringResource(R.string.unknown_status)
}

@Composable
private fun LogLevel.displayName(): String = when (this) {
    LogLevel.INFO -> stringResource(R.string.info)
    LogLevel.WARNING -> stringResource(R.string.warning)
    LogLevel.ERROR -> stringResource(R.string.error)
    LogLevel.UNKNOWN -> stringResource(R.string.other)
}

private fun LogLevel.icon(): ImageVector = when (this) {
    LogLevel.INFO -> Icons.Outlined.Info
    LogLevel.WARNING -> Icons.Outlined.WarningAmber
    LogLevel.ERROR -> Icons.Outlined.ErrorOutline
    LogLevel.UNKNOWN -> Icons.Outlined.ListAlt
}

private fun formatBytes(value: Long): String {
    if (value < 1024) return "$value B"
    val units = listOf("KB", "MB", "GB", "TB", "PB")
    var amount = value.toDouble()
    var index = -1
    while (amount >= 1024 && index < units.lastIndex) {
        amount /= 1024
        index += 1
    }
    return if (amount >= 100) "%.0f %s".format(amount, units[index])
    else "%.1f %s".format(amount, units[index])
}

private fun formatDate(epochSeconds: Long): String =
    DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT)
        .format(Date(epochSeconds * 1000))

@Composable
private fun formatDuration(seconds: Long): String {
    val days = seconds / 86_400
    val hours = (seconds % 86_400) / 3_600
    return if (days > 0) {
        stringResource(R.string.days_hours, days, hours)
    } else {
        stringResource(R.string.hours_only, hours)
    }
}
