import 'package:flutter/foundation.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/database/app_database.dart';
import '../../data/datasources/watch_response_dao.dart';
import '../../data/repositories/watch_response_repository.dart';
import '../../domain/entities/watch_response.dart';
import '../../../location_tracker/presentation/controllers/visit_question_orchestrator.dart';

class HistoryController extends ChangeNotifier {
  final WatchResponseDao _dao;
  final WatchResponseRepository _repository;
  final VisitQuestionOrchestrator _orchestrator;

  List<WatchResponse> _responses = [];
  bool _isLoading = false;

  List<WatchResponse> get responses => List.unmodifiable(_responses);
  bool get isLoading => _isLoading;

  HistoryController({
    WatchResponseDao? dao,
    WatchResponseRepository? repository,
    required VisitQuestionOrchestrator orchestrator,
  })  : _dao = dao ?? WatchResponseDao(appDb: AppDatabase()),
        _repository = repository ?? WatchResponseRepository(),
        _orchestrator = orchestrator;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _responses = await _dao.getAll();
    _responses.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _isLoading = false;
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _dao.deleteAll();
    _responses = [];
    notifyListeners();
  }

  /// Resend a question to the watch. Returns a human-readable result message.
  Future<String> resendQuestion(WatchResponse r) async {
    final result = await _orchestrator.resend(r);
    switch (result) {
      case ResendResult.sent:
        await load();
        return 'Pergunta reenviada ao relógio.';
      case ResendResult.watchOffline:
        return 'Relógio não conectado. Conecte primeiro.';
      case ResendResult.noCommand:
        return 'Dados da pergunta não disponíveis.';
      case ResendResult.alreadyPending:
        return 'Aguardando resposta do relógio...';
      case ResendResult.sendFailed:
        return 'Falha ao enviar para o relógio.';
    }
  }

  /// Retry server sync for a single answered record.
  Future<String> retrySync(WatchResponse r) async {
    if (r.questionStatus != QuestionStatus.answered) {
      return 'Apenas respostas respondidas podem ser sincronizadas.';
    }
    await _repository.retrySingle(r.id, AppConfig.serverApiUrl);
    await load();
    final updated = _responses.firstWhere((x) => x.id == r.id, orElse: () => r);
    return updated.syncStatus == SyncStatus.synced
        ? 'Sincronizado com sucesso!'
        : 'Falha ao sincronizar. Tente novamente.';
  }
}
