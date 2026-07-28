package io.github.qwertyuiop1995.dsmnativeclient.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

private val LightColors = lightColorScheme(
    primary = Color(0xFF005AC1),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFD8E2FF),
    onPrimaryContainer = Color(0xFF001A41),
    secondary = Color(0xFF435E91),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFD8E2FF),
    onSecondaryContainer = Color(0xFF001A41),
    tertiary = Color(0xFF006A6A),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFF70F5F5),
    onTertiaryContainer = Color(0xFF002020),
    error = Color(0xFFBA1A1A),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
    background = Color(0xFFF8FAFC),
    onBackground = Color(0xFF191C1E),
    surface = Color(0xFFF8FAFC),
    onSurface = Color(0xFF191C1E),
    surfaceVariant = Color(0xFFE1E2EC),
    onSurfaceVariant = Color(0xFF44474F),
    outline = Color(0xFF757780),
    outlineVariant = Color(0xFFC5C6D0),
    surfaceContainer = Color(0xFFEEF0F5),
    surfaceContainerHigh = Color(0xFFE8EAF0),
    surfaceContainerHighest = Color(0xFFE2E4EA),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFAEC6FF),
    onPrimary = Color(0xFF002E6C),
    primaryContainer = Color(0xFF004494),
    onPrimaryContainer = Color(0xFFD8E2FF),
    secondary = Color(0xFFABC7FF),
    onSecondary = Color(0xFF102F60),
    secondaryContainer = Color(0xFF2A4678),
    onSecondaryContainer = Color(0xFFD8E2FF),
    tertiary = Color(0xFF4CD8D8),
    onTertiary = Color(0xFF003737),
    tertiaryContainer = Color(0xFF004F4F),
    onTertiaryContainer = Color(0xFF70F5F5),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    background = Color(0xFF101318),
    onBackground = Color(0xFFE1E2E5),
    surface = Color(0xFF101318),
    onSurface = Color(0xFFE1E2E5),
    surfaceVariant = Color(0xFF44474F),
    onSurfaceVariant = Color(0xFFC5C6D0),
    outline = Color(0xFF8F909A),
    outlineVariant = Color(0xFF44474F),
    surfaceContainer = Color(0xFF1B1F26),
    surfaceContainerHigh = Color(0xFF22262E),
    surfaceContainerHighest = Color(0xFF2B303A),
)

val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(24.dp),
    extraLarge = RoundedCornerShape(32.dp),
)

@Composable
fun LanStashTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false, // 禁用系统随机动态调色，保持一致的定制工程美学
    content: @Composable () -> Unit,
) {
    val colors = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColors
        else -> LightColors
    }
    MaterialTheme(
        colorScheme = colors,
        shapes = AppShapes,
        typography = MaterialTheme.typography,
        content = content,
    )
}

