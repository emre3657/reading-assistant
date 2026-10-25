# Reading Assistant

Fotoğraf çekerek, galeriden görsel seçerek veya elle yazarak metin oluşturmayı; bu metinleri düzenleyip cihazda saklamayı ve sesli dinlemeyi sağlayan Flutter mobil uygulaması.

> **Durum:** Geliştirme sırasının 1. adımı (galeriden görsel seçme ve önizleme), 2. adımı (cihazda OCR ve metin düzeltme) ve 3. adımı (temel cihaz TTS: "Sesli oku" / "Durdur") uygulandı. Veritabanı ve kamera henüz yok; çıkarılan metin kalıcı kaydedilmez. TTS yalnızca sahte servisle test edildi; gerçek motor, emülatör, iOS ve gerçek cihaz doğrulanmadı.

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
- Bağımlılıklar: `flutter`, `cupertino_icons`, `image_picker ^1.2.4` (Android SDK 24+, iOS 13+), `google_mlkit_text_recognition ^0.17.1` (Android minSdk 21, iOS 15.5+), `image ^4.12.0` (saf Dart), `flutter_tts ^4.2.5` (Android minSdk 24); geliştirme tarafında `flutter_test` ve `flutter_lints`.
- Android `minSdk`/`targetSdk`/`compileSdk` değerleri Flutter varsayılanlarından gelir (bu Flutter sürümünde minSdk 24, compile/target 36); ML Kit için değişiklik gerekmedi. Android'de depolama izni istenmez; Android 13+ sistem fotoğraf seçicisi kullanılır. Activity sistem tarafından kapatılırsa seçim `retrieveLostData` ile kurtarılır.
- iOS: minimum sürüm ML Kit nedeniyle 15.0'dan **15.5'e** yükseltildi ([project.pbxproj](ios/Runner.xcodeproj/project.pbxproj) ve yeni [Podfile](ios/Podfile); armv7 hariç tutuldu). `NSPhotoLibraryUsageDescription` [Info.plist](ios/Runner/Info.plist) içinde tanımlı; `requestFullMetadata: false` ile ek izin istenmez. Kamera yok. **iOS derlemesi Windows'ta doğrulanamadı**; macOS'ta `pod install` ve derleme denenmeli.
- OCR: Latin script modeli, cihaz üzerinde. Android'de `com.google.mlkit:text-recognition:16.0.1` (paketlenmiş model) kullanılır; debug APK'nın içinde `assets/mlkit-google-ocr-models/...` altında Latin modelleri ve `libmlkit_google_ocr_pipeline.so` bulunduğu doğrulandı, yani ilk kullanımda indirme gerekmez. İnternetsiz gerçek cihaz/emülatör testi henüz yapılmadı (adım 7).
- Ekran: galeriden tek görsel seçme, oranı koruyarak ve görüntü boyutuna göre sınırlı çözünürlükte önizleme (kaynak dosya değiştirilmez), değiştirme, kaldırma, iptalde mevcut görseli ve metni koruma, Türkçe hata mesajları. "Metni çıkar" düğmesine basılınca OCR, küçültülmüş önizlemeyle değil seçilen orijinal dosyayla çalışır; sonuç çok satırlı, düzenlenebilir ve "kaydedilmedi" uyarılı bir alanda gösterilir. Yeni görsel seçilince veya görsel kaldırılınca metin temizlenir. Düzenlenmiş metnin üzerine yeniden OCR için onay istenir. Metin bulunamazsa veya hata olursa mevcut metin korunur ve yeniden denenebilir. Ekran kapandıktan veya görsel kalktıktan sonra biten OCR sonucu yok sayılır; yerel OCR çağrısı gerçekten iptal edilmez.
- Metin koruması: düzenlenmiş metin için üç onay vardır: yeniden OCR, görseli kaldırma ve (görsel gerçekten seçilmişse) görseli değiştirme. "Görseli değiştir" önce seçiciyi açar; seçim iptal edilirse onay çıkmaz. Onay reddedilirse mevcut görsel ve metin korunur. Düzenlenmemiş OCR sonucu onaysız temizlenir. Hiçbir akışta dosya silinmez.
- Görsel yönü: görsel seçiliyken "Sola döndür" / "Sağa döndür" düğmeleri önizlemeyi 90° adımlarla döndürür (iki kez basınca 180°). Dönüş yalnızca bir görsel için tutulur: yeni görselde ve kaldırınca sıfırlanır, galeri seçimi iptal edilirse korunur; döndürmek metni silmez. Dönüş 0° değilse "Metni çıkar" orijinalden **yeniden üretilen** döndürülmüş bir geçici kopyayla çalışır (her seferinde orijinal dosya ve toplam açıdan; önceki çıktı yeniden sıkıştırılmaz). 0° iken orijinal dosya doğrudan kullanılır. Otomatik yön algılama yoktur.
- Döndürme çözümü: `image ^4.12.0` (saf Dart, native bağımlılığı yok; Android/iOS ek yapılandırma gerektirmez). Çözme, döndürme ve JPEG (kalite 95) yazma `Isolate.run` ile arka planda yapılır. EXIF yönü çözme sırasında bir kez uygulanır, çıktıda yön etiketi bulunmaz (testle doğrulandı). Önizleme EXIF'i Flutter motoru üzerinden uygular; ikisinin gerçek cihazda aynı görüntüyü verdiği manuel olarak doğrulanmalı. Alfa kanallı görseller (ör. şeffaf PNG) JPEG'e yazılırken şeffaflık kaybolur; HEIC gibi `image` paketinin çözemediği biçimlerde "Görsel döndürülemedi" hatası gösterilir.
- Geçici döndürülmüş kopya: yalnızca bu ekranın OCR çalıştırması için `Directory.systemTemp` altında `reading_assistant_ocr_*` klasöründe üretilir; OCR sürerken silinmez, başarı, hata veya ekranın kapanması durumunda OCR bittikten sonra silinir. Yalnızca bu önekli kendi klasörü silinir; galeri orijinallerine ve image_picker'ın kopyalarına dokunulmaz. Uygulama OCR sırasında sonlandırılırsa kopya önbellekte kalabilir; genel bir önbellek temizliği yoktur.
- OCR yön bilgisi: `local_test_images` örneklerinde dönüşün piksellere işlendiği, EXIF yön etiketinin bulunmadığı doğrulandı; yani sorun EXIF işleme hatası değil, ML Kit'in yan/ters yazıyı okuma sınırı olarak değerlendirildi (kesin kanıt için OCR çalıştırılmadı). Bu yüzden elle döndürme eklendi. ML Kit'in native EXIF davranışı kapalı kaynak olduğundan doğrulanamadı.
- Satırları birleştir: OCR başarılı olunca metin alanının üstünde "Satırları birleştir" anahtarı çıkar (varsayılan kapalı). Ham OCR sonucu ayrıca tutulur; anahtar her seferinde ham sonuçtan dönüşüm üretir (üretilmiş metin tekrar işlenmez), kapatınca ham sonuç geri gelir. Dönüşüm saf Dart fonksiyonudur ([ocr_text_formatter.dart](lib/features/image_import/services/ocr_text_formatter.dart)): CRLF/CR/LF aynı işlenir, tek satır sonu boşluk olur, boş satırla ayrılmış paragraflar korunur, `-`/`•`/`*`/`–`/`1.`/`2)` ile başlayan satırlar ayrı satırda kalır, satır sonunda harf+tire ve sonraki satırda küçük harf varsa kelime tiresiz birleştirilir (Türkçe harfler dahil). Satır içi tireler, işaretler ve harfler değiştirilmez. Sınırlar: tire kuralı sezgiseldir, gerçek tireli kelimeleri de birleştirebilir (ör. "sosyo-\nekonomik" → "sosyoekonomik"); OCR paragraf sınırını zaten kaybettiyse geri getirilemez; sütunlu, tablolu veya şiir/şarkı sözü gibi satır sonunun anlamlı olduğu metinlerde kapalı bırakılmalıdır. Kullanıcı metni düzenlediyse anahtarı değiştirmek önce onay ister (vazgeçilirse metin ve anahtar aynı kalır); düzenleme, gösterilen üretilmiş metne göre algılandığı için yalnızca otomatik birleştirme metni "düzenlenmiş" saymaz. Yeni görselde, görsel kaldırılınca ve yeni OCR sonucunda anahtar kapanır ve ham sonuç yenilenir. Arayüzdeki açıklama: "Satırları birleştirir; paragraf ve başlık ayrımlarını tahmin eder." Yerleşim kullanımı (sezgisel, kusursuz değildir): servis ham metnin yanında satır metinlerini, blok numarasını ve sınır kutularını küçük değişmez veri sınıflarıyla ([ocr_result.dart](lib/features/image_import/services/ocr_result.dart)) döndürür; satırlar ML Kit'in okuma sırasında kalır, konuma göre yeniden sıralanmaz. Anahtar açılınca `joinOcrResult`, ham sonuç ve yerleşimden üretir; her OCR bloğu paragraf sayılmaz. Paragraf ayrımı: yerel sütunun (komşu satırların medyan sol/sağ kenarı) genişliğine oranla belirgin ilk satır girintisi (en az %3) **ve** önceki satırın cümle sonu noktalaması (`. ! ? …`) taşıması veya belirgin kısa olması (sağ kenardan en az %12 kısa); önceki satır harf+tire ile bitiyorsa bölünmez. Başlık: tek satırlık blok, sütunun en çok %60'ı genişliğinde, sütuna göre ortalanmış (%8 tolerans), cümle sonu noktalaması yok; başlığın önünde ve arkasında ayrılır ve bu sınırda tire birleştirmesi yapılmaz. Eşikler piksel değil oransaldır (ölçek bağımsız, testle doğrulandı). Dikey boşluk, satır açısı ve karakter sayısı kullanılmaz (eğik fotoğrafta güvenilmez). Yerleşim yoksa, 6 satırdan azsa, metinle tutarsızsa, kutular geçersizse veya ham metinde zaten boş satır varsa metin tabanlı birleştirme kullanılır; sütun ölçüsü güvenilir değilse (ör. şiir) o satırlarda paragraf tahmini yapılmaz. Hiçbir içerik silinmez, harf düzeltilmez. Bilinen sınırlar: girintisiz paragraflar ve önceki satırı cümle bitirmeyen/kısa olmayan girintiler ayrılmaz; başlık yalnızca OCR'nin ayrı blok yaptığı tek satırlar için aranır, sayfa numarası gibi ortalanmış kısa tek satırlar da "başlık" gibi ayrılabilir; farklı sayfa düzenleriyle (sütunlu, tablo, şiir, tarif) denenmedi. Testlerdeki metinler yapaydır; koordinatlar gerçek bir cihaz logundan alınmıştır, test başarısı gerçek OCR doğruluğu anlamına gelmez.
- OCR yerleşim teşhisi (yalnızca debug): `flutter run` ile (debug) çalışan uygulamada "Metni çıkar" sonrası konsolda `[OCR layout]` satırları blok/satır indekslerini ve sınır kutularını (L/T/R/B piksel) yazar; metin içeriği loglanmaz. Release/profile derlemede üretilmez (`kDebugMode`). Servis artık satır metinlerini ve konumlarını da döndürür (yukarıya bakın); teşhis logu metin içeriği yazmaz.
- Android release ağ erişimi: [android/app/src/release/AndroidManifest.xml](android/app/src/release/AndroidManifest.xml) manifest merger kuralıyla (`tools:node="remove"`) `INTERNET` iznini kaldırır; ML Kit'in kullandığı DataTransport kütüphanesi bu izni getirdiği için gerekliydi. Release APK'nın nihai izinlerinde `INTERNET` olmadığı `aapt dump permissions` ile doğrulandı. Android release OCR testi Pixel 5 emülatöründe geçti (yerel model yüklendi, OCR çalıştı); iOS ve gerçek cihaz testi yapılmadı. Release'te R8, ML Kit registrar sınıflarının public parametresiz constructor'larını kaldırıyordu; `proguard-rules.pro` içindeki dar `-keepclassmembers` kuralları (yalnızca `CommonComponentRegistrar`, `VisionCommonRegistrar`, `TextRegistrar`) bunu önler. `TextRecognitionService`, `close()` hatasının asıl `processImage` hatasını örtmesine izin vermez. Bu, ML Kit telemetrisini SDK içinde kapatmaz; yalnızca Android uygulamasının ağ erişimini engeller (DataTransport bileşenleri yerinde durur, gönderimler başarısız olur). Debug ve profile derlemeleri `INTERNET` izni almaya devam eder (geliştirme araçları için). iOS için aynı garanti verilmez ve doğrulanmadı. Release derlemesi için `android/app/proguard-rules.pro` Latin dışı ML Kit tanıyıcı sınıfları için R8 uyarılarını bastırır.
- OCR çıktısı ML Kit'in döndürdüğü metindir; yalnızca satır/blok ayrımları korunur, kelime düzeltme veya özetleme yapılmaz.
- Dosya sahipliği (paket kaynağından doğrulandı): `image_picker_android 0.8.13+25` seçilen dosyayı uygulamanın önbelleğine (`cacheDir/{uuid}/{ad}`), `image_picker_ios 0.8.13+13` ise `NSTemporaryDirectory` altına kopyalayıp yolunu döndürür. Bizim kodumuz picker kopyalarını silmez (OCR sonrasında da silinmez); bu kopyaların yaşam döngüsü henüz yönetilmiyor. Tek istisna, döndürme için kendi ürettiğimiz geçici kopyadır (yukarıda).
- Android ve iOS dışında web, windows, linux ve macos dizinleri de var; hedef platformlar yalnızca Android ve iOS.
- Testler: [test/features/image_import/](test/features/image_import) altında ekran, önizleme, döndürme, OCR ve döndürme servisi testleri; gerçek ML Kit çağrısı yapılmaz, servis sahtesi kullanılır (döndürme servisi gerçek dosyalarla test edilir).

