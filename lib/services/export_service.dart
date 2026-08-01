import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/app_database.dart';
import '../models/subscription.dart';

/// Verileri CSV olarak dışa aktarıp paylaşım/indirme menüsüyle sunar.
class ExportService {
  static String _escape(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  static String _dateOnly(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Tüm abonelikleri (iptal edilenler dahil) CSV satırına dönüştürür.
  static Future<String> buildCsv(List<Subscription> subscriptions) async {
    final buffer = StringBuffer();
    buffer.writeln(
      'id,name,price,currency,billing_cycle,start_date,status,category,'
      'trial_end_date,reminder_days,next_renewal_date,days_until_renewal,'
      'monthly_equivalent',
    );
    for (final s in subscriptions) {
      buffer.writeln([
        s.id ?? '',
        s.name,
        s.price,
        s.currency,
        s.billingCycle,
        _dateOnly(s.startDate),
        s.status,
        s.category,
        s.trialEndDate == null ? '' : _dateOnly(s.trialEndDate!),
        s.reminderDays,
        _dateOnly(s.nextRenewalDate),
        s.daysUntilRenewal,
        s.monthlyEquivalent,
      ].map((e) => _escape(e.toString())).join(','));
    }
    return buffer.toString();
  }

  /// CSV'yi uygulama klasörüne yazar ve paylaşım menüsünü açar.
  static Future<void> exportAndShare() async {
    final subscriptions = await AppDatabase.instance.getSubscriptions();
    final csv = await buildCsv(subscriptions);

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/abonelikler.csv');
    await file.writeAsString(csv, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Abonelik Listesi (CSV Yedek)',
    );
  }
}
