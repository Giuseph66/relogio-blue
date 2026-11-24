import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geonexo_mobile/core/auth/account_api.dart';
import 'package:geonexo_mobile/core/auth/auth_service.dart';
import 'package:geonexo_mobile/features/profile/data/profile_service.dart';
import 'package:geonexo_mobile/features/profile/domain/user_profile.dart';
import 'package:geonexo_mobile/features/profile/presentation/pages/edit_profile_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserProfile profile(Map<String, dynamic> json) => UserProfile.fromJson(json);

/// Minimal stand-in for /api/account, with one profile per e-mail.
class FakeServer {
  bool online = true;
  bool expired = false;
  final profiles = <String, (Map<String, dynamic>, int)>{};
  Future<void>? holdPut;
  Completer<void>? putStarted;

  Future<http.Response> handle(http.Request request) async {
    if (!online) throw http.ClientException('offline');
    http.Response json(int status, Object body) => http.Response.bytes(
        utf8.encode(jsonEncode(body)), status);
    final path = request.url.path.split('/api/account').last;
    final body = request.body.isEmpty ? {} : jsonDecode(request.body) as Map;
    if (path == '/login' || path == '/register') {
      final email = body['email'] as String;
      if (body['password'] != 'senha-segura') {
        return json(401, {'error': 'E-mail ou senha incorretos.'});
      }
      return json(200, {'user': {'id': 'id-$email', 'email': email}, 'token': 't:$email'});
    }
    if (path == '/logout') return json(200, {'ok': true});
    final email = request.headers['Authorization']?.replaceFirst('Bearer t:', '');
    if (email == null || expired) return json(401, {'error': 'Sessão expirada.'});
    if (path.isEmpty) return json(200, {'ok': true});
    Object view((Map<String, dynamic>, int) p) => {'profile': p.$1, 'revision': p.$2};
    if (request.method == 'GET') {
      return json(200, view(profiles[email] ?? (<String, dynamic>{}, 0)));
    }
    putStarted?.complete();
    putStarted = null;
    await holdPut;
    final current = profiles[email] ?? (<String, dynamic>{}, 0);
    if (body['revision'] != current.$2) return json(409, view(current));
    profiles[email] = (Map<String, dynamic>.from(body['profile'] as Map), current.$2 + 1);
    return json(200, view(profiles[email]!));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = AuthService();
  final service = ProfileService();
  final server = FakeServer();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    AccountApi.client = MockClient(server.handle);
    await service.init();
  });

  setUp(() async {
    server
      ..online = true
      ..expired = false
      ..holdPut = null
      ..profiles.clear();
    await service.sync();
    await auth.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await service.save(UserProfile.empty);
  });

  group('model', () {
    test('every field is optional and round-trips', () {
      expect(profile({}).isEmpty, isTrue);
      expect(profile({'name': '  ', 'sex': 'x', 'occupations': []}).isEmpty, isTrue);
      final full = profile({
        'name': ' Giuseppe ', 'birthDate': '2004-01-31', 'sex': 'masculino',
        'city': 'Cuiabá', 'occupations': ['empregado', 'estudante'],
      });
      expect(full.name, 'Giuseppe');
      expect(full.occupations, ['estudante', 'empregado']);
      expect(profile(jsonDecode(jsonEncode(full.toJson())) as Map<String, dynamic>), full);
    });

    test('age counts only completed birthdays', () {
      final p = profile({'birthDate': '2004-11-24'});
      expect(p.ageAt(DateTime(2026, 11, 23)), 21);
      expect(p.ageAt(DateTime(2026, 11, 24)), 22);
    });

    test('birth dates must be real and in the past', () {
      expect(parseBirthDate('31/01/2004'), '2004-01-31');
      for (final bad in ['30/02/2004', '1/1/2004', '01/13/2004', '01/01/1899', '01/01/2999', 'x']) {
        expect(parseBirthDate(bad), isNull, reason: bad);
      }
    });
  });

  test('guest profile works offline and stays only on the device', () async {
    server.online = false;
    await service.save(profile({'name': 'Ana'}));
    expect(service.record.value.profile.name, 'Ana');
    expect(service.record.value.dirty, isFalse);
    expect(server.profiles, isEmpty);
  });

  test('guest profile moves into a new account and syncs', () async {
    await service.save(profile({'name': 'Ana'}));
    await auth.register('a@x.com', 'senha-segura');
    expect(await service.sync(), isTrue);
    expect(server.profiles['a@x.com']!.$1, {'name': 'Ana'});
    await auth.logout();
    expect(service.record.value.profile.isEmpty, isTrue);
  });

  test('guest profile never replaces an existing account profile', () async {
    server.profiles['a@x.com'] = ({'name': 'Conta'}, 3);
    await service.save(profile({'name': 'Visitante', 'city': 'X'}));
    await auth.login('a@x.com', 'senha-segura');
    await service.sync();
    expect(service.record.value.profile, profile({'name': 'Conta'}));
    expect(server.profiles['a@x.com']!.$2, 3);
  });

  test('offline edits merge with edits from the other device', () async {
    server.profiles['a@x.com'] = ({'name': 'Ana', 'city': 'A'}, 1);
    await auth.login('a@x.com', 'senha-segura');
    await service.sync();
    server.online = false;
    await service.save(profile({'name': 'Ana Maria', 'city': 'A'}));
    expect(await service.sync(), isFalse);
    expect(service.record.value.dirty, isTrue);
    server.online = true;
    server.profiles['a@x.com'] = ({'name': 'Ana', 'city': 'B'}, 2);
    expect(await service.sync(), isTrue);
    expect(server.profiles['a@x.com']!.$1, {'name': 'Ana Maria', 'city': 'B'});
    expect(service.record.value.dirty, isFalse);
  });

  test('a write conflict during PUT is merged and retried', () async {
    await auth.login('a@x.com', 'senha-segura');
    await service.sync();
    final started = server.putStarted = Completer<void>();
    final hold = Completer<void>();
    server.holdPut = hold.future;
    await service.save(profile({'name': 'Ana'}));
    await started.future;
    server.profiles['a@x.com'] = ({'city': 'B'}, 1);
    hold.complete();
    expect(await service.sync(), isTrue);
    expect(server.profiles['a@x.com']!.$1, {'name': 'Ana', 'city': 'B'});
  });

  test('an edit made during a running sync is not lost', () async {
    await auth.login('a@x.com', 'senha-segura');
    await service.sync();
    final started = server.putStarted = Completer<void>();
    final hold = Completer<void>();
    server.holdPut = hold.future;
    await service.save(profile({'name': 'Ana'}));
    await started.future;
    await service.save(profile({'name': 'Ana', 'city': 'B'}));
    hold.complete();
    expect(await service.sync(), isTrue);
    expect(server.profiles['a@x.com']!.$1, {'name': 'Ana', 'city': 'B'});
  });

  test('accounts sharing a device stay apart; unsent edits survive logout', () async {
    await auth.login('a@x.com', 'senha-segura');
    await service.sync();
    server.online = false;
    await service.save(profile({'name': 'Ana'}));
    await service.sync();
    await auth.logout();
    server.online = true;
    await auth.login('b@x.com', 'senha-segura');
    await service.sync();
    expect(service.record.value.profile.isEmpty, isTrue);
    expect(server.profiles, isEmpty);
    await auth.logout();
    await auth.login('a@x.com', 'senha-segura');
    expect(await service.sync(), isTrue);
    expect(server.profiles['a@x.com']!.$1, {'name': 'Ana'});
  });

  test('expired session keeps unsent edits for the next login', () async {
    await auth.login('a@x.com', 'senha-segura');
    await service.sync();
    server.expired = true;
    await service.save(profile({'name': 'Ana'}));
    await service.sync();
    expect(auth.account, isNull);
    expect(auth.sessionExpired, isTrue);
    server.expired = false;
    await auth.login('a@x.com', 'senha-segura');
    expect(await service.sync(), isTrue);
    expect(server.profiles['a@x.com']!.$1, {'name': 'Ana'});
  });

  test('participant login never grants admin; offline restart keeps it', () async {
    expect(await auth.login('a@x.com', 'errada'), isFalse);
    expect(await auth.login('a@x.com', 'senha-segura'), isTrue);
    expect(auth.isAuthenticated, isFalse);
    expect(auth.hasAppSession, isTrue);
    server.online = false;
    auth.accountNotifier.value = null;
    await auth.init();
    expect(auth.account!.email, 'a@x.com');
    expect(auth.accountToken, 't:a@x.com');
  });

  test('deleting the account clears the device copy', () async {
    await auth.login('a@x.com', 'senha-segura');
    await service.save(profile({'name': 'Ana'}));
    await service.sync();
    await service.deleteAccount('senha-segura');
    final prefs = await SharedPreferences.getInstance();
    expect(auth.account, isNull);
    expect(prefs.getKeys().where((k) => k.contains('a@x.com')), isEmpty);
  });

  testWidgets('form saves empty, rejects bad date and saves what was typed', (tester) async {
    Future<void> open() async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => TextButton(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute<void>(builder: (_) => const EditProfilePage())),
          child: const Text('abrir'),
        )),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    Future<void> save() async {
      await tester.ensureVisible(find.text('Salvar'));
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
    }

    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await open();
    await save();
    expect(find.byType(EditProfilePage), findsNothing);

    await open();
    await tester.enterText(find.widgetWithText(TextFormField, 'Data de nascimento'), '30022004');
    expect(find.text('30/02/2004'), findsOneWidget);
    await save();
    expect(find.byType(EditProfilePage), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Data de nascimento'), '31012004');
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Giuseppe');
    await tester.ensureVisible(find.text('Estudante'));
    await tester.tap(find.text('Estudante'));
    await save();
    expect(service.record.value.profile, profile({
      'name': 'Giuseppe', 'birthDate': '2004-01-31', 'occupations': ['estudante'],
    }));
  });
}
