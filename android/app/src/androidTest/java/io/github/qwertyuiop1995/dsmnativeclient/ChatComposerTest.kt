package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.hasSetTextAction
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.ui.ChatComposer
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ChatComposerTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 草稿输入与发送操作可访问() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var draft by mutableStateOf("")
        var sends = 0
        var attachments = 0
        rule.setContent {
            LanStashTheme {
                ChatComposer(
                    text = draft,
                    enabled = true,
                    onTextChange = { draft = it },
                    onSend = { sends++ },
                    onAttach = { attachments++ },
                )
            }
        }

        rule.onNode(hasSetTextAction()).performTextInput("你好 👋")
        rule.onNodeWithContentDescription(context.getString(R.string.send_message))
            .assertIsEnabled().performClick()
        rule.onNodeWithContentDescription(context.getString(R.string.attach_file))
            .assertIsEnabled().performClick()
        rule.runOnIdle {
            assertEquals("你好 👋", draft)
            assertEquals(1, sends)
            assertEquals(1, attachments)
        }
    }
}
