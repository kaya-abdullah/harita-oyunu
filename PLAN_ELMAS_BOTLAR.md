# Geliştirme Planı — Normal Afrika, Atom Bombası Girişi, Elmas, 6 Bot

Kaynak: `WhatsApp Audio 2026-10-06 at 20.29.27.mp4` (sesli istek, Whisper ile yazıya döküldü).

## İstekler (ses kaydından) ve yorumları
1. "Afrika kare kare olmasın, yuvarlak yuvarlak da olmasın, normal çiz."
   → Afrika gerçek kıyı çizgisi ve gerçek ülke sınırlarıyla (Natural Earth verisi) çiziliyor.
   Topraklar hâlâ kare, ama kıyıya göre kırpılıyor; harita basamaklı görünmüyor.
2. "Beyaz ekranda atom bombası çarpsın, dumanlar gidince Yeni Oyun ve Nasıl Oynanır yazsın;
   Devam Et de olsun." → Her açılışta beyaz ekranda bomba düşüyor, ateş topu, şok dalgası ve
   mantar bulutu oluşuyor, duman ekranı kaplıyor. Duman dağılınca ana menü (Yeni Oyun,
   Devam Et, Nasıl Oynanır?) görünüyor. Dokununca animasyon atlanıyor.
3. "Nasıl oynanıyor şeylerinin emojilerini kaldır", "bebekli yapma hiç."
   → Nasıl Oynanır ekranlarındaki ve oyundaki tüm emojiler kaldırıldı; yerlerine sade
   Material ikonları kondu. Metinlerdeki çocuksu ünlemler azaltıldı.
4. "Ateş bombası kartlarını yeşil yap." → Her kartın kendi rengi var. Ateş Bombası yeşil
   (hem oyundaki kart hem dükkândaki paket), Bombardıman turuncu, Asker Büyüsü mavi,
   Mega Bomba kırmızı.
5. "Çok kötü ses efektleri var, saldırı kalsın, iyisini bul."
   → `attack.mp3` aynen kaldı. Diğer efektler `tool/generate_sfx.py` ile yeniden sentezlendi
   (kart: uğultu + patlama, tur sonu: savaş davulu + boru, dokunma: tok tık,
   zafer: boru fanfarı + timpani). Yeni sesler: `nuke.mp3` (giriş bombası), `diamond.mp3`
   (maden). Ses seviyeleri saldırı sesine eşitlendi.
6. "Afrika haritasında bir toprak çok küçük olsun, çok olsun."
   → 1,5°'lik ızgarada **1163 minik kare** (önceki harita 227 kareydi). Sayılar ancak
   yakınlaştırınca görünüyor; en fazla 8 kat yakınlaştırılabiliyor.
7. "Oyuna altı kişi ekleyebildiğimiz botlar olsun." (Whisper "notlar" yazdı; "botlar" olarak
   yorumlandı.) → Yeni Oyun'da **1–6 bot** seçiliyor. Sen Kazablanka'da başlıyorsun;
   botlar sırayla Cape Town, Kahire, Lagos, Mogadişu, Kinşasa ve Dakar'da başlıyor.
   Her ordunun bir rengi var (Mavi, Kırmızı, Mor, Turuncu, Turkuaz, Pembe, Kahverengi).
8. "Bazı yerlere elmas madenleri ekle, ele geçirince 250 elmas alalım, her turda 80 elmas
   gelsin. Elma olmasın, elmas olsun, fiyatlar aynı kalsın."
   → Para birimi Elma'dan **Elmas**'a çevrildi, dükkân fiyatları değişmedi. Her ordu tur
   sonunda 80 Elmas kazanıyor; üslerden ayrıca para gelmiyor. Haritada 22 elmas madeni
   var (çoğu gerçek yatak: Jwaneng, Kimberley, Mbuji-Mayi, Kono…). Saldırıyla ya da kartla
   ele geçirilen her maden +250 Elmas getiriyor.
