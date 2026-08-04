package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.CapacitySummary
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasStorageDisk
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.StorageAnalysisProgress
import io.github.qwertyuiop1995.dsmnativeclient.domain.StorageAnalysisSnapshot
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.NasStorageScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class NasStorageScreenTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 存储页覆盖空闲运行和结果状态() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val analysis = mutableStateOf<Loadable<StorageAnalysisSnapshot>>(Loadable.Idle)
        val progress = mutableStateOf<StorageAnalysisProgress?>(null)
        rule.setContent {
            LanStashTheme {
                NasStorageScreen(
                    snapshot = snapshot(),
                    analysis = analysis.value,
                    progress = progress.value,
                    diskTestStatuses = emptyMap(),
                    diskTestMutationTarget = null,
                    diskTestMutationBaseline = null,
                    diskTestMutationOperation = null,
                    diskTestMutationConfirmationRequested = false,
                    diskTestMutationInProgress = false,
                    diskTestMutationResult = null,
                    diskTestMutationFailure = null,
                    diskTestMutationRefreshFailure = null,
                    diskTestMutationRefreshInProgress = false,
                    diskTestMutationRefreshCompleted = false,
                    diskTestActionsEnabled = true,
                    onBeginAnalysis = {
                        analysis.value = Loadable.Loading
                        progress.value = StorageAnalysisProgress("scanning", 0, 1)
                    },
                    onCancelAnalysis = { analysis.value = Loadable.Idle },
                    onLoadDiskTest = {},
                    onRequestDiskTest = { _, _, _ -> },
                    onConfirmDiskTest = { false },
                    onCancelDiskTestConfirmation = {},
                    onRefreshDiskTest = {},
                    onContinueDiskTest = {},
                    onCloseDiskTestResult = {},
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.begin_analysis))
            .performScrollTo().performClick()
        rule.onNodeWithText(context.getString(R.string.cancel_analysis))
            .performScrollTo().assertIsDisplayed()

        rule.runOnIdle {
            analysis.value = Loadable.Ready(analysisResult())
            progress.value = null
        }
        rule.onNodeWithText(context.getString(R.string.analysis_duplicates))
            .performScrollTo().assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.analyze_again))
            .performScrollTo().assertIsDisplayed()
    }

    private fun snapshot() = NasSettingsSnapshot(
        system = null,
        volumes = listOf(CapacitySummary("volume-1", "Volume 1", 100, 40, ResourceState.HEALTHY)),
        pools = emptyList(),
        disks = emptyList(),
        storageDisks = listOf(
            NasStorageDisk("disk-1", "synthetic-device", "Drive 1", "Example", "normal", "normal", 30.0, true),
        ),
        packages = emptyList(),
        scheduledTasks = emptyList(),
        accounts = emptyList(),
        groups = emptyList(),
        logs = emptyList(),
        connections = emptyList(),
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

    private fun analysisResult() = StorageAnalysisSnapshot(
        generatedAtEpochSeconds = 1,
        shares = emptyList(),
        categories = emptyList(),
        owners = emptyList(),
        largeFiles = emptyList(),
        recentlyModifiedFiles = emptyList(),
        leastRecentlyAccessedFiles = emptyList(),
        duplicateGroups = emptyList(),
        scannedFileCount = 0,
        scannedBytes = 0,
        duplicateCheckWasLimited = false,
        duplicateCheckUnavailable = false,
    )
}
