package io.github.qwertyuiop1995.dsmnativeclient.data

import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class FileStationFixtureTest {
    @Test
    fun `三端共享Fixture兼容字符串数字和异常附加信息`() {
        val stringNumbers = parseFixture("synthetic-string-numbers")
        assertEquals(2, stringNumbers.total)
        assertEquals(2, stringNumbers.items.size)
        assertEquals(5L, stringNumbers.items.first().size)
        assertEquals(1_700_000_000L, stringNumbers.items.first().modifiedAtEpochSeconds)

        val missingAdditional = parseFixture("synthetic-missing-additional")
        assertEquals(1, missingAdditional.items.size)
        assertFalse(missingAdditional.items.single().isDirectory)

        val malformedAdditional = parseFixture("synthetic-malformed-additional")
        assertEquals(2, malformedAdditional.items.size)
    }

    private fun parseFixture(id: String) =
        Json.parseToJsonElement(fixturePath(id).readText())
            .jsonObject["data"]!!
            .jsonObject
            .let(::parseFilePageFixture)

    private fun fixturePath(id: String): Path {
        var current = Path.of(System.getProperty("user.dir")).toAbsolutePath()
        repeat(8) {
            val candidate = current.resolve(
                "contracts/fixtures-redacted/file-station/list-folder/$id/response.json"
            )
            if (Files.isRegularFile(candidate)) {
                return candidate
            }
            current = current.parent
        }
        error("找不到共享 Fixture：$id")
    }
}
