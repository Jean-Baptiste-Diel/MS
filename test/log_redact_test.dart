import 'package:booking_system_flutter/utils/log_redact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('les données sensibles sont masquées', () {
    const header = '{"authorization":"Bearer eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyIjoiMSJ9.abc-DEF_123","content-type":"application/json"}';
    const body = '{"fcm_token":"eMG14EekTju9h-F3HaN1MI:APA91bFppqhpq","password":"1234","first_name":"Awa","phone":"+221771234567"}';

    final h = redactForLog(header);
    final b = redactForLog(body);

    expect(h, isNot(contains('eyJ')));
    expect(h, contains('application/json'));
    expect(b, isNot(contains('APA91')));
    expect(b, isNot(contains('1234"')));
    expect(b, isNot(contains('Awa')));
    expect(redactForLog('wss://dev-api.mison.app/ws/chat/1?token=eyJabc.def.ghi'), isNot(contains('eyJ')));
    expect(redactForLog('appel du +221771234567'), 'appel du +22177*****67');
    expect(redactForLog('URL: https://dev-api.mison.app/api/orders'), 'URL: https://dev-api.mison.app/api/orders');
  });
}
