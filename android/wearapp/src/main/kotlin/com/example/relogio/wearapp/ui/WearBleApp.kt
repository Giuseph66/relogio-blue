package com.example.relogio.wearapp.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bluetooth
import androidx.compose.material.icons.filled.CleaningServices
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Send
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material3.Icon
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.SwitchButton
import androidx.wear.compose.material3.Text
import com.example.relogio.wearapp.R
import com.example.relogio.wearapp.model.ActiveQuestion
import com.example.relogio.wearapp.model.PeripheralStatus
import com.example.relogio.wearapp.model.QuestionOption
import com.example.relogio.wearapp.model.WearBleUiState
import kotlinx.coroutines.delay
import kotlin.math.max

private val ScreenBackground = Color(0xFF02070A)
private val HeaderBackground = Color(0xFF082233)
private val PanelBackground = Color(0xFF0A1721)
private val PanelAltBackground = Color(0xFF102330)
private val BorderColor = Color(0xFF21475E)
private val CyanAccent = Color(0xFF66E2FF)
private val OrangeAccent = Color(0xFFFF9A2B)
private val GreenAccent = Color(0xFF67E480)
private val YellowAccent = Color(0xFFFFD84D)
private val RedAccent = Color(0xFFFF6B6B)
private val BlueAccent = Color(0xFF2F8BFF)
private val MutedText = Color(0xFF9AB6C4)

@Composable
fun WearBleApp(
    uiState: WearBleUiState,
    currentScreen: WearScreen,
    permissionsGranted: Boolean,
    onNavigate: (WearScreen) -> Unit,
    onToggleService: (Boolean) -> Unit,
    onRequestPermissions: () -> Unit,
    onCommand: (String, String) -> Unit,
    onClearLogs: () -> Unit,
    onAnswer: (QuestionOption) -> Unit,
) {
    Box(
        modifier =
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(Color(0xFF04111A), ScreenBackground),
                    ),
                ),
    ) {
        Column(
            modifier =
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 10.dp, vertical = 12.dp),
        ) {
            HeaderSection(currentScreen = currentScreen, onNavigate = onNavigate)
            Spacer(modifier = Modifier.height(10.dp))

            when (currentScreen) {
                WearScreen.STATUS ->
                    StatusScreen(
                        uiState = uiState,
                        permissionsGranted = permissionsGranted,
                        onToggleService = onToggleService,
                        onRequestPermissions = onRequestPermissions,
                    )

                WearScreen.CONTROLS ->
                    ControlsScreen(
                        uiState = uiState,
                        onCommand = onCommand,
                        onClearLogs = onClearLogs,
                    )
            }
        }

        uiState.activeQuestion?.let { question ->
            QuestionOverlay(question = question, onAnswer = onAnswer)
        }
    }
}

@Composable
private fun HeaderSection(
    currentScreen: WearScreen,
    onNavigate: (WearScreen) -> Unit,
) {
    Panel(
        modifier = Modifier.fillMaxWidth(),
        background = HeaderBackground,
        border = CyanAccent,
    ) {
        Column {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Image(
                    painter = painterResource(R.drawable.relogio),
                    contentDescription = stringResource(R.string.watch_logo_content_description),
                    modifier =
                        Modifier
                            .size(42.dp)
                            .clip(RoundedCornerShape(12.dp)),
                    contentScale = ContentScale.Fit,
                )
                Spacer(modifier = Modifier.width(10.dp))
                Column {
                    Text(
                        text = "GEONEXO",
                        style = MaterialTheme.typography.titleMedium,
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = "WATCH",
                        style = MaterialTheme.typography.bodySmall,
                        color = MutedText,
                    )
                }
            }

            Spacer(modifier = Modifier.height(10.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HeaderTab(
                    label = "STATUS",
                    selected = currentScreen == WearScreen.STATUS,
                    activeColor = CyanAccent,
                    modifier = Modifier.weight(1f),
                    onClick = { onNavigate(WearScreen.STATUS) },
                )
                HeaderTab(
                    label = "CTRL",
                    selected = currentScreen == WearScreen.CONTROLS,
                    activeColor = OrangeAccent,
                    modifier = Modifier.weight(1f),
                    onClick = { onNavigate(WearScreen.CONTROLS) },
                )
            }
        }
    }
}

