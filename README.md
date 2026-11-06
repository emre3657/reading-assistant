# Okuma Asistanı

Görsellerden metin çıkaran, yazılan veya yapıştırılan metinleri seslendiren ve içerikleri cihazda saklayan Flutter mobil uygulaması.

Android ve iOS hedeflenir. Geliştirme ve manuel kontroller Android Pixel 5 emülatöründe yapılmaktadır. Gerçek cihaz ve iOS doğrulaması henüz tamamlanmamıştır.

## Özellikler

### Metin oluşturma ve OCR

- Galeriden görsel seçme, önizleme, değiştirme ve kaldırma.
- Görseli sola veya sağa 90° döndürme.
- Latin karakter modeliyle cihaz üzerinde metin çıkarma.
- Görsel kullanmadan metin yazma veya yapıştırma.
- Metni elle düzeltme ve düzenlenmiş metni değiştiren işlemlerden önce onay isteme.
- Başarılı OCR sonrasında metin biçimlendirme bölümüne otomatik kaydırma.

“Satırları birleştir” seçeneği basılı satır sonlarını birleştirir; paragraf, başlık ve satır sonunda tireyle bölünmüş kelimeleri tahmin eder. Varsayılan olarak kapalıdır. Kapatıldığında oturumdaki ham OCR sonucu geri gelir; elle düzenleme varsa önce onay istenir.

### Sesli okuma

Metinler cihazın TTS motoruyla Türkçe seslendirilir.

- Başlatma, duraklatma, devam etme ve durdurma.
- Önceki/sonraki cümle ve başa dönme.
- 0.75×, 1×, 1.25× ve 1.5× hız seçenekleri.
- Ekranın altında küçültülebilen dinleme paneli; hız seçenekleri üstteki “Okuma ayarları” menüsündedir.

Devam et, mevcut cümlenin başından okur. Okuma sırasında hız değiştirilirse aynı cümle yeni hızla yeniden başlar. Aktif ve duraklatılmış oturumlarda metin düzenleme kilitlidir; düzenlemek için okuma durdurulmalıdır.

### İçerikler ve sayfalar

İçerikler **Kitap, Not, Yemek tarifi, Ders notu ve Şarkı sözü** kategorilerinde SQLite veritabanında saklanır. Her içerik birden fazla sıralı sayfa içerebilir.

- İlk ekrandaki metni yeni içeriğin ilk sayfası olarak kaydetme.
- “Kayıtlarım” ekranında içerikleri listeleme ve açma.
- Mevcut içeriğe aynı ekranda galeri/OCR veya yazma/yapıştırma yoluyla sayfa ekleme.
- Açık sayfayı dinleme ve yalnızca o sayfanın metnini düzenleme.
- Başlık ve kategoriyi içerik menüsünden, sayfa metinlerinden bağımsız düzenleme.
- Onay alarak tek sayfayı veya içeriğin tamamını silme.
- Sayfa okuma ekranında önceki/sonraki sayfa düğmeleri ve "Sayfa 2 / 5" göstergesi; sayfalar kayıtlı sırayla gezilir, geçişte okuma durdurulur ve yeni sayfa otomatik okunmaz. Kaydedilmemiş düzenlemede devam etme, kaydetmeden geçme veya kaydedip geçme sorulur.
- Çok sayfalı içeriklerde “Okuma ayarları”ndaki varsayılan kapalı “Sonraki sayfayı otomatik oku” anahtarı, sayfa doğal olarak bittiğinde sonraki sayfayı okur. Tercih ekran oturumunda tutulur; son veya boş sayfada okuma biter. Bekleyen geçiş Durdur, anahtarı kapatma veya arka plana geçme ile iptal edilir.
- Sayfaları basılı tutup (veya tutamaçtan) sürükleyerek yeniden sıralama; yeni sıra tek SQLite transaction'ıyla kaydedilir, hatada önceki sıra korunur.

Son sayfa silindiğinde içerik kaydı korunur ve yeniden sayfa eklenebilir. Silme sonrasında kalan sayfalar ekranda kesintisiz numaralanır.

