package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.ContainerRegistryImage
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ContainerRegistryRequestTokenTest {
    @Test
    fun `搜索结果只归属当前代次 NAS 查询和可见容器模块`() {
        val state = state()
        val token = ContainerRegistrySearchToken(7, "profile-a", "nginx")

        assertTrue(state.matchesContainerRegistrySearch(token, 7))
        assertFalse(state.matchesContainerRegistrySearch(token, 8))
        assertFalse(state.copy(profile = profile("profile-b")).matchesContainerRegistrySearch(token, 7))
        assertFalse(state.copy(containerRegistryQuery = "redis").matchesContainerRegistrySearch(token, 7))
        assertFalse(state.copy(containerRegistryVisible = false).matchesContainerRegistrySearch(token, 7))
        assertFalse(state.copy(selectedModule = Module.FILES).matchesContainerRegistrySearch(token, 7))
    }

    @Test
    fun `标签结果只归属当前代次 NAS 镜像和可见容器模块`() {
        val imageA = image("image-a")
        val state = state().copy(selectedContainerRegistryImage = imageA)
        val token = ContainerRegistryTagsToken(11, "profile-a", imageA.id)

        assertTrue(state.matchesContainerRegistryTags(token, 11))
        assertFalse(state.matchesContainerRegistryTags(token, 12))
        assertFalse(state.copy(profile = profile("profile-b")).matchesContainerRegistryTags(token, 11))
        assertFalse(
            state.copy(selectedContainerRegistryImage = image("image-b"))
                .matchesContainerRegistryTags(token, 11),
        )
        assertFalse(state.copy(containerRegistryVisible = false).matchesContainerRegistryTags(token, 11))
        assertFalse(state.copy(selectedModule = Module.FILES).matchesContainerRegistryTags(token, 11))
    }

    private fun state() = WorkspaceState(
        profile = profile("profile-a"),
        selectedModule = Module.CONTAINERS,
        containerRegistryVisible = true,
        containerRegistryQuery = "  nginx  ",
    )

    private fun profile(id: String) = NasProfile(
        id = id,
        name = "Synthetic",
        address = "https://nas.example.invalid",
        username = "operator",
    )

    private fun image(id: String) = ContainerRegistryImage(
        name = id,
        registry = "registry.example.invalid",
        description = "Synthetic",
        starCount = 0,
        isOfficial = false,
        isAutomated = false,
        isTrusted = false,
    )
}
