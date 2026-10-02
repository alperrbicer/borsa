# Doğrulama · 3 Ekim 2026

Bu kayıt 0.3.0 kaynak ağacındaki gerçek veri/sanal hesap uygulamasını kapsar. Son talimat **“cihaza bağlanmadan kalan işleri bitir”** olduğu için bu çalışmada fiziksel telefon sorgulanmadı, kurulmadı veya çalıştırılmadı. Mac testleri, çalışan yerel sunucu ve geçmiş cihaz kanıtı aşağıda ayrı tutulur.

## Güncel kaynaklarla tamamlanan kontroller

| Kontrol | Sonuç |
| --- | --- |
| `bun run check` | Çıkış kodu 0; `build/check-oct03.log` |
| Kurulum scriptleri | 12 test geçti |
| Bun sunucusu | 49 test geçti, 0 hata |
| Swift | 38 test geçti, 0 hata; 31 eski çekirdek, 3 Paper modeli, 4 gerçek yerel HTTPS istemci testi |
| İmzasız iOS Simulator derlemesi | Geçti; genel simülatör hedefi, `CODE_SIGNING_ALLOWED=NO` |
| Çalışan Mac sunucusu | Sertifikası doğrulanan HTTPS sağlık isteği 200; kimliksiz durum isteği 401; kimlikli durum isteği 200 |
| Kalıcı hesap / servis açılışı | Nakit, pozisyon, emir, ayar ve takip listesi özeti değişmedi; geçici test erişimi kaldırıldı |
| Gerçek haberler | Doğrulama anında 42 kayıt: 20 TCMB, 22 Federal Reserve; iki kaynak bağlı |
| Gerçek fiyatlar | 0; sağlayıcı hesabı yok. Örnek fiyat eklenmedi, sanal emir oluşmadı |
| Fiziksel iPhone / APNs teslimi | Bu turda çalıştırılmadı |
| Commit / push / App Store işlemi | Bu turda yapılmadı |

Toplam **99 otomatik test** geçti. `check` fiziksel cihaza bağlanmaz; simülatörü açıp UI testi de yapmaz. Derleme Xcode 27, testler Bun 1.3.14 / Swift 6 ile yapıldı.

## Test edilen davranışlar

Sunucu testleri ayrı geçici SQLite hesapları kullanır. Bakiye ve hisse rezervasyonu, komisyon/kayma, kısmi gerçekleşme, aynı kotasyonun likiditesinin paylaşılması, sonraki fiyat olayı şartı, limit, seans, eski/gelecek/gecikmeli verinin reddi, kaynak değişiminde iptal ve tekrar eden işlemlerde muhasebe eşitliği kontrol edilir. Günlük kayıp, pozisyon/sektör yoğunluğu, günlük emir sayısı ve otomatik bekleme süresi sınanır.

Haber testleri şirket/özne eşleşmesi, Türkçe/İngilizce yön, olumsuzlama, çelişki, eski veya gelecekteki haber, kaynak dayanağı, kopya olay, cevapsız inceleme, önizleme süresi ve geç onayda yeniden değerlendirmeyi kapsar. Lisanslı köprüden Türkçe şirket haberi ve fiyatın aynı döngüde karar oluşturması test edildi. Üretim hesabına test haberi/fiyatı yazılmadı.

Servis testleri SQLite yeniden açılışını, bozuk kaydın sessizce sıfırlanmamasını, başarısız işlemin geri alınmasını, kimlik doğrulamayı, tek kullanımlık/süreli eşleşmeyi, deneme sınırını, büyük/geçersiz istekleri ve eşzamanlı istek tekilleştirmesini kapsar. APNs testlerinde gönderici taklit edilir: teslim kabulünden önce başarı gösterilmemesi, hatanın görünmesi, yeniden deneme, yinelenen teslimlerin engellenmesi, 10'dan fazla incelemenin kuyrukta ilerlemesi ve bir hatalı cihazın diğerini engellememesi doğrulanır. Apple'a gerçek bildirim gönderilmedi.

Dört Swift HTTPS testi Mac'te `127.0.0.1` ve geçici sertifika kullanır. Üretim HTTP işleyicisiyle eşleşme, gerçek API yanıtının Swift modellerine dönüşmesi, işlem/risk hata metni, yedek okuma, yanlış sertifika parmak izinin ve HTTP yönlendirmesinin reddi doğrulanır. Test sertifikaları ve hesaplar kapanışta temizlenir. Swift'in eski 31 testi kayıt/migrasyon/kurtarma, para hesabı, tekrar istek, Türkçe arama ve tercihlerin korunmasını kapsar.

## Bu turda giderilen sorunlar

