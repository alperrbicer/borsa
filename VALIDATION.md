# Doğrulama · 2 Ekim 2026

Bu kayıt, kişisel kullanım için yapılan 0.2.1 (3) tasarım ve sağlamlaştırma çalışmasını kapsar. Önceki aşamadan kalan cihaz ekran testleri tamamlandı. Canlı piyasa verisi, haber analizi ve otomatik sanal işlem henüz uygulanmadı; mevcut uygulama sabit örnek veriler kullanır.

| Kontrol | Sonuç |
| --- | --- |
| `bun run check` | Güncel 0.2.1 kaynaklarıyla tamamlandı; çıkış kodu 0 |
| Dağıtım scriptleri | 12 test geçti, 0 hata |
| Swift hesap/kayıt/arama motoru | 31 test geçti, 0 hata |
| İmzasız iOS Simulator derlemesi | Geçti; `check` kapsamında |
| İmzalı fiziksel cihaz derlemesi | Debug 0.2.1 (3), Xcode 27.0 / iOS 27.0 ile geçti |
| iPhone 16 Pro UI testleri | 7 test geçti, 0 hata, 0 atlanan test; `TEST SUCCEEDED` |
| Fiziksel testte çalışma zamanı uyarıları | xcresult özeti: `runtimeWarnings: []` |
| Kurulu sürümün kontrolü | Cihaz sorgusu: 0.2.1 / build 3 |
| Normal hesapla açılış | Test parametreleri olmadan `devicectl` launch başarılı; piyasa ekranı görüntülendi |
| Normal hesabın korunması | Test öncesi ve sonrası v2 hesap dosyası bayt düzeyinde aynı |
| Arşiv, export, upload, TestFlight | Gerçek dağıtım çalıştırılmadı; kişisel sürümün kapsamı dışında |
| Gerçek fiyat / haber / otomatik sanal işlem | Henüz bağlı değil; sonraki geliştirme planının konusu |

## Bu aşamada tamamlanan düzeltmeler

- Ana sekme seçimi açık bir durum ve sabit etiketlerle yönetiliyor.
- Emir iptali yerel bir onay uyarısı kullanıyor; iptal edilecek emir onay boyunca korunuyor.
- Sayısal klavyedeki yerleşim uyarısına yol açan araç çubuğu kaldırıldı; klavyeyi kapatma düğmesi üst çubukta gösteriliyor.
- Büyük erişilebilirlik yazısında taşan maksimum adet düğmesinin görünür metni “Tümü”, erişilebilirlik etiketi “Maksimum adet” oldu.
- UI testleri görünürlük, sekme seçimi, ekran geçişi ve kaydırma için bekliyor. İşlem doğrulama kontrolleri korunuyor; son fiziksel test çalıştırması tekrar deneme gerektirmeden geçti.

## Fiziksel cihaz kanıtı

- Cihaz: iPhone 16 Pro, iOS 27.0; bundle ID: `dev.prototype.borsa`.
- Derleme, test kurulumu ve test kaydı: `build/quality-ui-physical.log`.
- Sonuç paketi: `build/PhysicalQualityUITests.xcresult`.
- Makine tarafından okunabilir sonuç: `build/quality-ui-physical-summary.json`.
- Test ekran görüntüleri: `build/ui-physical-attachments/`; eşleştirmeler `manifest.json` içinde.
- Kurulu uygulama sorgusu: `build/quality-device-app-v021.json`.
- Normal açılış: `build/quality-device-launch-v021.json`.
- Test hesabından çıkıldıktan sonraki ekran: `outputs/Borsa-iPhone16Pro-0.2.1.png`; görüntü incelendi ve Borsa'nın normal piyasa ekranı doğrulandı.
- Hesap karşılaştırması: `build/quality-account-preservation.json`. Önceki ve sonraki kopyalar yerel `build/device-migration/` dizininde; hesap içeriği rapora alınmadı.

