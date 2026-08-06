package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.ui.WorkspaceShell
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WorkspacePageLinkUiTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 默认不展示本机页面链接按钮() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        show()

        rule.onNodeWithContentDescription(context.getString(R.string.copy_page_link))
            .assertDoesNotExist()
    }

    @Test
    fun 可签发时按钮在刷新前显示并达到原生触控尺寸() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var copied = 0
        show(canCopyPageLink = true, onCopyPageLink = { copied += 1 })

        val pageLink = rule.onNodeWithContentDescription(context.getString(R.string.copy_page_link))
            .assertIsDisplayed()
            .assertHeightIsAtLeast(48.dp)
        val refresh = rule.onNodeWithContentDescription(context.getString(R.string.refresh))

        assertTrue(
            pageLink.fetchSemanticsNode().boundsInRoot.left <
                refresh.fetchSemanticsNode().boundsInRoot.left,
        )
        pageLink.performClick()
        rule.runOnIdle {
            assertEquals(1, copied)
        }
    }

    private fun show(
        canCopyPageLink: Boolean = false,
        onCopyPageLink: () -> Unit = {},
    ) {
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(density.density, fontScale = 2f),
            ) {
                LanStashTheme(darkTheme = true) {
                    Box(Modifier.width(360.dp)) {
                        WorkspaceShell(
                            state = WorkspaceState(
                                profile = NasProfile(
                                    "synthetic-page-link",
                                    "Synthetic",
                                    "https://nas.example.invalid",
                                    "operator",
                                ),
                            ),
                            onModuleSelected = {},
                            onRefresh = {},
                            onNavigateUp = {},
                            onLogout = {},
                            onMessageShown = {},
                            canCopyPageLink = canCopyPageLink,
                            onCopyPageLink = onCopyPageLink,
                            content = {},
                        )
                    }
                }
            }
        }
    }
}
