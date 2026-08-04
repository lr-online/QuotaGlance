package com.liangrui.quotaglance.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.shape.RoundedCornerShape
import com.liangrui.quotaglance.data.AppThemeMode

private val LightColors = lightColorScheme(
    primary = Color(0xFF129D96),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFC9ECEB),
    onPrimaryContainer = Color(0xFF073C3B),
    secondary = Color(0xFF5D6875),
    secondaryContainer = Color(0xFFE2E8EE),
    tertiary = Color(0xFFB86A28),
    tertiaryContainer = Color(0xFFFFDEC4),
    error = Color(0xFFB3261E),
    background = Color(0xFFF3F5FA),
    surface = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFFE5E9EF),
    surfaceContainerLow = Color(0xFFFFFFFF),
    onSurface = Color(0xFF17202A),
    onSurfaceVariant = Color(0xFF657181),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF4CC8B4),
    onPrimary = Color(0xFF003A35),
    primaryContainer = Color(0xFF15544C),
    onPrimaryContainer = Color(0xFFB2F2E7),
    secondary = Color(0xFFB5C1CD),
    secondaryContainer = Color(0xFF34414D),
    tertiary = Color(0xFFFFB77E),
    tertiaryContainer = Color(0xFF6B3B16),
    error = Color(0xFFFFB4AB),
    background = Color(0xFF0B1013),
    surface = Color(0xFF151C20),
    surfaceVariant = Color(0xFF293238),
    surfaceContainerLow = Color(0xFF182126),
    onSurface = Color(0xFFE6EEF0),
    onSurfaceVariant = Color(0xFFB6C2C5),
)

private val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(18.dp),
    large = RoundedCornerShape(24.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

private val AppTypography = Typography()

@Composable
fun QuotaGlanceTheme(themeMode: AppThemeMode, content: @Composable () -> Unit) {
    val colors = when (themeMode) {
        AppThemeMode.System -> if (androidx.compose.foundation.isSystemInDarkTheme()) DarkColors else LightColors
        AppThemeMode.Light -> LightColors
        AppThemeMode.Dark -> DarkColors
    }
    MaterialTheme(colorScheme = colors, typography = AppTypography, shapes = AppShapes, content = content)
}
