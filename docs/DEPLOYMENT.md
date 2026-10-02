# Borsa: iPhone kurulumu ve dağıtım komutları

CarMirror'daki `package.json` komut düzeni Borsa'nın SwiftUI/Xcode projesine uyarlandı. Borsa tek uygulama hedefidir. Komutlar mevcut `Borsa.xcodeproj` ve `Borsa` scheme'ini kullanır; proje üretmez.

## Başlangıç

macOS, Xcode ve Node.js 22.12+ gerekir. Üçüncü taraf Node paketi yoktur; `bun install` veya `npm install` gerekmez. Kurulum komutları Bun, npm ya da doğrudan Node ile çağrılabilir. Sunucu, `check` ve HTTPS entegrasyon testleri ayrıca PATH üzerinde Bun gerektirir; bu çalışma Bun 1.3.14 ile doğrulandı.

```sh
cd /Users/alperbicer/Documents/projects/private/borsa
bun run mobile:doctor
# Bun PATH içinde yoksa:
npm run mobile:doctor
# Başka bir dizinden de çalışır:
node /Users/alperbicer/Documents/projects/private/borsa/scripts/ios.mjs doctor
```

`Config/Base.xcconfig` varsayılan bundle ID'yi `dev.prototype.borsa` olarak korur. Takımını `Config/Local.xcconfig` içinde `DEVELOPMENT_TEAM = TAKIM_KIMLIGI` ile ayarla. Gerekirse aynı dosyada `BORSA_BUNDLE_ID` değerini değiştirebilirsin. Yerel ayar dosyası Git'e alınmaz. Bu kurulumda mevcut Apple Developer takımın yerel dosyaya tanımlandı.

`.env.deploy.example` dosyası isteğe bağlı `.env.deploy` için şablondur. `BORSA_TEAM_ID`, komutlarda yerel Xcode takımını geçersiz kılar. Kabuk ortamı `.env.deploy` değerlerinden önceliklidir. Ortam dosyası kabuk kodu olarak çalıştırılmaz. API anahtarı yalnızca App Store Connect yüklemesi içindir; cihaz kurulumu için gerekli değildir.

## Komutlar

| Komut | İşlem |
| --- | --- |
| `bun run check` | Dağıtım scriptleri, sunucu, Swift ve yerel HTTPS testleri; imzasız simülatör derlemesi |
| `bun run test:server` | Sanal hesap, veri, haber, API ve bildirim sunucusu testleri |
| `bun run test:scripts` | Yalnızca dağıtım script testleri |
| `bun run mobile:doctor` | Xcode, takım, yerel imzalama sertifikaları ve provisioning profilleri |
| `bun run mobile:devices` | Eşlenmiş iPhone'lar ve kullanılabilir iPhone simülatörleri |
| `bun run mobile:ios:prepare` | `check` ile aynı; kurulum yapmaz |
| `bun run mobile:ios:install` | İmzalı Debug derlemesi, profil doğrulaması, iPhone'a kurulum ve açılış |
| `bun run mobile:ios:simulator` | Simülatör için derleme, kurulum ve açılış |
| `bun run mobile:ios:archive` | Testler, yerel build numarası ve imzalı Release arşivi |
| `bun run mobile:ios:export` | Son doğrulanmış arşivden App Store IPA üretimi |
| `bun run mobile:ios:upload` | Arşiv, IPA doğrulaması ve App Store Connect yüklemesi |
| `bun run mobile:ios:testflight` | `upload` ile aynı |

Her komut `--help` ve dosya yazmadan/Apple'a bağlanmadan planı gösteren `--dry-run` seçeneğini destekler. Dry run sonucu sertifika, profil, App Store kaydı veya yükleme yetkisi doğrulaması değildir.

## iPhone 16 Pro'ya yükleme

```sh
cd /Users/alperbicer/Documents/projects/private/borsa
bun run mobile:devices
bun run mobile:ios:install --device 00008140-000E60E20EC0801C --allow-provisioning-updates
```

Cihaz adı veya UDID kabul edilir; birden fazla eşleşme varsa işlem durur. iPhone'un eşlenmiş, kilidinin açık ve Geliştirici Modu'nun etkin olması gerekir. `--allow-provisioning-updates`, Xcode'un mevcut Apple hesabıyla gerekli profili oluşturmasına/güncellemesine izin verir. Seçenek verilmezse yerel kaynaklar kullanılır. Script `-allowProvisioningDeviceRegistration` kullanmaz; gerekiyorsa cihaz kaydı Xcode/Apple Developer üzerinden tamamlanmalıdır.

