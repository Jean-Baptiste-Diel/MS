package com.mison.serviceuser

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Sortie audio d'un appel : écouteur, haut-parleur ou casque Bluetooth.
 *
 * Agora gère le haut-parleur (setEnableSpeakerphone, côté Dart) et bascule seul
 * sur le Bluetooth quand un casque est connecté ; ce canal liste les sorties
 * disponibles et force l'écouteur ou le Bluetooth, ce qu'Agora ne sait pas faire.
 */
class AudioRouteHandler(context: Context, messenger: BinaryMessenger) {

    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val channel = MethodChannel(messenger, "mison/audio_route")

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getRoutes" -> result.success(routes())
                    "setRoute" -> {
                        setRoute(call.arguments as? String ?: "earpiece")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("AUDIO_ROUTE", e.message, null)
            }
        }
        // Casque Bluetooth connecté / déconnecté pendant l'appel : Dart rafraîchit.
        audioManager.registerAudioDeviceCallback(object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = notifyChanged()
            override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = notifyChanged()
        }, Handler(Looper.getMainLooper()))
    }

    private fun notifyChanged() {
        channel.invokeMethod("routeChanged", null)
    }

    private fun isBluetooth(type: Int): Boolean =
        type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && type == AudioDeviceInfo.TYPE_BLE_HEADSET)

    private fun isWired(type: Int): Boolean =
        type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
            type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
            type == AudioDeviceInfo.TYPE_USB_HEADSET

    private fun routes(): Map<String, Any> {
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val bluetooth = outputs.firstOrNull { isBluetooth(it.type) }
        val current = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val type = audioManager.communicationDevice?.type
            when {
                type == null -> "earpiece"
                type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
                isBluetooth(type) -> "bluetooth"
                isWired(type) -> "wired"
                else -> "earpiece"
            }
        } else {
            @Suppress("DEPRECATION")
            when {
                audioManager.isSpeakerphoneOn -> "speaker"
                audioManager.isBluetoothScoOn -> "bluetooth"
                outputs.any { isWired(it.type) } -> "wired"
                else -> "earpiece"
            }
        }
        return mapOf(
            "current" to current,
            "bluetooth" to (bluetooth != null),
            "bluetoothName" to (bluetooth?.productName?.toString() ?: ""),
        )
    }

    private fun setRoute(route: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val devices = audioManager.availableCommunicationDevices
            val target = when (route) {
                "speaker" -> devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                "bluetooth" -> devices.firstOrNull { isBluetooth(it.type) }
                else -> devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
            }
            if (target != null) audioManager.setCommunicationDevice(target)
            return
        }
        @Suppress("DEPRECATION")
        when (route) {
            "bluetooth" -> {
                audioManager.isSpeakerphoneOn = false
                audioManager.startBluetoothSco()
                audioManager.isBluetoothScoOn = true
            }
            "speaker" -> {
                audioManager.stopBluetoothSco()
                audioManager.isBluetoothScoOn = false
                audioManager.isSpeakerphoneOn = true
            }
            else -> {
                audioManager.stopBluetoothSco()
                audioManager.isBluetoothScoOn = false
                audioManager.isSpeakerphoneOn = false
            }
        }
    }
}
