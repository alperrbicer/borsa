# Borsa · Kişisel iOS uygulaması

Türkçe SwiftUI uygulaması: takip listesi, portföy, limit alış/satış denemeleri ve kalıcı emir geçmişi. iOS 17+; üçüncü taraf uygulama paketi gerektirmez.

**Canlı piyasa verisi ve aracı kurum bağlantısı henüz yok.** Sekiz BIST hissesi için sabit örnek fiyatlar ve yerel deneme hesabı kullanılır. Gerçek emir gönderilmez. Bu sürüm kişisel cihaz kullanımı için hazırlanmıştır; App Store yayını yapılmaz.

BIST ve ABD için gerçek veriye dayalı otomatik sanal işlem hedefi, ücretsiz/ücretli veri seçenekleri ve aşama kabul ölçütleri [geliştirme planında](docs/AUTOMATION_PLAN.md) yer alır. Bu özellikler henüz uygulanmadı.

## iPhone'a kurulum

```sh
cd /Users/alperbicer/Documents/projects/private/borsa
bun run mobile:ios:install
```

Tek eşlenmiş iPhone otomatik seçilir. Telefonun bağlı, kilidinin açık ve Geliştirici Modu'nun etkin olması gerekir. Birden fazla cihaz varsa:

```sh
bun run mobile:ios:install --device 00008140-000E60E20EC0801C
```

Kurulum uygulamayı silmez. Bundle ID `dev.prototype.borsa` korunarak mevcut hesap yükseltilir. `Config/Local.xcconfig` yerel imzalama takımını tutar. Sertifika/profil durumunu `bun run mobile:doctor` ile kontrol edebilirsin. Gerekirse `--allow-provisioning-updates` kullanılır.

CarMirror'dan uyarlanan komutlar ve ayrıntılar: `docs/DEPLOYMENT.md`. Bun yerine npm veya doğrudan Node da kullanılabilir; `bun install` gerekmez.

## Kullanım

- **Piyasa:** hisse, şirket veya sektöre göre Türkçe karakter toleranslı arama; kod, yükseliş, düşüş ve fiyat sıralaması.
- **Takip:** detay ekranındaki yıldızla şirket ekleme/çıkarma; cihazda kalıcı liste.
- **Portföy:** toplam varlık, hisse/nakit dağılımı, kullanılabilir ve ayrılan bakiye, gerçekleşen/açık pozisyon kâr/zararı; bakiyeleri gizleme.
- **Emir:** alış/satış, %25/%50/Tümü adet, limit tutarı, bakiye/adet kontrolleri; ayrı gözden geçirme ve onay.
- **Geçmiş:** tüm/bekleyen/gerçekleşen/iptal edilen emir filtreleri; onaylı iptal ile nakit veya adet blokajını çözme.
- **Ayarlar:** koyu/açık/sistem teması, JSON yedek dışa aktarma, doğrulanmış yedekten geri yükleme ve önceki yerel kayda dönme.

Fiyat girişinde `312,50` ve `312.50` kabul edilir; binlik ayırıcılar ve ikiden fazla ondalık basamak reddedilir. Para işlemleri tam sayı kuruş ile hesaplanır.

## Kayıt ve kurtarma

Hesap, takip listesi ve tercihler Application Support içinde tek bir sürümlü JSON dosyasına atomik olarak yazılır. İşlem ancak kayıt başarıyla tamamlanınca ekrana yansır. Önceki geçerli dosya yerel yedek olarak korunur.

Eski UserDefaults kaydı ilk açılışta otomatik taşınır; eski anahtar silinmez. Bozuk veya desteklenmeyen kayıt hesap sıfırlanarak örtülmez: işlem ekranları durdurulur, kurtarma ekranı açılır. Kullanıcı yedek yükleyebilir veya açık onayla yeni deneme hesabı oluşturabilir. Okunamayan dosya bu işlem sırasında ayrıca korunur.

Dışa aktarılan yedek hesabın tamamını içerir ve şifreli değildir. Yedek bir dosyadır; otomatik bulut eşitlemesi yoktur. Uygulama silinirse cihazdaki hesap ve yerel yedekler silinebilir. Ayarlar → Yedeği dışa aktar ile uygulama dışında kopya saklanabilir.

## Deneme hesabının sınırları

Başlangıçtaki 100.000 TL ve hisse pozisyonları sanaldır. Grafikler gerçek fiyat geçmişi göstermez. Alış limiti örnek son fiyata eşit/yüksekse, satış limiti eşit/düşükse emir örnek fiyattan tamamen gerçekleşir. Diğer emirler iptal edilene kadar bekler; fiyat akışı olmadığından kendiliğinden gerçekleşmez.

Komisyon, vergi, kısmi gerçekleşme, seans/takas ve kurumsal işlemler modellenmez. Hesap motoru gerçek aracı kurum muhasebesi yerine kullanılamaz. Canlı kullanım için seçilen veri sağlayıcısı ve aracı kurumun resmi API sözleşmeleriyle ayrı entegrasyon gerekir. `LiveBrokerGateway` yalnızca bu sınırı tanımlar; `UnconfiguredBroker` gerçek emir isteklerini reddeder.

## Geliştirme ve doğrulama

```sh
bun run check        # Script testleri + Swift testleri + simülatör derlemesi
bun run test:scripts # Yalnızca kurulum/dağıtım scriptleri
swift test           # Muhasebe, kayıt, yedek ve arama testleri
```

`Borsa.xcodeproj` → `Borsa` scheme → Product → Test, seçili simülatör veya iPhone üzerindeki UI akışlarını çalıştırır. `check`, UI testi veya fiziksel cihaz kurulumu yapmaz. Ayrıntılı sonuçlar ve kanıt dosyaları `VALIDATION.md` içindedir.

UI testleri **ayrı bir hesap dizini ve UserDefaults alanı** kullanır. `--ui-testing` bu alanı seçer, `--reset-test-state` yalnızca test hesabını sıfırlar. Bu yardımcılar sadece Debug derlemesinde etkindir. Normal kullanıcının hesabı testler tarafından sıfırlanmaz.

Kod: `BorsaApp/` ekranlar; `Sources/BorsaCore/Trading.swift` muhasebe; `Persistence.swift` doğrulama/kalıcılık/arama; `Market.swift` örnek fiyatlar. `Tests/` çekirdek ve dağıtım testlerini, `UITests/` uçtan uca ekran akışlarını içerir. Uygulama simgesi `swift scripts/generate-icon.swift` ile yeniden üretilebilir.
