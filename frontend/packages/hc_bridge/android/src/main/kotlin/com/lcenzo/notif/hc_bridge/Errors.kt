package com.lcenzo.notif.hc_bridge

import android.health.connect.HealthConnectException
import android.os.Build
import android.os.RemoteException
import androidx.annotation.RequiresApi
import java.io.IOException

/** The bridge refused its arguments before calling Health Connect. */
internal class BridgeArgumentException(message: String) : IllegalArgumentException(message)

/** Health Connect is not installed, disabled, or too old. */
internal class HealthConnectUnavailableException(message: String) : IllegalStateException(message)

/** A failure as the Dart side sees it: one of `HcErrorCode`'s wire names and a message. */
internal data class BridgeError(val code: String, val message: String)

/**
 * Maps what connect-client throws to an error code. Android 14+ converts a
 * platform `HealthConnectException` to SecurityException, IOException,
 * RemoteException or IllegalArgumentException, and everything else (rate limit
 * included) to IllegalStateException; the pre-14 client uses the same classes
 * plus UnsupportedOperationException for a missing or outdated provider.
 */
internal fun classify(error: Throwable, sdkInt: Int = Build.VERSION.SDK_INT): BridgeError {
    val message = error.message ?: error.javaClass.simpleName
    val code =
        when (error) {
            is BridgeArgumentException -> "invalid_argument"
            is HealthConnectUnavailableException -> "unavailable"
            is SecurityException -> "permission_denied"
            is IOException -> "io"
            is RemoteException -> "remote"
            is IllegalArgumentException -> "invalid_argument"
            is UnsupportedOperationException -> "unavailable"
            is IllegalStateException ->
                if (sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && isRateLimit(error.cause)) {
                    "rate_limited"
                } else {
                    "unexpected"
                }
            else -> "unexpected"
        }
    return BridgeError(code, message)
}

@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
private fun isRateLimit(cause: Throwable?): Boolean =
    cause is HealthConnectException && cause.errorCode == HealthConnectException.ERROR_RATE_LIMIT_EXCEEDED
