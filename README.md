# Okuma Asistanı

Görsellerden metin çıkaran, metinleri cihazda saklayan ve Türkçe seslendiren Flutter mobil uygulaması.

Android ve iOS hedeflenir. Geliştirme ve manuel kontroller şu ana kadar Android Pixel 5 emülatöründe yapılmıştır. iOS ve gerçek cihaz doğrulaması henüz tamamlanmamıştır.

## Mevcut özellikler

### Görsel seçme ve OCR

- Galeriden tek görsel seçme, önizleme, değiştirme ve kaldırma.
- Seçim iptal edildiğinde mevcut görselin ve metnin korunması.
- Android'de sistem tarafından kesilen görsel seçiminin kurtarılması.
- Görseli sola veya sağa 90° döndürme.
- Latin karakter modeliyle cihaz üzerinde metin tanıma.
- Çıkarılan metni elle düzenleme.
- Başarılı OCR sonrasında “Satırları birleştir” bölümüne otomatik kaydırma.
- Düzenlenmiş metni değiştirecek işlemlerden önce onay isteme.

OCR orijinal çözünürlükteki görselle çalışır; önizleme için kullanılan küçültülmüş görüntü OCR girdisi değildir.

### Metin biçimlendirme

“Satırları birleştir” isteğe bağlıdır ve varsayılan olarak kapalıdır.

Açıldığında:

- Basılı satır sonları birleştirilir.
- Satır sonunda tireyle bölünmüş kelimeler sezgisel olarak birleştirilir.
- OCR satırlarının konumlarından paragraf ve başlık sınırları tahmin edilir.
- Liste başlangıçları mümkün olduğunca korunur.

Ham OCR sonucu bellekte ayrıca tutulur. Seçenek kapatıldığında ham sonuç geri gelir. Kullanıcı metni elle değiştirmişse biçim değiştirmeden önce onay istenir.

Bu özellik düz yazı için tasarlanmıştır. Şiir, şarkı sözü, tablo veya sütunlu metinlerde kapalı bırakılması daha uygun olabilir.

### Sesli okuma

Metin alanında görünen veya kayıttan açılan metin, cihazın TTS motoruyla Türkçe okunur.

Kontroller:

- Sesli oku.
- Duraklat ve devam et.
- Önceki ve sonraki cümle.
- Başa dön.
- Durdur.
- 0.75×, 1×, 1.25× ve 1.5× okuma hızı.

Duraklatma uygulamanın takip ettiği cümle konumunu kullanır. Devam edildiğinde mevcut cümle baştan okunur; kelime seviyesinde devam edilmez.

Okuma sırasında hız değiştirilirse mevcut cümle yeni hızla baştan okunur. Duraklatılmışken hız değiştirmek okumayı başlatmaz.

Dinleme paneli ekranın altında sabittir. Ana kontroller görünür; cümle gezinmesi ve hız seçenekleri “Diğer kontroller” bölümündedir.

### Düzenleme ve odak davranışı

- Aktif veya duraklatılmış dinleme oturumunda düzenleme kilitlidir.
- OCR ekranında metin etiketinin yanında kilit ikonu görünür.
- Kilide dokunulduğunda açıklama gösterilir.
- Kilitli metne dokunulduğunda üstte geçici bir bilgilendirme görünür.
- Durdurma sonrasında klavye kendiliğinden açılmaz.
- Oturum bittikten sonra kullanıcı metne yeniden dokunarak düzenlemeye başlayabilir.
- Dinleme oturumu yokken klavye açılırsa OCR ekranındaki alt panel gizlenir.

### Yerel kayıt ve kayıt yönetimi

Metinler SQLite veritabanında başlık ve kategoriyle saklanır.

Kategoriler:

- Kitap.
- Not.
- Yemek tarifi.
- Ders notu.
- Şarkı sözü.

Mevcut akış:

- Görünen metni yeni kayıt olarak kaydetme.
- “Kayıtlarım” ekranında kayıtları listeleme ve açma.
- Kayıtlı metni seslendirme.
- Başlık, kategori ve metni düzenleme.
- Düzenlemeyi aynı kayıt üzerinde güncelleme.
- Kayıt güncellendiğinde listeyi yenileme.
- Kayıt menüsünden onay alarak silme.
- Silme başarısız olduğunda kaydı listede koruma ve tekrar deneme.

Yeni kayıt oluşturma her seferinde ayrı bir kayıt ekler. Kayıtlı içeriğin düzenleme ekranındaki Kaydet işlemi ise aynı kimlikli kaydı günceller ve oluşturulma tarihini korur.

Düzenleme ekranında Kaydet düğmesi AppBar'dadır. Kaydedilmemiş değişikliklerle çıkışta şu seçenekler sunulur:

- Düzenlemeye devam et.
- Kaydetmeden çık.
- Kaydet ve çık.

