package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.PerformanceSample
import io.github.qwertyuiop1995.dsmnativeclient.localization.localize
import io.github.qwertyuiop1995.dsmnativeclient.ui.formatBytes
import java.text.DateFormat
import java.util.Date

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun NasPerformanceScreen(
    history: List<PerformanceSample>,
    isLoading: Boolean,
    error: DsmFailure?,
    isPaused: Boolean,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onTogglePause: () -> Unit,
    onRetry: () -> Unit,
) {
    DisposableEffect(Unit) {
        onStart()
        onDispose(onStop)
    }
    val latest = history.lastOrNull()
    val timeFormatter = DateFormat.getTimeInstance(DateFormat.MEDIUM)
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.performance),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        stringResource(
                            if (isPaused) R.string.performance_paused_description
                            else R.string.performance_live_description,
                        ),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                OutlinedButton(onClick = onTogglePause) {
                    Icon(
                        if (isPaused) Icons.Outlined.PlayArrow else Icons.Outlined.Pause,
                        contentDescription = null,
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(if (isPaused) R.string.resume else R.string.pause))
                }
            }
        }
        if (isLoading && history.isEmpty()) {
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 32.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(Modifier.width(28.dp))
                    Spacer(Modifier.width(12.dp))
                    Text(stringResource(R.string.performance_loading))
                }
            }
        }
        if (error != null) {
            item {
                val message = error.localize(LocalContext.current).combined
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                        contentColor = MaterialTheme.colorScheme.onErrorContainer,
                    ),
                    modifier = Modifier.semantics {
                        liveRegion = LiveRegionMode.Assertive
                    },
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            stringResource(R.string.performance_error_title),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(message)
                        Button(onClick = onRetry) { Text(stringResource(R.string.retry)) }
                    }
                }
            }
        }
        if (history.isEmpty() && !isLoading && error == null) {
            item {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceContainer,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(
                        modifier = Modifier.padding(20.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            stringResource(R.string.performance_empty),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            stringResource(R.string.performance_empty_message),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (!isPaused) {
                            OutlinedButton(onClick = onRetry) {
                                Text(stringResource(R.string.retry))
                            }
                        }
                    }
                }
            }
        }
        if (latest != null) {
            item {
                Text(
                    stringResource(
                        R.string.performance_latest_sample,
                        timeFormatter.format(Date(latest.timeEpochSeconds * 1_000)),
                    ),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            item {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    PerformanceMetricCard(
                        stringResource(R.string.cpu_usage),
                        formatPercent(latest.cpuPercent),
                        Icons.Outlined.Speed,
                    )
                    PerformanceMetricCard(
                        stringResource(R.string.memory_usage),
                        formatPercent(latest.memoryPercent),
                        Icons.Outlined.Memory,
                    )
                    PerformanceMetricCard(
                        stringResource(R.string.network_receive),
                        formatRate(latest.networkReceiveBytesPerSecond),
                        Icons.Outlined.SwapVert,
                    )
                    PerformanceMetricCard(
                        stringResource(R.string.network_send),
                        formatRate(latest.networkSendBytesPerSecond),
                        Icons.Outlined.SwapVert,
                    )
                    PerformanceMetricCard(
                        stringResource(R.string.disk_read),
                        formatRate(latest.diskReadBytesPerSecond),
                        Icons.Outlined.Storage,
                    )
                    PerformanceMetricCard(
                        stringResource(R.string.disk_write),
                        formatRate(latest.diskWriteBytesPerSecond),
                        Icons.Outlined.Storage,
                    )
                }
            }
            item {
                PerformanceTrendCard(
                    title = stringResource(R.string.performance_processor_memory_title),
                    subtitle = stringResource(R.string.performance_processor_memory_subtitle),
                    history = history,
                    firstLabel = stringResource(R.string.cpu_usage),
                    secondLabel = stringResource(R.string.memory_usage),
                    firstValues = history.map(PerformanceSample::cpuPercent),
                    secondValues = history.map(PerformanceSample::memoryPercent),
                    fixedMaximum = 100.0,
                    formatValue = { formatPercent(it) },
                    timeFormatter = timeFormatter,
                )
            }
            item {
                PerformanceTrendCard(
                    title = stringResource(R.string.performance_network_title),
                    subtitle = stringResource(R.string.performance_network_subtitle),
                    history = history,
                    firstLabel = stringResource(R.string.network_receive),
                    secondLabel = stringResource(R.string.network_send),
                    firstValues = history.map { it.networkReceiveBytesPerSecond?.toDouble() },
                    secondValues = history.map { it.networkSendBytesPerSecond?.toDouble() },
                    formatValue = { formatRate(it?.toLong()) },
                    timeFormatter = timeFormatter,
                )
            }
            item {
                PerformanceTrendCard(
                    title = stringResource(R.string.performance_storage_title),
                    subtitle = stringResource(R.string.performance_storage_subtitle),
                    history = history,
                    firstLabel = stringResource(R.string.disk_read),
                    secondLabel = stringResource(R.string.disk_write),
                    firstValues = history.map { it.diskReadBytesPerSecond?.toDouble() },
                    secondValues = history.map { it.diskWriteBytesPerSecond?.toDouble() },
                    formatValue = { formatRate(it?.toLong()) },
                    timeFormatter = timeFormatter,
                )
            }
        }
    }
}

