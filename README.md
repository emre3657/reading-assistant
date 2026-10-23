# Reading Assistant

Fotoğraf çekerek, galeriden görsel seçerek veya elle yazarak metin oluşturmayı; bu metinleri düzenleyip cihazda saklamayı ve sesli dinlemeyi sağlayan Flutter mobil uygulaması.

> **Durum:** Geliştirme sırasının 1. adımı (galeriden görsel seçme ve önizleme) ve 2. adımı (cihazda OCR ve metin düzeltme) uygulandı. TTS, veritabanı ve kamera henüz yok; çıkarılan metin kalıcı kaydedilmez.

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
- Bağımlılıklar: `flutter`, `cupertino_icons`, `image_picker ^1.2.4` (Android SDK 24+, iOS 13+), `google_mlkit_text_recognition ^0.17.1` (Android minSdk 21, iOS 15.5+); geliştirme tarafında `flutter_test` ve `flutter_lints`.
- Android `minSdk`/`targetSdk`/`compileSdk` değerleri Flutter varsayılanlarından gelir (bu Flutter sürümünde minSdk 24, compile/target 36); ML Kit için değişiklik gerekmedi. Android'de depolama izni istenmez; Android 13+ sistem fotoğraf seçicisi kullanılır. Activity sistem tarafından kapatılırsa seçim `retrieveLostData` ile kurtarılır.
- iOS: minimum sürüm ML Kit nedeniyle 15.0'dan **15.5'e** yükseltildi ([project.pbxproj](ios/Runner.xcodeproj/project.pbxproj) ve yeni [Podfile](ios/Podfile); armv7 hariç tutuldu). `NSPhotoLibraryUsageDescription` [Info.plist](ios/Runner/Info.plist) içinde tanımlı; `requestFullMetadata: false` ile ek izin istenmez. Kamera yok. **iOS derlemesi Windows'ta doğrulanamadı**; macOS'ta `pod install` ve derleme denenmeli.
- OCR: Latin script modeli, cihaz üzerinde. Android'de `com.google.mlkit:text-recognition:16.0.1` (paketlenmiş model) kullanılır; debug APK'nın içinde `assets/mlkit-google-ocr-models/...` altında Latin modelleri ve `libmlkit_google_ocr_pipeline.so` bulunduğu doğrulandı, yani ilk kullanımda indirme gerekmez. İnternetsiz gerçek cihaz/emülatör testi henüz yapılmadı (adım 7).
- Ekran: galeriden tek görsel seçme, oranı koruyarak ve görüntü boyutuna göre sınırlı çözünürlükte önizleme (kaynak dosya değiştirilmez), değiştirme, kaldırma, iptalde mevcut görseli ve metni koruma, Türkçe hata mesajları. "Metni çıkar" düğmesine basılınca OCR, küçültülmüş önizlemeyle değil seçilen orijinal dosyayla çalışır; sonuç çok satırlı, düzenlenebilir ve "kaydedilmedi" uyarılı bir alanda gösterilir. Yeni görsel seçilince veya görsel kaldırılınca metin temizlenir. Düzenlenmiş metnin üzerine yeniden OCR için onay istenir. Metin bulunamazsa veya hata olursa mevcut metin korunur ve yeniden denenebilir. Ekran kapandıktan veya görsel kalktıktan sonra biten OCR sonucu yok sayılır; yerel OCR çağrısı gerçekten iptal edilmez.
- OCR çıktısı ML Kit'in döndürdüğü metindir; yalnızca satır/blok ayrımları korunur, kelime düzeltme veya özetleme yapılmaz.
- Dosya sahipliği (paket kaynağından doğrulandı): `image_picker_android 0.8.13+25` seçilen dosyayı uygulamanın önbelleğine (`cacheDir/{uuid}/{ad}`), `image_picker_ios 0.8.13+13` ise `NSTemporaryDirectory` altına kopyalayıp yolunu döndürür. Bizim kodumuz kopya oluşturmaz ve dosya silmez (OCR sonrasında da silinmez); bu kopyaların yaşam döngüsü henüz yönetilmiyor, temizlik ayrı bir adımda yapılacak.
- Android ve iOS dışında web, windows, linux ve macos dizinleri de var; hedef platformlar yalnızca Android ve iOS.
- Testler: [test/features/image_import/](test/features/image_import) altında ekran, önizleme ve OCR testleri; gerçek ML Kit çağrısı yapılmaz, servis sahtesi kullanılır.

## Klasör yapısı

```text
lib/
  main.dart                      # yalnızca uygulamayı başlatır
  app.dart                       # MaterialApp ve tema
  features/
    image_import/
      presentation/
        image_import_screen.dart # ekran, OCR akışı ve basit durum yönetimi
        widgets/image_preview.dart
      services/
        image_picker_service.dart
        text_recognition_service.dart # ML Kit OCR sarmalayıcısı
```

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
