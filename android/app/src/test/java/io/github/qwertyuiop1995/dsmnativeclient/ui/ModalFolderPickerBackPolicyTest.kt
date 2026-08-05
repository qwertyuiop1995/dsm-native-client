package io.github.qwertyuiop1995.dsmnativeclient.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class ModalFolderPickerBackPolicyTest {
    @Test
    fun `子目录返回上级而不是关闭选择器`() {
        assertEquals(
            ModalFolderPickerBackAction.NAVIGATE_UP,
            modalFolderPickerBackAction(hasParentFolder = true, isBusy = false),
        )
    }

    @Test
    fun `根目录返回关闭选择器`() {
        assertEquals(
            ModalFolderPickerBackAction.DISMISS,
            modalFolderPickerBackAction(hasParentFolder = false, isBusy = false),
        )
    }

    @Test
    fun `忙碌时根目录和子目录都不处理退出`() {
        listOf(false, true).forEach { hasParentFolder ->
            assertEquals(
                ModalFolderPickerBackAction.BLOCKED,
                modalFolderPickerBackAction(hasParentFolder = hasParentFolder, isBusy = true),
            )
        }
    }
}