Kaydetme başarısız olursa veya alanlar geçersizse düzenlemeler korunur ve ekran kapanmaz.

Kayıtlı kitap metinleri iki yana, diğer kategoriler başlangıç yönüne hizalanır. Düzenleme alanları başlangıç yönüne hizalıdır.

## Çevrimdışı çalışma ve ağ erişimi

### OCR

Android'de OCR modeli uygulamayla paketlenir. İlk kullanım için model indirilmesi gerekmez.

Android release APK'da:

- `INTERNET` izni manifest birleştirme kuralıyla kaldırılır.
- Nihai APK izinlerinde `INTERNET` bulunmadığı kontrol edilmiştir.
- Bu yapılandırmayla OCR'nin Pixel 5 emülatöründe çalıştığı doğrulanmıştır.

ML Kit bağımlılıkları telemetri bileşenleri içerir. Release internet izninin kaldırılması bu bileşenleri SDK içinde kapatmaz; uygulamanın standart ağ erişimini engeller.

Debug ve profile sürümleri geliştirme araçları için internet izni taşıyabilir. Release davranışı bu sürümlere genellenmemelidir.

### TTS

Android'de kurulu ve ağ gerektirmediğini bildiren `tr-TR` sesi seçilir. Uygun ses bulunamazsa kullanıcıdan cihazın TTS ayarlarından Türkçe ses verisini yüklemesi istenir.

Ses verilerinin ilk kurulumu internet gerektirebilir. Uygulama bulut TTS servisi veya API anahtarı kullanmaz.

TTS motoru ayrı bir sistem uygulaması olabilir. Bu nedenle uygulamanın internet izninin olmaması, motorun ağ erişimini de engellediği anlamına gelmez.

iOS'ta Türkçe dil desteği kontrol edilir; çevrimdışı davranış henüz doğrulanmamıştır.

## Veri ve dosya yönetimi

- Kayıtlı içeriklerin başlık, kategori, metin ve oluşturulma tarihi SQLite'ta tutulur.
- Fotoğraflar kayıtlı içeriğin parçası olarak veritabanına eklenmez.
- Kullanıcının galerisindeki orijinal dosyalar silinmez.
- `image_picker` geçici kopyalar oluşturabilir; bu kopyaların temizliği henüz uygulama tarafından yönetilmez.
- Döndürme için uygulamanın oluşturduğu geçici kopyalar, ilgili OCR işlemi tamamlandıktan sonra temizlenir.
- OCR sırasında uygulama sonlandırılırsa geçici dosya kalabilir; açılışta genel temizlik henüz yoktur.
- Ham OCR sonucu ve yerleşim bilgisi mevcut düzenleme oturumunda tutulur; kayda görünen metin yazılır.
- Hesap, sunucu, bulut senkronizasyonu ve uygulama içi yedekleme henüz yoktur.

## Teknik yapı

- Flutter ve Dart.
- `ChangeNotifier` tabanlı controller'lar.
- `image_picker`: galeri erişimi.
- `google_mlkit_text_recognition`: cihaz üzerinde OCR.
- `image`: görsel döndürme.
- `flutter_tts`: cihaz seslendirmesi.
- `sqflite`: yerel SQLite veritabanı.

Bağımlılık sürümleri için [pubspec.yaml](pubspec.yaml) ve [pubspec.lock](pubspec.lock) dosyalarına bakın.

### Uygulama kimlikleri

- Görünen ad: `Okuma Asistanı`.
- Flutter paket adı: `reading_assistant`.
- Android applicationId: `com.emreekincidev.reading_assistant`.

### Platform gereksinimleri

- Android: mevcut proje minimum API 24 hedefler.
- iOS: ML Kit nedeniyle minimum iOS 15.5.
- Windows geliştirme ortamında Android emülatörü kullanılır.
- iOS derleme ve cihaz kontrolleri macOS/Xcode ortamında yapılmalıdır.
- Diğer platform klasörlerinin bulunması, bu platformların desteklendiği anlamına gelmez.

### Sorumluluklar

- `ImageImportController`: görsel seçimi, döndürme, OCR ve metin durumu.
- `ListeningController`: dinleme oturumu, cümle konumu ve hız.
- `SpeechService`: cihaz TTS motoruyla iletişim.
- `DocumentStore`: yerel kayıt ve sorgular.
- Ekranlar: arayüz, kullanıcı etkileşimi ve onay diyalogları.

Native OCR çağrısı ekran kapanınca gerçekten iptal edilmez. Sonuç yok sayılır ve uygulamanın oluşturduğu geçici döndürülmüş kopya işlem tamamlandıktan sonra temizlenir.

## Klasör yapısı

