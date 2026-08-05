package io.github.qwertyuiop1995.dsmnativeclient.ui

internal enum class ModalFolderPickerBackAction {
    NAVIGATE_UP,
    DISMISS,
    BLOCKED,
}

/** 全屏目录选择器优先返回上级；根层才关闭，在途操作保持现有退出门禁。 */
internal fun modalFolderPickerBackAction(
    hasParentFolder: Boolean,
    isBusy: Boolean,
): ModalFolderPickerBackAction = when {
    isBusy -> ModalFolderPickerBackAction.BLOCKED
    hasParentFolder -> ModalFolderPickerBackAction.NAVIGATE_UP
    else -> ModalFolderPickerBackAction.DISMISS
}
