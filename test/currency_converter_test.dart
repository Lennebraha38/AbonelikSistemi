import 'package:flutter_test/flutter_test.dart';
import 'package:subscription_manager/models/subscription.dart';

void main() {
  group('CurrencyConverter.convert', () {
    test('aynı para birimi değişmez', () {
      expect(CurrencyConverter.convert(100, 'TRY', 'TRY'), 100);
      expect(CurrencyConverter.convert(50, 'USD', 'USD'), 50);
    });

    test('TRY -> USD çevirir', () {
      expect(CurrencyConverter.convert(100, 'TRY', 'USD'), closeTo(2.9, 0.0001));
    });

    test('EUR -> USD çevirir', () {
      expect(
        CurrencyConverter.convert(100, 'EUR', 'USD'),
        closeTo(109.0, 0.0001),
      );
    });

    test('TRY -> EUR çevirir', () {
      expect(
        CurrencyConverter.convert(100, 'TRY', 'EUR'),
        closeTo(100 * 0.029 / 1.09, 0.0001),
      );
    });

    test('yuvarlak yolculuk (TRY -> USD -> TRY)', () {
      final usd = CurrencyConverter.convert(100, 'TRY', 'USD');
      expect(CurrencyConverter.convert(usd, 'USD', 'TRY'), closeTo(100, 0.0001));
    });

    test('desteklenmeyen birimde fallback oranı kullanılır', () {
      expect(
        CurrencyConverter.convert(100, 'XYZ', 'TRY'),
        closeTo(100 / 0.029, 0.01),
      );
    });
  });
}
