# Okuma Asistanı – Copilot Talimatları

Flutter mobil uygulaması (Android + iOS). Ürün amacı ve geliştirme sırası için [README.md](../README.md) dosyasına bak.

## Ürün özeti

Kullanıcı fotoğraf çekerek, galeriden görsel seçerek veya elle yazarak metin oluşturur; metni düzenler, cihazda saklar ve sesli dinler. İçerik kitap, not, tarif, ders notu veya şarkı sözü olabilir; bir içerik birden fazla sıralı metin sayfası içerir.

## Kısıtlar

- OCR cihazda çalışır. TTS cihazın seslendirme motorunu kullanır.
- Çevrimdışı çalışma hedeflenir; OCR modeli ve TTS seslerinin kurulu olduğu kontrol edilir, eksikse kullanıcıya Türkçe açıklama gösterilir.
- Veriler yerel SQLite'ta tutulur.
- Fotoğraflar kalıcı saklanmaz. Metin onaylanınca veya işlem iptal edilince yalnızca uygulamanın oluşturduğu geçici dosyalar silinir; kullanıcının galerisindeki orijinalleri ve sahipliği belirsiz dosyaları asla silme.
- Dinleme: oynat, duraklat/devam et, durdur, önceki/sonraki cümle, sayfa başına dön, hız ayarı. Son okuma konumu saklanır. İlk sürümde arka planda dinleme yok.
- Backend, bulut servisi, hesap sistemi veya API anahtarı ekleme.

## Geliştirme kuralları

- Küçük, çalışan adımlarla ilerle; README'deki sırayı izle.
- Değiştirmeden önce mevcut kodu incele; incelemeden yeniden yazma.
- Basit yapı kullan. İhtiyaç oluşmadan soyutlama, katman veya paket ekleme.
- Paket eklerken güncel sürümü, bakım durumunu ve Android/iOS gereksinimlerini (minSdk, iOS sürümü, izinler) kontrol et.
- İstenmedikçe commit, push veya kapsam dışı değişiklik yapma.

## Kod stili

- UI metinleri Türkçe, kod (sınıf, değişken, dosya adları, yorumlar) İngilizce.
- `analysis_options.yaml` ve `flutter_lints` kurallarına uy. Yalnızca açıklama gerektiren yerlere yorum yaz.

## Erişilebilirlik

- Büyük yazı boyutlarında (metin ölçeklendirme) taşma olmamalı; sabit yükseklikten kaçın, kaydırılabilir düzen kullan.
- Düğmelerin anlamlı Türkçe etiketleri/`tooltip`/`Semantics` açıklamaları olsun; yalnızca ikon kullanma.
- Yeterli renk kontrastı ve en az 48x48 dokunma alanı sağla.

## Asenkron işlemler

- Yüklenme, hata, boş durum ve iptal durumlarını ele al; hatalar kullanıcıya Türkçe gösterilsin.
- `await` sonrası `BuildContext` veya `setState` kullanmadan önce `mounted` kontrol et.
- `dispose` içinde controller, stream ve TTS/OCR kaynaklarını serbest bırak; sayfadan çıkınca devam eden işlemi durdur.
- Geçici dosyalar: yalnızca uygulamanın kendisinin oluşturduğu ve sahipliğini bildiğin kopyaları temizle (örn. kendi geçici klasörümüzde oluşturduğumuz dosyalar). Galerideki orijinalleri veya sahipliği belirsiz dosyaları asla silme. `image_picker`'ın döndürdüğü yolun uygulamaya ait kopya olduğu doğrulanmadan silinmez. Görsel ekranda gösterilirken veya sonraki OCR akışında kullanılacakken temizleme yapma; temizlik metin onaylandığında veya işlem iptal edildiğinde, başarı/hata/iptal yollarının hepsinde yapılır.

## Doğrulama

Kod değişikliğinden sonra:

```bash
dart format .
flutter analyze
flutter test   # değişiklikle ilgili testler
```

Çalıştırılamayan kontrolleri (örn. gerçek cihaz, OCR/TTS testleri) son özette açıkça belirt. Davranış değişince ilgili testi ve README'yi güncelle.
