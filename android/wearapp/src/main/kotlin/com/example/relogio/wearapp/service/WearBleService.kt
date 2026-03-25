package com.example.relogio.wearapp.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.example.relogio.wearapp.R
import com.example.relogio.wearapp.ble.BlePeripheralController
import com.example.relogio.wearapp.ble.BleProtocolEngine
import com.example.relogio.wearapp.ble.WearBleStore
import com.example.relogio.wearapp.model.ActiveQuestion
import com.example.relogio.wearapp.model.PeripheralStatus
import com.example.relogio.wearapp.ui.WearAppActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class WearBleService : Service() {
    private val serviceScope =
        CoroutineScope(SupervisorJob() + Dispatchers.IO.limitedParallelism(1))

    private lateinit var controller: BlePeripheralController
    private val engine = BleProtocolEngine()
    private var tickJob: Job? = null
    private var lastPresentedQuestionDeadlineAt: Long? = null
    private var lastQuestionPresentationAttemptAt = 0L

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        controller =
            BlePeripheralController(
                context = this,
                listener =
                    object : BlePeripheralController.Listener {
                        override fun onStatusChanged(
                            status: PeripheralStatus,
                            detail: String,
                        ) {
                            serviceScope.launch {
                                WearBleStore.update {
                                    it.copy(
                                        serviceRunning = it.serviceRunning || status == PeripheralStatus.STARTING || status == PeripheralStatus.ADVERTISING || status == PeripheralStatus.CONNECTED,
                                        peripheralStatus = status,
                                        statusDetail = detail,
                                    )
                                }
                                updateNotification(detail)
                            }
                        }

                        override fun onClientConnected(address: String) {
                            serviceScope.launch {
                                WearBleStore.update {
                                    it.copy(
                                        connectedDeviceAddress = address,
                                        notificationsEnabled = false,
                                    )
                                }
                                engine.onBleConnected()
                                syncSnapshot()
                                flushOutgoing()
                            }
                        }

                        override fun onClientDisconnected() {
                            serviceScope.launch {
                                WearBleStore.update {
                                    it.copy(
                                        connectedDeviceAddress = null,
                                        notificationsEnabled = false,
                                    )
                                }
                                engine.onBleDisconnected()
                                syncSnapshot()
                            }
                        }

                        override fun onNotificationsChanged(enabled: Boolean) {
                            serviceScope.launch {
                                WearBleStore.update { it.copy(notificationsEnabled = enabled) }
                                flushOutgoing()
                            }
                        }

                        override fun onMessageReceived(message: String) {
                            serviceScope.launch {
                                engine.onBleMessage(message)
                                syncSnapshot()
                                flushOutgoing()
                            }
                        }
                    },
            )
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        when (intent?.action) {
            ACTION_START -> startPeripheral()
            ACTION_STOP -> stopPeripheral()
            ACTION_SEND_COMMAND -> {
                val command = intent.getStringExtra(EXTRA_COMMAND) ?: return START_NOT_STICKY
                val label = intent.getStringExtra(EXTRA_ACTION_LABEL) ?: command
                serviceScope.launch {
                    engine.onLocalCommand(command, actionLabel = label)
                    syncSnapshot()
                    flushOutgoing()
                }
            }

            ACTION_CLEAR_LOGS -> {
                serviceScope.launch {
                    engine.clearLogs()
                    syncSnapshot()
                }
            }

            else -> startPeripheral()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        tickJob?.cancel()
        controller.stop()
        cancelQuestionNotification()
        if (WearBleStore.state.value.serviceRunning) {
            WearBleStore.update {
                it.copy(
                    serviceRunning = false,
                    peripheralStatus = PeripheralStatus.STOPPED,
                    statusDetail = "Serviço parado",
                    connectedDeviceAddress = null,
                    notificationsEnabled = false,
                    activeQuestion = null,
                )
            }
        }
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startPeripheral() {
        startForeground(NOTIFICATION_ID, buildNotification(WearBleStore.state.value.statusDetail))
        WearBleStore.update {
            it.copy(
                serviceRunning = true,
                peripheralStatus = PeripheralStatus.STARTING,
                statusDetail = "Iniciando BLE",
            )
        }

        val started = controller.start()
        if (!started) {
            WearBleStore.update { current ->
                current.copy(serviceRunning = false)
            }
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        if (tickJob?.isActive != true) {
            tickJob =
                serviceScope.launch {
                    while (isActive) {
                        engine.tick()
                        syncSnapshot()
                        flushOutgoing()
                        delay(TICK_POLL_MS)
                    }
                }
        }
    }

    private fun stopPeripheral() {
        tickJob?.cancel()
        controller.stop()
        cancelQuestionNotification()
        WearBleStore.update {
            it.copy(
                serviceRunning = false,
                peripheralStatus = PeripheralStatus.STOPPED,
                statusDetail = "Serviço parado",
                connectedDeviceAddress = null,
                notificationsEnabled = false,
                activeQuestion = null,
            )
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun syncSnapshot() {
        val snapshot = engine.snapshot()
        WearBleStore.update {
            it.copy(
                lastRx = snapshot.lastRx,
                lastTx = snapshot.lastTx,
                lastAction = snapshot.lastAction,
                ledEnabled = snapshot.ledEnabled,
                activeQuestion = snapshot.activeQuestion,
            )
        }
        maybePresentQuestion(snapshot.activeQuestion)
    }

    private fun maybePresentQuestion(question: ActiveQuestion?) {
        if (question == null) {
            lastPresentedQuestionDeadlineAt = null
            lastQuestionPresentationAttemptAt = 0L
            cancelQuestionNotification()
            return
        }

        val now = System.currentTimeMillis()
        val isSameQuestion = lastPresentedQuestionDeadlineAt == question.deadlineAtMillis
        if (isSameQuestion && now - lastQuestionPresentationAttemptAt < QUESTION_PRESENTATION_RETRY_MS) {
            return
        }
        lastPresentedQuestionDeadlineAt = question.deadlineAtMillis
        lastQuestionPresentationAttemptAt = now

        val activityIntent = Intent(this, WearAppActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
            putExtra(EXTRA_OPEN_QUESTION, true)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            QUESTION_REQUEST_CODE,
            activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(this, QUESTION_CHANNEL_ID)
            .setContentTitle(getString(R.string.question_notification_title))
            .setContentText(
                question.question.ifBlank { getString(R.string.question_notification_text) },
            )
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(pendingIntent, true)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()

        getSystemService(NotificationManager::class.java).notify(QUESTION_NOTIFICATION_ID, notification)

        // Tenta trazer a activity diretamente caso ela já esteja em foreground
        startActivity(activityIntent)
    }

    private fun cancelQuestionNotification() {
        getSystemService(NotificationManager::class.java).cancel(QUESTION_NOTIFICATION_ID)
    }

    private fun flushOutgoing() {
        engine.flushOutgoing { payload ->
            controller.notifyMessage(payload)
        }
    }

    private fun updateNotification(detail: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(detail))
    }

    private fun buildNotification(detail: String): Notification {
        val openAppIntent =
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, WearAppActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        return NotificationCompat
            .Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(detail)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(openAppIntent)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java)

        // Canal do serviço BLE em background (prioridade baixa, silencioso)
        val serviceChannel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.notification_channel_description)
        }

        // Canal de perguntas (prioridade alta, acende a tela)
        val questionChannel = NotificationChannel(
            QUESTION_CHANNEL_ID,
            getString(R.string.question_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(R.string.question_channel_description)
            enableVibration(true)
            enableLights(true)
        }

        manager.createNotificationChannel(serviceChannel)
        manager.createNotificationChannel(questionChannel)
    }

    companion object {
        private const val CHANNEL_ID = "wear_ble_service"
        private const val QUESTION_CHANNEL_ID = "wear_ble_question"
        private const val NOTIFICATION_ID = 2107
        private const val QUESTION_NOTIFICATION_ID = 2108
        private const val QUESTION_REQUEST_CODE = 42
        private const val TICK_POLL_MS = 250L
        private const val QUESTION_PRESENTATION_RETRY_MS = 2_000L

        private const val ACTION_START = "com.example.relogio.wearapp.action.START"
        private const val ACTION_STOP = "com.example.relogio.wearapp.action.STOP"
        private const val ACTION_SEND_COMMAND = "com.example.relogio.wearapp.action.SEND_COMMAND"
        private const val ACTION_CLEAR_LOGS = "com.example.relogio.wearapp.action.CLEAR_LOGS"
        private const val EXTRA_COMMAND = "extra_command"
        private const val EXTRA_ACTION_LABEL = "extra_action_label"
        const val EXTRA_OPEN_QUESTION = "extra_open_question"

        fun startIntent(context: Context): Intent =
            Intent(context, WearBleService::class.java).setAction(ACTION_START)

        fun stopIntent(context: Context): Intent =
            Intent(context, WearBleService::class.java).setAction(ACTION_STOP)

        fun commandIntent(
            context: Context,
            command: String,
            actionLabel: String = command,
        ): Intent =
            Intent(context, WearBleService::class.java)
                .setAction(ACTION_SEND_COMMAND)
                .putExtra(EXTRA_COMMAND, command)
                .putExtra(EXTRA_ACTION_LABEL, actionLabel)

        fun clearLogsIntent(context: Context): Intent =
            Intent(context, WearBleService::class.java).setAction(ACTION_CLEAR_LOGS)

        fun startForeground(context: Context) {
            ContextCompat.startForegroundService(context, startIntent(context))
        }
    }
}