## Temel seslendirme (adım 3)

Kapsam: metin alanında o an görünen metnin anlık kopyası (ham OCR değil) Türkçe okunur. Yalnızca "Sesli oku" ve "Durdur" vardır; duraklat, ileri/geri, hız, kayıt ve arka planda oynatma yok. Durdurduktan sonra okuma metnin başından başlar. Boş veya yalnızca boşluk içeren metin okunmaz.

- Paket: `flutter_tts ^4.2.5` (pub.dev, 2026-01-05; Dart >=3.4, Android minSdk 24, iOS ek izin gerektirmez). Android'de TTS motorunu görebilmek için [AndroidManifest.xml](android/app/src/main/AndroidManifest.xml) `queries` içine `android.intent.action.TTS_SERVICE` eklendi. INTERNET izni eklenmedi; release kaldırma kuralı ve ProGuard kuralları değişmedi. Derleme sırasında `flutter_tts`'in Kotlin Gradle Plugin kullandığına dair Flutter uyarısı çıkar; derleme başarılıdır.
- Yapı: `SpeechService` (platform çağrıları, testte sahtesiyle değiştirilir), `ListeningController` (dinleme durumu; `ImageImportController`'a bağımlı değil) ve ekran ikisini koordine eder. Servisi ekran sahiplenir (enjekte edilmediyse kendisi oluşturup dispose eder).
- Durumlar: hazırlanıyor, okunuyor, durduruluyor, tamamlandı, hata. Çift başlatma ve çakışan başlat/durdur engellenir. Okuma sırasında metin düzenleme, satır birleştirme, OCR ve görsel işlemleri kapalıdır; "Durdur" erişilebilir kalır.
- Çevrimdışı Türkçe ses (Android): `getVoices` listesinden `tr-TR` yerel ayarlı, `network_required` değeri `0` olan ve `features` içinde `notInstalled` bulunmayan ses seçilir (yüksek kalite ve `embeddedTts` tercih edilir) ve `setVoice` başarılı olmalıdır. Bu bilgiler motorun bildirdiği değerlerdir; Android bundan güçlü bir kanıt sunmaz. Uygun ses yoksa cihazın Metin okuma (TTS) ayarlarından Türkçe ses yüklemesi önerilir; otomatik indirme veya bulut TTS yoktur. iOS'ta ses bayrağı yoktur; yalnızca `tr-TR` dil desteği kontrol edilir ve **iOS çevrimdışı davranışı doğrulanmadı, garanti edilmez**. TTS motoru ayrı bir sistem uygulaması olabileceğinden uygulamanın INTERNET izninin olmaması motorun ağ kullanımını engellediği anlamına gelmez.
- Uzun metin: metin kayıpsız parçalara bölünür (parça = en fazla 1000 karakter veya platformun `getMaxSpeechInputLength` değeri; hangisi küçükse), tercih sırası satır sonu, cümle sonu, boşluk; gerekirse sert kesim vekil çiftini bölmez. Birleştirilince özgün metni verir. Parçalar sırayla okunur; durdurulunca sıradaki parça başlamaz. Sınır: sert kesim birleştirici işaretleri ayırabilir.
- Geri çağrı yaklaşımı: `flutter_tts 4.2.5` geri çağrıları okuma kimliği taşımaz. Bu yüzden `speak` dönüşü tamamlanma sayılmaz; `awaitSpeakCompletion(true)` ile beklenen sonuç, hata geri çağrısı ve `stop()` yarıştırılır ve her okuma bir oturum sayacıyla korunur (eski oturumun sonucu yeni oturumu etkilemez). Garanti verilemeyen nokta: Android'de iptal bildirimi `stop()` sonrası eşzamansız gelir; eski bir hata geri çağrısının yeni oturumda görünmesi kuramsal olarak dışlanamaz. Motor hatasında `speak` sonucunun hiç dönmemesi ve iOS'ta iptalde sonucun asılı kalabilmesi de paket kaynağında görüldü; bu yüzden sonuç beklemesi hata/durdurma sinyalleriyle yarıştırılır.
- Yaşam döngüsü: uygulama `hidden`/`paused`/`detached` olunca okuma durdurulur ve ekran kapanınca durdurulup kaynaklar bırakılır. `inactive` bilinçli olarak yok sayılır (sistem diyalogları ve bildirim paneli bunu tetikler); okuma sırasında galeri seçici zaten açılamaz.
- Testler: [test/features/listening/](test/features/listening) altında sahte servisle durum geçişleri, uzun metin sırası, durdurma, geç sonuçlar, dispose, bölücü, ses seçimi ve widget kontrol durumları sınanır. Bunlar yalnızca bizim sıralamamızı doğrular; gerçek TTS motoru doğrulanmış sayılmaz.

## Durum yönetimi ve sahiplik

- `ImageImportController` (Flutter'ın `ChangeNotifier`'ı; ek paket yok) BuildContext, widget veya diyalog bilgisi taşımaz. Ekran onu `initState`'te oluşturur, `dispose`'ta bırakır ve `ListenableBuilder` ile dinler. Servisler hâlâ ekrana enjekte edilir ve controller'a iletilir.
- `TextEditingController`'ı controller oluşturur, dinler ve dispose eder; metin değişince "düzenlenmiş" durumu güncellenir.
- Onay gerektiren akışlar iki parçalıdır: ekran `revision` değerini okuyup diyaloğu gösterir, sonra controller'ı çağırır; beklerken durum değiştiyse eski onay yok sayılır. Galeri seçimi `pickImage` → (onay) → `applyPick`/`discardPick` ile ilerler; iptal, hata, vazgeçme ve ekran kapanmasında meşgul durumu serbest bırakılır.
- `dispose` süren native OCR'yi iptal etmez; sonuç yok sayılır, o çalıştırmanın döndürülmüş geçici kopyası yine silinir.

## Klasör yapısı

```text
lib/
  main.dart                      # yalnızca uygulamayı başlatır
  app.dart                       # MaterialApp ve tema
  features/
    image_import/
      presentation/
        image_import_controller.dart # ChangeNotifier: seçim/kurtarma, döndürme, OCR, birleştirme, metin durumu, mesajlar
        image_import_screen.dart     # yalnızca arayüz, diyaloglar ve mounted kontrolleri
        widgets/image_preview.dart
      services/
        image_picker_service.dart
        image_rotation_service.dart   # döndürülmüş geçici OCR kopyası (isolate)
        ocr_text_formatter.dart       # saf Dart satır birleştirme (metin + yerleşim)
        ocr_result.dart               # OcrResult / OcrLine veri sınıfları
        text_recognition_service.dart # ML Kit OCR sarmalayıcısı
    listening/
      presentation/
        listening_controller.dart     # ChangeNotifier: oturum korumalı dinleme durumu
      services/
        speech_service.dart           # flutter_tts sarmalayıcısı, çevrimdışı Türkçe ses seçimi
        speech_text_splitter.dart     # kayıpsız metin parçalama
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