`bun run mobile:ios:install` aynı bundle ID ile yeniden derleyip yükseltme yapar. Telefonun bağlı, kilidinin açık ve Geliştirici Modu'nun etkin olması; sertifika ve profilin geçerli olması gerekir. Son sürüm fiziksel test çalıştırmasıyla cihaza kuruldu ve sürümü ayrıca sorgulandı. `check` cihaz kurulumu veya UI testi yapmaz.

## Otomatik test kapsamı

12 script testi; cihaz seçimindeki belirsizlikleri, başarısız derleme sonrasında kurulumun durmasını, imza/profil kimliğini, profil süresini ve cihaz kapsamını, build numarası rezervasyonunu ve dry-run davranışını kapsar.

31 Swift testi; alış/satış bakiyelerini, tam sayı kuruş hesaplarını, kısmi satış maliyetini ve gerçekleşen kâr/zararı, nakit/hisse blokajını, iptali, tekrarlanan isteğin tek işlem oluşturmasını, 300 karışık işlemde değer korunmasını, Türkçe arama/sıralamayı, v1 kayıt geçişini, yedek geri yüklemeyi ve bozuk/taşan kayıtların reddini kapsar. Disk yazımı başarısız olduğunda hesap ve tercihler yayımlanmaz; bozuk dosya sessizce sıfırlanmaz.

Tam kontrol kaydı: `build/quality-check-v021.log`.

Fiziksel iPhone'daki 7 UI senaryosu:

1. Alış emrini gözden geçirme, onaylama ve yeniden açılışta hesap/emir kaydını koruma.
2. Bozuk test kaydında açık kurtarma işlemi gerektirme.
3. Bakiyeleri gizleme tercihinin kalıcılığı ve yedek dışa aktarma ekranının açılması.
4. Büyük erişilebilirlik yazısında hisse ve emir ekranlarında gezinme.
5. Bekleyen emrin filtrelenmesi, onaylı iptali ve nakit blokajının çözülmesi.
6. Türkçe arama, takip listesi ve tema tercihinin kalıcılığı.
7. Satış miktarı doğrulaması, gözden geçirmeden düzenlemeye dönünce satış yönünün korunması ve satışın hesapta görünmesi.

UI testleri ayrı `BorsaUITestAccount` dizini ve UserDefaults alanıyla çalışır. Normal hesabın değişmediği ayrıca cihazdan dosya karşılaştırmasıyla doğrulandı. Test yardımcıları yalnızca Debug derlemesinde etkindir.

## Kanıtın sınırları

Önceki simülatör çalıştırmaları tümüyle başarılı değildir. iOS 27 simülatörü uygulama testlerine geçmeden sistemin anahtar zinciri geçişinde takıldı. iOS 26.5 çalıştırmalarında geçiş/dokunma zamanlaması başarısızlıkları görüldü; loglar ve sonuç paketleri saklandı. Sonuçların tümünün geçtiği uçtan uca çalışma, yukarıdaki fiziksel iPhone 16 Pro çalıştırmasıdır.

Yedek dışa aktarma UI testi dosya seçiciyi açar; Dosyalar'a kaydetme ve geri yüklemenin tam cihaz turunu yapmaz. JSON dışa/içe aktarma doğrulaması çekirdek testlerinde bulunur. v1 geçişi birim testinde doğrulandı; cihazdaki mevcut dosya zaten v2 olduğundan bu çalıştırma gerçek bir v1 cihaz geçişi kanıtı değildir.

Geçen testler hatasızlık garantisi değildir. Canlı veri kesintileri, haber analizi, arka planda otomasyon ve gerçek fiyatla sanal gerçekleşme bu sürümde bulunmadığından test edilmiş sayılmaz. Derlemede AppIntents kullanılmadığını belirten metadata extraction uyarısı vardır; test sonucunda çalışma zamanı uyarısı raporlanmamıştır.
