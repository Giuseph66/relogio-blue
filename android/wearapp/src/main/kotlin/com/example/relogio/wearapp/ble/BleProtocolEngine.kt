package com.example.relogio.wearapp.ble

import com.example.relogio.wearapp.model.ActiveQuestion
import com.example.relogio.wearapp.model.ProtocolSnapshot
import com.example.relogio.wearapp.model.QuestionMode
import com.example.relogio.wearapp.model.QuestionOption

class BleProtocolEngine(
    private val nowProvider: () -> Long = { System.currentTimeMillis() },
    private val heartbeatIntervalMs: Long = NOTIFY_INTERVAL_MS,
    private val questionTimeoutMs: Long = QUESTION_TIMEOUT_MS,
) {
    private data class OutgoingMessage(
        val payload: String,
        val updateLastTx: Boolean,
    )

    private val outgoingQueue = ArrayDeque<OutgoingMessage>()

    private var connected = false
    private var lastHeartbeatAt = 0L
    private var tickCounter = 0L
    private var awaitingAnswer = false
    private var awaitingStructuredAnswer = false
    private var questionStartTime = 0L
    private var activeQuestionId = ""
    private var activeOptions: List<QuestionOption> = emptyList()

    private var snapshot = ProtocolSnapshot()

    fun snapshot(): ProtocolSnapshot = snapshot

    fun onBleConnected() {
        connected = true
        lastHeartbeatAt = nowProvider()
        enqueueText(if (snapshot.ledEnabled) "LED:ON" else "LED:OFF", updateUi = true)
        enqueueText("ESP32 conectado", updateUi = true)
    }

    fun onBleDisconnected() {
        connected = false
        clearActiveQuestion()
    }

    fun onBleMessage(message: String) {
        val trimmed = message.trim()
        if (trimmed.isEmpty()) {
            return
        }

        snapshot = snapshot.copy(lastRx = trimmed)
        processText(trimmed, fromBle = true)
    }

    fun onLocalCommand(
        command: String,
        actionLabel: String = command,
    ) {
        val trimmed = command.trim()
        if (trimmed.isEmpty()) {
            return
        }

        snapshot = snapshot.copy(lastAction = actionLabel)
        processText(trimmed, fromBle = false)
    }

    fun clearLogs() {
        snapshot = snapshot.copy(
            lastRx = "-",
            lastTx = "-",
            lastAction = "LIMPO",
        )
    }

    fun tick() {
        val now = nowProvider()

        if (awaitingAnswer && now - questionStartTime >= questionTimeoutMs) {
            if (awaitingStructuredAnswer && activeQuestionId.isNotEmpty()) {
                enqueueText("QERR|$activeQuestionId|TIMEOUT", updateUi = true)
            } else {
                enqueueText("Vacoooo(504)", updateUi = true)
            }
            clearActiveQuestion()
        }

        if (connected && now - lastHeartbeatAt >= heartbeatIntervalMs) {
            lastHeartbeatAt = now
            tickCounter += 1
            enqueueText("tick: $tickCounter", updateUi = false)
        }
    }

    fun flushOutgoing(notify: (String) -> Boolean) {
        while (outgoingQueue.isNotEmpty()) {
            val next = outgoingQueue.first()
            if (!notify(next.payload)) {
                return
            }
            outgoingQueue.removeFirst()
        }
    }

    private fun processText(
        message: String,
        fromBle: Boolean,
    ) {
        if (handleStructuredQuestion(message)) {
            return
        }

        if (awaitingAnswer && handleAnswer(message)) {
            return
        }

        if (message.endsWith("?")) {
            val question = message.dropLast(1).trim()
            clearActiveQuestion()
            awaitingAnswer = true
            awaitingStructuredAnswer = false
            questionStartTime = nowProvider()
            snapshot = snapshot.copy(
                activeQuestion = ActiveQuestion(
                    mode = QuestionMode.LEGACY,
                    questionId = LEGACY_QUESTION_ID,
                    question = question,
                    options = legacyOptions(),
                    deadlineAtMillis = questionStartTime + questionTimeoutMs,
                ),
            )
            return
        }

        when (message) {
            "PING" -> enqueueText("PONG", updateUi = true)
            "LED_ON" -> {
                snapshot = snapshot.copy(ledEnabled = true)
                enqueueText("LED:ON", updateUi = true)
            }
            "LED_OFF" -> {
                snapshot = snapshot.copy(ledEnabled = false)
                enqueueText("LED:OFF", updateUi = true)
            }
            "LED_STATUS" -> enqueueText(
                if (snapshot.ledEnabled) "LED:ON" else "LED:OFF",
                updateUi = true,
            )
            else -> enqueueText(
                if (fromBle) "OK: $message" else "TOUCH: $message",
                updateUi = true,
            )
        }
    }

    private fun handleAnswer(message: String): Boolean {
        if (!awaitingAnswer) {
            return false
        }

        if (awaitingStructuredAnswer) {
            val selected = activeOptions.firstOrNull { it.id == message } ?: return false
            enqueueText("QANS|$activeQuestionId|${selected.id}", updateUi = true)
            clearActiveQuestion()
            return true
        }

        if (message != "SIM" && message != "NAO") {
            return false
        }

        enqueueText(message, updateUi = true)
        clearActiveQuestion()
        return true
    }

    private fun handleStructuredQuestion(message: String): Boolean {
        if (!message.startsWith("$QUESTION_HEADER|")) {
            return false
        }

        val parts = message.split("|")
        if (parts.size < 5) {
            enqueueText("QERR|unknown|INVALID_FORMAT", updateUi = true)
            return true
        }

        val questionId = parts[1].trim()
        val question = parts[2].trim()
        if (questionId.isEmpty() || question.isEmpty()) {
            enqueueText("QERR|unknown|INVALID_FORMAT", updateUi = true)
            return true
        }

        val parsedOptions = buildList {
            for (token in parts.drop(3).take(MAX_QUESTION_OPTIONS)) {
                val chunks = token.split(":", limit = 2)
                if (chunks.size != 2) {
                    clear()
                    break
                }

                val optionId = chunks[0].trim()
                val optionLabel = chunks[1].trim()
                if (optionId.isEmpty() || optionLabel.isEmpty()) {
                    clear()
                    break
                }

                add(QuestionOption(id = optionId, label = optionLabel))
            }
        }

        if (parsedOptions.size < MIN_QUESTION_OPTIONS) {
            enqueueText("QERR|unknown|INVALID_FORMAT", updateUi = true)
            return true
        }

        clearActiveQuestion()
        awaitingAnswer = true
        awaitingStructuredAnswer = true
        questionStartTime = nowProvider()
        activeQuestionId = questionId
        activeOptions = parsedOptions
        snapshot = snapshot.copy(
            activeQuestion = ActiveQuestion(
                mode = QuestionMode.STRUCTURED,
                questionId = questionId,
                question = question,
                options = parsedOptions,
                deadlineAtMillis = questionStartTime + questionTimeoutMs,
            ),
        )
        return true
    }

    private fun clearActiveQuestion() {
        awaitingAnswer = false
        awaitingStructuredAnswer = false
        questionStartTime = 0L
        activeQuestionId = ""
        activeOptions = emptyList()
        snapshot = snapshot.copy(activeQuestion = null)
    }

    private fun enqueueText(
        message: String,
        updateUi: Boolean,
    ) {
        outgoingQueue.addLast(
            OutgoingMessage(
                payload = message,
                updateLastTx = updateUi,
            ),
        )
        if (updateUi) {
            snapshot = snapshot.copy(lastTx = message)
        }
    }

    private fun legacyOptions(): List<QuestionOption> =
        listOf(
            QuestionOption(id = "SIM", label = "SIM"),
            QuestionOption(id = "NAO", label = "NAO"),
        )

    companion object {
        const val DEVICE_NAME = "ESP32"
        const val SERVICE_UUID = "0000ffe0-0000-1000-8000-00805f9b34fb"
        const val CHARACTERISTIC_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb"
        const val QUESTION_TIMEOUT_MS = 10_000L
        const val NOTIFY_INTERVAL_MS = 2_000L

        private const val QUESTION_HEADER = "QST"
        private const val LEGACY_QUESTION_ID = "legacy"
        private const val MAX_QUESTION_OPTIONS = 4
        private const val MIN_QUESTION_OPTIONS = 2
    }
}