9. "Direkt kartını kaldır, direkt kartı kötü, öyle bir kart olmasın."
   → Direkt Lazer kartı, şarj sistemi ve Lazer Paketi tamamen kaldırıldı.
10. "Ateş bombası minicik topraktan iki tanesini alsın; kartların toprak sayısını yükselt."
   → Ateş Bombası **2**, Bombardıman **8**, Mega Bomba **25** kare alıyor
   (önceden 1 / 3 / 9).

## Tasarım kararları
- Harita verisi: `tool/extract_africa_geo.py`, Natural Earth 1:50m verisini
  (world-atlas TopoJSON) sadeleştirip `tool/data/africa_geo.json` olarak kaydeder. Ortak
  sınırlar tek seferde sadeleştirildiği için komşu ülkeler birbirine tam oturur.
  `tool/generate_africa_map.py` bu veriyi ızgaraya döker; her kare, en çok alanını kaplayan
  ülkeye ait olur. JSON'a ülke dış hatları dünya koordinatlarında yazılır (`outlines`),
  başlangıç kareleri `startIds` listesinde tutulur, madenler `diamondMine: true` ile işaretlenir.
- Çizim sırası: kıyı bandı → ülke dolguları → ordu renkli kareler (kıyıya kırpılmış) → silik
  ızgara → ülke sınırları. Ardından üs ve maden işaretleri, sayılar ve seçim çerçeveleri gelir.
- `GameState` artık `armies` listesi tutuyor (sıra = tur sırası). `ArmyId` army1…army7
  değerlerini alıyor. `army1` sensin, diğerleri bot.
- Tur sırası canlı ordular arasında dönüyor, elenen ordu atlanıyor. Sıra tekrar sana
  gelince tur sayısı artıyor.
- Zafer: ayakta kalan son ordu kazanır. Sen elenirsen oyun biter ve en çok karesi olan bot
  kazanır; ekranda "Kaybettin" yazar.
- Bot: aktif orduyu oynar, diğer her ordu (sen ya da başka bot) ona düşmandır. Madenlere ek
  puan verir. 2'den fazla bot oynarken animasyon hızlanır; 6 botluk bir tur kısa sürer.
- Kayıt şeması 3 oldu (tüm ordular tek listede). Eski kayıtlar reddedilip siliniyor.
- Asker bonusu büyük haritaya göre ayarlandı: her 12 kare için +1 asker. Başlangıçta her
  orduya 20 kare veriliyor.

## Test
- `flutter analyze`: temiz. `flutter test`: **119 test geçiyor**.
- Yeni testler:
  - `test/e2e/app_flow_test.dart`: uygulamanın tamamı uçtan uca. Bomba girişi → menü →
    öğretici → 3 bot + Zor → haritada saldırı → Ateş Bombası (2 kare) → dükkân → tur sonu,
    3 botun oynaması → ana menü → Devam Et.
  - `test/presentation/intro_test.dart`: animasyonun akışı ve atlanması.
  - Harita: 1000'den fazla kare, gerçek dış hatlar, 7 başlangıç, maden dağılımı, 1–6 botla
    başlangıç.
  - Kurallar: maden ödülü (saldırı ve kart), 80 Elmas gelir, tur sırası ve elenen botu atlama,
    zafer ve yenilgi, 6 botla bir tam tur.
  - Kartlar: 2 / 8 / 25 kare, Direkt kartının olmaması, yeşil Ateş Bombası kartı.
- Denge simülasyonu (oyuncu yerine Orta seviye bot oynatıldı):
  - Çok Kolay: oyuncu her bot sayısında kazanıyor.
  - Orta (1 bot): 80 turda sonuç çıkmıyor.
  - Zor: oyuncuyu 1 botla 13., 3 botla 12. turda yeniyor.
  - Bot hamlesi başına hesaplama yaklaşık 10 ms.
- Harita görüntüleri: `test/presentation/goldens/africa_map*.png`.

## Derleme
`cd android && JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 ./gradlew assembleRelease --no-daemon`
