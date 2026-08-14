package com.liangrui.quotaglance.core

import org.junit.Assert.assertEquals
import org.junit.Test

class ProviderIdTest {
    @Test
    fun `provider identifiers preserve the shared append-only order`() {
        assertEquals(
            listOf("apiInfo", "deepSeek", "kimi", "openRouter", "miniMax", "bioMapCoding"),
            ProviderId.entries.map { it.raw },
        )
    }
}
