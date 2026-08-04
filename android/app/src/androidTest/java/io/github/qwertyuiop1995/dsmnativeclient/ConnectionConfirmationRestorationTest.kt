package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import io.github.qwertyuiop1995.dsmnativeclient.domain.ActiveConnection
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

class ConnectionConfirmationRestorationTest {
    @get:Rule
    val rule = createAndroidComposeRule<MainActivity>()

    @Test
    fun 当前连接确认跨Activity配置重建保留同一安全目标且取消不提交() {
        val connection = ActiveConnection(
            id = "synthetic-connection",
            user = "operator",
            service = "HTTPS",
            client = "Synthetic browser",
            connectedAtEpochSeconds = null,
            isCurrent = false,
            deviceId = "private-device-id-not-shown",
            type = "HTTP/HTTPS",
            canDisconnect = true,
        )
        rule.runOnIdle {
            workspace(rule.activity).value = WorkspaceState(
                profile = profile(),
                selectedModule = Module.NAS_SETTINGS,
                nasSettings = Loadable.Ready(snapshot(connection)),
                connectionMutationTarget = connection,
            )
        }

        rule.runOnIdle {
            assertEquals(connection, workspace(rule.activity).value?.connectionMutationTarget)
        }

        rule.activityRule.scenario.recreate()

        rule.runOnIdle {
            assertEquals(connection, workspace(rule.activity).value?.connectionMutationTarget)
            val model = ViewModelProvider(rule.activity)[AppViewModel::class.java]
            model.cancelConnectionDisconnectRequest()
            val state = workspace(rule.activity).value
            assertNull(state?.connectionMutationTarget)
            assertNull(state?.connectionMutationResult)
            assertEquals(false, state?.connectionMutationInProgress)
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun workspace(activity: MainActivity): MutableStateFlow<WorkspaceState?> {
        val field = AppViewModel::class.java.getDeclaredField("_workspace").apply {
            isAccessible = true
        }
        return field.get(ViewModelProvider(activity)[AppViewModel::class.java])
            as MutableStateFlow<WorkspaceState?>
    }

    private fun profile() = NasProfile(
        id = "synthetic",
        name = "Synthetic",
        address = "https://nas.example.invalid",
        username = "operator",
    )

    private fun snapshot(connection: ActiveConnection) = NasSettingsSnapshot(
        system = null,
        volumes = emptyList(),
        pools = emptyList(),
        disks = emptyList(),
        storageDisks = emptyList(),
        packages = emptyList(),
        scheduledTasks = emptyList(),
        accounts = emptyList(),
        groups = emptyList(),
        logs = emptyList(),
        connections = listOf(connection),
        connectionsAvailable = true,
        networkInterfaces = emptyList(),
        networkInterfacesAvailable = true,
        ddnsDirectory = null,
        ddnsDirectoryAvailable = true,
        fileServiceSettings = null,
        terminalSettings = null,
        proxySettings = null,
        regionSettings = null,
        securitySettings = null,
        hardwareSettings = null,
        security = emptyList(),
    )
}