- `bun test Tests/Server` ayrıntısız çıkış kodu 1 veriyordu. Aynı testler açık dosya listesiyle geçti; `scripts/test-server.mjs` sadece gerçek test dosyalarını seçiyor. `test:server` ve `check` bu çalıştırıcıyı kullanıyor; kontroller zayıflatılmadı.
- Yerel TLS sertifikasında Apple istemcisinin istediği `serverAuth` alanı yoktu. Sertifika üretimi düzeltildi ve yerel sertifika eskisi saklanarak yenilendi. Swift istemcisi görev düzeyindeki doğrulama isteğini de işliyor; alan adı/geçerlilik denetimi korunuyor. İlk başarısız HTTPS denemelerinden sonra dört test geçti.
- APNs yapılandırmasının teslim edilmiş gibi görünmesi, gönderim hatalarının gizlenmesi ve bildirim kuyruğunda eski kararların ilerleyememesi düzeltildi. Bildirim döngüsü fiyat toplama döngüsünden ayrıldı.
- Bildirimden belirli kararı açma, reddedilmiş izin için iOS Ayarlar'a geçiş, portföy tutarlarının gizlenmesi ve kalan emir için iptal onayı eklendi. Bu SwiftUI değişiklikleri derlendi; telefonda görsel doğrulanmadı.

## Mac sunucusunun kanıtı

`build/live-server-oct03.json` sertifika doğrulaması, HTTP durumları, kaynak sağlıkları ve hesap korunumu sonucunu içerir. Doğrulama Node HTTPS istemcisi ve ayrıca `curl --cacert` ile yapıldı; TLS doğrulaması kapatılmadı. Geçici erişim tokenı yalnızca hash olarak eklendi ve işlem sonunda silindi; hiçbir sağlayıcı anahtarı kayda yazılmadı.

Oturumda yüklenmemiş olan mevcut LaunchAgent kaydı yeniden yüklendi; ardından `server:service:restart` başarıyla çalıştı. `server:service:status` sonucu `running`. Sunucu `review` modunda, 100.000 sanal TL ve 10.000 sanal USD, sıfır pozisyon/emir ile devam ediyor. Tam Mac yeniden başlatması, uyku dönüşü veya saatler süren kararlılık testi yapılmadı.

## Önceki fiziksel cihaz kanıtı · 2 Ekim

Son cihaz doğrulaması iPhone 16 Pro / iOS 27.0 üzerinde **0.3.0 (4)** içindi: **9 test, 0 hata, 0 atlanan test**, `runtimeWarnings: []`. Yedi test eski deneme hesabının alış/satış, kalıcılık, kurtarma, tema/arama, erişilebilirlik ve iptal akışlarını; iki test yeni uygulamanın eşleşmemiş ekranlarını ve geçersiz kod denetimini kapsar. Testlerden sonra normal uygulama açıldı; örnek fiyat yoktu, telefon sunucuyla eşleştirilmedi.

Kanıtlar: `build/physical-paper-tests.log`, `build/PhysicalPaperUITests.xcresult`, `build/physical-paper-summary.json`, `build/paper-device-app.json`, `build/paper-device-launch.json`, `outputs/Borsa-iPhone16Pro-0.3.0.png`.

Daha eski 0.2.1 (3) çalışmasında yedi cihaz testi ve normal hesabın öncesi/sonrası bayt eşitliği doğrulandı. Kanıtlar `build/quality-ui-physical.log`, `build/PhysicalQualityUITests.xcresult`, `build/quality-ui-physical-summary.json`, `build/quality-account-preservation.json`, `build/quality-device-app-v021.json` ve `outputs/Borsa-iPhone16Pro-0.2.1.png` içinde korunur. Sonraki turlarda aynı dosya karşılaştırması yeniden yapılmadı. Eski başarısız simülatör UI denemeleri başarılı fiziksel çalışmayla karıştırılmaz.

## Doğrulanmamış olanlar

Gerçek fiyat hesabıyla veri gecikmesi/kota, gerçek seans boyunca sanal emir gerçekleşmesi, sağlayıcıya özel BIST köprüsü, kapalı uygulamaya APNs teslimi ve yeni kaynaklarla telefon eşleşmesi henüz doğrulanmadı. Ücretsiz TCMB/Fed erişimi bunların yerine geçmez. Yeni sertifika parmak izi bir sonraki izin verilen telefon kurulumuna alınmalıdır.

Testler modelin belirlenmiş kurallarını doğrular; bölünme/temettü, vergi, takas, bağımsız hisse durdurma olayları, karşılaştırma endeksi veya LLM analizi bu sürümde yoktur. Sunucu yedeğinin dışa aktarılması desteklenir; yeni sunucu hesabı için geri yükleme UI'si yoktur. Arşiv/export/upload/TestFlight çalıştırılmadı.
