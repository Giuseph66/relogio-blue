package com.example.relogio.wearapp.model

enum class PeripheralStatus {
    STOPPED,
    STARTING,
    ADVERTISING,
    CONNECTED,
    UNSUPPORTED,
    ERROR,
    PERMISSION_REQUIRED,
}

enum class QuestionMode {
    LEGACY,
    STRUCTURED,
}

data class QuestionOption(
    val id: String,
    val label: String,
)

data class ActiveQuestion(
    val mode: QuestionMode,
    val questionId: String,
    val question: String,
    val options: List<QuestionOption>,
    val deadlineAtMillis: Long,
)

data class ProtocolSnapshot(
    val lastRx: String = "-",
    val lastTx: String = "-",
    val lastAction: String = "-",
    val ledEnabled: Boolean = false,
    val activeQuestion: ActiveQuestion? = null,
)

data class WearBleUiState(
    val serviceRunning: Boolean = false,
    val peripheralStatus: PeripheralStatus = PeripheralStatus.STOPPED,
    val statusDetail: String = "Serviço parado",
    val connectedDeviceAddress: String? = null,
    val notificationsEnabled: Boolean = false,
    val lastRx: String = "-",
    val lastTx: String = "-",
    val lastAction: String = "-",
    val ledEnabled: Boolean = false,
    val activeQuestion: ActiveQuestion? = null,
)
