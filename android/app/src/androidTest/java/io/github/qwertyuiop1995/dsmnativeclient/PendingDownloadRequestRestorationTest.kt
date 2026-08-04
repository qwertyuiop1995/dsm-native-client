package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.qwertyuiop1995.dsmnativeclient.ui.PendingDownloadRequest
import io.github.qwertyuiop1995.dsmnativeclient.ui.PendingDownloadRequestState
import io.github.qwertyuiop1995.dsmnativeclient.ui.PendingDownloadRequestStateSaver
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

class PendingDownloadRequestRestorationTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 保存页面重建后恢复原资料的待下载请求() {
        val restoration = StateRestorationTester(rule)
        val expected = request(profileId = "profile-a")
        var observed = PendingDownloadRequestState()
        lateinit var update: (PendingDownloadRequestState) -> Unit
        restoration.setContent {
            var pending by rememberSaveable(
                "profile-a",
                stateSaver = PendingDownloadRequestStateSaver,
            ) { mutableStateOf(PendingDownloadRequestState()) }
            SideEffect {
                observed = pending
                update = { pending = it }
            }
        }

        rule.runOnIdle { update(expected) }
        restoration.emulateSavedInstanceStateRestore()

        rule.runOnIdle { assertEquals(expected, observed) }
    }

    @Test
    fun 切换资料后不恢复其他资料的待下载请求() {
        var profileId by mutableStateOf("profile-a")
        var observed = PendingDownloadRequestState()
        lateinit var update: (PendingDownloadRequestState) -> Unit
        rule.setContent {
            var pending by rememberSaveable(
                profileId,
                stateSaver = PendingDownloadRequestStateSaver,
            ) { mutableStateOf(PendingDownloadRequestState()) }
            SideEffect {
                observed = pending
                update = { pending = it }
            }
        }

        rule.runOnIdle { update(request(profileId = "profile-a")) }
        rule.runOnIdle { profileId = "profile-b" }

        rule.runOnIdle { assertNull(observed.request) }
    }

    private fun request(profileId: String) = PendingDownloadRequestState(
        PendingDownloadRequest(
            profileId = profileId,
            path = "/synthetic/file.bin",
            name = "file.bin",
            isDirectory = false,
            size = 42,
            canRead = true,
        ),
    )
}
