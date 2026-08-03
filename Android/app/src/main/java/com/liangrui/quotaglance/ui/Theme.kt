package com.liangrui.quotaglance.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF006A6A),
    onPrimary = Color.White,
    primaryContainer = Color(0xFF8FF3F2),
    secondary = Color(0xFF795900),
    secondaryContainer = Color(0xFFFFDEA0),
    tertiary = Color(0xFF8D3E00),
    tertiaryContainer = Color(0xFFFFDCC7),
    error = Color(0xFFB3261E),
    surface = Color(0xFFFFFBFF),
    surfaceVariant = Color(0xFFDEE5E5),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF72D6D5),
    primaryContainer = Color(0xFF004F50),
    secondary = Color(0xFFEFC36A),
    secondaryContainer = Color(0xFF5D4300),
    tertiary = Color(0xFFFFB784),
    tertiaryContainer = Color(0xFF713000),
    error = Color(0xFFFFB4AB),
)

@Composable
fun QuotaGlanceTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (androidx.compose.foundation.isSystemInDarkTheme()) DarkColors else LightColors, content = content)
}
