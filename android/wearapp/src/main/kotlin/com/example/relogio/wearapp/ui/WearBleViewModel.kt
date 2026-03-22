package com.example.relogio.wearapp.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import com.example.relogio.wearapp.ble.WearBleStore
import com.example.relogio.wearapp.model.QuestionOption
import com.example.relogio.wearapp.service.WearBleService

enum class WearScreen {
    STATUS,
    CONTROLS,
}

class WearBleViewModel(
    application: Application,
) : AndroidViewModel(application) {
    val uiState = WearBleStore.state
    private val appContext = application.applicationContext

    fun startService() {
        WearBleService.startForeground(appContext)
    }

    fun stopService() {
        appContext.startService(WearBleService.stopIntent(appContext))
    }

    fun sendCommand(
        command: String,
        label: String = command,
    ) {
        appContext.startService(WearBleService.commandIntent(appContext, command, label))
    }

    fun answer(option: QuestionOption) {
        sendCommand(option.id, option.label)
    }

    fun clearLogs() {
        appContext.startService(WearBleService.clearLogsIntent(appContext))
    }
}
