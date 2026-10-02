# Borsa otomasyonu: kapsam ve kabul durumu

3 Ekim 2026. Kapsam, kişisel iOS uygulamasında BIST ve ABD hisselerini gerçek kaynaklarla izlemek ve sanal parayla işlem yapmaktır. Son talimat doğrultusunda bu çalışma fiziksel cihaza bağlanmadan tamamlandı. Gerçek para, aracı kuruma emir gönderme veya App Store yayını kapsamda değildir.

## Beş hedefin mevcut karşılığı

| Hedef | Uygulanan davranış | Doğrulama ve dış girdi |
| --- | --- | --- |
| Gerçek fiyat ve haber | Her kayıtta kaynak, olay/yayın saati, alınma saati ve gecikme. Boş/eski veri açık gösterilir; örnek fiyat veya grafik üretilmez. | TCMB/Fed gerçek erişimi çalışıyor. Alpaca, Twelve Data ve lisanslı HTTPS köprü bağlayıcıları test edildi; fiyat hesabı/anahtarı henüz yok. |
| Sanal hesap | Ayrı TL/USD, tam sayı para hesabı, komisyon, olumsuz kayma, limit, nakit/adet rezervi, sonraki kotasyonda kısmi gerçekleşme, seans ve süre denetimi. SQLite kalıcı kayıt. | Tekrarlı/eşzamanlı istekler, kesinti, kısmi gerçekleşme, nakit/maliyet korunumu ve servis açılışı test edildi. Gerçek sağlayıcı kotasyonuyla ileriye dönük deneme hesap erişiminden sonra yapılır. |
| Haber değerlendirmesi | Kaynak bağlantısı ve karar anındaki metin saklanır; şirket, sektör, portföy etkisi ve belirsizlik gösterilir. Türkçe ve İngilizce dar başlık/özet kuralları kullanılır. | Olumsuzlama, söylenti, eski/gelecek zaman, farklı şirket öznesi ve doğrudan Türkçe haber testleri var. Kapsamlı LLM analizi veya tüm dünya gündemi kapsamı yok. |
| Otomatik işlemler | Açık şirket sinyali + fiyat yönü + güncel/yetkili kaynak + risk kuralları ile emir; diğer durumlarda inceleme. Cevapsız/süresi geçmiş karar işlem yapmaz. | Risk, tekilleştirme, 30 saniyelik önizleme, geç onay, duraklatma ve bildirim kuyruğu test edildi. Gerçek APNs için Apple anahtarı ve cihaz izni gerekiyor. |
| Takip ekranları | Özet, Piyasalar, Portföy, Asistan; veri/otomasyon sağlığı, son karar, incelemeler, kaynaklı fiyatlar ve masraf sonrası sonuç. | Swift modelleri/HTTPS ve iOS derlemesi geçti. Son değişiklikler telefona yüklenmedi; bağlı telefon akışları henüz doğrulanmadı. |

Kodun ve otomatik testlerin tamamlanması, fiyat hesabı veya APNs erişiminin açıldığı anlamına gelmez. Anlık çalışan durum ve kanıtlar [WORK_STATUS.md](WORK_STATUS.md) ve [VALIDATION.md](../VALIDATION.md) içindedir.

## Kurulan yapı

SwiftUI iPhone istemcisi ve Mac üzerinde Bun/JavaScript servisi kullanılır. İlk plandaki PostgreSQL yerine tek kullanıcılı yerel kurulum için SQLite WAL seçildi. Hesabın yetkili kaydı sunucudadır; telefon korumalı yerel dosyadan son durumu ve tarihini gösterebilir. Erişim tokenı Keychain'de, sunucudaki karşılığı hash olarak tutulur. API anahtarları uygulamaya eklenmez. HTTPS bağlantısında sertifika parmak izi, alan adı ve geçerlilik doğrulanır.

