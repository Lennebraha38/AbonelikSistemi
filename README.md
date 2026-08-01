# Abonelik Yöneticisi (Subscription Manager)

Tamamen **çevrimdışı (offline)** çalışan, sunucu gerektirmeyen Kişisel Finans ve
Abonelik Yönetimi uygulaması. Netflix, Spotify gibi aylık/yıllık abonelikleri
takip eder, aylık toplam gideri hesaplar ve yenilenmesine 3 gün veya daha az
kalan abonelikler için **sabah 09:00**'da yerel bildirim gönderir.

## Özellikler

- **Dashboard**: En üstte büyük puntolarla "Aylık Toplam Gider", altında
  tarihe göre sıralı yaklaşan ödemeler; kategoriye göre filtreleme; iptal,
  iptali geri alma, silme ve **düzenleme** menüsü.
- **Abonelik Ekle / Düzenle**: Uygulama adı, fiyat, para birimi (TRY/USD/EUR),
  fatura döngüsü (aylık/yıllık), kategori, ilk ödeme tarihi, hatırlatma günü
  (1/3/7) ve opsiyonel deneme süresi.
- **İstatistikler**: Aylık/yıllık toplam, önümüzdeki 7 gündeki ödemeler,
  kategoriye göre donut grafik ve en pahalı abonelikler.
- **Ayarlar**: Açık/koyu/sistem teması, görüntüleme para birimi, bildirim
  aç/kapa, bildirim saati ve **CSV dışa aktarma** (yedek/paylaşım).
- **Bildirimler**: Yenilenmesine 3 gün veya daha az kalan abonelikler için
  günlük uyarı + **bitmesine 3 gün veya daha az kalan deneme süreleri** için
  uyarı (varsayılan 09:00, ayarlanabilir).
- **Veritabanı**: SQLite (sqflite) — tüm veriler cihazda, internet gerektirmez.
- **Arka plan**: flutter_background_service ile uygulama kapalıyken de
  periyodik kontrol; flutter_local_notifications ile bildirim.

## Kurulum

1. Flutter SDK (3.16+) kurulu olduğundan emin olun:
   ```bash
   flutter --version
   ```
2. Boş bir Flutter iskeleti oluşturun (gerekli gradle/ios dosyalarını üretir):
   ```bash
   mkdir subscription_manager && cd subscription_manager
   flutter create --org com.anomalyco --project-name subscription_manager .
   ```
3. Bu klasördeki `pubspec.yaml` ve `lib/` klasörünü projenin üzerine
   kopyalayın; `android/app/src/main/AndroidManifest.xml` dosyasını da
   bu projedeki haliyle değiştirin.
4. Bağımlılıkları çekip analiz edin:
   ```bash
   flutter pub get
   flutter analyze
   ```
5. Cihazda çalıştırın (Android önerilir):
   ```bash
   flutter run
   ```

> **Not:** `AndroidManifest.xml` dosyasındaki izinler ve
> `BackgroundService` servis kaydı arka plan servisinin çalışması için
> zorunludur; dosyayı olduğu gibi kullanın.

## Nasıl çalışıyor (arka plan akışı)

1. Uygulama açılırken `NotificationService.init()` bildirim kanallarını ve
   izinleri kurar.
2. Bildirimler açıksa `configureAndStartBackgroundService()` cihazda bir
   arka plan servisi başlatır (uygulama kapalıyken de çalışır,
   `autoStartOnBoot` ile cihaz açılışında da yeniden başlar).
3. Servis her 30 dakikada bir `performDailyCheck()` çalıştırır. Bu fonksiyon:
   - Ayarlarda seçili "bildirim saati" (varsayılan 09:00) gelmediyse çıkar,
   - Günde yalnızca **bir kez** kontrol yapar,
   - Yenilenmesine **3 gün veya daha az** kalmış abonelikleri bulur,
   - Her biri için "Dikkat: [Abonelik] yenilemesine az kaldı!" bildirimini
     atar ve aynı gün tekrar bildirim atmamak için `last_notified_date`
     kolonunu günceller.
   - Bitmesine **3 gün veya daha az** kalan aktif deneme süreleri için
     "Deneme Süresi Uyarısı" bildirimi atar (günde bir kez, ayrı anahtarla
     takip edilir).

## Testler

Model, döviz çevirimi ve veritabanı CRUD mantığı `test/` altında birim
testleriyle doğrulanır. Veritabanı testleri `sqflite_common_ffi` ile
masaüstünde çalışır; cihaz/emülatör gerekmez.

```bash
flutter test
```

CI (`.github/workflows/build-apk.yml`) `flutter analyze` ve `flutter test`
adımlarını çalıştırır; hatalar GitHub Actions'da annotation olarak görünür.

## Yayınlama (APK indirme)

Bu proje `.github/workflows/build-apk.yml` dosyasıyla **GitHub Actions** üzerinde
APK derleyip indirilebilir hale getirir (yerel Flutter/Android SDK gerekmez):

1. Repo'yu GitHub'a push edin.
2. Bir sürüm etiketi atın:
   ```bash
   git tag v1.0.0 && git push origin v1.0.0
   ```
3. GitHub'daki **Actions** sekmesinde build tamamlanınca:
   - Etiketli sürümlerde **Releases** sayfasında
     `subscription_manager-v1.0.0.zip` (içinde `app-release.apk` + tüm kaynak)
     otomatik oluşur → oradan indirin.
   - Etiketsiz (manuel "Run workflow") çalıştırmalarda zip, işin
     **Artifacts** bölümünden indirilebilir.

## Platform notları

- **Android**: Arka plan servisi en iyi şekilde çalışır. Kesintisiz kontrol
  için uygulamayı **pil optimizasyonundan muaf** tutmanız önerilir
  (Ayarlar → Pil → Pil optimizasyonu → Abonelik Yöneticisi → İzin verme).
- **iOS**: flutter_background_service iOS'ta kısıtlıdır; tam arka plan
  yürütme için BGTaskScheduler ile ek yapılandırma gerekebilir.
  Bildirim izni ilk açılışta sorulur.

## Teknik mimari

```
lib/
├── main.dart                  → uygulama girişi, tema + servis kurulumu
├── models/
│   ├── subscription.dart      → Subscription modeli + CurrencyConverter
│   └── categories.dart        → kategori kataloğu (ad, simge, renk)
├── database/
│   └── app_database.dart      → SQLite CRUD + aylık toplam hesapları
├── services/
│   ├── notification_service.dart → yerel bildirimler + arka plan servisi
│   └── export_service.dart    → CSV dışa aktarma + paylaşım
├── theme/
│   └── theme_controller.dart  → açık/koyu/sistem teması yönetimi
└── screens/
    ├── dashboard_screen.dart
    ├── add_subscription_screen.dart  → ekle + düzenleme
    ├── insights_screen.dart
    └── settings_screen.dart
```

## Bağımlılıklar

| Paket | Amaç |
|---|---|
| `sqflite` | Yerel SQLite veritabanı |
| `shared_preferences` | Ayarların ve tema tercihinin saklanması |
| `flutter_local_notifications` | Yerel bildirimler |
| `flutter_background_service` | Uygulama kapalıyken arka plan kontrolü |
| `intl` | Tarih / para formatlama |
| `path` | Veritabanı yolu birleştirme |
| `path_provider` | CSV dosyası için uygulama klasörü |
| `share_plus` | CSV dosyasını paylaşma / indirme menüsü |
| `sqflite_common_ffi` (dev) | Veritabanı testlerini masaüstünde çalıştırma |
