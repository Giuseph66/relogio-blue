package com.example.relogio.wearapp.ble

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.example.relogio.wearapp.model.PeripheralStatus
import java.nio.charset.StandardCharsets
import java.util.UUID

class BlePeripheralController(
    private val context: Context,
    private val listener: Listener,
) {
    interface Listener {
        fun onStatusChanged(
            status: PeripheralStatus,
            detail: String,
        )

        fun onClientConnected(address: String)

        fun onClientDisconnected()

        fun onNotificationsChanged(enabled: Boolean)

        fun onMessageReceived(message: String)
    }

    private val bluetoothManager =
        context.getSystemService(BluetoothManager::class.java)
    private val serviceUuid = UUID.fromString(BleProtocolEngine.SERVICE_UUID)
    private val characteristicUuid = UUID.fromString(BleProtocolEngine.CHARACTERISTIC_UUID)
    private val cccdUuid = UUID.fromString(CLIENT_CONFIG_UUID)

    private var advertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private var gattCharacteristic: BluetoothGattCharacteristic? = null
    private var connectedDevice: BluetoothDevice? = null
    private var notificationsEnabled = false
    private var running = false
    private var latestValue = "ready".toByteArray(StandardCharsets.UTF_8)

    private val advertiseCallback =
        object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                listener.onStatusChanged(
                    status = if (connectedDevice == null) PeripheralStatus.ADVERTISING else PeripheralStatus.CONNECTED,
                    detail = if (connectedDevice == null) "Anunciando como ${BleProtocolEngine.DEVICE_NAME}" else "Cliente conectado",
                )
            }

            override fun onStartFailure(errorCode: Int) {
                listener.onStatusChanged(
                    status = PeripheralStatus.ERROR,
                    detail = "Falha ao iniciar advertising ($errorCode)",
                )
            }
        }

    private val gattCallback =
        object : BluetoothGattServerCallback() {
            override fun onConnectionStateChange(
                device: BluetoothDevice,
                status: Int,
                newState: Int,
            ) {
                if (!running) {
                    return
                }

                when (newState) {
                    BluetoothGatt.STATE_CONNECTED -> {
                        if (connectedDevice != null && connectedDevice?.address != device.address) {
                            gattServer?.cancelConnection(device)
                            return
                        }

                        connectedDevice = device
                        notificationsEnabled = false
                        listener.onClientConnected(device.address)
                        listener.onNotificationsChanged(false)
                        listener.onStatusChanged(PeripheralStatus.CONNECTED, "Cliente conectado")
                    }

                    BluetoothGatt.STATE_DISCONNECTED -> {
                        if (connectedDevice?.address == device.address) {
                            connectedDevice = null
                            notificationsEnabled = false
                            listener.onClientDisconnected()
                            listener.onNotificationsChanged(false)
                        }

                        if (running) {
                            startAdvertising()
                        }
                    }
                }
            }

            override fun onCharacteristicReadRequest(
                device: BluetoothDevice,
                requestId: Int,
                offset: Int,
                characteristic: BluetoothGattCharacteristic,
            ) {
                if (!hasConnectPermission()) {
                    return
                }

                val value = latestValue.drop(offset).toByteArray()
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }

            override fun onCharacteristicWriteRequest(
                device: BluetoothDevice,
                requestId: Int,
                characteristic: BluetoothGattCharacteristic,
                preparedWrite: Boolean,
                responseNeeded: Boolean,
                offset: Int,
                value: ByteArray?,
            ) {
                if (!hasConnectPermission()) {
                    return
                }

                val payload = value ?: ByteArray(0)
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
                }
                if (payload.isEmpty()) {
                    return
                }

                listener.onMessageReceived(payload.toString(StandardCharsets.UTF_8))
            }

            override fun onDescriptorReadRequest(
                device: BluetoothDevice,
                requestId: Int,
                offset: Int,
                descriptor: BluetoothGattDescriptor,
            ) {
                if (!hasConnectPermission()) {
                    return
                }

                if (descriptor.uuid != cccdUuid) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, offset, null)
                    return
                }

                val value =
                    if (notificationsEnabled) {
                        BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    } else {
                        BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                    }
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }

            override fun onDescriptorWriteRequest(
                device: BluetoothDevice,
                requestId: Int,
                descriptor: BluetoothGattDescriptor,
                preparedWrite: Boolean,
                responseNeeded: Boolean,
                offset: Int,
                value: ByteArray?,
            ) {
                if (!hasConnectPermission()) {
                    return
                }

                if (descriptor.uuid != cccdUuid) {
                    if (responseNeeded) {
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, offset, null)
                    }
                    return
                }

                val enable = value?.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == true
                notificationsEnabled = enable
                descriptor.value =
                    if (enable) {
                        BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    } else {
                        BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                    }
                listener.onNotificationsChanged(enable)

                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                }
            }
        }

    fun start(): Boolean {
        if (!hasBluetoothPermissions()) {
            listener.onStatusChanged(PeripheralStatus.PERMISSION_REQUIRED, "Permissões BLE não concedidas")
            return false
        }

        val adapter = bluetoothManager?.adapter
        if (adapter == null || !context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            listener.onStatusChanged(PeripheralStatus.UNSUPPORTED, "Bluetooth LE indisponível no relógio")
            return false
        }

        if (!adapter.isEnabled) {
            listener.onStatusChanged(PeripheralStatus.ERROR, "Bluetooth do relógio está desligado")
            return false
        }

        if (!adapter.isMultipleAdvertisementSupported) {
            listener.onStatusChanged(PeripheralStatus.UNSUPPORTED, "O relógio não suporta BLE advertising")
            return false
        }

        advertiser = adapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            listener.onStatusChanged(PeripheralStatus.UNSUPPORTED, "BluetoothLeAdvertiser indisponível")
            return false
        }

        listener.onStatusChanged(PeripheralStatus.STARTING, "Subindo servidor GATT")

        @Suppress("DEPRECATION")
        adapter.name = BleProtocolEngine.DEVICE_NAME

        val server =
            bluetoothManager.openGattServer(context, gattCallback)
                ?: run {
                    listener.onStatusChanged(PeripheralStatus.ERROR, "Não foi possível abrir o GATT server")
                    return false
                }

        val characteristic =
            BluetoothGattCharacteristic(
                characteristicUuid,
                BluetoothGattCharacteristic.PROPERTY_READ or
                    BluetoothGattCharacteristic.PROPERTY_WRITE or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                    BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ or
                    BluetoothGattCharacteristic.PERMISSION_WRITE,
            )

        val cccd =
            BluetoothGattDescriptor(
                cccdUuid,
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
            )
        characteristic.addDescriptor(cccd)
        characteristic.value = latestValue

        val service = BluetoothGattService(serviceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(characteristic)

        if (!server.addService(service)) {
            server.close()
            listener.onStatusChanged(PeripheralStatus.ERROR, "Não foi possível registrar o serviço BLE")
            return false
        }

        gattServer = server
        gattCharacteristic = characteristic
        running = true
        startAdvertising()
        return true
    }

    fun stop() {
        running = false
        connectedDevice = null
        notificationsEnabled = false
        advertiser?.stopAdvertising(advertiseCallback)
        advertiser = null
        gattServer?.close()
        gattServer = null
        gattCharacteristic = null
    }

    fun notifyMessage(message: String): Boolean {
        if (!running || !hasConnectPermission()) {
            return false
        }

        val device = connectedDevice ?: return false
        if (!notificationsEnabled) {
            return false
        }

        val characteristic = gattCharacteristic ?: return false
        latestValue = message.toByteArray(StandardCharsets.UTF_8)
        characteristic.value = latestValue
        return gattServer?.notifyCharacteristicChanged(device, characteristic, false) == true
    }

    private fun startAdvertising() {
        if (!running || !hasAdvertisePermission()) {
            return
        }

        advertiser?.stopAdvertising(advertiseCallback)

        val settings =
            AdvertiseSettings
                .Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .setConnectable(true)
                .build()

        val advertiseData =
            AdvertiseData
                .Builder()
                .setIncludeDeviceName(true)
                .addServiceUuid(android.os.ParcelUuid(serviceUuid))
                .build()

        advertiser?.startAdvertising(settings, advertiseData, advertiseCallback)
    }

    private fun hasBluetoothPermissions(): Boolean = hasConnectPermission() && hasAdvertisePermission()

    private fun hasConnectPermission(): Boolean =
        android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun hasAdvertisePermission(): Boolean =
        android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED

    companion object {
        private const val CLIENT_CONFIG_UUID = "00002902-0000-1000-8000-00805f9b34fb"
    }
}
