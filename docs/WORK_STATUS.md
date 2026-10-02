# Çalışmaya devam notu · 2 Ekim 2026

Kullanıcının son talimatı: **“cihaz testlerini bitir ve dur. kaldığın yeri not al”**. Devam eden fiziksel cihaz testi tamamlandı; geliştirme bu noktada durduruldu. Kullanıcı devam istemeden kalan işleri yürütme.

## Cihazda doğrulanan durum

- iPhone 16 Pro, iOS 27.0, cihaz `00008140-000E60E20EC0801C`.
- `dev.prototype.borsa` sürüm **0.3.0 (4)** kurulu; cihaz uygulama sorgusuyla doğrulandı.
- **9 UI testi geçti, 0 hata, 0 atlanan test**, `runtimeWarnings: []`.
- 7 test eski hesabın alış/satış, kayıt, kurtarma, arama, tema, erişilebilirlik ve iptal akışlarını ayrı test hesabında kontrol ediyor.
- 2 yeni test gerçek veri ekranlarının **sunucu eşleşmesi olmayan durumunu** kontrol ediyor: dört sekme, örnek fiyat gösterilmemesi, bağlantı ayarları ve geçersiz/boş kodla eşleşmenin kapalı olması.
- Bu sonuç, gerçek fiyatla emir gerçekleşmesinin veya APNs bildiriminin fiziksel cihazda doğrulandığı anlamına gelmez.
- Testlerden sonra uygulama test parametreleri olmadan açıldı. Görüntü incelendi: yeni Özet ekranı, “Gerçek veriye bağlan”, dört yeni sekme; örnek fiyat yok. Telefon sunucuyla henüz eşleştirilmedi.
- Normal eski hesabın dosyası bu turda cihazdan tekrar alınarak bayt düzeyinde karşılaştırılmadı. Önceki 0.2.1 karşılaştırmasının kanıtı ayrı duruyor.

Kanıtlar:

- `build/physical-paper-tests.log`
- `build/PhysicalPaperUITests.xcresult`
- `build/physical-paper-summary.json`
- `build/paper-device-app.json`
- `build/paper-device-launch.json`
- `outputs/Borsa-iPhone16Pro-0.3.0.png`

## Yazılmış kod

- `server/domain.mjs`: ayrı 100.000 sanal TL / 10.000 sanal USD, tam sayı para hesabı, alış/satış kotasyonu, kayma, kümülatif komisyon, kısmi gerçekleşme, nakit/adet rezervasyonu, iptal, 15 dakika emir süresi, pozisyon/sektör/günlük kayıp/emir sıklığı sınırları. Emir ancak oluşturulmasından sonraki güncel kotasyonla doluyor. Tekrarlanan istek aynı emri döndürüyor.
- `server/storage.mjs`: Bun SQLite, WAL ve atomik işlem; kalıcı hesap, hash olarak tutulan erişim tokenları, cihaz/bildirim kayıtları. Bozuk hesap sessizce sıfırlanmıyor.
- `server/providers.mjs`: Alpaca IEX/SIP fiyat ve clock bağlantıları, ayrı Alpaca haber bağlantısı, Twelve Data BIST gün sonu, lisanslı sağlayıcı için sürümlü HTTPS köprü sözleşmesi, ücretsiz Fed ve TCMB RSS/Atom. Gecikmeli/gün sonu veriyle gün içi gerçekleşme kapalı. Sağlayıcı kesintisi kotasyonların işlem iznini kapatıyor.
- `server/analysis.mjs`: kaynaklı ve açıkça kural temelli şirket/sektör/portföy değerlendirmesi; çelişkili, eski veya belirsiz haberlerde otomatik işlem yok. Haber başlığının şirketi doğrudan özne olarak taşıması ve fiyat yönü gibi ek koşullar var. İnceleme süresi dolunca emir yok. İşlem önizlemesi 30 saniye geçerli; fiyat/masraf değişirse tekrar onay gerekiyor.
- `server/http.mjs`: HTTPS sunucusu için kimlik doğrulamalı API, tek kullanımlık eşleşme, bounded JSON, inceleme önizlemesi/onayı, ayarlar, takip listesi ve yedek dışa aktarımı.
- `server/notifications.mjs`: APNs ES256/HTTP2 gönderimi, karar bağlantısı, süre ve teslim tekilleştirmesi. APNs anahtarı henüz yok.
- `BorsaApp/PaperStore.swift`, `PaperViews.swift`, `PaperSettings.swift`, `Sources/BorsaCore/PaperModels.swift`: yeni Özet/Piyasalar/Portföy/Asistan ekranları; HTTPS sertifika pinleme, Keychain, çevrimdışı kayıt, kaynak/saat/gecikme, emir/inceleme önizlemesi, risk ayarları ve bildirim izni.
- Normal kök ekran `PaperRootView`; eski örnek fiyatlı ekranlar yalnızca Debug `--ui-testing` yolunda. Eski hesap yeni performansa eklenmiyor; eski hesap dışa aktarılabiliyor.
- `scripts/server.mjs`: setup/pair/status. `scripts/service.mjs`: macOS kullanıcı servisi install/status/restart/uninstall. Bun komutları `package.json` içinde.
- `Config/Server.local.xcconfig` yalnızca yerel sunucu adı ve açık sertifika parmak izi içeriyor; gizli anahtar uygulamaya gömülmüyor. `.env.server`, `.borsa-server/` ve yerel config Git dışında.

