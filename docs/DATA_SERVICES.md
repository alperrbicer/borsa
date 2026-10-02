# Borsa veri servisleri ve maliyetleri

3 Ekim 2026 tarihli resmî kaynak kontrolü. Ücretsiz başlangıçta TCMB/Fed haberleri çalışıyor; fiyat hesabı henüz yok. API kodu ve sağlayıcı erişimi ayrı aşamalardır. Ücretli abonelik satın alınmadı, sağlayıcıyla kullanıcı adına iletişim kurulmadı.

## Seçenekler

| Servis | Açıklanan aylık fiyat | Kapsam ve projedeki durum |
| --- | --- | --- |
| Alpaca Basic | Ücretsiz | ABD hisseleri/ETF için IEX; fiyat, seans ve ayrı haber bağlantısı hazır. Hesap/anahtar gerekir. Tüm ABD borsalarının birleşik kapsamı değildir. |
| Alpaca Algo Trader Plus | 99 USD | Birleşik ABD fiyat kapsamı için SIP seçeneği hazır. BIST sağlamaz; haber yetkisi ayrıca doğrulanacak. |
| Twelve Data Grow | 29 / 49 / 79 USD | Aynı pakette sırasıyla 55 / 144 / 377 API kredisi/dakika. BIST kapsamı gün sonudur. Gösterim bağlantısı hazır; gün içi sanal gerçekleşme için kullanılmaz. |
| Matriks API | Teklif gerekir | Bireysel erişim ve deneme sunuluyor. Canlı/gecikmeli kapsam, API ve borsa lisansları birlikte fiyatlandırılır. Sağlayıcıya özel bağlantı, hesap ve teknik sözleşme bekliyor. |

Alpaca fiyat ve kapsamı [resmî plan tablosundan](https://docs.alpaca.markets/us/v1.1/docs/about-market-data-api); Twelve Data fiyat katmanları [resmî fiyat metninden](https://twelvedata.com/pricing.md) ve [fiyat sayfasından](https://twelvedata.com/pricing), BIST gecikmesi [XIST sayfasından](https://twelvedata.com/exchanges/XIST) kontrol edildi. Önceki nottaki “Grow 79 USD” üst kredi katmanıdır; başlangıç katmanı 29 USD olarak listeleniyor. Matriks için [resmî API açıklaması](https://www.matriksdata.com/website/egitim/sikca-sorulan-sorular/veri-ve-icerik-saglayici-servisler-sss) esas alındı.

Bunlar veri aboneliği fiyatlarıdır. Vergi, haber eklentisi, borsa kullanım lisansı, kota veya barındırma bedeli dahil varsayılmaz. TL karşılığı için sabit kur kullanılmadı. Paket ve kullanım hakkı satın alma sırasında yeniden teyit edilmeli.

## Bu uygulama için tercih

Ücretsiz başlangıç önerisi ABD'de Alpaca Basic ve mevcut TCMB/Fed akışlarıdır. Gerekçe, IEX kapsamının açık olması ve aynı bağlayıcıdan SIP'e geçilebilmesidir. Ücretli ABD genişlemesi için 99 USD/ay plan adaydır; daha geniş kapsamın strateji sonucunu iyileştireceği varsayılmaz.

BIST'te gün içi haberle işlem için gerçek zamanlı yetkili API gereklidir. Twelve Data Grow bu ihtiyacı karşılamaz; gün sonu izleme içindir. Matriks'ten fiyat/kapsam teklifi ve deneme alınmadan BIST aylık maliyeti yazılamaz. [Borsa İstanbul açıklaması](https://www.borsaistanbul.com/sss/veri-dagitim-ve-endeks-lisanslama) gösterim dışı otomatik kullanımın ayrıca değerlendirilmesini gerektirir. Mevcut köprü, Matriks'e bağlanıldığı veya lisans alındığı iddiası taşımaz.

## Hesap açılınca yapılacak doğrulama

1. Kişisel gösterim, sunucuda otomatik analiz ve veriyi saklama kullanımını sağlayıcıya açıkça belirt. Terminal aboneliğinin API veya haber hakkı verdiğini varsayma.
2. Anahtarları yerel `.env.server` dosyasına gir; Git'e, uygulama kaynaklarına veya sohbete yazma. `bun run server:service:restart` ile uygula.
3. Özet ekranında fiyat ve haber yetkilerini ayrı kontrol et. 401/403/kota hatası, son başarılı zaman ve gerçek kaynak adını incele.
4. Bir seans boyunca olay zamanı, alınma zamanı, kotasyon miktarı, eksik sembol ve API kotasını ölç. Alpaca miktar alanları güncel API'de hisse adedidir; 100 ile çarpılmaz. [Resmî değişiklik kaydı](https://docs.alpaca.markets/us/v1.1/changelog/marketdata-bid-and-ask-size-display-change).
5. Önce inceleme modunda ileriye dönük sanal kayıt biriktir. Paket değişimi, kapanış, kesinti ve yeniden bağlantı davranışını sağlayıcının gerçek hesabıyla doğrula. Test verisiyle geçen muhasebe testleri bu erişim testinin yerine geçmez.

## Haber kapsamı

[TCMB RSS](https://www.tcmb.gov.tr/wps/wcm/connect/TR/TCMB%2BTR/Bottom%2BMenu/Diger/RSS) ve [Fed RSS](https://www.federalreserve.gov/feeds/feeds.htm) resmî makro duyurular sağlar; tüm dünya gündemini veya şirket haberlerini kapsamaz. Alpaca şirket haberlerinin güncelliği ve yetkisi hesapta ayrıca ölçülür. SEC/KAP doğrudan bağlayıcıları bu sürümde yoktur. KAP, hesap açılmadan kullanılabilen sınırsız bir API olarak sunulmaz.

Sunucunun maliyeti Mac açıkken mevcut donanım/elektrik/internet kullanımından oluşur. Bulut barındırma satın alınmadı; LLM çağrısı yapılmadığı için model kullanım ücreti yoktur. APNs anahtarı ve cihaz izni de veri aboneliğinden bağımsız kurulum girdileridir.