@Composable
private fun StatusScreen(
    uiState: WearBleUiState,
    permissionsGranted: Boolean,
    onToggleService: (Boolean) -> Unit,
    onRequestPermissions: () -> Unit,
) {
    Panel(
        modifier = Modifier.fillMaxWidth(),
        background = PanelBackground,
        border = statusAccent(uiState.peripheralStatus),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                StatusIcon(
                    icon = Icons.Default.Bluetooth,
                    tint = statusAccent(uiState.peripheralStatus),
                )
                Spacer(modifier = Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Conexão BLE",
                        style = MaterialTheme.typography.titleSmall,
                        color = Color.White,
                    )
                    Text(
                        text = uiState.statusDetail,
                        style = MaterialTheme.typography.bodySmall,
                        color = MutedText,
                    )
                }
            }

            SwitchButton(
                checked = uiState.serviceRunning,
                onCheckedChange = onToggleService,
                modifier = Modifier.fillMaxWidth(),
                label = {
                    Text(
                        if (uiState.serviceRunning) "BLE ativo" else "BLE parado",
                        color = Color.White,
                    )
                },
                secondaryLabel = {
                    Text(
                        uiState.peripheralStatus.label(),
                        color = MutedText,
                    )
                },
            )

            if (!permissionsGranted) {
                ActionPill(
                    label = "Conceder permissões",
                    accent = YellowAccent,
                    modifier = Modifier.fillMaxWidth(),
                    onClick = onRequestPermissions,
                )
            }
        }
    }

    Spacer(modifier = Modifier.height(10.dp))

    Panel(
        modifier = Modifier.fillMaxWidth(),
        background = PanelBackground,
        border = BorderColor,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = "Estado rápido",
                style = MaterialTheme.typography.titleSmall,
                color = Color.White,
            )
            StatusBadge(
                modifier = Modifier.fillMaxWidth(),
                title = "Notify",
                value = if (uiState.notificationsEnabled) "ATIVO" else "PARADO",
                accent = if (uiState.notificationsEnabled) CyanAccent else BorderColor,
                icon = Icons.Default.NotificationsActive,
            )
            StatusBadge(
                modifier = Modifier.fillMaxWidth(),
                title = "Cliente",
                value = uiState.connectedDeviceAddress ?: "Aguardando conexão",
                accent = if (uiState.connectedDeviceAddress != null) GreenAccent else BorderColor,
                icon = if (uiState.connectedDeviceAddress != null) Icons.Default.Bluetooth else Icons.Default.LinkOff,
            )
        }
    }

    Spacer(modifier = Modifier.height(10.dp))

    Panel(
        modifier = Modifier.fillMaxWidth(),
        background = PanelAltBackground,
        border = BorderColor,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = "Log de atividade",
                style = MaterialTheme.typography.titleSmall,
                color = Color.White,
            )
            LogRow(label = "RX", value = uiState.lastRx, accent = GreenAccent)
            LogRow(label = "TX", value = uiState.lastTx, accent = CyanAccent)
            LogRow(label = "TOQ", value = uiState.lastAction, accent = OrangeAccent)
        }
    }
}

