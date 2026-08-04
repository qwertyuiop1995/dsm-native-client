package io.github.qwertyuiop1995.dsmnativeclient.ui

import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.ModuleAvailability
import io.github.qwertyuiop1995.dsmnativeclient.domain.ModuleUnavailableReason
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ModuleAvailabilityNavigationTest {
    @Test
    fun `可用模块不显示不可用原因`() {
        val availability = ModuleAvailability(Module.CHAT, isAvailable = true)

        assertNull(availability.navigationStatusResource())
        assertNull(null.navigationStatusResource())
    }

    @Test
    fun `不可用模块优先显示具体原因并安全回退`() {
        val chat = ModuleAvailability(
            Module.CHAT,
            isAvailable = false,
            reason = ModuleUnavailableReason.CHAT_SERVICE,
        )
        val unknown = ModuleAvailability(Module.CHAT, isAvailable = false)

        assertEquals(R.string.module_unavailable_chat, chat.navigationStatusResource())
        assertEquals(R.string.unavailable, unknown.navigationStatusResource())
    }
}
