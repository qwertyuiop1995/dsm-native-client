package io.github.qwertyuiop1995.dsmnativeclient.ui

import io.github.qwertyuiop1995.dsmnativeclient.Loadable
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure

internal sealed interface PageUiState<out T> {
    data object Loading : PageUiState<Nothing>
    data object Empty : PageUiState<Nothing>
    data object FilteredEmpty : PageUiState<Nothing>
    data class Error(val failure: DsmFailure) : PageUiState<Nothing>
    data class Content<T>(val value: T) : PageUiState<T>
}

internal fun <T> Loadable<T>.toPageUiState(
    isEmpty: (T) -> Boolean = { false },
    isFilteredEmpty: (T) -> Boolean = { false },
): PageUiState<T> = when (this) {
    Loadable.Idle, Loadable.Loading -> PageUiState.Loading
    is Loadable.Failed -> PageUiState.Error(error)
    is Loadable.Ready -> when {
        isFilteredEmpty(value) -> PageUiState.FilteredEmpty
        isEmpty(value) -> PageUiState.Empty
        else -> PageUiState.Content(value)
    }
}
