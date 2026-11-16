import 'package:flutter_test/flutter_test.dart';
import 'package:server_core/server_core.dart';

void main() {
  test('Live TV recording follows management, admin, or EnableLiveTvRecording', () {
    expect(
      UserPolicy.fromJson(<String, dynamic>{
        'EnableLiveTvManagement': true,
      }).canRecordLiveTv,
      isTrue,
    );
    expect(
      UserPolicy.fromJson(<String, dynamic>{
        'IsAdministrator': true,
      }).canRecordLiveTv,
      isTrue,
    );
    expect(
      UserPolicy.fromJson(<String, dynamic>{
        'EnableLiveTvRecording': true,
      }).canRecordLiveTv,
      isTrue,
    );
    expect(
      UserPolicy.fromJson(<String, dynamic>{
        'EnableLiveTvAccess': true,
      }).canRecordLiveTv,
      isFalse,
    );
  });
}
