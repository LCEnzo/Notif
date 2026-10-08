package com.lcenzo.notif.hc_bridge

import android.os.RemoteException
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Test

class ErrorsTest {
    private fun code(error: Throwable, sdkInt: Int = 33) = classify(error, sdkInt).code

    @Test
    fun mapsConnectClientExceptionsToCodes() {
        assertEquals("permission_denied", code(SecurityException("no READ_STEPS")))
        assertEquals("io", code(IOException("disk")))
        assertEquals("remote", code(RemoteException()))
        assertEquals("invalid_argument", code(IllegalArgumentException("bad filter")))
        assertEquals("invalid_argument", code(BridgeArgumentException("bad window")))
        assertEquals("unavailable", code(UnsupportedOperationException("provider needs update")))
        assertEquals("unavailable", code(HealthConnectUnavailableException("not installed")))
        assertEquals("unexpected", code(IllegalStateException("internal")))
        assertEquals("unexpected", code(IllegalStateException("internal"), sdkInt = 34))
        assertEquals("unexpected", code(RuntimeException("boom")))
        assertEquals("unexpected", code(NoClassDefFoundError("android/health/connect/X")))
    }

    @Test
    fun keepsTheMessageOrFallsBackToTheClassName() {
        assertEquals("disk full", classify(IOException("disk full")).message)
        assertEquals("RuntimeException", classify(RuntimeException()).message)
    }
}
