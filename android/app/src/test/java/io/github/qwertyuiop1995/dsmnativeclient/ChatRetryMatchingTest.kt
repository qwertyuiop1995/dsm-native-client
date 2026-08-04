package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatMessage
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatRetryMatchingTest {
    @Test
    fun `重试前只接受本人相同正文且时间接近的服务端消息`() {
        val pending = message("local", "hello", 1_000, true)

        assertTrue(message("server", "hello", 1_120, true).matchesPendingChatMessage(pending))
        assertFalse(message("server", "hello", 1_121, true).matchesPendingChatMessage(pending))
        assertFalse(message("server", "different", 1_010, true).matchesPendingChatMessage(pending))
        assertFalse(message("server", "hello", 1_010, false).matchesPendingChatMessage(pending))
    }

    @Test
    fun `缺少可靠时间时不会把相同正文误判为已发送`() {
        assertFalse(message("server", "hello", 0, true).matchesPendingChatMessage(message("local", "hello", 1_000, true)))
    }

    private fun message(id: String, body: String, time: Long, mine: Boolean) = ChatMessage(
        id = id,
        conversationId = "channel-1",
        sender = null,
        body = body,
        createdAtEpochSeconds = time,
        isMine = mine,
    )
}
