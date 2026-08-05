package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.ui.downloads.DownloadRssRefreshMutationFeedback
import io.github.qwertyuiop1995.dsmnativeclient.ui.downloads.downloadRssRefreshFeedbackPolicy
import io.github.qwertyuiop1995.dsmnativeclient.ui.downloads.messageResource
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DownloadRssMutationUiTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 八类刷新结果均有明确反馈策略() {
        val titles = mapOf(
            MutationResultStatus.CONFIRMED_SUCCESS to R.string.download_rss_refresh_confirmed_title,
            MutationResultStatus.PARTIAL_SUCCESS to R.string.download_rss_refresh_partial_title,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED to R.string.download_rss_refresh_check_title,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION to R.string.download_rss_refresh_check_title,
            MutationResultStatus.PERMISSION_DENIED to R.string.download_rss_refresh_permission_title,
            MutationResultStatus.UNSUPPORTED to R.string.download_rss_refresh_unavailable_title,
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION to R.string.download_rss_refresh_cancelled_title,
            MutationResultStatus.CONFIRMED_FAILURE to R.string.download_rss_refresh_failed_title,
        )
        titles.forEach { (status, title) ->
            assertEquals(title, downloadRssRefreshFeedbackPolicy(result(status)).title)
        }
    }

    @Test
    fun 四种回读结论均有独立文案() {
        assertEquals(R.string.download_rss_refresh_verification_matches, DownloadRssRefreshVerification.MATCHES.messageResource())
        assertEquals(R.string.download_rss_refresh_verification_differs, DownloadRssRefreshVerification.DIFFERS.messageResource())
        assertEquals(R.string.download_rss_refresh_verification_disappeared, DownloadRssRefreshVerification.DISAPPEARED.messageResource())
        assertEquals(R.string.download_rss_refresh_verification_unavailable, DownloadRssRefreshVerification.UNAVAILABLE.messageResource())
    }

    @Test
    fun 未确认结果在窄屏深色两倍字体下只能再次核对且达到48dp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var rechecks = 0
        show(
            DownloadRssRefreshWorkspaceState(
                target = target(),
                mutationResult = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
            ),
            darkTheme = true,
            fontScale = 2f,
            width = 320.dp,
            onRecheck = { rechecks++ },
        )

        rule.onNodeWithText(context.getString(R.string.download_rss_refresh_counts, 0, 0, 1))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.download_rss_refresh_recheck))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.onNodeWithText(context.getString(R.string.download_rss_refresh_close_checked))
            .assertDoesNotExist()
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive),
        ).assertIsDisplayed()
        assertEquals(1, rechecks)
    }

    @Test
    fun 异常提供只读再次核对入口() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var rechecks = 0
        show(
            DownloadRssRefreshWorkspaceState(
                target = target(),
                mutationFailure = DsmFailure(null, "Synthetic failure", "Try again."),
            ),
            onRecheck = { rechecks++ },
        )

        rule.onNodeWithText(context.getString(R.string.download_rss_refresh_recheck))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        assertEquals(1, rechecks)
    }

    @Test
    fun 安全终态提供明确关闭入口() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var dismisses = 0
        show(
            DownloadRssRefreshWorkspaceState(
                target = target(),
                mutationResult = result(MutationResultStatus.PERMISSION_DENIED),
            ),
            onDismiss = { dismisses++ },
        )

        rule.onNodeWithText(context.getString(R.string.download_rss_refresh_close_checked))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        assertEquals(1, dismisses)
    }

    private fun show(
        state: DownloadRssRefreshWorkspaceState,
        darkTheme: Boolean = false,
        fontScale: Float = 1f,
        width: androidx.compose.ui.unit.Dp? = null,
        onRecheck: () -> Unit = {},
        onDismiss: () -> Unit = {},
    ) {
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(density.density, fontScale = fontScale),
            ) {
                LanStashTheme(darkTheme = darkTheme) {
                    Box(if (width == null) Modifier else Modifier.width(width)) {
                        DownloadRssRefreshMutationFeedback(state, onRecheck, onDismiss)
                    }
                }
            }
        }
    }

    private fun target() = DownloadRssRefreshTarget("synthetic-profile", "site-1")

    private fun result(status: MutationResultStatus): MutationResult = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "downloadRssRefresh",
        submitted = status !in setOf(
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
            MutationResultStatus.CONFIRMED_FAILURE,
        ),
        requiresRefresh = status in setOf(
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
        counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            else -> MutationResultCounts(0, 0, 0)
        },
        errorCategory = if (status == MutationResultStatus.CONFIRMED_FAILURE) {
            MutationErrorCategory.UNKNOWN
        } else null,
        diagnosticTag = "synthetic.download.rss.refresh",
    )
}
