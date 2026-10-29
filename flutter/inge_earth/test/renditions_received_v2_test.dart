import 'package:flutter_test/flutter_test.dart';
import 'package:inge_earth/renditions/v2/received/received_models.dart';

// Pruebas de lógica de Recibidas (las pruebas de widgets y del tablero Metro
// se retiraron con la interfaz Flutter, Visual Zero 2026-10-10).
void main() {
  test(
    'Search covers code, owner and project; periods overlap and orders are deterministic',
    () {
      final rows = [
        ReceivedRendition({
          'rendition_id': 'a',
          'visible_code': 'RDC-2026-000002',
          'owner_name': 'Ana',
          'primary_project_name': 'Norte',
          'period_start': '2026-07-01',
          'period_end': '2026-09-02',
          'submitted_at': '2026-08-30T12:00:00Z',
        }),
        ReceivedRendition({
          'rendition_id': 'b',
          'visible_code': 'RDC-2026-000001',
          'owner_name': 'Luis',
          'primary_project_name': 'Sur',
          'period_start': '2026-09-03',
          'period_end': '2026-09-30',
          'submitted_at': '2026-09-01T12:00:00Z',
          'received_at': '2026-09-02T12:00:00Z',
        }),
      ];
      final f = ReceivedFilter();
      expect(f.apply(rows, 'ANA').single.id, 'a');
      expect(f.apply(rows, 'sur').single.id, 'b');
      expect(f.apply(rows, '000002').single.id, 'a');
      expect(f.apply(rows, '').first.id, 'b');
      f.order = ReceivedOrder.oldest;
      expect(f.apply(rows, '').first.id, 'a');
      f.periodFrom = '2026-08-01';
      f.periodTo = '2026-08-31';
      expect(f.apply(rows, '').single.id, 'a');
      f.periodFrom = '2026-10-01';
      expect(f.valid, false);
      f.clear();
      f.order = ReceivedOrder.code;
      expect(f.apply(rows, '').first.id, 'b');
      expect(rows.first.reception, 'PENDIENTE DE RECEPCIÓN');
      expect(rows.last.reception, 'RECIBIDA');
      expect(receivedDate('2026-09-03'), '03/09/2026');
    },
  );
}
