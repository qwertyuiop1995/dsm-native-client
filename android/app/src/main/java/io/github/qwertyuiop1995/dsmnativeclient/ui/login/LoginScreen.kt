package io.github.qwertyuiop1995.dsmnativeclient.ui.login

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image as FoundationImage
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
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
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AdminPanelSettings
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.HourglassTop
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.NetworkCheck
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.UploadFile
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
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.platform.testTag
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
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferDirection
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineOverview
import io.github.qwertyuiop1995.dsmnativeclient.network.ConnectionStatus
import io.github.qwertyuiop1995.dsmnativeclient.localization.localize
import io.github.qwertyuiop1995.dsmnativeclient.ui.downloads.DownloadsScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.NasSettingsScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.settings.LanguageMenu
import io.github.qwertyuiop1995.dsmnativeclient.ui.settings.SettingsScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.ContainersScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.VirtualMachinesScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.transfers.TransfersScreen
import java.text.DateFormat
import java.util.Date


import io.github.qwertyuiop1995.dsmnativeclient.ui.ConfirmDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.ErrorBanner

@Composable
internal fun LoginScreen(state: LoginState, model: AppViewModel) {
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
    // 密码和一次性验证码只保留在当前组合生命周期内，不进入 Activity SavedState。
    var password by remember(selectedProfileId) { mutableStateOf(state.savedPassword) }
    var otp by remember(selectedProfileId) { mutableStateOf("") }
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
        otp = ""
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
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("login_name"),
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
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("login_address"),
            )
            OutlinedTextField(
                value = username,
                onValueChange = onUsername,
                label = { Text(stringResource(R.string.account)) },
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                singleLine = true,
                shape = MaterialTheme.shapes.small,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("login_username"),
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
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("login_password"),
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
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("login_otp"),
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
                            .heightIn(min = 48.dp)
                            .clip(MaterialTheme.shapes.small)
                            .clickable(role = Role.Switch) { onRememberPassword(!rememberPassword) }
                            .padding(horizontal = 8.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Switch(checked = rememberPassword, onCheckedChange = null)
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
                            .heightIn(min = 48.dp)
                            .clip(MaterialTheme.shapes.small)
                            .clickable(role = Role.Switch) { onAutoLogin(!autoLoginEnabled) }
                            .padding(horizontal = 8.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Switch(checked = autoLoginEnabled, onCheckedChange = null)
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
            .heightIn(min = 48.dp)
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
