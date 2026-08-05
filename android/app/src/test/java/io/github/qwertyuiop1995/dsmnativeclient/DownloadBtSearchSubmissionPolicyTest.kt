package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchCatalog
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchModule
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchModuleScope
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchOptions
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadBtSearchSubmissionPolicyTest {
    @Test
    fun `当前目录能够解释全部选项时允许搜索`() {
        assertTrue(
            canSubmitDownloadBtSearch(
                Loadable.Ready(catalog()),
                options(),
                Loadable.Idle,
            ),
        )
        listOf(DownloadBtSearchModuleScope.ALL, DownloadBtSearchModuleScope.ENABLED).forEach { scope ->
            assertTrue(
                canSubmitDownloadBtSearch(
                    Loadable.Ready(catalog()),
                    options().copy(moduleScope = scope, selectedModuleIds = emptySet()),
                    Loadable.Idle,
                ),
            )
        }
    }

    @Test
    fun `目录为空加载未完成或搜索进行中时禁止提交`() {
        val validOptions = options()
        assertFalse(
            canSubmitDownloadBtSearch(
                Loadable.Ready(DownloadBtSearchCatalog(emptyList(), emptyList())),
                validOptions,
                Loadable.Idle,
            ),
        )
        assertFalse(canSubmitDownloadBtSearch(Loadable.Loading, validOptions, Loadable.Idle))
        assertFalse(
            canSubmitDownloadBtSearch(
                Loadable.Ready(catalog()),
                validOptions,
                Loadable.Loading,
            ),
        )
        assertFalse(
            canSubmitDownloadBtSearch(
                Loadable.Ready(
                    catalog().copy(
                        modules = listOf(
                            DownloadBtSearchModule("provider-a", "Provider A", false),
                        ),
                    ),
                ),
                validOptions.copy(
                    moduleScope = DownloadBtSearchModuleScope.ENABLED,
                    selectedModuleIds = emptySet(),
                ),
                Loadable.Idle,
            ),
        )
    }

    @Test
    fun `目录漂移后的模块或分类标识禁止提交`() {
        val catalog = Loadable.Ready(catalog())
        assertFalse(
            canSubmitDownloadBtSearch(
                catalog,
                options().copy(selectedModuleIds = setOf("removed-provider")),
                Loadable.Idle,
            ),
        )
        assertFalse(
            canSubmitDownloadBtSearch(
                catalog,
                options().copy(categoryId = "Removed"),
                Loadable.Idle,
            ),
        )
    }

    @Test
    fun `外部错误入口不能绕过关键词和指定模块门禁`() {
        val catalog = Loadable.Ready(catalog())
        assertFalse(canSubmitDownloadBtSearch(catalog, options().copy(keyword = " "), Loadable.Idle))
        assertFalse(
            canSubmitDownloadBtSearch(
                catalog,
                options().copy(selectedModuleIds = emptySet()),
                Loadable.Idle,
            ),
        )
        listOf(DownloadBtSearchModuleScope.ALL, DownloadBtSearchModuleScope.ENABLED).forEach { scope ->
            assertFalse(
                canSubmitDownloadBtSearch(
                    catalog,
                    options().copy(moduleScope = scope),
                    Loadable.Idle,
                ),
            )
        }
    }

    private fun catalog() = DownloadBtSearchCatalog(
        modules = listOf(DownloadBtSearchModule("provider-a", "Provider A", true)),
        categories = listOf(DownloadBtSearchCategory("Books", "Books")),
    )

    private fun options() = DownloadBtSearchOptions(
        keyword = "linux",
        moduleScope = DownloadBtSearchModuleScope.SELECTED,
        selectedModuleIds = setOf("provider-a"),
        categoryId = "Books",
    )
}