## Çalışan yerel servis

`dev.prototype.borsa.server` LaunchAgent kuruldu ve `running` durumu görüldü. Kullanıcı oturumu açılınca başlar. Geçici terminal sunucusu kapatılıp bu servise geçildi. Haber sunucusu bu durdurma anında çalışmaya bırakıldı; geliştirme durdu.

```sh
bun run server:service:status
bun run server:service:restart
bun run server:service:uninstall
```

Son komut otomatik başlangıcı kaldırır; hesap dosyalarını silmez. Mac uyurken/kapalıyken sürekli çalışma garantisi yoktur. LAN dışı erişim kurulmadı.

- Adres: `https://Alper-MacBook-Air.local:8787`.
- Sertifika, SQLite, bağlantı bilgisi ve günlükler: `.borsa-server/`.
- `server:setup` çalıştırıldı; `.env.server` boş sağlayıcı anahtarlarıyla oluşturuldu.
- Canlı HTTP erişiminde **TCMB'den 20 ve Fed'den 20 gerçek duyuru** alındı; fiyat adedi **0**. Bu haberler SQLite'a yazıldı.
- Fiyat servisi hesabı yok. Kullanıcı “ücretsiz başlangıç ve ücretli bağlantıları hazırla” dedi; anahtar istemek veya ücretli abonelik satın almak bu aşamanın ön koşulu değil.
- Hesap varsayılanı `review`; fiyat olmadığı için sanal emir yok.
- Sağlayıcı veya APNs anahtarı hiçbir nota/loga eklenmedi.

## Son kontrollerin kapsamı ve açık sorun

Ara sürümde `bun run check` geçti: **12 script + 39 sunucu + 31 Swift testi ve imzasız simülatör derlemesi**. Kayıt: `build/paper-quality-check.log`.

Bu geçişten SONRA ek değişiklikler yapıldı:

1. `PaperModels.swift` Swift paketinin altına taşındı; `PaperModelTests.swift` içinde 3 test eklendi. Yeni Swift testleri henüz çalıştırılmadı. Taşınan modeller fiziksel iOS derlemesinde derlendi.
2. Sunucuya 2 ek analiz testi, daha sıkı muhasebe doğrulaması, başlık öznesi/olumsuzlama kontrolleri eklendi. Güncel sunucu test çalıştırması **başarılı değil**: `bun test Tests/Server` ilk test dosyasının adını yazıp, hata ayrıntısı olmadan çıkış kodu 1 veriyor. Sandbox dışında da aynı. Sebebi henüz araştırılmadı. `bun -e` ile domain yükleme/ilk state doğrulaması çalıştı; ayrı minimal Bun testi geçti. `build/server-tests.log` bu SON başarısız denemeyi içerir. Önceki 39 başarılı testin kaydı `build/paper-quality-check.log` içinde.
3. `PaperStore.swift` içine APNs açıkken aynı inceleme için yerel bildirimi tekrarlamama koşulu eklendi. Bu küçük değişiklik fiziksel test derlemesi başladıktan sonra yazıldı; telefondaki test edilmiş binary bu son koşulu içermiyor. Son kaynak ağacı için yeni build yapılmalı.
4. LaunchAgent başlangıcı görüldü; reboot/uyku dönüşü ve uzun süre çalışma henüz test edilmedi.

Güncel ağacın tamamı geçti veya beş hedef uçtan uca çalışıyor denmemeli. Fiziksel 9 test geçti; yukarıdaki kapsam sınırları geçerli.

## Kullanıcı devam istediğinde sıradaki işler