@Composable
private fun PerformanceMetricCard(
    title: String,
    value: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
        modifier = Modifier.widthIn(min = 148.dp, max = 190.dp),
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(
                title,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun PerformanceTrendCard(
    title: String,
    subtitle: String,
    history: List<PerformanceSample>,
    firstLabel: String,
    secondLabel: String,
    firstValues: List<Double?>,
    secondValues: List<Double?>,
    formatValue: @Composable (Double?) -> String,
    timeFormatter: DateFormat,
    fixedMaximum: Double? = null,
) {
    val latestFirst = formatValue(firstValues.lastOrNull())
    val latestSecond = formatValue(secondValues.lastOrNull())
    val summary = stringResource(
        R.string.performance_chart_summary,
        title,
        "$firstLabel $latestFirst",
        "$secondLabel $latestSecond",
        history.size,
    )
    val firstColor = MaterialTheme.colorScheme.primary
    val secondColor = MaterialTheme.colorScheme.tertiary
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (history.size < 2) {
                Text(
                    stringResource(R.string.performance_collecting_more),
                    modifier = Modifier.padding(vertical = 24.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                PerformanceLineChart(
                    firstValues = firstValues,
                    secondValues = secondValues,
                    firstColor = firstColor,
                    secondColor = secondColor,
                    fixedMaximum = fixedMaximum,
                    summary = summary,
                )
                Text(
                    stringResource(
                        R.string.performance_samples,
                        history.size,
                        timeFormatter.format(Date(history.first().timeEpochSeconds * 1_000)),
                        timeFormatter.format(Date(history.last().timeEpochSeconds * 1_000)),
                    ),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun PerformanceLineChart(
    firstValues: List<Double?>,
    secondValues: List<Double?>,
    firstColor: Color,
    secondColor: Color,
    fixedMaximum: Double?,
    summary: String,
) {
    val maximum = fixedMaximum ?: (firstValues + secondValues)
        .filterNotNull()
        .maxOrNull()
        ?.coerceAtLeast(1.0)
        ?: 1.0
    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(156.dp)
            .clearAndSetSemantics { contentDescription = summary },
    ) {
        val gridColor = firstColor.copy(alpha = 0.14f)
        repeat(3) { row ->
            val y = size.height * row / 2f
            drawLine(gridColor, Offset(0f, y), Offset(size.width, y), strokeWidth = 1.dp.toPx())
        }
        fun path(values: List<Double?>): Path {
            val result = Path()
            var continuing = false
            values.forEachIndexed { index, value ->
                if (value == null) {
                    continuing = false
                } else {
                    val x = size.width * index / (values.size - 1).coerceAtLeast(1)
                    val y = size.height * (1f - (value / maximum).coerceIn(0.0, 1.0).toFloat())
                    if (continuing) result.lineTo(x, y) else result.moveTo(x, y)
                    continuing = true
                }
            }
            return result
        }
        drawPath(path(firstValues), firstColor, style = Stroke(width = 3.dp.toPx()))
        drawPath(
            path(secondValues),
            secondColor,
            style = Stroke(
                width = 3.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(10.dp.toPx(), 7.dp.toPx())),
            ),
        )
    }
}

@Composable
private fun formatPercent(value: Double?): String = value?.let {
    stringResource(R.string.percentage_value, it)
} ?: stringResource(R.string.performance_no_value)

@Composable
private fun formatRate(value: Long?): String = value?.let {
    stringResource(R.string.rate_value, formatBytes(it))
} ?: stringResource(R.string.performance_no_value)
