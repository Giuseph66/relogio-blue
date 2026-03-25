package com.example.relogio.wearapp.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.relogio.wearapp.theme.WearBleTheme

class WearAppActivity : ComponentActivity() {
    private val viewModel by viewModels<WearBleViewModel>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyScreenOnFlags()
        enableEdgeToEdge()

        setContent {
            val uiState by viewModel.uiState.collectAsStateWithLifecycle()
            var currentScreen by remember { mutableStateOf(WearScreen.STATUS) }
            var permissionsGranted by remember { mutableStateOf(WearPermissionHelper.hasAllPermissions(this)) }

            val permissionLauncher =
                rememberLauncherForActivityResult(
                    contract = ActivityResultContracts.RequestMultiplePermissions(),
                ) {
                    permissionsGranted = WearPermissionHelper.hasAllPermissions(this)
                    if (permissionsGranted) {
                        viewModel.startService()
                    }
                }

            WearBleTheme {
                WearBleApp(
                    uiState = uiState,
                    currentScreen = currentScreen,
                    permissionsGranted = permissionsGranted,
                    onNavigate = { currentScreen = it },
                    onToggleService = { enabled ->
                        if (enabled) {
                            if (WearPermissionHelper.hasAllPermissions(this)) {
                                permissionsGranted = true
                                viewModel.startService()
                            } else {
                                permissionsGranted = false
                                permissionLauncher.launch(WearPermissionHelper.requiredPermissions())
                            }
                        } else {
                            viewModel.stopService()
                        }
                    },
                    onRequestPermissions = {
                        permissionLauncher.launch(WearPermissionHelper.requiredPermissions())
                    },
                    onCommand = { command, label -> viewModel.sendCommand(command, label) },
                    onClearLogs = viewModel::clearLogs,
                    onAnswer = viewModel::answer,
                )
            }
        }
    }

    // Chamado quando a activity já existe (singleTask) e chega um novo intent
    // (ex: serviço dispara pergunta com a tela apagada)
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyScreenOnFlags()
    }

    private fun applyScreenOnFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
        )
    }
}

private object WearPermissionHelper {
    fun requiredPermissions(): Array<String> =
        buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(Manifest.permission.BLUETOOTH_SCAN)
                add(Manifest.permission.BLUETOOTH_CONNECT)
                add(Manifest.permission.BLUETOOTH_ADVERTISE)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }.toTypedArray()

    fun hasAllPermissions(activity: ComponentActivity): Boolean =
        requiredPermissions().all { permission ->
            ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED
        }
}