Haber/fiyat toplama, kararlar ve emir gerçekleşmeleri telefonun açık olmasına bağlı değildir. Mac kapalı/uykudayken veya ağı kesildiğinde sürekli çalışma garanti edilmez. LaunchAgent kullanıcı oturumunda başlar. 24 saat erişim için sürekli açık bir makine gerekir; bulut sunucusu satın alınmadı. [Kurulum ve işletim](SERVER.md).

Varsayılan mod `review` ve başlangıç bakiyeleri 100.000 sanal TL / 10.000 sanal USD'dir. `auto` seçilse bile eski/gecikmeli/gün sonu, kapalı seans veya eksik kotasyonla emir gerçekleşmez. Piyasa saati sağlayıcıdan alınır; yerel saate göre seans uydurulmaz. Otomasyon durdurulduğunda ona ait bekleyen emirler iptal edilir. Manuel emirler kullanıcı tarafından ayrı yönetilir.

## Veri akışını etkinleştirme

Ücretsiz başlangıç ABD'de Alpaca IEX, makro haberlerde mevcut TCMB/Fed bağlantılarıdır. SIP'e geçiş aynı Alpaca bağlayıcısında paket seçimiyle yapılır. BIST gün içi için yetkili sağlayıcı erişimi gerekir; Twelve Data'nın gün sonu verisi yalnızca gösterim içindir. Lisanslı köprü fiyatlarla birlikte şirket haberlerini de kabul eder. Doğrudan Matriks API bağlantısı, sağlayıcının gerçek erişim belgesi olmadan doğrulanmış sayılmaz.

Güncel ücretsiz/ücretli fiyatlar, kapsam, haber yetkisi, kullanım hakları ve satın alma öncesi sorular [DATA_SERVICES.md](DATA_SERVICES.md) içinde toplandı. Önceki 79 USD Grow notu düzeltildi; güncel kredi katmanları orada açıklanır. Bir abonelik açılmadı, ödeme veya sağlayıcıya mesaj gönderilmedi.

Hesap erişimi sağlanınca yapılacak kabul adımları:

1. Anahtarları yerel `.env.server` dosyasına tanımlayıp servisi yeniden başlat; kaynak/kapsam/yetki hatalarını kontrol et.
2. Gerçek seans boyunca zaman, fiyat, alış/satış miktarı, kota ve kesinti dönüşünü ölç. Veri paketi değişiminde bekleyen emirlerin kapanmasını doğrula.
3. Önce inceleme modunda, sonra kullanıcı seçimiyle otomatik modda ileriye dönük sanal kayıt biriktir. Sabit test verisinden elde edilen kazancı gerçek performans gibi sunma.
4. Kullanıcı cihaz çalışmasına izin verdiğinde güncel sürümü kur/eşleştir; çevrimdışı dönüşü, inceleme onay/red akışını ve bildirimden ilgili karara geçişi kontrol et. APNs anahtarı yoksa kapalı uygulamaya teslim testi bekler.

## Model sınırları ve ileri aşamalar

Bu sürüm tam adet, peşin nakit ve limit emir modeli kullanır. Komisyon/kayma maliyeti ve likidite sınırı modellenmiştir. Vergi, takas gecikmesi, bölünme/temettü muhasebesi, tek hisse durdurma olayları ve karşılaştırma endeksi henüz yoktur. Bunlar için olay/tarihsel veri kapsamı ve düzeltme akışı gerekir; uzun vadeli gerçek toplam getiri eşdeğerliği iddia edilmez.

LLM ile çok kaynaklı bağlam analizi, SEC/KAP doğrudan bağlantıları, tam dünya gündemi ve tarihsel strateji değerlendirmesi ayrı genişletmelerdir. Mevcut kurallar başlık ve özeti sınırlı kalıplarla değerlendirir; belirsizlik kullanıcı incelemesine düşer. Ücretli model kullanılmadığı için model çağrı maliyeti yoktur.

Eski deneme hesabı arşiv olarak korunur ve yeni hesabın performansına katılmaz. Gerçek kaynak verileri ile sanal gerçekleşme varsayımları ekranda ayrıdır; sanal sonuç gerçek aracı kurumda aynı fiyatı veya sonucu garanti etmez.
