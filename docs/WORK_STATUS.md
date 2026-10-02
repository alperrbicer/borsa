# Çalışma durumu · 3 Ekim 2026

Son talimat: **“cihaza bağlanmadan kalan işleri bitir”**. Önceki durdurma notundaki cihaz gerektirmeyen kod, hata giderme, test ve belgeleme işleri tamamlandı. Bu turda telefon sorgusu, bağlantısı, kurulumu veya UI testi yapılmadı. Cihaz işlemlerine yeni kullanıcı yönlendirmesi olmadan geçme.

## Tamamlananlar

- Ayrıntısız duran Bun test çalıştırması düzeltildi. `scripts/test-server.mjs` test dosyalarını açıkça seçiyor; `bun run test:server` ve `bun run check` aynı yolu kullanıyor.
- Ortak HTTPS istemcisi `Sources/BorsaCore/PaperAPI.swift` altına alındı. Mac'te gerçek Bun HTTPS sunucusuyla eşleşme, API/Swift veri uyumu, yanlış sertifika ve yönlendirme reddi test edildi.
- Apple istemcisinin reddettiği yerel sertifika düzeltildi: SAN, `serverAuth`, anahtar kullanımı, RSA/SHA-256. Sertifika/pin doğrulaması devre dışı bırakılmadı. Eski yerel sertifika yedeklendi, yeni parmak izi `Config/Server.local.xcconfig` içine yazıldı.
- APNs yapılandırılması, gönderim kabulü ve hata durumları ayrıldı. Hatalar görünür; başarısız teslimler tekrar denenir, yinelenen teslim yapılmaz, kuyruk 10 incelemeden sonra da ilerler. Bildirim işi yavaşladığında fiyat döngüsü beklemez.
- Bildirim belirli karar ekranını hedefler. Bildirim izni reddedilmişse düğme iOS Ayarlar'a gider. Cihaz kaydı hataları kullanıcıya gösterilir. Bu UI değişikliklerinin fiziksel testi yapılmadı.
- Emir iptalinde kalan miktar için onay var. Portföy tutarları bakiye gizleme tercihini izliyor. Kaynak/paket değişirse bekleyen emir yeni kaynakla sessizce gerçekleşmiyor.
- Lisanslı köprü fiyatla birlikte şirket haberlerini alabiliyor. Türkçe yön/olumsuzlama, hatalı/gelecek tarihli haberler ve yinelenen kısmi işlem muhasebesi için testler eklendi.
- README, dağıtım rehberi, kabul planı ve doğrulama kaydı güncellendi. Yeni `docs/SERVER.md` ve `docs/DATA_SERVICES.md` yazıldı. Ücretli abonelik veya sağlayıcıya mesaj gönderimi yapılmadı.

## Son doğrulama

`bun run check` çıkış kodu **0**: **12 script + 49 sunucu + 38 Swift = 99 test**, ardından imzasız genel iOS Simulator derlemesi geçti. Fiziksel cihaz veya simülatör UI testi içermez. Kayıt `build/check-oct03.log`; ayrıntılar [VALIDATION.md](../VALIDATION.md).

Dört Swift HTTPS testi yalnızca `127.0.0.1` üzerinde geçici sertifika ve ayrı test hesabı kullanır. Üretim hesabına örnek fiyat veya haber yazılmaz. `Tests/Fixtures/https-server.mjs` yalnızca test ortamı işaretiyle açılır.

Canlı Mac sunucusunda doğrulananlar:

- Sertifika denetimi açık HTTPS; sağlık 200, kimliksiz durum 401, kimlikli durum 200.
- Doğrulama anında 42 gerçek haber: 20 TCMB + 22 Fed. Fiyat adedi 0.
- Hesap `review` modunda; 100.000 sanal TL / 10.000 sanal USD, sıfır pozisyon/emir. Servis açılışı ve yeniden başlatmada bakiyeler, pozisyon/emirler, ayarlar ve takip listesi korunuyor.
- Kontrol için oluşturulan geçici erişim silindi. Kanıt `build/live-server-oct03.json`; finansal içerik veya anahtarlar rapora dökülmedi.

## Yerel servis

Önceden mevcut `~/Library/LaunchAgents/dev.prototype.borsa.server.plist` bu oturumda yüklü değildi. Aynı kayıt yeniden yüklendi; ardından normal `server:service:restart` komutu geçti. Durum `running`; geliştirme bitince servis çalışmaya bırakıldı.

```sh
bun run server:service:status
bun run server:service:restart
bun run server:service:uninstall
```

Son komut otomatik başlangıcı kaldırır, hesabı silmez. Kullanıcı oturumunda çalışır; Mac uyurken/kapalıyken sürekli izleme garantisi yoktur. Tam yeniden başlatma/uyku dönüşü testi yapılmadı.

