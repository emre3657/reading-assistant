# Reading Assistant

Fotoğraf çekerek, galeriden görsel seçerek veya elle yazarak metin oluşturmayı; bu metinleri düzenleyip cihazda saklamayı ve sesli dinlemeyi sağlayan Flutter mobil uygulaması.

> **Durum:** Geliştirme sırasının 1. adımı (galeriden görsel seçme ve önizleme) uygulandı. OCR, TTS, veritabanı ve kamera henüz yok.

## Hedefler

- Android ve iOS. İlk geliştirme/test ortamı: Android Pixel 5 emülatörü.
- İçerik türleri: kitap, not, yemek tarifi, ders notu, şarkı sözü.
- Bir içerik birden fazla sıralı metin sayfasından oluşabilir.
- OCR cihazda çalışır.
- TTS cihazın seslendirme motorunu kullanır.
- Çevrimdışı kullanım hedeflenir; gerekli OCR modeli ve TTS seslerinin kurulu olup olmadığı kontrol edilir.
- Veriler yerel SQLite veritabanında saklanır.
- Fotoğraflar kalıcı saklanmaz. Metin onaylandığında veya işlem iptal edildiğinde yalnızca uygulamanın oluşturduğu geçici dosyalar silinir; kullanıcının galerisindeki orijinallere dokunulmaz.
- Dinleme kontrolleri: oynat, duraklat/devam et, durdur, önceki/sonraki cümle, açık sayfanın başına dön, hız ayarı.
- Son okuma konumu saklanır.
- İlk sürümde dinleme yalnızca uygulama açıkken çalışır.
- Backend, bulut servisi, hesap sistemi veya API anahtarı yoktur.

## Geliştirme sırası

1. Galeriden görsel seçme ve önizleme
2. OCR ve metin düzeltme
3. Temel seslendirme
4. Cümle bazlı dinleme kontrolleri
5. Yerel kayıt
6. İçerik ve sayfa yönetimi
7. Kamera ve gerçek cihazda çevrimdışı test

Her adım küçük ve çalışır halde tamamlanır; sonraki adıma geçmeden önce analiz ve ilgili testler çalıştırılır.

## Mevcut proje durumu

Doğrulanan bilgiler:

- Paket adı: `reading_assistant`, Android `applicationId`: `com.emreekincidev.reading_assistant`.
- Dart SDK: `^3.13.5` ([pubspec.yaml](pubspec.yaml)).
- Bağımlılıklar: `flutter`, `cupertino_icons`, `image_picker ^1.2.4` (Android SDK 24+, iOS 13+ destekler); geliştirme tarafında `flutter_test` ve `flutter_lints`.
- Android `minSdk`/`targetSdk`/`compileSdk` değerleri Flutter varsayılanlarından gelir. Android'de depolama izni istenmez; Android 13+ sistem fotoğraf seçicisi kullanılır. Activity sistem tarafından kapatılırsa seçim `retrieveLostData` ile kurtarılır.
- iOS'ta `NSPhotoLibraryUsageDescription` açıklaması [Info.plist](ios/Runner/Info.plist) içinde tanımlı; `requestFullMetadata: false` ile ek izin istenmez. Kamera yok.
- [lib/main.dart](lib/main.dart): tek ekran; galeriden tek görsel seçme, oranı koruyarak önizleme, değiştirme, kaldırma, iptalde mevcut görseli koruma, Türkçe hata mesajları. Seçici, testlerde değiştirilebilmesi için fonksiyon olarak enjekte edilir.
- Seçilen görselin dosyası bu adımda silinmez; temizlik OCR akışında, yalnızca uygulamaya ait kopyalar için yapılacak.
- Android ve iOS dışında web, windows, linux ve macos dizinleri de var; hedef platformlar yalnızca Android ve iOS.
- [test/widget_test.dart](test/widget_test.dart): başlangıç ekranı, seçim, iptal, kaldırma, hata, çift seçimi engelleme, kayıp görsel kurtarma ve büyük yazı testleri.

## Geliştirme

```bash
flutter pub get
dart format .
flutter analyze
flutter test
flutter run
```

## Kurallar

Kod ve proje kuralları için [.github/copilot-instructions.md](.github/copilot-instructions.md) dosyasına bakın.
