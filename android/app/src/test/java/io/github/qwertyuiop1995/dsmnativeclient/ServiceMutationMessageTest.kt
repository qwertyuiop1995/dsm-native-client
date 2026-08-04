package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import org.junit.Assert.assertEquals
import org.junit.Test

class ServiceMutationMessageTest {
    @Test
    fun `下载设置保存状态映射到可恢复提示`() {
        assertEquals(
            R.string.download_settings_saved,
            downloadSettingsMutationMessageResource(result(MutationResultStatus.CONFIRMED_SUCCESS)),
        )
        assertEquals(
            R.string.download_settings_partial,
            downloadSettingsMutationMessageResource(result(MutationResultStatus.PARTIAL_SUCCESS)),
        )
        assertEquals(
            R.string.download_settings_unverified,
            downloadSettingsMutationMessageResource(
                result(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION),
            ),
        )
        assertEquals(
            R.string.download_settings_permission_denied,
            downloadSettingsMutationMessageResource(result(MutationResultStatus.PERMISSION_DENIED)),
        )
        assertEquals(
            R.string.download_settings_unsupported,
            downloadSettingsMutationMessageResource(result(MutationResultStatus.UNSUPPORTED)),
        )
        assertEquals(
            R.string.download_settings_cancelled,
            downloadSettingsMutationMessageResource(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)),
        )
        assertEquals(
            R.string.download_settings_conflict,
            downloadSettingsMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
            ),
        )
        assertEquals(
            R.string.download_settings_failed,
            downloadSettingsMutationMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE)),
        )
    }

    @Test
    fun `上传和文本保存状态映射到可恢复提示`() {
        assertEquals(
            R.string.upload_completed,
            uploadMutationMessageResource(result(MutationResultStatus.CONFIRMED_SUCCESS)),
        )
        assertEquals(
            R.string.upload_unverified,
            uploadMutationMessageResource(result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED)),
        )
        assertEquals(
            R.string.upload_permission_denied,
            uploadMutationMessageResource(result(MutationResultStatus.PERMISSION_DENIED)),
        )
        assertEquals(
            R.string.upload_unsupported,
            uploadMutationMessageResource(result(MutationResultStatus.UNSUPPORTED)),
        )
        assertEquals(
            R.string.upload_cancelled,
            uploadMutationMessageResource(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)),
        )
        assertEquals(
            R.string.upload_conflict,
            uploadMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
            ),
        )
        assertEquals(
            R.string.upload_failed,
            uploadMutationMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE)),
        )

        assertEquals(
            R.string.text_file_saved,
            textSaveMutationMessageResource(result(MutationResultStatus.CONFIRMED_SUCCESS)),
        )
        assertEquals(
            R.string.text_save_unverified,
            textSaveMutationMessageResource(
                result(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION),
            ),
        )
        assertEquals(
            R.string.text_save_permission_denied,
            textSaveMutationMessageResource(result(MutationResultStatus.PERMISSION_DENIED)),
        )
        assertEquals(
            R.string.text_save_unsupported,
            textSaveMutationMessageResource(result(MutationResultStatus.UNSUPPORTED)),
        )
        assertEquals(
            R.string.text_save_cancelled,
            textSaveMutationMessageResource(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)),
        )
        assertEquals(
            R.string.text_save_conflict,
            textSaveMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
            ),
        )
        assertEquals(
            R.string.text_save_failed,
            textSaveMutationMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE)),
        )
    }

    @Test
    fun `压缩解压状态映射到可恢复的专用提示`() {
        assertEquals(
            R.string.archive_created,
            archiveMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "archiveCompress"),
            ),
        )
        assertEquals(
            R.string.archive_extracted,
            archiveMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "archiveExtract"),
            ),
        )
        assertEquals(
            R.string.archive_operation_partial,
            archiveMutationMessageResource(result(MutationResultStatus.PARTIAL_SUCCESS)),
        )
        assertEquals(
            R.string.archive_operation_unverified,
            archiveMutationMessageResource(result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED)),
        )
        assertEquals(
            R.string.archive_operation_unverified,
            archiveMutationMessageResource(
                result(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION),
            ),
        )
        assertEquals(
            R.string.archive_operation_permission_denied,
            archiveMutationMessageResource(result(MutationResultStatus.PERMISSION_DENIED)),
        )
        assertEquals(
            R.string.archive_operation_unsupported,
            archiveMutationMessageResource(result(MutationResultStatus.UNSUPPORTED)),
        )
        assertEquals(
            R.string.archive_operation_cancelled,
            archiveMutationMessageResource(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)),
        )
        assertEquals(
            R.string.archive_operation_conflict,
            archiveMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
            ),
        )
        assertEquals(
            R.string.archive_operation_failed,
            archiveMutationMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE)),
        )
    }

    @Test
    fun `下载任务创建状态映射到可恢复的专用提示`() {
        assertEquals(
            R.string.download_task_created,
            downloadCreateMessageResource(result(MutationResultStatus.CONFIRMED_SUCCESS)),
        )
        assertEquals(
            R.string.download_create_partial,
            downloadCreateMessageResource(result(MutationResultStatus.PARTIAL_SUCCESS)),
        )
        assertEquals(
            R.string.download_create_unverified,
            downloadCreateMessageResource(result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED)),
        )
        assertEquals(
            R.string.download_create_unverified,
            downloadCreateMessageResource(
                result(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION),
            ),
        )
        assertEquals(
            R.string.download_create_permission_denied,
            downloadCreateMessageResource(result(MutationResultStatus.PERMISSION_DENIED)),
        )
        assertEquals(
            R.string.download_create_unsupported,
            downloadCreateMessageResource(result(MutationResultStatus.UNSUPPORTED)),
        )
        assertEquals(
            R.string.download_create_cancelled,
            downloadCreateMessageResource(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)),
        )
        assertEquals(
            R.string.download_create_conflict,
            downloadCreateMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
            ),
        )
        assertEquals(
            R.string.download_create_failed,
            downloadCreateMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE)),
        )
    }

    @Test
    fun `服务写操作状态映射到不同用户提示`() {
        val success = R.string.container_deleted
        assertEquals(success, serviceMutationMessageResource(result(MutationResultStatus.CONFIRMED_SUCCESS), success))
        assertEquals(
            R.string.service_action_unverified,
            serviceMutationMessageResource(result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED), success),
        )
        assertEquals(
            R.string.service_action_permission_denied,
            serviceMutationMessageResource(result(MutationResultStatus.PERMISSION_DENIED), success),
        )
        assertEquals(
            R.string.service_action_unsupported,
            serviceMutationMessageResource(result(MutationResultStatus.UNSUPPORTED), success),
        )
        assertEquals(
            R.string.service_action_cancelled,
            serviceMutationMessageResource(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION), success),
        )
        assertEquals(
            R.string.service_action_partial,
            serviceMutationMessageResource(result(MutationResultStatus.PARTIAL_SUCCESS), success),
        )
        assertEquals(
            R.string.service_action_conflict,
            serviceMutationMessageResource(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    MutationErrorCategory.CONFLICT,
                ),
                success,
            ),
        )
        assertEquals(
            R.string.service_action_failed,
            serviceMutationMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE), success),
        )
    }

    @Test
    fun `照片删除状态映射到可恢复的专用提示`() {
        assertEquals(
            R.string.photo_deleted,
            photoDeleteMessageResource(result(MutationResultStatus.CONFIRMED_SUCCESS)),
        )
        assertEquals(
            R.string.photo_delete_partial,
            photoDeleteMessageResource(result(MutationResultStatus.PARTIAL_SUCCESS)),
        )
        assertEquals(
            R.string.photo_delete_unverified,
            photoDeleteMessageResource(result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED)),
        )
        assertEquals(
            R.string.photo_delete_unverified,
            photoDeleteMessageResource(
                result(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION),
            ),
        )
        assertEquals(
            R.string.photo_delete_permission_denied,
            photoDeleteMessageResource(result(MutationResultStatus.PERMISSION_DENIED)),
        )
        assertEquals(
            R.string.photo_delete_unsupported,
            photoDeleteMessageResource(result(MutationResultStatus.UNSUPPORTED)),
        )
        assertEquals(
            R.string.photo_delete_cancelled,
            photoDeleteMessageResource(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)),
        )
        assertEquals(
            R.string.photo_delete_in_progress,
            photoDeleteMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
            ),
        )
        assertEquals(
            R.string.photo_delete_failed,
            photoDeleteMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE)),
        )
    }

    @Test
    fun `照片移动状态映射到可恢复的专用提示`() {
        assertEquals(
            R.string.photo_moved,
            photoMoveMessageResource(result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "fileMove")),
        )
        assertEquals(
            R.string.photo_move_partial,
            photoMoveMessageResource(result(MutationResultStatus.PARTIAL_SUCCESS, operation = "fileMove")),
        )
        assertEquals(
            R.string.photo_move_unverified,
            photoMoveMessageResource(
                result(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, operation = "fileMove"),
            ),
        )
        assertEquals(
            R.string.photo_move_permission_denied,
            photoMoveMessageResource(result(MutationResultStatus.PERMISSION_DENIED, operation = "fileMove")),
        )
        assertEquals(
            R.string.photo_move_unavailable,
            photoMoveMessageResource(result(MutationResultStatus.UNSUPPORTED, operation = "fileMove")),
        )
        assertEquals(
            R.string.photo_move_cancelled,
            photoMoveMessageResource(
                result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, operation = "fileMove"),
            ),
        )
        assertEquals(
            R.string.photo_move_conflict,
            photoMoveMessageResource(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    MutationErrorCategory.CONFLICT,
                    "fileMove",
                ),
            ),
        )
        assertEquals(
            R.string.photo_move_failed,
            photoMoveMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE, operation = "fileMove")),
        )
    }

    @Test
    fun `文件复制移动状态保留操作类型并提供分级提示`() {
        assertEquals(
            R.string.files_copied,
            fileCopyMoveMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "fileCopy"),
            ),
        )
        assertEquals(
            R.string.files_moved,
            fileCopyMoveMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "fileMove"),
            ),
        )
        assertEquals(
            R.string.file_copy_move_partial,
            fileCopyMoveMessageResource(result(MutationResultStatus.PARTIAL_SUCCESS, operation = "fileMove")),
        )
        assertEquals(
            R.string.file_copy_move_unverified,
            fileCopyMoveMessageResource(
                result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, operation = "fileCopy"),
            ),
        )
        assertEquals(
            R.string.file_copy_move_permission_denied,
            fileCopyMoveMessageResource(result(MutationResultStatus.PERMISSION_DENIED, operation = "fileMove")),
        )
        assertEquals(
            R.string.file_copy_move_cancelled,
            fileCopyMoveMessageResource(
                result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, operation = "fileCopy"),
            ),
        )
        assertEquals(
            R.string.file_copy_move_conflict,
            fileCopyMoveMessageResource(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    MutationErrorCategory.CONFLICT,
                    "fileMove",
                ),
            ),
        )
        assertEquals(
            R.string.file_copy_move_failed,
            fileCopyMoveMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, operation = "fileCopy"),
            ),
        )
    }

    @Test
    fun `新建文件夹与重命名状态映射到可恢复提示`() {
        assertEquals(
            R.string.folder_created,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "folderCreate"),
            ),
        )
        assertEquals(
            R.string.folder_create_partial,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.PARTIAL_SUCCESS, operation = "folderCreate"),
            ),
        )
        assertEquals(
            R.string.folder_create_unverified,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, operation = "folderCreate"),
            ),
        )
        assertEquals(
            R.string.folder_create_unverified,
            fileEntryMutationMessageResource(
                result(
                    MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
                    operation = "folderCreate",
                ),
            ),
        )
        assertEquals(
            R.string.folder_create_permission_denied,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.PERMISSION_DENIED, operation = "folderCreate"),
            ),
        )
        assertEquals(
            R.string.folder_create_unsupported,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.UNSUPPORTED, operation = "folderCreate"),
            ),
        )
        assertEquals(
            R.string.folder_create_cancelled,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, operation = "folderCreate"),
            ),
        )
        assertEquals(
            R.string.folder_create_conflict,
            fileEntryMutationMessageResource(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    MutationErrorCategory.CONFLICT,
                    "folderCreate",
                ),
            ),
        )
        assertEquals(
            R.string.folder_create_failed,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, operation = "folderCreate"),
            ),
        )
        assertEquals(
            R.string.name_changed,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "fileRename"),
            ),
        )
        assertEquals(
            R.string.file_rename_partial,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.PARTIAL_SUCCESS, operation = "fileRename"),
            ),
        )
        assertEquals(
            R.string.file_rename_unverified,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, operation = "fileRename"),
            ),
        )
        assertEquals(
            R.string.file_rename_permission_denied,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.PERMISSION_DENIED, operation = "fileRename"),
            ),
        )
        assertEquals(
            R.string.file_rename_unsupported,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.UNSUPPORTED, operation = "fileRename"),
            ),
        )
        assertEquals(
            R.string.file_rename_cancelled,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, operation = "fileRename"),
            ),
        )
        assertEquals(
            R.string.file_rename_conflict,
            fileEntryMutationMessageResource(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    MutationErrorCategory.CONFLICT,
                    "fileRename",
                ),
            ),
        )
        assertEquals(
            R.string.file_rename_failed,
            fileEntryMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, operation = "fileRename"),
            ),
        )
    }

    @Test
    fun `回收站恢复状态映射到刷新两个位置的提示`() {
        assertEquals(
            R.string.photo_restored,
            fileRestoreMessageResource(result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "fileRestore")),
        )
        assertEquals(
            R.string.file_restore_partial,
            fileRestoreMessageResource(result(MutationResultStatus.PARTIAL_SUCCESS, operation = "fileRestore")),
        )
        assertEquals(
            R.string.file_restore_unverified,
            fileRestoreMessageResource(
                result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, operation = "fileRestore"),
            ),
        )
        assertEquals(
            R.string.file_restore_unverified,
            fileRestoreMessageResource(
                result(
                    MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
                    operation = "fileRestore",
                ),
            ),
        )
        assertEquals(
            R.string.file_restore_permission_denied,
            fileRestoreMessageResource(result(MutationResultStatus.PERMISSION_DENIED, operation = "fileRestore")),
        )
        assertEquals(
            R.string.file_restore_unsupported,
            fileRestoreMessageResource(result(MutationResultStatus.UNSUPPORTED, operation = "fileRestore")),
        )
        assertEquals(
            R.string.file_restore_cancelled,
            fileRestoreMessageResource(
                result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, operation = "fileRestore"),
            ),
        )
        assertEquals(
            R.string.file_restore_conflict,
            fileRestoreMessageResource(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    MutationErrorCategory.CONFLICT,
                    "fileRestore",
                ),
            ),
        )
        assertEquals(
            R.string.file_restore_failed,
            fileRestoreMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE, operation = "fileRestore")),
        )
    }

    @Test
    fun `共享链接状态只在确认成功时提示已复制`() {
        assertEquals(
            R.string.share_link_copied,
            shareLinkMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "shareLinkCreate"),
            ),
        )
        assertEquals(
            R.string.share_link_create_partial,
            shareLinkMutationMessageResource(
                result(MutationResultStatus.PARTIAL_SUCCESS, operation = "shareLinkCreate"),
            ),
        )
        assertEquals(
            R.string.share_link_create_unverified,
            shareLinkMutationMessageResource(
                result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, operation = "shareLinkCreate"),
            ),
        )
        assertEquals(
            R.string.share_link_create_unverified,
            shareLinkMutationMessageResource(
                result(
                    MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
                    operation = "shareLinkCreate",
                ),
            ),
        )
        assertEquals(
            R.string.share_link_create_permission_denied,
            shareLinkMutationMessageResource(
                result(MutationResultStatus.PERMISSION_DENIED, operation = "shareLinkCreate"),
            ),
        )
        assertEquals(
            R.string.share_link_create_unsupported,
            shareLinkMutationMessageResource(
                result(MutationResultStatus.UNSUPPORTED, operation = "shareLinkCreate"),
            ),
        )
        assertEquals(
            R.string.share_link_create_cancelled,
            shareLinkMutationMessageResource(
                result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, operation = "shareLinkCreate"),
            ),
        )
        assertEquals(
            R.string.share_link_create_conflict,
            shareLinkMutationMessageResource(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    MutationErrorCategory.CONFLICT,
                    "shareLinkCreate",
                ),
            ),
        )
        assertEquals(
            R.string.share_link_create_failed,
            shareLinkMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, operation = "shareLinkCreate"),
            ),
        )
    }

    @Test
    fun `Chat 文字发送状态映射到可恢复提示`() {
        assertEquals(
            R.string.message_sent,
            chatTextSendMessageResource(result(MutationResultStatus.CONFIRMED_SUCCESS)),
        )
        assertEquals(
            R.string.chat_text_send_unverified,
            chatTextSendMessageResource(result(MutationResultStatus.PARTIAL_SUCCESS)),
        )
        assertEquals(
            R.string.chat_text_send_unverified,
            chatTextSendMessageResource(
                result(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION),
            ),
        )
        assertEquals(
            R.string.chat_text_send_permission_denied,
            chatTextSendMessageResource(result(MutationResultStatus.PERMISSION_DENIED)),
        )
        assertEquals(
            R.string.chat_text_send_unsupported,
            chatTextSendMessageResource(result(MutationResultStatus.UNSUPPORTED)),
        )
        assertEquals(
            R.string.chat_text_send_cancelled,
            chatTextSendMessageResource(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)),
        )
        assertEquals(
            R.string.chat_text_send_conflict,
            chatTextSendMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
            ),
        )
        assertEquals(
            R.string.chat_text_send_invalid,
            chatTextSendMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.VALIDATION),
            ),
        )
        assertEquals(
            R.string.message_send_failed,
            chatTextSendMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE)),
        )
    }

    @Test
    fun `Chat 附件发送状态映射到可恢复提示`() {
        assertEquals(
            R.string.message_sent,
            chatAttachmentSendMessageResource(result(MutationResultStatus.CONFIRMED_SUCCESS)),
        )
        assertEquals(
            R.string.chat_attachment_send_unverified,
            chatAttachmentSendMessageResource(result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED)),
        )
        assertEquals(
            R.string.chat_attachment_send_permission_denied,
            chatAttachmentSendMessageResource(result(MutationResultStatus.PERMISSION_DENIED)),
        )
        assertEquals(
            R.string.chat_attachment_send_unsupported,
            chatAttachmentSendMessageResource(result(MutationResultStatus.UNSUPPORTED)),
        )
        assertEquals(
            R.string.chat_attachment_send_cancelled,
            chatAttachmentSendMessageResource(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)),
        )
        assertEquals(
            R.string.chat_attachment_send_conflict,
            chatAttachmentSendMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
            ),
        )
        assertEquals(
            R.string.chat_attachment_send_invalid,
            chatAttachmentSendMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.VALIDATION),
            ),
        )
        assertEquals(
            R.string.message_send_failed,
            chatAttachmentSendMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE)),
        )
    }

    @Test
    fun `Chat 提醒变更状态映射到可恢复提示`() {
        assertEquals(
            R.string.chat_reminder_saved,
            chatReminderMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "chatReminderSet"),
            ),
        )
        assertEquals(
            R.string.chat_reminder_removed,
            chatReminderMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "chatReminderDelete"),
            ),
        )
        assertEquals(
            R.string.chat_reminder_change_unverified,
            chatReminderMutationMessageResource(
                result(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION),
            ),
        )
        assertEquals(
            R.string.chat_reminder_change_permission_denied,
            chatReminderMutationMessageResource(result(MutationResultStatus.PERMISSION_DENIED)),
        )
        assertEquals(
            R.string.chat_reminder_change_unsupported,
            chatReminderMutationMessageResource(result(MutationResultStatus.UNSUPPORTED)),
        )
        assertEquals(
            R.string.chat_reminder_change_cancelled,
            chatReminderMutationMessageResource(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)),
        )
        assertEquals(
            R.string.chat_reminder_change_conflict,
            chatReminderMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
            ),
        )
        assertEquals(
            R.string.chat_reminder_change_invalid,
            chatReminderMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.VALIDATION),
            ),
        )
        assertEquals(
            R.string.chat_reminder_change_failed,
            chatReminderMutationMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE)),
        )
    }

    @Test
    fun `Chat 定时消息变更状态映射到可恢复提示`() {
        assertEquals(
            R.string.chat_schedule_saved,
            chatScheduleMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "chatScheduleCreate"),
            ),
        )
        assertEquals(
            R.string.chat_schedule_removed,
            chatScheduleMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "chatScheduleDelete"),
            ),
        )
        assertEquals(
            R.string.chat_schedule_change_unverified,
            chatScheduleMutationMessageResource(
                result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
            ),
        )
        assertEquals(
            R.string.chat_schedule_change_permission_denied,
            chatScheduleMutationMessageResource(result(MutationResultStatus.PERMISSION_DENIED)),
        )
        assertEquals(
            R.string.chat_schedule_change_unsupported,
            chatScheduleMutationMessageResource(result(MutationResultStatus.UNSUPPORTED)),
        )
        assertEquals(
            R.string.chat_schedule_change_cancelled,
            chatScheduleMutationMessageResource(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)),
        )
        assertEquals(
            R.string.chat_schedule_change_conflict,
            chatScheduleMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
            ),
        )
        assertEquals(
            R.string.chat_schedule_change_invalid,
            chatScheduleMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.VALIDATION),
            ),
        )
        assertEquals(
            R.string.chat_schedule_change_failed,
            chatScheduleMutationMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE)),
        )
    }

    @Test
    fun `Chat 投票创建状态映射到可恢复提示`() {
        assertEquals(
            R.string.chat_poll_created,
            chatPollMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "chatPollCreate"),
            ),
        )
        assertEquals(
            R.string.chat_poll_change_unverified,
            chatPollMutationMessageResource(
                result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
            ),
        )
        assertEquals(
            R.string.chat_poll_change_permission_denied,
            chatPollMutationMessageResource(result(MutationResultStatus.PERMISSION_DENIED)),
        )
        assertEquals(
            R.string.chat_poll_change_unsupported,
            chatPollMutationMessageResource(result(MutationResultStatus.UNSUPPORTED)),
        )
        assertEquals(
            R.string.chat_poll_change_cancelled,
            chatPollMutationMessageResource(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)),
        )
        assertEquals(
            R.string.chat_poll_change_conflict,
            chatPollMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
            ),
        )
        assertEquals(
            R.string.chat_poll_change_invalid,
            chatPollMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.VALIDATION),
            ),
        )
        assertEquals(
            R.string.chat_poll_change_failed,
            chatPollMutationMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE)),
        )
    }

    @Test
    fun `Chat 会话创建状态区分单聊群聊并映射到可恢复提示`() {
        assertEquals(
            R.string.conversation_started,
            chatConversationMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "chatDirectOpen"),
            ),
        )
        assertEquals(
            R.string.private_group_created,
            chatConversationMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_SUCCESS, operation = "chatGroupCreate"),
            ),
        )
        assertEquals(
            R.string.chat_conversation_change_partial,
            chatConversationMutationMessageResource(
                result(MutationResultStatus.PARTIAL_SUCCESS, operation = "chatGroupCreate"),
            ),
        )
        assertEquals(
            R.string.chat_conversation_change_unverified,
            chatConversationMutationMessageResource(
                result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, operation = "chatDirectOpen"),
            ),
        )
        assertEquals(
            R.string.chat_conversation_change_unverified,
            chatConversationMutationMessageResource(
                result(
                    MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
                    operation = "chatGroupCreate",
                ),
            ),
        )
        assertEquals(
            R.string.chat_conversation_change_permission_denied,
            chatConversationMutationMessageResource(
                result(MutationResultStatus.PERMISSION_DENIED, operation = "chatDirectOpen"),
            ),
        )
        assertEquals(
            R.string.chat_conversation_change_unsupported,
            chatConversationMutationMessageResource(
                result(MutationResultStatus.UNSUPPORTED, operation = "chatDirectOpen"),
            ),
        )
        assertEquals(
            R.string.chat_conversation_change_cancelled,
            chatConversationMutationMessageResource(
                result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, operation = "chatDirectOpen"),
            ),
        )
        assertEquals(
            R.string.chat_conversation_change_conflict,
            chatConversationMutationMessageResource(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    MutationErrorCategory.CONFLICT,
                    "chatDirectOpen",
                ),
            ),
        )
        assertEquals(
            R.string.chat_conversation_change_invalid,
            chatConversationMutationMessageResource(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    MutationErrorCategory.VALIDATION,
                    "chatGroupCreate",
                ),
            ),
        )
        assertEquals(
            R.string.chat_conversation_change_failed,
            chatConversationMutationMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, operation = "chatDirectOpen"),
            ),
        )
    }

    @Test
    fun `共享链接删除状态映射到可恢复提示`() {
        assertEquals(
            R.string.share_link_delete_success,
            shareLinkDeleteMessageResource(result(MutationResultStatus.CONFIRMED_SUCCESS)),
        )
        assertEquals(
            R.string.share_link_delete_partial,
            shareLinkDeleteMessageResource(result(MutationResultStatus.PARTIAL_SUCCESS)),
        )
        assertEquals(
            R.string.share_link_delete_unverified,
            shareLinkDeleteMessageResource(
                result(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION),
            ),
        )
        assertEquals(
            R.string.share_link_delete_permission_denied,
            shareLinkDeleteMessageResource(result(MutationResultStatus.PERMISSION_DENIED)),
        )
        assertEquals(
            R.string.share_link_delete_unsupported,
            shareLinkDeleteMessageResource(result(MutationResultStatus.UNSUPPORTED)),
        )
        assertEquals(
            R.string.share_link_delete_cancelled,
            shareLinkDeleteMessageResource(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)),
        )
        assertEquals(
            R.string.share_link_delete_conflict,
            shareLinkDeleteMessageResource(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
            ),
        )
        assertEquals(
            R.string.share_link_delete_failed,
            shareLinkDeleteMessageResource(result(MutationResultStatus.CONFIRMED_FAILURE)),
        )
    }

    private fun result(
        status: MutationResultStatus,
        errorCategory: MutationErrorCategory? = null,
        operation: String = "containerControl",
    ): MutationResult {
        val submitted = status in setOf(
            MutationResultStatus.CONFIRMED_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            MutationResultStatus.PARTIAL_SUCCESS,
        )
        val counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
            else -> MutationResultCounts(0, 1, 0)
        }
        return MutationResult(
            schemaVersion = 1,
            status = status,
            operation = operation,
            submitted = submitted,
            requiresRefresh = status in setOf(
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            ),
            counts = counts,
            errorCategory = errorCategory,
        )
    }
}