Adres `https://Alper-MacBook-Air.local:8787`. Hesap `.borsa-server/account.sqlite`; sertifika, bağlantı bilgisi ve günlükler `.borsa-server/` içinde. `.env.server` sağlayıcı anahtarları henüz boş olan yerel dosyadır. Bu dosyalar ve `Config/Server.local.xcconfig` Git dışındadır. LAN dışı erişim kurulmadı.

## Cihazın son bilinen durumu

2 Ekim'de iPhone 16 Pro / iOS 27.0 üzerinde **0.3.0 (4)** doğrulandı: 9 UI testi geçti. Yedi test eski deneme hesabını, iki test yeni eşleşmemiş ekranları kapsıyordu. Telefon sunucuyla eşleşmedi. Bu bilgi geçmiş kanıttır; cihaz bu turda tekrar sorgulanmadı.

Kanıtlar `build/physical-paper-tests.log`, `build/PhysicalPaperUITests.xcresult`, `build/physical-paper-summary.json`, `outputs/Borsa-iPhone16Pro-0.3.0.png` içinde. Önceki 0.2.1 normal hesap dosyası korunumu kanıtı ayrıca saklanıyor.

**Yeni kod ve sertifika parmak izi telefona yüklenmedi.** Sonraki cihaz çalışmasına izin verildiğinde güncel sürüm yeniden derlenmeli; yeni pin ile `server:pair` eşleşmesi, bağlı ekranlar, çevrimdışı dönüş, onay/red ve bildirimden karara geçiş sınanmalı. `bun run mobile:ios:install` aynı bundle ID ile yükseltir; telefonu silmez. Yalnızca eski kurulu sürümün çalışması yeni kodun kanıtı değildir.

## Etkinleştirme için açık girdiler

1. **Fiyat hesabı:** Ücretsiz ABD başlangıcı için Alpaca hesabı/anahtarı; BIST gün içi için yetkili API ve lisans gerekir. Twelve Data Grow yalnızca BIST gün sonu gösterimidir. Anahtarlar sohbete veya Git'e değil, yerel `.env.server` dosyasına yazılır.
2. **Sağlayıcı denemesi:** Lisanslı köprü ortak şeması hazır; Matriks'in gerçek dokümanı/hesabı olmadan doğrudan entegrasyonu doğrulanmış sayma. Yetki, gecikme, miktar, kota, gerçek seans ve kesinti dönüşü erişim açılınca ölçülür.
3. **Apple bildirimleri:** APNs anahtarı, konu/ortam ve cihaz izni gerekir. Otomatik testte Apple göndericisi taklit edildi; canlı kapalı uygulama teslimi yapılmadı.
4. **Cihaz kabulü:** Kullanıcı izin verince yapılır; mevcut “cihaza bağlanmadan” sınırını koru.

Bu girdiler olmadan fiyatları, haber kapsamını veya başarılı bildirim teslimini uydurma. Ücretsiz gerçek makro haber akışı çalışıyor; fiyat olmadığında otomatik sanal emir yok.

## Ücretli veri çalışması

3 Ekim resmî kaynakları ve bağlantılar [DATA_SERVICES.md](DATA_SERVICES.md) içinde: Alpaca Basic ücretsiz IEX; SIP planı 99 USD/ay; Twelve Data Grow kredi katmanları 29/49/79 USD/ay; Matriks için kapsam/lisans teklifi gerekiyor. Eski “Grow 79 USD” notu tek başlangıç fiyatı olarak kullanılmamalı. Vergi, haber ve borsa lisansı dahil varsayılmaz; satın alma öncesi güncel paket teyit edilir.

## Kapsam sınırı ve Git

Haber analizi dar Türkçe/İngilizce başlık/özet kurallarıdır; LLM değildir. Bölünme/temettü, vergi/takas, ayrı hisse durdurma olayları, karşılaştırma endeksi, SEC/KAP doğrudan bağlantıları ve tam dünya gündemi sonraki kapsamdır. Bu sürüm uzun vadeli gerçek toplam getiri eşdeğerliği iddia etmez. Yeni sunucu yedeği dışa aktarılabilir; geri yükleme UI'si yoktur. Beş hedefin karşılığı ve sınırları [AUTOMATION_PLAN.md](AUTOMATION_PLAN.md) içinde.

Başlangıç commit'i `c479c9f feat(paper): add server-backed paper trading experience`, dal `main`. Önceki iş kullanıcı tarafından commit edilmişti. Bu turdaki değişiklikler çalışma ağacında; commit/push yapılmadı. API anahtarı, yerel hesap, sertifika veya erişim tokenını Git'e ekleme.
