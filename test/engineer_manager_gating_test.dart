import 'package:axon/core/auth/auth_state.dart';
import 'package:axon/core/auth/user_model.dart';
import 'package:axon/core/permissions/user_role.dart';
import 'package:axon/features/engineer/engineer_providers.dart';
import 'package:axon/features/engineer/models/clinic_model.dart';
import 'package:axon/features/engineer/models/device_type_model.dart';
import 'package:axon/features/engineer/screens/clinics_tab.dart';
import 'package:axon/features/engineer/screens/device_types_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._status);
  final AuthStatus _status;
  @override
  AuthStatus build() => _status;
}

Future<void> _pump(WidgetTester tester, Widget tab, {required bool isManager}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authStateProvider.overrideWith(() => _FakeAuth(AuthAuthenticated(UserModel(
            id: 1,
            username: 'eng',
            email: '',
            role: UserRole.engineer,
            isManager: isManager,
          )))),
      clinicsListProvider.overrideWith((ref) async => [
            ClinicModel.fromJson({'id': 1, 'name': 'Clinic A', 'address': '', 'phone_number': ''}),
          ]),
      deviceTypesListProvider.overrideWith((ref) async => [
            DeviceTypeModel.fromJson(
                {'id': 1, 'name': 'Type A', 'description': '', 'setup_schema': <String, dynamic>{}, 'is_active': true}),
          ]),
    ],
    child: MaterialApp(home: tab),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('isManager is read from /me and defaults to false', () {
    final base = {'id': 1, 'username': 'e', 'email': '', 'role': 'engineer'};
    expect(UserModel.fromJson(base).isManager, isFalse);
    expect(UserModel.fromJson({...base, 'is_manager': true}).isManager, isTrue);
  });

  for (final (name, tab, addLabel, item) in [
    ('clinics', const ClinicsTab(), 'New Clinic', 'Clinic A'),
    ('device types', const DeviceTypesTab(), 'New Type', 'Type A'),
  ]) {
    testWidgets('$name: regular engineer sees the list without add/edit', (tester) async {
      await _pump(tester, tab, isManager: false);
      expect(find.text(item), findsOneWidget);
      expect(find.text(addLabel), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
    });

    testWidgets('$name: manager can add and edit', (tester) async {
      await _pump(tester, tab, isManager: true);
      expect(find.text(addLabel), findsOneWidget);
      expect(find.byTooltip('Edit'), findsOneWidget);
    });
  }
}