@Composable
private fun ControlsScreen(
    uiState: WearBleUiState,
    onCommand: (String, String) -> Unit,
    onClearLogs: () -> Unit,
) {
    Panel(
        modifier = Modifier.fillMaxWidth(),
        background = PanelBackground,
        border = OrangeAccent,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                text = "Ações BLE",
                style = MaterialTheme.typography.titleSmall,
                color = Color.White,
            )

            ActionTile(
                modifier = Modifier.fillMaxWidth(),
                label = "PING",
                accent = CyanAccent,
                icon = Icons.Default.Send,
                enabled = uiState.serviceRunning,
                onClick = { onCommand("PING", "PING") },
            )

            ActionPill(
                label = "Emular pergunta",
                accent = BlueAccent,
                modifier = Modifier.fillMaxWidth(),
                enabled = uiState.serviceRunning,
                icon = Icons.Default.HelpOutline,
                onClick = {
                    onCommand(
                        "QST|demo|Deseja prosseguir?|sim:SIM|nao:NAO",
                        "EMULAR_QST",
                    )
                },
            )

            ActionPill(
                label = "Limpar log",
                accent = OrangeAccent,
                modifier = Modifier.fillMaxWidth(),
                enabled = uiState.serviceRunning,
                icon = Icons.Default.CleaningServices,
                onClick = onClearLogs,
            )
        }
    }
}

@Composable
private fun QuestionOverlay(
    question: ActiveQuestion,
    onAnswer: (QuestionOption) -> Unit,
) {
    var remainingMillis by remember(question.deadlineAtMillis) {
        mutableLongStateOf(max(0L, question.deadlineAtMillis - System.currentTimeMillis()))
    }
    var progress by remember(question.deadlineAtMillis) { mutableFloatStateOf(1f) }

    LaunchedEffect(question.deadlineAtMillis) {
        while (remainingMillis > 0L) {
            val now = System.currentTimeMillis()
            remainingMillis = max(0L, question.deadlineAtMillis - now)
            progress = (remainingMillis / 10_000f).coerceIn(0f, 1f)
            delay(250)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xD9000000)),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Panel(
                modifier = Modifier.fillMaxWidth(),
                background = PanelBackground,
                border = CyanAccent,
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        text = "NOVA PERGUNTA",
                        style = MaterialTheme.typography.titleMedium,
                        color = CyanAccent,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center,
                    )
                    CountdownBar(progress = progress)
                    Text(
                        text = question.question,
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White,
                        textAlign = TextAlign.Center,
                    )
                    QuestionOptions(options = question.options, onAnswer = onAnswer)
                }
            }
        }
    }
}

