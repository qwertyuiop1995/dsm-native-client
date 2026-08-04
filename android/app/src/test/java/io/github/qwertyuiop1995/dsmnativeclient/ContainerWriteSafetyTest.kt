package io.github.qwertyuiop1995.dsmnativeclient

import org.junit.Assert.assertFalse
import org.junit.Test

class ContainerWriteSafetyTest {
    @Test
    fun `未行为验证的Container写入口保持关闭`() {
        assertFalse(containerWriteActionsEnabled())
    }
}