Sayfa ekleme ve metin düzenleme ekranlarından kaydedilmemiş metinle çıkarken düzenlemeye devam etme, kaydetmeden çıkma veya kaydedip çıkma seçenekleri sunulur. Kaydetme hatasında taslak korunur.

Kayıtlı kitap metinleri iki yana, diğer kategoriler ve sayfa düzenleme alanları başlangıç yönüne hizalanır.

## Çevrimdışı çalışma ve veriler

- Hesap, backend, bulut OCR/TTS servisi veya API anahtarı kullanılmaz.
- Metinler yerel SQLite veritabanında tutulur. İçerik bilgileri `documents`, sayfalar `pages` tablosundadır.
- Fotoğraflar kayıtlı içeriğin parçası olarak saklanmaz; kullanıcının galerisindeki orijinaller silinmez.
- Ham OCR ve yerleşim bilgisi yalnızca mevcut oturumda tutulur. Veritabanına görünen metin kaydedilir.

Android OCR modeli uygulamayla paketlenir; ilk kullanımda model indirmek gerekmez. Android **release** derlemesinde `INTERNET` izni kaldırılmıştır ve bu yapılandırmayla OCR emülatörde doğrulanmıştır. Debug/profile sürümleri geliştirme için internet izni taşıyabilir.

ML Kit telemetri bileşenleri içerir. Release internet izninin kaldırılması, bu bileşenlerin SDK içinde kapatılması anlamına gelmez.

Android'de kurulu ve ağ gerektirmediğini bildiren Türkçe TTS sesi seçilir. Ses verilerinin ilk kurulumu internet gerektirebilir. TTS motoru ayrı bir sistem uygulaması olabileceğinden uygulamanın internet izni, motorun ağ erişimini belirlemez. iOS'ta çevrimdışı çalışma henüz doğrulanmamıştır.

## Geliştirme

Flutter SDK ve hedef platformun geliştirme araçları gereklidir. Mevcut minimum sürümler Android API 24 ve iOS 15.5'tir. iOS derlemesi için macOS/Xcode gerekir.

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run
```

Android release APK:

```bash
flutter build apk --release
```

Temel bağımlılıklar: `image_picker`, `google_mlkit_text_recognition`, `image`, `flutter_tts` ve `sqflite`. Sürümler için [pubspec.yaml](pubspec.yaml) ve [pubspec.lock](pubspec.lock) dosyalarına bakın.

Testler arayüz/controller akışlarını, metin biçimlendirmeyi, cümle bölmeyi ve gerçek SQLite üzerinde veritabanı işlemlerini kapsar. Sahte OCR/TTS servisleriyle geçen testler, gerçek motor veya cihaz davranışının doğrulandığı anlamına gelmez.

## Sınırlamalar

- OCR, Türkçe karakterleri, dipnotları ve kaynak numaralarını yanlış okuyabilir. Otomatik yazım düzeltme yoktur.
- Görsel yönü kullanıcı tarafından düzeltilir. Çok sütunlu metin ve tablolarda okuma sırası garanti edilmez.
- Satır birleştirme ve cümle bölme sezgiseldir; şiir ve şarkı sözlerinde satır birleştirme kapalı bırakılabilir.
- Sayfa numarası girerek atlama yoktur; otomatik sayfa geçişi yalnızca kayıtlı içerik okuma ekranındadır ve uygulama yeniden açılınca kapalıdır.
- Arka planda/ekran kilitliyken dinleme, son okuma konumunu ve hız tercihini kalıcı saklama desteklenmez.
- Metin sürüm geçmişi, uygulama içi yedekleme ve bulut senkronizasyonu yoktur.
- Galeri eklentisinin geçici kopyaları için genel temizlik henüz yoktur. Uygulamanın döndürme için oluşturduğu kopyalar OCR tamamlanınca temizlenir; işlem sırasında uygulama sonlandırılırsa dosya kalabilir.

Kod ve çalışma kuralları için [Copilot talimatlarına](.github/copilot-instructions.md) bakın.
