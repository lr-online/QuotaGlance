package com.liangrui.quotaglance.refresh

import android.util.Log
import com.liangrui.quotaglance.core.ProviderId

fun interface AccountSaveLogger {
    fun record(stage: String, provider: ProviderId, detail: String)
}

object NoopAccountSaveLogger : AccountSaveLogger {
    override fun record(stage: String, provider: ProviderId, detail: String) = Unit
}

/** Emits only bounded diagnostic fields; never log credentials, headers, names, or exception messages. */
class AndroidAccountSaveLogger : AccountSaveLogger {
    override fun record(stage: String, provider: ProviderId, detail: String) {
        val message = "account_save stage=$stage provider=${provider.raw} $detail"
        if (stage == "failure") Log.w(TAG, message) else Log.d(TAG, message)
    }

    private companion object {
        const val TAG = "QuotaGlance/AccountSave"
    }
}
