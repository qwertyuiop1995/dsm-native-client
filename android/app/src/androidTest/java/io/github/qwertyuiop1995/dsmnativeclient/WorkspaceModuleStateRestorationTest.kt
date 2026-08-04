package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.ui.WorkspaceModuleSaveableState
import io.github.qwertyuiop1995.dsmnativeclient.ui.isWorkspaceModuleSaveable
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class WorkspaceModuleStateRestorationTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 仅文件照片和聊天进入模块保存容器() {
        assertTrue(isWorkspaceModuleSaveable(Module.FILES))
        assertTrue(isWorkspaceModuleSaveable(Module.PHOTOS))
        assertTrue(isWorkspaceModuleSaveable(Module.CHAT))
        Module.entries
            .filterNot { it in setOf(Module.FILES, Module.PHOTOS, Module.CHAT) }
            .forEach { assertFalse(isWorkspaceModuleSaveable(it)) }
    }

    @Test
    fun 模块切换配置恢复和资料切换分别保留独立可保存状态() {
        val restorationTester = StateRestorationTester(rule)
        var profileId by mutableStateOf("profile-a")
        var selectedModule by mutableStateOf(Module.FILES)

        restorationTester.setContent {
            LanStashTheme {
                WorkspaceModuleSaveableState(profileId, selectedModule) {
                    ModuleStateProbe(profileId, selectedModule)
                }
            }
        }

        increment(1)
        scrollTo(profileId, selectedModule, 12)

        rule.runOnIdle { selectedModule = Module.PHOTOS }
        increment(2)
        scrollTo(profileId, selectedModule, 8)

        rule.runOnIdle {
            profileId = "profile-b"
            selectedModule = Module.FILES
        }
        increment(3)
        scrollTo(profileId, selectedModule, 15)

        rule.runOnIdle { profileId = "profile-a" }
        assertProbe(profileId, selectedModule, count = 1, visibleItem = 12)

        restorationTester.emulateSavedInstanceStateRestore()
        assertProbe(profileId, selectedModule, count = 1, visibleItem = 12)

        rule.runOnIdle { selectedModule = Module.PHOTOS }
        assertProbe(profileId, selectedModule, count = 2, visibleItem = 8)

        rule.runOnIdle {
            profileId = "profile-b"
            selectedModule = Module.FILES
        }
        assertProbe(profileId, selectedModule, count = 3, visibleItem = 15)
    }

    @Test
    fun 下载和管理模块不保存自造业务草稿() {
        val restorationTester = StateRestorationTester(rule)
        var profileId by mutableStateOf("profile-a")
        var selectedModule by mutableStateOf(Module.DOWNLOADS)

        restorationTester.setContent {
            LanStashTheme {
                WorkspaceModuleSaveableState(profileId, selectedModule) {
                    ModuleStateProbe(profileId, selectedModule)
                }
            }
        }

        increment(2)
        scrollTo(profileId, selectedModule, 9)
        restorationTester.emulateSavedInstanceStateRestore()
        assertProbe(profileId, selectedModule, count = 0, visibleItem = 0)

        increment(1)
        rule.runOnIdle { selectedModule = Module.VIRTUAL_MACHINES }
        increment(3)
        rule.runOnIdle { selectedModule = Module.DOWNLOADS }
        assertProbe(profileId, selectedModule, count = 0, visibleItem = 0)

        rule.runOnIdle { selectedModule = Module.SETTINGS }
        increment(2)
        rule.runOnIdle { profileId = "profile-b" }
        assertProbe(profileId, selectedModule, count = 0, visibleItem = 0)
    }

    private fun increment(times: Int) {
        repeat(times) {
            rule.onNodeWithTag("module-counter").performClick()
        }
    }

    private fun scrollTo(profileId: String, module: Module, index: Int) {
        rule.onNodeWithTag("module-list").performScrollToIndex(index)
        rule.onNodeWithText(itemLabel(profileId, module, index)).assertIsDisplayed()
    }

    private fun assertProbe(
        profileId: String,
        module: Module,
        count: Int,
        visibleItem: Int,
    ) {
        rule.onNodeWithText(counterLabel(profileId, module, count)).assertIsDisplayed()
        rule.onNodeWithText(itemLabel(profileId, module, visibleItem)).assertIsDisplayed()
    }
}

@Composable
private fun ModuleStateProbe(profileId: String, module: Module) {
    var count by rememberSaveable { mutableIntStateOf(0) }
    val listState = rememberLazyListState()
    Column {
        Button(
            onClick = { count += 1 },
            modifier = Modifier.testTag("module-counter"),
        ) {
            Text(counterLabel(profileId, module, count))
        }
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxWidth()
                .height(160.dp)
                .testTag("module-list"),
        ) {
            items((0 until 30).toList()) { index ->
                Text(
                    text = itemLabel(profileId, module, index),
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp),
                )
            }
        }
    }
}

private fun counterLabel(profileId: String, module: Module, count: Int): String =
    "$profileId-${module.name}-count-$count"

private fun itemLabel(profileId: String, module: Module, index: Int): String =
    "$profileId-${module.name}-item-$index"
