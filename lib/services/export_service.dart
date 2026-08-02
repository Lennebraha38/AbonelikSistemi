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
    final payments = await AppDatabase.instance.getAllPayments();
    final subNames = <int, String>{
      for (final s in subscriptions)
        if (s.id != null) s.id!: s.name,
    };
    final csv = await buildCsv(subscriptions);
    final paymentsCsv = await buildPaymentsCsv(payments, subNames);

    final dir = await getApplicationDocumentsDirectory();
    final subFile = File('${dir.path}/abonelikler.csv');
    await subFile.writeAsString(csv, flush: true);
    final payFile = File('${dir.path}/odemeler.csv');
    await payFile.writeAsString(paymentsCsv, flush: true);

    await Share.shareXFiles(
      [
        XFile(subFile.path, mimeType: 'text/csv'),
        XFile(payFile.path, mimeType: 'text/csv'),
      ],
      subject: 'Abonelik Verileri (CSV)',
    );
  }

  /// Ödeme geçmişini CSV'ye dönüştürür. Abonelik adı kimliği yerine
  /// okunabilir olması için yazılır.
  static Future<String> buildPaymentsCsv(
    List<Payment> payments,
    Map<int, String> subscriptionNames,
  ) async {
    final buffer = StringBuffer();
    buffer.writeln('subscription_name,amount,currency,paid_at,note');
    for (final p in payments) {
      buffer.writeln([
        subscriptionNames[p.subscriptionId] ?? '',
        p.amount,
        p.currency,
        p.paidAt.toIso8601String(),
        p.note ?? '',
      ].map((e) => _escapeCsv(e.toString())).join(','));
    }
    return buffer.toString();
  }

  /// CSV satırını tırnak/kaçış kurallarını dikkate alarak parçalar.
  static List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buffer.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buffer.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(c);
      }
    }
    result.add(buffer.toString());
    return result;
  }

  static List<String> _nonEmptyLines(String csv) =>
      csv.split('\n').where((l) => l.trim().isNotEmpty).toList();

  /// Abonelik CSV satırlarını çözer. İlk satır başlık kabul edilir;
  /// bilinmeyen sütunlar yoksayılır, türetilmiş alanlar atlanır.
  static List<Subscription> _parseSubscriptionRows(List<String> lines) {
    final header = _parseCsvLine(lines.first);
    final idx = <String, int>{
      for (var i = 0; i < header.length; i++) header[i].trim(): i,
    };
    int? at(String name) => idx[name];

    final result = <Subscription>[];
    for (final line in lines.skip(1)) {
      final cells = _parseCsvLine(line);
      String cell(String name, [String fallback = '']) {
        final i = at(name);
        if (i == null || i >= cells.length) return fallback;
        return cells[i].trim();
      }

      final name = cell('name');
      final price = double.tryParse(cell('price').replaceAll(',', '.'));
      final currency = cell('currency');
      if (name.isEmpty || price == null || price <= 0) continue;

      final startDate = DateTime.tryParse(cell('start_date'));
      if (startDate == null) continue;

      final trialDate = DateTime.tryParse(cell('trial_end_date'));
      result.add(Subscription(
        name: name,
        price: price,
        currency: currency.isEmpty ? 'TRY' : currency,
        billingCycle: cell('billing_cycle', 'monthly') == 'yearly'
            ? 'yearly'
            : 'monthly',
        startDate: startDate,
        status: cell('status', Subscription.active) == Subscription.cancelled
            ? Subscription.cancelled
            : Subscription.active,
        category: cell('category', 'other'),
        trialEndDate: trialDate,
        reminderDays:
            int.tryParse(cell('reminder_days', '3')) ?? Subscription.defaultReminderDays,
      ));
    }
    return result;
  }

  /// Ödeme CSV satırlarını çözer.
  static List<PaymentDraft> _parsePaymentRows(List<String> lines) {
    final header = _parseCsvLine(lines.first);
    final idx = <String, int>{
      for (var i = 0; i < header.length; i++) header[i].trim(): i,
    };
    int? at(String name) => idx[name];

    final result = <PaymentDraft>[];
    for (final line in lines.skip(1)) {
      final cells = _parseCsvLine(line);
      String cell(String name, [String fallback = '']) {
        final i = at(name);
        if (i == null || i >= cells.length) return fallback;
        return cells[i].trim();
      }

      final name = cell('subscription_name');
      final amount = double.tryParse(cell('amount').replaceAll(',', '.'));
      final paidAt = DateTime.tryParse(cell('paid_at'));
      if (name.isEmpty || amount == null || amount <= 0 || paidAt == null) {
        continue;
      }
      result.add(PaymentDraft(
        subscriptionName: name,
        amount: amount,
        currency: cell('currency', 'TRY'),
        paidAt: paidAt,
        note: cell('note').isEmpty ? null : cell('note'),
      ));
    }
    return result;
  }

  /// CSV içeriğini çözer. Başlığa bakarak abonelik veya ödeme dosyası
  /// olduğunu anlar.
  static ParsedCsvData parseCsv(String csv) {
    final lines = _nonEmptyLines(csv);
    if (lines.isEmpty) return const ParsedCsvData();
    final header = _parseCsvLine(lines.first);
    if (header.contains('paid_at')) {
      return ParsedCsvData(payments: _parsePaymentRows(lines));
    }
    if (header.contains('price') && header.contains('billing_cycle')) {
      return ParsedCsvData(subscriptions: _parseSubscriptionRows(lines));
    }
    return const ParsedCsvData();
  }

  /// Kullanıcının seçtiği CSV dosyasını okur ve çözer.
  static Future<ParsedCsvData?> pickCsvFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    return parseCsv(await File(path).readAsString());
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Çözümlenmiş CSV verisini veritabanına içe aktarır. Aynı ada ve
  /// fatura döngüsüne sahip abonelikler tekrar eklenmez; adı eşleşmeyen
  /// ödemeler atlanır.
  static Future<CsvImportResult> importCsvData(ParsedCsvData data) async {
    final db = AppDatabase.instance;
    final existing = await db.getSubscriptions();
    final existingPayments = await db.getAllPayments();
    final paymentKeys = {
      for (final p in existingPayments)
        '${p.subscriptionId}|${p.amount.toStringAsFixed(2)}|'
            '${p.paidAt.year}-${p.paidAt.month}-${p.paidAt.day}',
    };

    var addedSubs = 0, skippedSubs = 0, addedPayments = 0, skippedPayments = 0;
    final idByName = <String, int>{
      for (final s in existing) s.name.trim().toLowerCase(): s.id!,
    };

    for (final s in data.subscriptions) {
      final key = s.name.trim().toLowerCase();
      final exists = existing.any((e) =>
          e.name.trim().toLowerCase() == key &&
          e.billingCycle == s.billingCycle &&
          _sameDay(e.startDate, s.startDate));
      if (exists) {
        skippedSubs++;
        continue;
      }
      final newId = await db.insertSubscription(s);
      idByName[key] = newId;
      addedSubs++;
    }

    for (final p in data.payments) {
      final id = idByName[p.subscriptionName.trim().toLowerCase()];
      if (id == null) {
        skippedPayments++;
        continue;
      }
      final key = '${id}|${p.amount.toStringAsFixed(2)}|'
          '${p.paidAt.year}-${p.paidAt.month}-${p.paidAt.day}';
      if (paymentKeys.contains(key)) {
        skippedPayments++;
        continue;
      }
      await db.insertPayment(Payment(
        subscriptionId: id,
        amount: p.amount,
        currency: p.currency,
        paidAt: p.paidAt,
        note: p.note,
      ));
      paymentKeys.add(key);
      addedPayments++;
    }

    return CsvImportResult(
      addedSubscriptions: addedSubs,
      skippedSubscriptions: skippedSubs,
      addedPayments: addedPayments,
      skippedPayments: skippedPayments,
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

/// Çözümlenmiş CSV verisi (abonelik ve/veya ödeme satırları).
class ParsedCsvData {
  final List<Subscription> subscriptions;
  final List<PaymentDraft> payments;

  const ParsedCsvData({this.subscriptions = const [], this.payments = const []});

  bool get isEmpty => subscriptions.isEmpty && payments.isEmpty;
}

/// CSV'den okunan, henüz kaydedilmemiş ödeme adayı.
class PaymentDraft {
  final String subscriptionName;
  final double amount;
  final String currency;
  final DateTime paidAt;
  final String? note;

  const PaymentDraft({
    required this.subscriptionName,
    required this.amount,
    required this.currency,
    required this.paidAt,
    this.note,
  });
}

/// CSV içe aktarma sonucu özeti.
class CsvImportResult {
  final int addedSubscriptions;
  final int skippedSubscriptions;
  final int addedPayments;
  final int skippedPayments;

  const CsvImportResult({
    required this.addedSubscriptions,
    required this.skippedSubscriptions,
    required this.addedPayments,
    required this.skippedPayments,
  });
}
