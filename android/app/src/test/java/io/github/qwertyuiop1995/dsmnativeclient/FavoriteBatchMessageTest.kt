package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import org.junit.Assert.assertEquals
import org.junit.Test

class FavoriteBatchMessageTest {
    @Test
    fun `全部确认时显示数量成功提示`() {
        val results = listOf(success(), success())

        assertEquals(2, confirmedFavoriteCount(results))
        assertEquals(R.string.favorites_added_count, favoriteBatchMessageResource(results))
    }

    @Test
    fun `普通确认结果混合时显示数量部分成功提示`() {
        val results = listOf(success(), failure())

        assertEquals(1, confirmedFavoriteCount(results))
        assertEquals(R.string.favorites_added_partial, favoriteBatchMessageResource(results))
        assertEquals(1, confirmedFavoriteCount(listOf(partial())))
        assertEquals(
            R.string.favorites_added_partial,
            favoriteBatchMessageResource(listOf(partial())),
        )
        assertEquals(
            R.string.favorites_added_partial,
            favoriteBatchMessageResource(listOf(success(), null)),
        )
    }

    @Test
    fun `未验证结果优先提示刷新核对`() {
        val statuses = listOf(
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        )

        statuses.forEach { status ->
            assertEquals(
                R.string.favorite_add_unverified,
                favoriteBatchMessageResource(listOf(success(), result(status))),
            )
        }
    }

    @Test
    fun `权限与不支持结果保留专用提示`() {
        assertEquals(
            R.string.favorite_add_permission_denied,
            favoriteBatchMessageResource(listOf(success(), result(MutationResultStatus.PERMISSION_DENIED))),
        )
        assertEquals(
            R.string.favorite_add_unsupported,
            favoriteBatchMessageResource(listOf(success(), result(MutationResultStatus.UNSUPPORTED))),
        )
    }

    @Test
    fun `冲突取消和失败结果保留专用提示`() {
        assertEquals(
            R.string.favorite_add_in_progress,
            favoriteBatchMessageResource(
                listOf(success(), failure(MutationErrorCategory.CONFLICT)),
            ),
        )
        assertEquals(
            R.string.favorite_add_cancelled,
            favoriteBatchMessageResource(
                listOf(success(), result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)),
            ),
        )
        assertEquals(
            R.string.favorite_add_failed,
            favoriteBatchMessageResource(listOf(failure(), null)),
        )
        assertEquals(R.string.favorite_add_failed, favoriteBatchMessageResource(listOf(null, null)))
        assertEquals(R.string.favorite_add_failed, favoriteBatchMessageResource(emptyList()))
    }

    private fun success(): MutationResult = result(MutationResultStatus.CONFIRMED_SUCCESS)

    private fun partial(): MutationResult = MutationResult(
        schemaVersion = 1,
        status = MutationResultStatus.PARTIAL_SUCCESS,
        operation = "favoriteAdd",
        submitted = true,
        requiresRefresh = true,
        counts = MutationResultCounts(1, 0, 1),
    )

    private fun failure(
        category: MutationErrorCategory? = null,
    ): MutationResult = result(MutationResultStatus.CONFIRMED_FAILURE, category)

    private fun result(
        status: MutationResultStatus,
        errorCategory: MutationErrorCategory? = null,
    ): MutationResult {
        val submitted = status in setOf(
            MutationResultStatus.CONFIRMED_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        )
        val counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
            else -> MutationResultCounts(0, 1, 0)
        }
        return MutationResult(
            schemaVersion = 1,
            status = status,
            operation = "favoriteAdd",
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
