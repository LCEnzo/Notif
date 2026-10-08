package com.lcenzo.notif.hc_bridge

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.time.Clock
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Channel glue for [HcReader]. Registered in every engine, the WorkManager
 * one included; only `requestPermissions` needs an activity.
 */
class HcBridgePlugin :
    FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var scope = newScope()
    private var reader: HcReader? = null
    private val permissionContract by lazy { PermissionController.createRequestPermissionResultContract() }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel =
            MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
        scope = newScope()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        scope.cancel()
        reader = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    // A rotation keeps the pending request: the recreated activity delivers its result.
    override fun onDetachedFromActivityForConfigChanges() = releaseActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        releaseActivity()
        pendingPermissionResult?.error("no_activity", "the activity went away during the permission request", null)
        pendingPermissionResult = null
    }

    private fun releaseActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> respond(result) { status() }
            "requestPermissions" -> requestPermissions(call, result)
            "readRecords" ->
                respond(result) {
                    reader().readRecords(
                        RecordKind.fromWire(call.requireArgument("type")),
                        call.requireLong("start_ms"),
                        call.requireLong("end_ms"),
                        call.argument<String>("page_token"),
                        call.requireLong("page_size").toInt(),
                    )
                }
            "aggregateHourly" ->
                respond(result) {
                    reader().aggregateHourly(
                        AggregateKind.fromWire(call.requireArgument("metric")),
                        call.requireLong("start_ms"),
                        call.requireLong("end_ms"),
                    )
                }
            "changesToken" -> respond(result) { reader().changesToken(call.requireKinds()) }
            "changes" -> respond(result) { reader().changes(call.requireArgument("token")) }
            "coverageProbe" ->
                respond(result) {
                    reader().coverageProbe(call.requireStringList("types").map(ProbeKind::fromWire).toSet())
                }
            else -> result.notImplemented()
        }
    }

    private fun respond(result: MethodChannel.Result, block: suspend () -> Any?) {
        scope.launch {
            val outcome =
                try {
                    Result.success(withContext(Dispatchers.Default) { block() })
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    // Platform boundary: HC and the binder throw arbitrary types,
                    // NoClassDefFoundError included on old devices. Each one becomes
                    // a typed error code rather than a crash or a null.
                    Result.failure(e)
                }
            outcome.fold(
                onSuccess = { result.success(it) },
                onFailure = {
                    val error = classify(it)
                    result.error(error.code, error.message, null)
                },
            )
        }
    }

    private suspend fun status(): Map<String, Any?> {
        val context = requireContext()
        val sdk = HealthConnectClient.getSdkStatus(context)
        if (sdk != HealthConnectClient.SDK_AVAILABLE) {
            return mapOf(
                "sdk" to
                    if (sdk == HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED) {
                        "update_required"
                    } else {
                        "unavailable"
                    },
                "history" to "unavailable",
                "background" to "unavailable",
                "granted" to emptyList<String>(),
            )
        }
        return reader().status()
    }

    private fun requestPermissions(call: MethodCall, result: MethodChannel.Result) {
        val permissions =
            try {
                call.requireStringList("permissions").toSet().also { requested ->
                    if (requested.isEmpty() || requested.any { !it.startsWith(HEALTH_PERMISSION_PREFIX) }) {
                        throw BridgeArgumentException("permissions must be non-empty Health Connect permissions")
                    }
                }
            } catch (e: BridgeArgumentException) {
                result.error("invalid_argument", e.message, null)
                return
            }
        val activity: Activity =
            activityBinding?.activity
                ?: return result.error("no_activity", "permission requests need a foreground activity", null)
        if (pendingPermissionResult != null) {
            return result.error("request_in_progress", "a permission request is already showing", null)
        }
        if (HealthConnectClient.getSdkStatus(activity) != HealthConnectClient.SDK_AVAILABLE) {
            return result.error("unavailable", "Health Connect is not available", null)
        }
        try {
            permissionContract.getSynchronousResult(activity, permissions)?.let {
                return result.success(it.value.toList())
            }
            pendingPermissionResult = result
            activity.startActivityForResult(permissionContract.createIntent(activity, permissions), REQUEST_CODE)
        } catch (e: Exception) {
            // startActivityForResult throws ActivityNotFoundException and friends.
            pendingPermissionResult = null
            val error = classify(e)
            result.error(error.code, error.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val pending = pendingPermissionResult ?: return true
        pendingPermissionResult = null
        try {
            pending.success(permissionContract.parseResult(resultCode, data).toList())
        } catch (e: Exception) {
            val error = classify(e)
            pending.error(error.code, error.message, null)
        }
        return true
    }

    private fun requireContext(): Context =
        context ?: throw HealthConnectUnavailableException("the plugin is detached from its engine")

    private fun reader(): HcReader {
        reader?.let { return it }
        val context = requireContext()
        if (HealthConnectClient.getSdkStatus(context) != HealthConnectClient.SDK_AVAILABLE) {
            throw HealthConnectUnavailableException("Health Connect is not available")
        }
        return HcReader(
                HealthConnectClient.getOrCreate(context),
                Clock.systemDefaultZone(),
                upsertsWinWithinPage = Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE,
            )
            .also { reader = it }
    }

    private companion object {
        const val CHANNEL = "com.lcenzo.notif/hc_bridge"
        const val HEALTH_PERMISSION_PREFIX = "android.permission.health."

        // Arbitrary; only has to differ from other plugins' request codes.
        const val REQUEST_CODE = 0x4843

        fun newScope() = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    }
}

private fun <T> MethodCall.requireArgument(key: String): T =
    argument<T>(key) ?: throw BridgeArgumentException("missing argument \"$key\"")

// The codec sends a Dart int as Integer or Long depending on its size.
private fun MethodCall.requireLong(key: String): Long =
    when (val value = argument<Any>(key)) {
        is Int -> value.toLong()
        is Long -> value
        else -> throw BridgeArgumentException("argument \"$key\" must be an integer")
    }

private fun MethodCall.requireStringList(key: String): List<String> {
    val value = argument<List<*>>(key) ?: throw BridgeArgumentException("missing argument \"$key\"")
    return value.map { it as? String ?: throw BridgeArgumentException("argument \"$key\" must hold strings") }
}

private fun MethodCall.requireKinds(): Set<RecordKind> = requireStringList("types").map(RecordKind::fromWire).toSet()
