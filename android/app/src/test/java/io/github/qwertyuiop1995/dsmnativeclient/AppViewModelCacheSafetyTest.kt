package io.github.qwertyuiop1995.dsmnativeclient

import java.io.File
import java.nio.file.Files
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile

class AppViewModelCacheSafetyTest {
    private val temporaryDirectory = Files.createTempDirectory("app-view-model-cache-test-").toFile()

    @After
    fun 清理临时目录() {
        temporaryDirectory.deleteRecursively()
    }

    @Test
    fun `旧任务完成不会移除同键的新任务`() {
        val oldJob = Any()
        val newJob = Any()
        val jobs = mutableMapOf("thumbnail" to newJob)

        assertFalse(jobs.removeIfSame("thumbnail", oldJob))
        assertSame(newJob, jobs["thumbnail"])
        assertTrue(jobs.removeIfSame("thumbnail", newJob))
        assertFalse(jobs.containsKey("thumbnail"))
    }

    @Test
    fun `用户清缓存只移除没有活动引用的内存缩略图`() {
        val removable = inactiveThumbnailKeys(
            cachedKeys = setOf("active", "missing", "released"),
            references = mapOf("active" to 2, "released" to 0),
        )

        assertEquals(setOf("missing", "released"), removable)
    }

    @Test
    fun `坏缩略缓存会删除并重新获取且不残留part`() = runTest {
        val cacheFile = File(temporaryDirectory, "thumbnail.bin")
        cacheFile.writeText("broken")
        val expected = "valid-thumbnail".encodeToByteArray()
        var fetchCount = 0

        val actual = loadCachedThumbnailBytes(
            cacheFile = cacheFile,
            fetch = {
                fetchCount += 1
                expected
            },
            isValid = { it.contentEquals(expected) },
        )

        assertEquals(1, fetchCount)
        assertArrayEquals(expected, actual)
        assertArrayEquals(expected, cacheFile.readBytes())
        assertFalse(temporaryDirectory.listFiles().orEmpty().any { it.extension == "part" })
    }

    @Test
    fun `缩略缓存写入异常会保留旧文件并清理part`() {
        val cacheFile = File(temporaryDirectory, "thumbnail.bin")
        cacheFile.writeText("previous")

        try {
            replaceFileAtomically(cacheFile) { output ->
                output.write("partial".encodeToByteArray())
                error("synthetic write failure")
            }
            fail("写入异常应向调用方传播")
        } catch (expected: IllegalStateException) {
            assertEquals("synthetic write failure", expected.message)
        }

        assertEquals("previous", cacheFile.readText())
        assertFalse(temporaryDirectory.listFiles().orEmpty().any { it.extension == "part" })
    }

    @Test
    fun `同目标并发替换使用独立part且只留下完整结果`() {
        val cacheFile = File(temporaryDirectory, "thumbnail.bin")
        val firstPartReady = CountDownLatch(1)
        val allowFirstMove = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        try {
            val first = executor.submit {
                replaceFileAtomically(cacheFile) { output ->
                    output.write("first-complete".encodeToByteArray())
                    firstPartReady.countDown()
                    check(allowFirstMove.await(5, TimeUnit.SECONDS))
                }
            }
            assertTrue(firstPartReady.await(5, TimeUnit.SECONDS))

            replaceFileAtomically(cacheFile) { output ->
                output.write("second-complete".encodeToByteArray())
            }
            assertEquals("second-complete", cacheFile.readText())

            allowFirstMove.countDown()
            first.get(5, TimeUnit.SECONDS)
            assertEquals("first-complete", cacheFile.readText())
            assertFalse(temporaryDirectory.listFiles().orEmpty().any { it.extension == "part" })
        } finally {
            allowFirstMove.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun `预览构造失败或取消会删除临时文件而成功会转交所有权`() = runTest {
        val failedFile = File(temporaryDirectory, "failed.preview")
        try {
            withTemporaryFileOwnership(failedFile) { file ->
                file.writeText("partial")
                error("synthetic preview failure")
            }
            fail("预览构造异常应向调用方传播")
        } catch (_: IllegalStateException) {
            assertFalse(failedFile.exists())
        }

        val cancelledFile = File(temporaryDirectory, "cancelled.preview")
        try {
            withTemporaryFileOwnership(cancelledFile) { file ->
                file.writeText("partial")
                throw CancellationException("synthetic cancellation")
            }
            fail("取消应向调用方传播")
        } catch (_: CancellationException) {
            assertFalse(cancelledFile.exists())
        }

        val readyFile = File(temporaryDirectory, "ready.preview")
        val result = withTemporaryFileOwnership(readyFile) { file ->
            file.writeText("ready")
            file
        }
        assertSame(readyFile, result)
        assertTrue(readyFile.exists())
    }

    @Test
    fun `下载列表结果只允许写回同一代请求和同一NAS工作区`() {
        val workspace = WorkspaceState(
            profile = NasProfile(
                id = "lab-synthetic",
                name = "Synthetic",
                address = "https://nas.example.invalid",
                username = "operator",
            ),
        )
        val current = DownloadListRequestToken(generation = 7, profileId = "lab-synthetic")
        val oldGeneration = current.copy(generation = 6)
        val otherProfile = current.copy(profileId = "other-synthetic")

        assertTrue(workspace.matchesDownloadListRequest(current, currentGeneration = 7))
        assertFalse(workspace.matchesDownloadListRequest(oldGeneration, currentGeneration = 7))
        assertFalse(workspace.matchesDownloadListRequest(otherProfile, currentGeneration = 7))
    }
}
