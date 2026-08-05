package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NasPerformanceRequestStateTest {
    private val token = NasPerformanceRequestToken(generation = 4, profileId = "profile-a")

    @Test
    fun `性能回调仅在请求身份和页面可见状态仍匹配时生效`() {
        val state = performanceWorkspace()

        assertTrue(state.matchesNasPerformanceRequest(token, 4, true, true))
        assertFalse(state.matchesNasPerformanceRequest(token, 5, true, true))
        assertFalse(state.matchesNasPerformanceRequest(token, 4, false, true))
        assertFalse(state.matchesNasPerformanceRequest(token, 4, true, false))
        assertFalse(state.copy(profile = state.profile.copy(id = "profile-b"))
            .matchesNasPerformanceRequest(token, 4, true, true))
        assertFalse(state.copy(selectedModule = Module.FILES)
            .matchesNasPerformanceRequest(token, 4, true, true))
        assertFalse(state.copy(nasPerformance = state.nasPerformance.copy(isPaused = true))
            .matchesNasPerformanceRequest(token, 4, true, true))
        assertFalse(state.copy(
            nasPerformance = state.nasPerformance.copy(selectedTab = NasSettingsTab.OVERVIEW),
        ).matchesNasPerformanceRequest(token, 4, true, true))
    }

    private fun performanceWorkspace() = WorkspaceState(
        profile = NasProfile(
            id = "profile-a",
            name = "Synthetic",
            address = "https://nas.example.invalid",
            username = "operator",
        ),
        selectedModule = Module.NAS_SETTINGS,
        nasPerformance = NasPerformanceWorkspaceState(
            selectedTab = NasSettingsTab.PERFORMANCE,
        ),
    )
}
