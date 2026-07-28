package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import org.junit.Rule
import org.junit.Test

class LoginScreenTest {
    @get:Rule
    val rule = createAndroidComposeRule<MainActivity>()

    @Test
    fun 登录页显示完整必要字段和主操作() {
        rule.onNodeWithText("连接 Synology NAS").assertIsDisplayed()
        rule.onNodeWithText("NAS 地址或 QuickConnect ID").assertIsDisplayed()
        rule.onNodeWithText("账号").assertIsDisplayed()
        rule.onNodeWithText("密码").assertIsDisplayed()
        rule.onNodeWithText("在这台设备上记住密码").assertIsDisplayed()
        rule.onNodeWithText("自动登录").assertIsDisplayed()
        rule.onAllNodesWithText("自定义 HTTPS 端口").assertCountEquals(0)
        rule.onNodeWithText("高级连接设置").performClick()
        rule.onNodeWithText("自定义 HTTPS 端口").assertIsDisplayed()
        rule.onNodeWithText("连接").assertIsDisplayed()
    }
}
