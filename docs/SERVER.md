# Borsa sunucusunun kurulumu ve işletimi

Sürekli haber takibi ve sanal işlemler Mac'teki Bun servisi tarafından yürütülür. Telefon ekranları ve onayları sunar. Telefon kapalıyken sunucu devam edebilir; Mac uyuduğunda veya kapandığında takip durur. Yerel kurulum LAN dışına açılmamıştır.

## Yerel kurulum

```sh
bun run server:setup
bun run server:service:install
bun run server:service:status
```

`setup`, `.env.server.example` dosyasından eksikse `.env.server` oluşturur. Mevcut sağlayıcı ayarlarını ve SQLite hesabını değiştirmez. `.borsa-server/` içinde RSA 2048/SHA-256 TLS anahtarı ve sertifika üretir. Sertifikada DNS/IP, `serverAuth` ve anahtar kullanım alanları vardır. Apple gereksinimleri [resmî sertifika belgesinde](https://support.apple.com/en-us/103769) açıklanır.

Sunucu adı değişmiş, sertifika süresi dolmuş veya gerekli kullanım alanı eksikse yeni sertifika oluşturulur; eskisi `.previous-<zaman>` uzantısıyla saklanır. `Config/Server.local.xcconfig` içine yalnızca adres ve açık SHA-256 parmak izi yazılır. Sertifika değişiminden sonra servis yeniden başlatılır; uygulamadaki parmak izi de güncellenmelidir. Keychain veya sistem güven deposuna genel bir güven istisnası eklenmez.

`server:service:install` yalnızca bu kullanıcının `~/Library/LaunchAgents/dev.prototype.borsa.server.plist` dosyasını yönetir. Aynı servisi yeniden kurmak hesabı silmez. Servis kullanıcı oturumunda çalışır; çökme durumunda launchd yeniden başlatır. Tam kapanış/uyku dönüşü bu çalışmada fiziksel olarak sınanmadı.

```sh
bun run server:service:restart   # .env.server değişikliğini uygula
bun run server:service:uninstall # Otomatik başlangıcı kaldır; hesabı koru
bun run server:start             # Servis yüklü değilken terminalde çalıştır
bun run server:status            # Genel adres ve sertifika parmak izi
bun run server:pair              # Üç dakikalık, tek kullanımlık kod
```

Aynı anda terminal sunucusu ve LaunchAgent başlatılmaz; ikisi de 8787 portunu kullanır. Günlükler `.borsa-server/logs/` içindedir. API anahtarları ve bearer tokenları günlüklere yazılmaz.

## Telefon eşleştirmesi

Telefon ve Mac aynı ağda olmalı. `server:pair` çıktısındaki kod Ayarlar → Sunucu bağlantısı alanına girilir. Uygulama sunucuya HTTPS ile bağlanır, sertifika parmak izini ve alan adını doğrular. Token Keychain'e, sunucudaki karşılığı hash olarak SQLite'a yazılır. Yanlış sertifika, HTTP adresi veya yönlendirme kabul edilmez. Beş hatalı kod denemesinden sonra bir dakika beklenir.

Özel bir sunucu taşınmasında yeni HTTPS adresi ve parmak izi Ayarlar'dan girilir; yeni sunucuda kod üretilir. Token başka bir sunucuya kendiliğinden taşınmaz. Cihaz kaydı ve portföy kaydı ayrıdır.

## Sağlayıcı ayarları

Anahtarlar `.env.server` içinde tutulur; dosya Git dışında ve yalnızca kullanıcı tarafından okunabilir olmalıdır. Ortam değişkeni dosya değerine göre önceliklidir.

| Ayar | Kullanım |
| --- | --- |
| `ALPACA_KEY_ID`, `ALPACA_SECRET_KEY` | ABD fiyat/haber erişimi ve salt okunur Paper clock API |
| `ALPACA_FEED=iex` | Ücretsiz IEX kapsamı |
| `ALPACA_FEED=sip` | Hesap yetkisi gerektiren birleşik ABD kapsamı |
| `ALPACA_FEED=delayed_sip` | Gecikmeli gösterim; gün içi gerçekleşme kapalı |
| `TWELVE_DATA_KEY` | BIST gün sonu gösterimi; saatlik sorgu |
| `LICENSED_FEED_URL`, `LICENSED_FEED_TOKEN` | Sağlayıcı tarafından yetkilendirilmiş HTTPS köprüsü |
| `APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID` | Apple bildirim anahtarı; `.p8` uygulamaya gömülmez |
| `APNS_TOPIC` | Bundle ID; varsayılan `dev.prototype.borsa` |
| `APNS_ENV` | `development` veya `production`; imza ortamıyla aynı olmalı |

TCMB ve Fed yaklaşık iki dakikada bir sorgulanır. Fiyat/işlem döngüsü tamamlandıktan 15 saniye sonra yenisi başlar; üst üste aynı döngü çalışmaz. Bildirim işi ayrı yürütülür, yavaş APNs fiyat döngüsünü tutmaz. Ağ yanıtları boyut ve süreyle sınırlıdır. Kesinti yeni fiyat üretmez, etkilenen akışta gerçekleşme izni kapanır. Kaynak/paket değişen bekleyen emir yeni kaynakla sessizce doldurulmaz.

## Lisanslı köprü sözleşmesi

Bu uygulamaya ait normalleştirilmiş sözleşmedir. **Doğrudan Matriks API şeması değildir.** Sağlayıcının onayladığı gerçek uç nokta ve erişim belgesi edinilince bir köprü bu sözleşmeye dönüştürülür. Varsayılan bir Matriks URL'si veya parolası yoktur.

HTTPS `GET`, `Authorization: Bearer <token>` ile alınır. Yanıt `version: 1`, boş olmayan sağlayıcı adı `source` ve `quotes` dizisi taşır. Her kayıtta aşağıdaki alanlar gerekir:

| Alan | Anlam |
| --- | --- |
| `symbol`, `currency` | Katalogdaki hisse; `TRY` veya `USD`, katalogla aynı |
| `priceUnits` | Gerçek kaynaktan fiyat × 10.000, pozitif tam sayı |
| `timestamp` | Fiyat olayının Unix zamanı, milisaniye |
| `quality`, `delaySeconds` | `realtime`, `delayed` veya `eod`; bilinen gecikme saniyesi |
| `sessionOpen` | Sağlayıcının doğruladığı işlem seansı durumu |
| `bidUnits`, `askUnits` | Gerçek alış/satış kotasyonu × 10.000; işlem için zorunlu |
| `bidSize`, `askSize` | Kotasyondaki tam hisse adedi; gerçekleşme buna göre sınırlanır |
| `previousCloseUnits` | Haber kuralının fiyat tepkisi için gerçek önceki kapanış; bilinmiyorsa otomatik sinyal çıkmaz |

Alınma zamanını sunucu yazar. Kaynak fiyatı veya kotasyon miktarı tahminle doldurulmaz. Sıralaması geriye giden fiyatlar reddedilir. EOD verisine alış/satış kotasyonu uydurulmaz. Köprü hesabının gerçek erişimi şu anda test edilmiş değildir.

Yanıt isteğe bağlı `news` dizisi de taşıyabilir. Her haber `id`, `title`, HTTPS `url`, milisaniye `publishedAt`, katalog sembollerinden `symbols` ve `scope` (`company` veya `macro`) içerir. `summary` isteğe bağlıdır; `market` BIST için `BIST`, ABD için `US` olur. Kaynak adı üstteki `source` alanından, kaynak sınıfı yetkili köprüden alınır. En fazla 100 haber işlenir; eksik/tarihsiz veya gelecekteki kayıtlar reddedilir. Aynı kimlik/URL ikinci karar üretmez. Türkçe şirket başlığıyla otomatik karar yolu ayrı test hesabında sınandı; gerçek sağlayıcı haber yetkisi ayrıca gerekir.

## Emir ve değerlendirme modeli

Her emir ayrı ve kalıcı bir istek kimliği taşır. Aynı kimlik ve aynı içerik ikinci emir oluşturmaz; farklı içerikle tekrar kullanımı reddedilir. Yeni emrin karar anındaki kotasyonla dolmasına izin verilmez. İşlem için kaynak ve alınma zamanının 45 saniyeden eski olmaması, açık seans, gecikmesiz veri, geçerli kotasyon ve miktar gerekir. Çok küçük saat farkına iki saniye tolerans vardır.

Limit, kayma sonrası fiyatla karşılaştırılır. Gerçekleşme miktarı kotasyon miktarını aşmaz; aynı kotasyon birden fazla emirde sınırsız kullanılamaz. Kısmi gerçekleşmelerde komisyon emir toplamından hesaplanır. Muhasebede nakit + eldeki maliyet = başlangıç nakdi + gerçekleşen net sonuç eşitliği kontrol edilir. Toplam performans için herhangi bir varlığın fiyatı eskimişse toplam/getiri boş gösterilir.

`review` varsayılan moddur. `auto` yalnızca dar şirket haberi kuralları, güncel fiyat tepkisi ve risk sınırları birlikte uygunsa sanal emir verir. Başlık/özet dışında tam haber bağlamı veya LLM kullanılmaz. İnceleme en çok 15 dakika, haberin işlem penceresi 30 dakikadır. Kullanıcı önizlemesi 30 saniye geçerlidir; miktar, fiyat veya masraf değiştiyse yeni önizleme gerekir. Cevapsız inceleme emir oluşturmaz.

Sanal model tam adet, peşin nakit ve limit emirlerle çalışır. Vergi ve takas gecikmesi yoktur. Bölünme/temettü düzeltmeleri, ayrı hisse durdurma takibi ve karşılaştırma endeksi bu sürümde yoktur. Bu olayların olduğu dönemler muhasebe/model açısından ayrıca değerlendirilmelidir; uzun vadeli gerçek toplam getiri doğrulaması yapılmış sayılmaz.

## Bildirim ve kayıt

APNs durumları ayrı gösterilir: anahtar eksik (`setup`), yapılandırıldı fakat gönderim doğrulanmadı (`ready`), Apple isteği kabul etti (`connected`), gönderim başarısız (`error`). Apple kabulü, bildirimin telefonda gösterildiğinin kanıtı değildir. Hatalı gönderim tekrar denenir; süresi dolan inceleme gönderilmez. Geçersizleşen cihaz kaydı kaldırılır. Ağ hatası diğer cihazların bildirimini durdurmaz.

iOS bildirim izni ve Apple anahtarı gerekir. Bildirime dokunmak ilgili kararın ayrıntısını hedefler. Canlı APNs teslimi ve telefondaki geçiş bu cihaz kullanılmayan çalışmada doğrulanmadı. İnceleme her durumda Asistan'da kalır.

SQLite hesap ve işlem günlüğünün asıl kaydıdır. API durum yanıtında son 500 emir, uygulama listesinde son 100 emir bulunur; tam emir ve gerçekleşme ayrıntıları JSON yedeğinde saklanır. En fazla 10.000 emir, 500 haber, 2.000 karar ve sembol başına 480 gözlenen fiyat tutulur. Emir sınırına ulaşıldığında yeni emir reddedilir; para sessizce sıfırlanmaz.

Ayarlar'dan dışa aktarılan JSON şifreli değildir. SQLite'ın ham dosyasını kopyalarken servis durdurulmalı veya SQLite'ın yedek yöntemi kullanılmalıdır; aktif WAL dosyası atlanmamalıdır. Hesap yedeği veri servisi anahtarlarını içermez. Bu sürümde sunucu yedeği geri yükleme UI'si yoktur; eski deneme hesabının kurtarma sistemi ayrıdır.
