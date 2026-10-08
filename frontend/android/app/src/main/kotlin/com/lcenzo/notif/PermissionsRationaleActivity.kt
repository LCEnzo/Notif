package com.lcenzo.notif

import android.app.Activity
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView

/** What Health Connect shows behind "privacy policy" on Notif's permission screen. */
class PermissionsRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val padding = (24 * resources.displayMetrics.density).toInt()
        val text =
            TextView(this).apply {
                setPadding(padding, padding, padding, padding)
                textSize = 16f
                text = RATIONALE
            }
        setContentView(ScrollView(this).apply { addView(text) })
    }

    private companion object {
        const val RATIONALE =
            "Notif reads steps, resting heart rate and sleep from Health Connect and uploads them to " +
                "the Notif server you sign in to, which keeps them for your own exports.\n\n" +
                "Past data: lets Notif copy what Health Connect held before you granted access.\n\n" +
                "Background: lets the daily sync run while Notif is closed.\n\n" +
                "Notif never writes to Health Connect and shares this data with no one else. Revoking " +
                "access in Health Connect stops the sync; data already uploaded stays on your server."
    }
}
