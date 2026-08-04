package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBrowserState
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FileUploadPreflightStatePolicyTest {
    @Test
    fun `当前身份目标与代次一致时接受上传预处理`() {
        assertTrue(workspace().matchesFileUploadPreflight(token(), currentGeneration = 7L))
    }

    @Test
    fun `切换 NAS 后拒绝旧上传预处理`() {
        assertFalse(
            workspace(profileId = "profile-b")
                .matchesFileUploadPreflight(token(), currentGeneration = 7L),
        )
    }

    @Test
    fun `切换模块后拒绝旧上传预处理`() {
        assertFalse(
            workspace(module = Module.PHOTOS)
                .matchesFileUploadPreflight(token(), currentGeneration = 7L),
        )
    }

    @Test
    fun `切换目录后拒绝旧上传预处理`() {
        assertFalse(
            workspace(path = "/shared/new")
                .matchesFileUploadPreflight(token(), currentGeneration = 7L),
        )
    }

    @Test
    fun `代次失效后拒绝旧上传预处理`() {
        assertFalse(workspace().matchesFileUploadPreflight(token(), currentGeneration = 8L))
    }

    private fun token() = FileUploadPreflightToken(
        profileId = "profile-a",
        module = Module.FILES,
        destinationPath = "/shared",
        generation = 7L,
    )

    private fun workspace(
        profileId: String = "profile-a",
        module: Module = Module.FILES,
        path: String = "/shared",
    ) = WorkspaceState(
        profile = NasProfile(profileId, "NAS", "https://nas.example.invalid", "operator"),
        selectedModule = module,
        fileBrowser = FileBrowserState(path = path),
    )
}
