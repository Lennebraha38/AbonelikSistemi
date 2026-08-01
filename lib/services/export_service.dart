import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/app_database.dart';
import '../models/payment.dart';
import '../models/subscription.dart';

/// CSV / JSON yedek ve ICS takvim dışa aktarma + geri yükleme.
///
/// Dosya yazma/paylaşma kısmı plugin kullanır; CSV/JSON/ICS üreten ve
/// ayrıştıran fonksiyonlar saftır ve birim testlerinde doğrudan çağrılabilir.
class ExportService {
  // ---------- Yardımcılar ----------

  static String _escapeCsv(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  static String _dateOnly(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _icsDate(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  static String _icsStamp(DateTime d) {
    final utc = d.toUtc();
    return '${utc.year}${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}'
        'T${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }

  static String _escapeIcs(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,');

  // ---------- CSV ----------

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
      ].map((e) => _escapeCsv(e.toString())).join(','));
    }
    return buffer.toString();
  }

  /// CSV'yi uygulama klasörüne yazar ve paylaşım menüsünü açar.
  static Future<void> exportCsvAndShare() async {
    final subscriptions = await AppDatabase.instance.getSubscriptions();
    final csv = await buildCsv(subscriptions);

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/abonelikler.csv');
    await file.writeAsString(csv, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Abonelik Listesi (CSV)',
    );
  }

  // ---------- JSON yedekleme ----------

  /// Tüm veriyi (abonelikler + ödemeler) JSON olarak oluşturur.
  static Future<String> buildBackupJson() async {
    final subscriptions = await AppDatabase.instance.getSubscriptions();
    final payments = await AppDatabase.instance.getAllPayments();
    return jsonEncode({
      'app': 'subscription_manager',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'subscriptions': subscriptions.map((s) => s.toMap()).toList(),
      'payments': payments.map((p) => p.toMap()).toList(),
    });
  }

  /// Yedek JSON'u çözümler. Hatalı/eksik formatlarda sağlam davranır.
  static BackupData parseBackupJson(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Geçersiz yedek dosyası');
    }
    final subscriptions = <Subscription>[];
    for (final item in decoded['subscriptions'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      subscriptions.add(
        Subscription.fromMap(item.cast<String, dynamic>()),
      );
    }
    final payments = <Payment>[];
    for (final item in decoded['payments'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      payments.add(Payment.fromMap(item.cast<String, dynamic>()));
    }
    return BackupData(subscriptions: subscriptions, payments: payments);
  }

  /// Yedek dosyasını paylaşım menüsüyle verir.
  static Future<void> exportBackupAndShare() async {
    final json = await buildBackupJson();

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/abonelikler_yedek.json');
    await file.writeAsString(json, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'Abonelik Yöneticisi Yedeği',
    );
  }

  /// Kullanıcının seçtiği JSON yedek dosyasını okur ve çözümler.
  static Future<BackupData?> pickBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    return parseBackupJson(await File(path).readAsString());
  }

  /// Yedeği veritabanına geri yükler.
  /// [replace] true ise mevcut veri silinir, false ise üzerine eklenir.
  static Future<void> restoreBackupData(
    BackupData data, {
    required bool replace,
  }) async {
    if (replace) await AppDatabase.instance.deleteAllData();

    final idMap = <int, int>{};
    for (final sub in data.subscriptions) {
      final newId = await AppDatabase.instance.insertSubscription(sub);
      if (sub.id != null) idMap[sub.id!] = newId;
    }
    for (final payment in data.payments) {
      final mappedId = idMap[payment.subscriptionId];
      if (mappedId == null) continue;
      await AppDatabase.instance.insertPayment(
        Payment(
          subscriptionId: mappedId,
          amount: payment.amount,
          currency: payment.currency,
          paidAt: payment.paidAt,
          note: payment.note,
        ),
      );
    }
  }

  // ---------- ICS takvim ----------

  /// Aktif abonelikler için tekrarlayan takvim etkinlikleri üretir.
  static String buildIcs(List<Subscription> subscriptions) {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//Abonelik Yöneticisi//TR//');
    buffer.writeln('CALSCALE:GREGORIAN');

    for (final s in subscriptions) {
      if (s.isCancelled) continue;
      final next = s.nextRenewalDate;
      buffer.writeln('BEGIN:VEVENT');
      buffer.writeln('UID:sub-${s.id ?? 0}@subscription-manager');
      buffer.writeln('DTSTAMP:${_icsStamp(DateTime.now())}');
      buffer.writeln('DTSTART;VALUE=DATE:${_icsDate(next)}');
      buffer.writeln(
        'SUMMARY:${_escapeIcs(s.name)} yenileme '
        '(${s.price.toStringAsFixed(2)} ${s.currency})',
      );
      buffer.writeln(
        'RRULE:FREQ=${s.billingCycle == 'yearly' ? 'YEARLY' : 'MONTHLY'};'
        'INTERVAL=1',
      );
      buffer.writeln('END:VEVENT');
    }
    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  /// ICS dosyasını paylaşım menüsüyle verir.
  static Future<void> exportIcsAndShare() async {
    final subscriptions = await AppDatabase.instance.getSubscriptions();
    final ics = buildIcs(subscriptions);

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/abonelikler.ics');
    await file.writeAsString(ics, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/calendar')],
      subject: 'Abonelik Takvimi',
    );
  }
}

/// Ayrıştırılmış yedek verisi.
class BackupData {
  final List<Subscription> subscriptions;
  final List<Payment> payments;

  const BackupData({required this.subscriptions, required this.payments});
}