Kurulumdan önce imza, bundle ID, sürüm/build, takım, profil süresi ve cihazın profil kapsamı kontrol edilir. Geçerli wildcard geliştirme profilleri desteklenir. Build veya kurulum başarısızsa açılışa geçilmez. Komut uygulamayı önceden silmez. Açılış komutunun başarısı, görünür ekranın doğru çalıştığını tek başına kanıtlamaz.

Kurulum başarılı olup açılış `Locked` hatasıyla durursa telefonun kilidini aç ve ekranı açık tut. Aynı sürümü tekrar derlemeden başlatmak için:

```sh
xcrun devicectl device process launch --device 00008140-000E60E20EC0801C dev.prototype.borsa
```

Bundle ID'yi değiştirdiysen son parametrede güncel kimliği kullan. `install.json` ve `launch.json` sonuçları ayrı kaydedilir; ilk adım başarılıyken ikinci adım başarısız olabilir.

Simülatör için:

```sh
bun run mobile:ios:simulator --device 'SIMULATOR_UDID'
```

Simülatör ad hoc imzalanır; cihaz provisioning profili gerekmez. Açılış beklemesi sınırlandırılmıştır. `check`, simülatörü başlatmadan derler. UI testlerini çalıştırmak için Xcode → Product → Test kullanılır; `check` UI testlerini içermez.

## Arşiv ve TestFlight

```sh
bun run mobile:ios:archive --version 0.1.0 --allow-provisioning-updates
bun run mobile:ios:export --allow-provisioning-updates
bun run mobile:ios:testflight --dry-run

# Hazır olduğunda gerçek yükleme:
bun run mobile:ios:testflight --allow-provisioning-updates
# Aynı arşivi yeniden kullanma:
bun run mobile:ios:upload --archive '/tam/yol/Borsa.xcarchive' --allow-provisioning-updates
```

Gerçek yükleme için App Store Connect uygulama kaydı ve uygun yetkili API anahtarı gerekir. `.env.deploy` alanları: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_PRIVATE_KEY_PATH`. Yol verilmezse `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` kullanılır. Anahtarlar bu projeye başka projelerden kopyalanmaz; `.p8` dosyaları ve yerel ortam dosyası Git tarafından yok sayılır.

Arşivleme build numarasını kaynak değeri ile `build/deploy/last-build.json` sayacının büyüğünden artırır. Kaynak sürüm/build değiştirilmez. Sayaç Apple'daki build'leri sorgulamaz; başka makineden yükleme yaptıysan `--build` ile uygun numara belirt. Arşiv başarısız olsa da ayrılan numara tüketilebilir.

`export` son başarılı arşivi kullanır. `--archive` başka takım/uygulamaya aitse reddedilir. IPA açılarak dağıtım imzası ve profili tekrar doğrulanır. Upload aynı doğrulanmış arşivi Apple'a gönderir; uygulamayı App Review'a göndermez veya yayımlamaz. Bu görevde yalnızca iPhone Debug kurulum akışı çalıştırılır; arşiv/export/upload seçenekleri dry run ve script testleriyle kontrol edilir.

Her çalıştırmanın DerivedData'sı ve JSON kayıtları `build/deploy/` altında ayrı dizindedir. Bu dizin, Swift derleme önbellekleri ve yerel ayarlar Git'e alınmaz.

Borsa normal kullanımda gerçek kaynakları ve sunucudaki sanal hesabı kullanır; veri yoksa örnek fiyat göstermez. Sunucunun kurulumu, sağlayıcı hesapları ve eşleşme [sunucu rehberinde](SERVER.md) anlatılır. Bu komutlar aracı kuruma gerçek emir göndermez. Güncel cihaz/test sonuçları [VALIDATION.md](../VALIDATION.md) içindedir.

3 Ekim çalışmasında telefon kullanılmadı. Yerel TLS sertifikası düzeltildi; sonraki cihaz kurulumunda `Config/Server.local.xcconfig` içindeki yeni parmak izi derlemeye alınmalı ve uygulama sunucuyla eşleştirilmelidir. Mac'te geçen testler telefonda eşleşme veya APNs teslimi kanıtı değildir.
