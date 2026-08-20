package com.liangrui.quotaglance.core

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

class OpenAIServiceStatusTest {
    @Test fun `degraded fixture maps affected components and active incidents`() {
        val body = File("src/test/resources/contracts/ServiceStatus/openai-degraded-response.json").readText()
        val actual = parseOpenAIServiceStatus(body)
        assertEquals(true, actual.available)
        assertEquals("openAI", actual.source)
        assertEquals(ServiceStatusLevel.Degraded, actual.overall)
        assertEquals(listOf("Realtime", "Batch"), actual.affectedComponents.map { it.name })
        assertEquals(listOf("Elevated errors for Realtime"), actual.activeIncidents.map { it.title })
    }
}