1. Ayrıntı vermeden duran güncel Bun testlerini teşhis et; tüm sunucu testlerini, yeni Swift testlerini ve `bun run check` komutunu son kaynaklarla geçir. Emrin likidite, para/adet rezervi, kısmi komisyon ve muhasebe korunumu testlerini zayıflatma.
2. Telefonu sunucuyla eşleştir (`bun run server:pair`, Ayarlar'daki 6 haneli kod). Debug'da `--pair-code` açılış argümanı da destekleniyor; kodu kalıcı log veya belgeye yazma. Yerel ağ izni gerekebilir. HTTPS/pinleme, 40 gerçek haber, boş fiyat durumları, çevrimdışı dönüş ve gerçek API snapshot'ının Swift modellerine decode edilmesini cihazda kontrol et.
3. Son kaynakları cihazda yeniden derle/kur; yeni bağlantı ve inceleme akışlarını doğrula. Mevcut 9 testin kanıtını koru.
4. Bildirim durumunu iyileştir: APNs anahtarı olmasını başarılı teslim gibi gösterme; gönderim hatalarını sağlık ekranına aktar. APNs canlı teslimi için Apple anahtarı/cihaz izni gerekiyor, mevcut koşullarda doğrulanmış sayma.
5. `README.md`, `VALIDATION.md`, `docs/AUTOMATION_PLAN.md` mevcut eski durumları anlatıyor; güncel gerçek kapsamla düzenle. `docs/SERVER.md` ve ücretli veri rehberi henüz yazılmadı. Hizmet ayarları, güvenli eşleşme, masraf/seans/likidite varsayımları, ücretsiz/ücretli seçenekler ve dış bağımlılıkları belgele.
6. Planın daha geniş hedeflerinden bölünme/temettü, tek hisse işlem durdurma akışı, takas, karşılaştırma endeksi ve LLM analizi henüz yok. Mevcut çalışma başlık/özet kurallarıyla değerlendirme yapıyor; bu sınırları açık tut. Lisanslı BIST köprüsü, sağlayıcı dokümanı doğrulanmış doğrudan Matriks entegrasyonu değildir.
7. Son diff/format/kod incelemesini tamamla; tüm yeni dosyalar şu anda commit edilmemiş. Bu durdurma sırasında commit/push yapılmadı.

## Ücretli veri araştırmasının korunacak bulguları

2 Ekim 2026'daki resmî kaynak kontrolü (satın alma yapılmadı):

- [Alpaca planları](https://docs.alpaca.markets/us/v1.1/docs/about-market-data-api): Basic ücretsiz IEX; Algo Trader Plus 99 USD/ay SIP. IEX tüm ABD borsalarının birleşik kapsamı değil. Haber yetkisi ayrıca doğrulanacak.
- [Alpaca snapshot API](https://docs.alpaca.markets/us/reference/stocksnapshots-1), [haber API](https://docs.alpaca.markets/us/reference/news-3), [clock API](https://docs.alpaca.markets/us/reference/legacyclock).
- [Alpaca kotasyon miktarı değişikliği](https://docs.alpaca.markets/us/v1.1/changelog/marketdata-bid-and-ask-size-display-change): 3 Kasım 2025 sonrası miktarlar hisse adedi; 100 ile çarpılmıyor.
- [Twelve Data Grow fiyat duyurusu](https://twelvedata.com/news/march-2026-updates): 79 USD/ay; [XIST kapsamı](https://twelvedata.com/exchanges/XIST) gün sonu, gün içi otomatik işlem için yeterli değil.
- [Matriks API açıklaması](https://www.matriksdata.com/website/egitim/sikca-sorulan-sorular/veri-ve-icerik-saglayici-servisler-sss): bireysel API mümkün, kapsam/lisans için teklif gerekiyor; kesin fiyat veya çalışan hesap yok.
- [BIST veri kullanım koşulları](https://www.borsaistanbul.com/sss/veri-dagitim-ve-endeks-lisanslama), [KAP REST erişimi](https://www.kap.org.tr/tr/api/about/content-file/8a019492945fbe080194b26d8bed4873).
- Ücretsiz resmî haberler: [Fed RSS](https://www.federalreserve.gov/feeds/feeds.htm), [TCMB RSS](https://www.tcmb.gov.tr/wps/wcm/connect/TR/TCMB%2BTR/Bottom%2BMenu/Diger/RSS).

Fiyat ve paketler yeniden devam edilirken değişmiş olabilir; satın alma öncesi güncel resmî kapsam kontrol edilmeli.