@Composable
private fun QuestionOptions(
    options: List<QuestionOption>,
    onAnswer: (QuestionOption) -> Unit,
) {
    if (options.size <= 2) {
        options.forEachIndexed { index, option ->
            ActionPill(
                label = option.label,
                accent = questionOptionAccent(index),
                modifier = Modifier.fillMaxWidth(),
                onClick = { onAnswer(option) },
            )
        }
    } else {
        // Grid 2×2 para 3–4 opções
        options.chunked(2).forEachIndexed { rowIndex, rowOptions ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                rowOptions.forEachIndexed { colIndex, option ->
                    ActionPill(
                        label = option.label,
                        accent = questionOptionAccent(rowIndex * 2 + colIndex),
                        modifier = Modifier.weight(1f),
                        onClick = { onAnswer(option) },
                    )
                }
                // Preenche espaço se última linha tiver opção ímpar
                if (rowOptions.size < 2) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun Panel(
    modifier: Modifier = Modifier,
    background: Color,
    border: Color,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier =
            modifier
                .clip(RoundedCornerShape(22.dp))
                .border(width = 1.5.dp, color = border, shape = RoundedCornerShape(22.dp))
                .background(background)
                .padding(12.dp),
        content = content,
    )
}

@Composable
private fun HeaderTab(
    label: String,
    selected: Boolean,
    activeColor: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier =
            modifier
                .clip(RoundedCornerShape(999.dp))
                .background(if (selected) activeColor else PanelAltBackground)
                .clickable(onClick = onClick)
                .padding(vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = if (selected) PanelBackground else MutedText,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
        )
    }
}

@Composable
private fun StatusIcon(
    icon: ImageVector,
    tint: Color,
) {
    Box(
        modifier =
            Modifier
                .size(42.dp)
                .clip(CircleShape)
                .background(tint.copy(alpha = 0.16f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(22.dp),
        )
    }
}

@Composable
private fun StatusBadge(
    modifier: Modifier = Modifier,
    title: String,
    value: String,
    accent: Color,
    icon: ImageVector,
) {
    Column(
        modifier =
            modifier
                .clip(RoundedCornerShape(18.dp))
                .background(PanelAltBackground)
                .padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = accent,
                modifier = Modifier.size(16.dp),
            )
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = title,
                color = MutedText,
                style = MaterialTheme.typography.labelSmall,
            )
        }
        Text(
            text = value,
            color = Color.White,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
private fun LogRow(
    label: String,
    value: String,
    accent: Color,
) {
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(PanelBackground)
                .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            color = accent,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
        )
        Spacer(modifier = Modifier.width(10.dp))
        Text(
            text = value,
            color = Color.White,
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

@Composable
private fun ActionTile(
    modifier: Modifier = Modifier,
    label: String,
    accent: Color,
    icon: ImageVector,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Column(
        modifier =
            modifier
                .clip(RoundedCornerShape(20.dp))
                .background(if (enabled) PanelAltBackground else PanelAltBackground.copy(alpha = 0.45f))
                .clickable(enabled = enabled, onClick = onClick)
                .padding(horizontal = 10.dp, vertical = 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        StatusIcon(icon = icon, tint = accent)
        Text(
            text = label,
            color = if (enabled) Color.White else MutedText.copy(alpha = 0.7f),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
        )
    }
}

@Composable
private fun ActionPill(
    label: String,
    accent: Color,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    icon: ImageVector? = null,
    onClick: () -> Unit,
) {
    Row(
        modifier =
            modifier
                .clip(RoundedCornerShape(999.dp))
                .background(if (enabled) accent else accent.copy(alpha = 0.35f))
                .clickable(enabled = enabled, onClick = onClick)
                .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        if (icon != null) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = PanelBackground,
                modifier = Modifier.size(16.dp),
            )
            Spacer(modifier = Modifier.width(8.dp))
        }
        Text(
            text = label,
            color = PanelBackground,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun CountdownBar(progress: Float) {
    Box(
        modifier =
            Modifier
                .fillMaxWidth()
                .height(8.dp)
                .clip(RoundedCornerShape(999.dp))
                .background(BorderColor),
    ) {
        Box(
            modifier =
                Modifier
                    .fillMaxWidth(progress.coerceIn(0f, 1f))
                    .height(8.dp)
                    .clip(RoundedCornerShape(999.dp))
                    .background(
                        when {
                            progress > 0.45f -> CyanAccent
                            progress > 0.20f -> YellowAccent
                            else -> RedAccent
                        },
                    ),
        )
    }
}

private fun PeripheralStatus.label(): String =
    when (this) {
        PeripheralStatus.STOPPED -> "Parado"
        PeripheralStatus.STARTING -> "Iniciando"
        PeripheralStatus.ADVERTISING -> "Anunciando"
        PeripheralStatus.CONNECTED -> "Conectado"
        PeripheralStatus.UNSUPPORTED -> "Sem suporte"
        PeripheralStatus.ERROR -> "Erro"
        PeripheralStatus.PERMISSION_REQUIRED -> "Permissão"
    }

private fun statusAccent(status: PeripheralStatus): Color =
    when (status) {
        PeripheralStatus.CONNECTED -> GreenAccent
        PeripheralStatus.ADVERTISING -> CyanAccent
        PeripheralStatus.STARTING -> BlueAccent
        PeripheralStatus.UNSUPPORTED -> OrangeAccent
        PeripheralStatus.ERROR -> RedAccent
        PeripheralStatus.PERMISSION_REQUIRED -> YellowAccent
        PeripheralStatus.STOPPED -> BorderColor
    }

private fun questionOptionAccent(index: Int): Color =
    when (index % 4) {
        0 -> GreenAccent
        1 -> BlueAccent
        2 -> OrangeAccent
        else -> RedAccent
    }
