# Borsa kişisel iOS uygulaması

BIST ve ABD hisselerini gerçek kaynaklarla izleyen, ayrı TL ve USD bakiyeleriyle sanal işlem yapan SwiftUI uygulaması. Özet, Piyasalar, Portföy ve Asistan ekranlarını; haber değerlendirmelerini ve işlem kurallarını içerir. Gerçek para veya aracı kuruma emir göndermez.

Normal uygulamada örnek fiyat veya sentetik grafik kullanılmaz. Kaynak yoksa fiyat boş kalır; eski, gecikmeli veya seansı doğrulanamayan veriyle emir gerçekleşmez. Önceki deneme hesabı ayrı saklanır.

## Mevcut bağlantılar

TCMB ve Fed duyuruları hesap açmadan alınır. ABD fiyatları ve şirket haberleri için Alpaca erişimi; BIST gün içi fiyatları için yetkili sağlayıcı bağlantısı gerekir. Alpaca IEX/SIP, Twelve Data BIST gün sonu ve lisanslı HTTPS veri köprüsü hazırlanmıştır. Henüz fiyat servisi hesabı veya APNs anahtarı tanımlanmamıştır. Bağlantı kodunun hazır olması bu servislerin hesap bazında doğrulandığı anlamına gelmez.

Kurulum ve işletim: [sunucu rehberi](docs/SERVER.md). Güncel kapsam ve fiyatlar: [veri servisleri](docs/DATA_SERVICES.md). Test sonuçları: [doğrulama kaydı](VALIDATION.md). Devam notu: [çalışma durumu](docs/WORK_STATUS.md).

## Başlatma

Bun ve iOS derlemesi için Xcode gerekir. Üçüncü taraf paket kurulumu gerekmez; sunucu Bun'ın SQLite ve HTTPS desteğini kullanır.

```sh
bun run server:setup
bun run server:start
```

Sunucunun Mac oturumunda kendiliğinden başlaması için `bun run server:service:install` kullanılabilir. Bu servis zaten kuruluysa ikinci bir `server:start` süreci açılmaz. `bun run server:service:status` ve `bun run server:service:restart` mevcut servisi yönetir.

Telefon ve Mac aynı yerel ağdayken `bun run server:pair` ile üretilen kod uygulamanın Ayarlar ekranına girilir. Kod üç dakika ve tek kullanım içindir. API anahtarları yalnızca Git dışında tutulan `.env.server` dosyasına yazılır; uygulamaya veya sohbete eklenmez.

## iPhone kurulumu

```sh
bun run mobile:ios:install
```

Bu komut mevcut bundle ID ile yükseltir; uygulamayı silmez. Telefon erişimi, kilidin açık olması, Geliştirici Modu ve geçerli imza gerekir. Birden fazla eşlenmiş cihazda `--device` seçilir. Gerekirse `--allow-provisioning-updates` eklenir. Ayrıntılar ve CarMirror'dan uyarlanan diğer komutlar [dağıtım rehberinde](docs/DEPLOYMENT.md).

**3 Ekim çalışması cihaza bağlanmadan yapıldı.** Yeni kaynaklar telefona yüklenmedi. Yerel sertifika düzeltildiği için bir sonraki yetkili kurulum yeni sertifika parmak izini de içermelidir; sonrasında telefon eşleştirilir.

## Sanal işlem kuralları

- Başlangıç 100.000 sanal TL ve 10.000 sanal USD; pozisyonlar sıfırdır. İki para birimi kur uydurularak birleştirilmez.
- Fiyatlar 1/10.000 para birimi, hesaplar kuruş/sent cinsinden tam sayıdır. Tam hisse adedi kullanılır.
- Varsayılan komisyon 10 baz puan, olumsuz fiyat kayması 5 baz puandır. 100 baz puan yüzde 1 eder. Komisyon maliyete, kayma gerçekleşme fiyatına yansır.
- Limit emir 15 dakika geçerlidir. Sonraki kotasyonun yönüne, miktarına, limite, seansa ve risk kontrollerine göre kısmen/tamamen gerçekleşir. Aynı kotasyonun likiditesi tekrar kullanılamaz.
- Varsayılan sınırlar: hisse yüzde 10, sektör yüzde 30, günlük kayıp yüzde 2, piyasa başına günde 10 emir; otomasyon için aynı hissede 30 dakika bekleme. Günlük kayıp yeni alışları durdurur; pozisyon azaltmaya izin verir.
- İnceleme modunda insan onayı beklenir. Otomatik modda doğrudan şirket haberi, dar metin kuralları, fiyat tepkisi ve risk kuralları birlikte sağlanır. Makro/çelişkili/belirsiz haberler incelemeye gider. Süresi geçen veya cevapsız inceleme işlem yapmaz.
- Duraklatma otomasyona ait bekleyen emirleri iptal eder. Kullanıcının ayrıca verdiği manuel emirler kendi iptal düğmeleriyle yönetilir.

Başlık/özet kuralları bir LLM veya kapsamlı haber yorumu değildir. Gerçek borsa takası, vergi, bölünme/temettü muhasebesi ve ayrı hisse durdurma akışı henüz modellenmez. Kotasyon güncelliği/seans koruması, bunların yerine geçtiği iddiasıyla sunulmaz. Ayrıntılı varsayımlar [sunucu rehberindedir](docs/SERVER.md).

## Kayıt ve test

Yeni hesabın yetkili kaydı `.borsa-server/account.sqlite` içindedir. SQLite işlemi başarısızsa değişiklik yayımlanmaz. iPhone Keychain'de bağlantı bilgisini, korumalı dosyada son ekran kaydını tutar. Eski yerel hesap yeni performansa eklenmez. Ayarlar'dan yeni sunucu hesabı veya eski deneme hesabı dışa aktarılabilir; dışa aktarılan JSON şifreli değildir. Otomatik bulut yedeği yoktur.

```sh
bun run check         # Script + sunucu + Swift testleri + imzasız iOS derlemesi
bun run test:server   # Açık dosya listesiyle Bun testleri
bun run test:scripts # Kurulum scriptleri
swift test           # Swift modelleri, eski hesap ve yerel HTTPS istemcisi
```

`check` fiziksel cihaza bağlanmaz veya kurulum yapmaz. HTTPS entegrasyon testleri yalnızca `127.0.0.1` üzerinde geçici sertifika ve ayrı SQLite hesabı kullanır. `Tests/Fixtures` fiyatları sadece test içindir; üretim servisine yüklenmez. UI testlerinin eski deneme hesabı da normal hesaptan ayrıdır.
