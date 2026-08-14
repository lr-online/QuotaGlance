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
    primary = Color(0xFF176B5F),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFBDEFE4),
    onPrimaryContainer = Color(0xFF063B33),
    secondary = Color(0xFF53615E),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFD7E4E0),
    onSecondaryContainer = Color(0xFF101D1A),
    tertiary = Color(0xFF8B5A18),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFFFDFA6),
    onTertiaryContainer = Color(0xFF2B1800),
    error = Color(0xFFB3261E),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
    background = Color(0xFFF6F8F7),
    onBackground = Color(0xFF17201E),
    surface = Color(0xFFFCFDFC),
    onSurface = Color(0xFF17201E),
    surfaceVariant = Color(0xFFE0E9E5),
    onSurfaceVariant = Color(0xFF3F4946),
    outline = Color(0xFF6F7975),
    outlineVariant = Color(0xFFBEC9C4),
    surfaceContainerLow = Color(0xFFF2F6F4),
    surfaceContainer = Color(0xFFEBF1EE),
    surfaceContainerHigh = Color(0xFFE4EBE7),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF88D8C7),
    onPrimary = Color(0xFF00382F),
    primaryContainer = Color(0xFF0D5147),
    onPrimaryContainer = Color(0xFFA4F2E1),
    secondary = Color(0xFFB6CAC4),
    onSecondary = Color(0xFF21332F),
    secondaryContainer = Color(0xFF394B47),
    onSecondaryContainer = Color(0xFFD2E8E2),
    tertiary = Color(0xFFFFC96F),
    onTertiary = Color(0xFF452B00),
    tertiaryContainer = Color(0xFF644A1B),
    onTertiaryContainer = Color(0xFFFFDFA6),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    background = Color(0xFF101513),
    onBackground = Color(0xFFE0E8E4),
    surface = Color(0xFF161D1B),
    onSurface = Color(0xFFE0E8E4),
    surfaceVariant = Color(0xFF3B4743),
    onSurfaceVariant = Color(0xFFBCCBC5),
    outline = Color(0xFF899792),
    outlineVariant = Color(0xFF3B4743),
    surfaceContainerLow = Color(0xFF1B2421),
    surfaceContainer = Color(0xFF202A26),
    surfaceContainerHigh = Color(0xFF2A3531),
)

private val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(20.dp),
    extraLarge = RoundedCornerShape(24.dp),
)

private val AppTypography = Typography().let { base ->
    base.copy(
        headlineLarge = base.headlineLarge.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
        headlineMedium = base.headlineMedium.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
        titleLarge = base.titleLarge.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
        titleMedium = base.titleMedium.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
        labelLarge = base.labelLarge.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Medium),
    )
}

@Composable
fun QuotaGlanceTheme(themeMode: AppThemeMode, content: @Composable () -> Unit) {
    val colors = when (themeMode) {
        AppThemeMode.System -> if (androidx.compose.foundation.isSystemInDarkTheme()) DarkColors else LightColors
        AppThemeMode.Light -> LightColors
        AppThemeMode.Dark -> DarkColors
    }
    MaterialTheme(colorScheme = colors, typography = AppTypography, shapes = AppShapes, content = content)
}
