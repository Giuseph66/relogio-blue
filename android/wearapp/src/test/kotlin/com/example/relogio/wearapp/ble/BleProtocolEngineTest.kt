package com.example.relogio.wearapp.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class BleProtocolEngineTest {
    private var now = 0L

    private fun engine() = BleProtocolEngine(nowProvider = { now })

    @Test
    fun `ping returns pong`() {
        val engine = engine()
        engine.onLocalCommand("PING")

        val sent = mutableListOf<String>()
        engine.flushOutgoing {
            sent += it
            true
        }

        assertEquals(listOf("PONG"), sent)
        assertEquals("PONG", engine.snapshot().lastTx)
    }

    @Test
    fun `structured question answer emits qans`() {
        val engine = engine()
        engine.onBleMessage("QST|abc|Escolha|1:Sim|2:Nao")
        val question = engine.snapshot().activeQuestion
        assertNotNull(question)

        engine.onLocalCommand("2", actionLabel = "Nao")

        val sent = mutableListOf<String>()
        engine.flushOutgoing {
            sent += it
            true
        }

        assertEquals(listOf("QANS|abc|2"), sent.takeLast(1))
        assertNull(engine.snapshot().activeQuestion)
    }

    @Test
    fun `structured question timeout emits qerr`() {
        val engine = engine()
        engine.onBleMessage("QST|abc|Escolha|1:Sim|2:Nao")

        now += 10_001L
        engine.tick()

        val sent = mutableListOf<String>()
        engine.flushOutgoing {
            sent += it
            true
        }

        assertEquals("QERR|abc|TIMEOUT", sent.last())
        assertNull(engine.snapshot().activeQuestion)
    }

    @Test
    fun `legacy question timeout emits legacy timeout text`() {
        val engine = engine()
        engine.onBleMessage("Deseja prosseguir?")

        now += 10_001L
        engine.tick()

        val sent = mutableListOf<String>()
        engine.flushOutgoing {
            sent += it
            true
        }

        assertEquals("Vacoooo(504)", sent.last())
        assertNull(engine.snapshot().activeQuestion)
    }

    @Test
    fun `invalid structured payload emits qerr`() {
        val engine = engine()
        engine.onBleMessage("QST|abc|Escolha|semseparador")

        val sent = mutableListOf<String>()
        engine.flushOutgoing {
            sent += it
            true
        }

        assertEquals(listOf("QERR|unknown|INVALID_FORMAT"), sent)
    }

    @Test
    fun `heartbeat is emitted when connected`() {
        val engine = engine()
        engine.onBleConnected()

        now += 2_001L
        engine.tick()

        val sent = mutableListOf<String>()
        engine.flushOutgoing {
            sent += it
            true
        }

        assertEquals("tick: 1", sent.last())
        assertEquals("ESP32 conectado", engine.snapshot().lastTx)
    }

    @Test
    fun `led commands update logical state`() {
        val engine = engine()
        engine.onLocalCommand("LED_ON")
        assertEquals(true, engine.snapshot().ledEnabled)

        engine.onLocalCommand("LED_OFF")
        assertEquals(false, engine.snapshot().ledEnabled)
    }
}
