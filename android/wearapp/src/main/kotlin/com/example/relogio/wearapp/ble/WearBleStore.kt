package com.example.relogio.wearapp.ble

import com.example.relogio.wearapp.model.WearBleUiState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

object WearBleStore {
    private val _state = MutableStateFlow(WearBleUiState())
    val state: StateFlow<WearBleUiState> = _state.asStateFlow()

    fun update(transform: (WearBleUiState) -> WearBleUiState) {
        _state.update(transform)
    }
}
