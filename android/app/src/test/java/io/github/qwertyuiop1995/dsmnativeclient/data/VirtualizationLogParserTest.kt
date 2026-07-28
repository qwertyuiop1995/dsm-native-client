package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.LogLevel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Test

class VirtualizationLogParserTest {
    @Test
    fun `兼容网页端日志容器和字段别名`() {
        val data = Json.parseToJsonElement(
            """
            {
              "records": [
                {
                  "log_id": "log-1",
                  "severity": "warning",
                  "create_time": 1785143565000,
                  "account": "tester",
                  "description": "虚拟机已停止"
                }
              ]
            }
            """.trimIndent()
        ).jsonObject

        val logs = parseVirtualizationLogs(data)

        assertEquals(1, logs.size)
        assertEquals("log-1", logs.single().id)
        assertEquals(LogLevel.WARNING, logs.single().level)
        assertEquals(1_785_143_565L, logs.single().timeEpochSeconds)
        assertEquals("tester", logs.single().user)
        assertEquals("虚拟机已停止", logs.single().event)
    }
}