```text
lib/
  main.dart
  app.dart
  features/
    image_import/
      presentation/
        image_import_controller.dart
        image_import_screen.dart
        widgets/
          image_preview.dart
      services/
        image_picker_service.dart
        image_rotation_service.dart
        ocr_result.dart
        ocr_text_formatter.dart
        text_recognition_service.dart
    listening/
      presentation/
        listening_controller.dart
        listening_controls.dart
      services/
        sentence_splitter.dart
        speech_service.dart
        speech_text_splitter.dart
    library/
      data/
        saved_document.dart
        document_store.dart
      presentation/
        library_screen.dart
        saved_document_screen.dart
        save_document_dialog.dart
```

## Geliştirme

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run
```

Yeni native paket eklendiğinde hot reload yerine uygulamayı tamamen yeniden başlatın.

Release APK oluşturmak için:

```bash
flutter build apk --release
```

Android release derlemesinde ML Kit'in reflection ile oluşturduğu registrar constructor'larını koruyan dar kapsamlı ProGuard kuralları bulunur. Kullanılmayan Latin dışı tanıyıcı sınıfları için sınıfa özel uyarı bastırma kuralları vardır.

`flutter_tts` için Kotlin Gradle Plugin geçiş uyarısı görülebilir. Mevcut derlemeler başarılıdır; gelecekte Flutter/paket yükseltmelerinde uyumluluk yeniden kontrol edilmelidir.

## Test ve doğrulama

Otomatik testler controller durumlarını, arayüz akışlarını, metin biçimlendirmeyi, cümle bölmeyi ve servis sınırlarını kapsar.

Sahte servis testleri gerçek OCR veya TTS motorunun doğruluğunu kanıtlamaz. Veritabanı API taklidi kullanan testler de gerçek SQLite dosyasını çalıştırmaz.

Pixel 5 emülatöründe manuel olarak denenen alanlar:

- Galeri seçimi ve önizleme.
- OCR ve elle metin düzeltme.
- Görsel döndürme.
- Satır birleştirme ve paragraf tahmini.
- Temel TTS ve cümle kontrolleri.
- Okuma hızı ve kompakt panel.
- Düzenleme kilidi ve odak davranışı.
- Yerel kayıt, listeleme ve yeniden açma.
- İnternet izni kaldırılmış Android release sürümünde OCR.

Kayıtlı metin düzenleme/dinleme ve son çıkış diyaloğu değişiklikleri için güncel analiz, otomatik test ve manuel regresyon kontrolleri tamamlanmalıdır.

iOS ve gerçek cihaz doğrulaması henüz yapılmamıştır.

## Bilinen sınırlamalar

- OCR Türkçe harfleri, eski kelimeleri, dipnotları ve kaynak numaralarını yanlış tanıyabilir.
- Otomatik yazım düzeltme veya dil modeli kullanılmaz.
- Görsel yönü kullanıcı tarafından düzeltilir; otomatik yön algılama yoktur.
- Paragraf, başlık ve tire birleştirme kuralları sezgiseldir; her sayfa düzeninde doğru çalışmaz.
- Çok sütunlu sayfaların ve tabloların okuma sırası garanti edilmez.
- Cümle bölme bilinmeyen kısaltmalarda veya alışılmadık noktalama kullanımında hata yapabilir.
- Devam et mevcut cümlenin başından okur.
- Hız seçenekleri göreli motor ayarlarıdır; tam süre oranı garanti edilmez.
- `flutter_tts` callback'leri okuma kimliği taşımadığından geç native callback'ler tamamen ayırt edilemez.
- Uzun metinlerin sert bölünmesi bazı birleşik Unicode karakterlerini ayırabilir.
- Emülatörde sistem TTS örneğinde de ses bozulması gözlenmiştir; Cold Boot sonrasında düzelmiştir. Gerçek cihazda ayrıca değerlendirilmelidir.
- Şu an her kayıt tek metin gövdesidir; çok sayfalı kitap yönetimi yoktur.
- Son okuma konumu ve hız tercihi uygulama yeniden açıldığında saklanmaz.
- Arka planda ve ekran kilitliyken dinleme desteklenmez.
- Kaydedilen metnin önceki sürümleri ve ham OCR'ye kalıcı geri dönüş henüz tutulmaz.

## Sonraki adımlar

- Kayıtlar içinde arama.
- Tüm kategoriler için çok sayfalı içerik yapısı ve mevcut kayıtların taşınması.
- Sayfa ekleme, sıralama, değiştirme ve silme.
- Sayfalar arasında geçiş ve ardışık seslendirme.
- Kameradan fotoğraf çekme.
- Son okuma konumunu ve tercihleri saklama.
- Yazı boyutu, hizalama, satır aralığı ve tema seçenekleri.
- Okunan cümleyi vurgulama ve isteğe bağlı otomatik kaydırma.
- Gerçek Android cihazda ve iOS'ta doğrulama.
- Dışa aktarma ve yedekleme.

## Proje kuralları

Kod ve çalışma kuralları için
[Copilot talimatları](.github/copilot-instructions.md) dosyasına bakın.

Commit ve push işlemleri manuel yapılır.
