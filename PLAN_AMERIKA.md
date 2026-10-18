# Geliştirme Planı — v1.7.0: Ortada Amerika, etrafı bot, 3D harita

Kaynak: `istekler/WhatsApp Audio 2026-10-18 at 19.02.12.mp4` (Mustafa'nın sesli
mesajı).

## Ses kaydı (yazıya dökülmüş)
> Botları şöyle yap, bot seçme olmasın. Bir de şu kareye benzemeyen üstündeki
> beyaz çizgileri kaldır, onun yerine ortaya Amerika ekle, Amerika biz olalım.
> Bir sürü bot şehir olsun, bot şehirler çok yakın olsun birbirine. Bir de
> bizim ülkemizde, Amerikamızda dört şehir olsun, dört Amerika şehri olsun.
> Bir de oyunu 3D yap.

Babasıyla netleştirilenler: Afrika haritası kalır, Amerika ortada olur; 3D =
eğik harita + 3D şehirler; botlar sabit, zorluk Orta.

## İstekler ve yapılanlar
1. "Bot seçme olmasın." → Yeni Oyun'da bot sayısı / zorluk seçme ekranı
   kalktı. Her oyunda 6 bot, Orta zorlukta.
2. "Kareye benzemeyen beyaz çizgileri kaldır." → Bir ülkenin şehirleri
   arasındaki ince beyaz çizgiler kalktı (kalın ülke sınırları duruyor).
3. "Ortaya Amerika ekle, Amerika biz olalım; 4 Amerika şehri." → Afrika'nın
   ortasındaki ülke (Çad'ın yeri) artık Amerika: Vaşington (altın madeni),
   New York, Şikago, Los Angeles. Oyuncu Amerika ile başlıyor; ortasında bir
   Amerikan bayrağı var.
4. "Bir sürü bot şehir, birbirine çok yakın." → 6 bot Amerika'nın hemen
   etrafındaki ülkelerde başlıyor: Libya, Sudan, Orta Afrika, Kamerun,
   Nijerya, Nijer. Hepsi Amerika'ya ve birbirine değiyor.
5. "Oyunu 3D yap." → Harita arkaya doğru eğik (perspektif, ufukta gökyüzü).
   Askerlerin olan topraklar kabartma gibi yükseliyor (altında koyu bir
   yamaç). Şehirler küçük 3D binalar (pencereli, çatılı); altın madenli
   başkentler kuleli ve taçlı.

## Denge
Amerika 6 botun ortasında olduğu için her şehrinde 150 asker ile başlıyor
(botlar 60). Simülasyon: hiçbir şey yapmayan (sadece yedek koyan) oyuncu bile
8 denemenin hepsinde en az 5 tur dayanıyor (`america_balance_test.dart`).

## Teknik not
3D eğimde Flame dokunmaları yanlış yere düşürüyordu (Flutter'ın
`RenderBox.globalToLocal` perspektifte hatalı). Dokunmalar artık
`MapGestureLayer` üzerinden doğru koordinatla haritaya gidiyor.

## Test
- `flutter analyze` temiz, bütün testler geçiyor.
- Yeni / güncellenen: Amerika ve 4 şehri, botların Amerika'ya değmesi,
  150 asker, denge simülasyonu, eğik haritada dokunma/kaydırma/yakınlaştırma,
  görüntü karşılaştırma (3D), uçtan uca oyun (seçim ekranı yok → 6 bot).

---

# v1.8.0: Çizgisiz Afrika, yuvarlak ve ayrıntılı Amerika, bina grupları

Kaynak: `istekler/WhatsApp Image 2026-10-18 at 19.47.18.jpeg` (Mustafa'nın
elle yazdığı not ve çizimleri).

## Not (okunduğu gibi)
> Afrika'daki şu çizgileri sil, böyle olacak. Sonra ortasına Amerika ekle,
> detaylı olsun. Amerika ortada olsun ve Amerika'da 4 şehir olsun, içinde,
> 3D'de. Binalar böyle değil, böyle yani (bir bina grubu) → şehir. Ve
> haritanın her yerinde böyle bot şehirler olsun.

Babasıyla netleştirildi: boş (kimsenin olmayan) şehirler kalıyor.

## Yapılanlar
1. "Çizgileri sil." → Afrika'da hiç ülke ya da şehir çizgisi kalmadı. Seçili
   şehrin komşuları artık beyaz çizgiyle değil, hafif bir parlamayla
   gösteriliyor. Sadece orduların renkli sınır duvarları duruyor.
2. "Ortasına Amerika, detaylı, 4 şehir, 3D." → Amerika artık Afrika'nın
   ortasında yuvarlak bir ülke (Çad'ın güneyinden ve komşularından
   kesildi; Çad kuzeyde 3 şehirle kaldı: Faya, Fada, Bardai). İçinde kare
   düzeninde 4 şehir var: Vaşington, New York, Şikago, Los Angeles. Amerika
   diğer topraklardan daha yüksek duruyor (taş yamaç). Üstünde yeşil çimen,
   göl, şehirleri birbirine bağlayan yollar, ağaçlar ve kuleli bir taş sur
   var. Bayrak ortada duruyor.
3. "Binalar böyle değil, böyle." → Her şehir artık 5 binalık bir grup:
   en yüksek bina ortada. Altın madenli başkentlerin ortasında taçlı bir
   kule var, Amerika'nın şehirleri gökdelen.
4. "Her yerde bot şehirler." → 6 bot Amerika'nın hemen yanında başlıyor:
   Kamerun, Orta Afrika, Çad, Sudan, Nijerya (hepsi Amerika'ya değiyor) ve
   Nijer (bir şehir ötede).

Harita artık 185 şehir. Eski kayıtlar açılmıyor, yeni oyun başlıyor.

## Test
- `flutter analyze` temiz, 108 testin hepsi geçiyor (denge simülasyonu
  dahil: hiçbir şey yapmayan bir Amerika bile 6 bota karşı 5 tur dayanıyor).
- Yeni / güncellenen: yuvarlak Amerika, Çad'ın 3 şehri, botların başlangıcı,
  görüntü karşılaştırma (3D, çizgisiz).

---

# v1.8.1: Çok yakınlaştırınca ekranın maviye dönmesi düzeltildi

Şikâyet (babası): "Haritayı çok yakınlaştırınca ekran tamamen maviye
dönüyor."

Sebep: Yakınlaşınca oyunun çizimi ekranın çok dışına taşıyordu. 3D eğimde bu
taşan parçalar perspektifte "gözün arkasına" düşüyor ve telefonun GPU'su
bütün resmi atıyordu; geriye sadece mavi gökyüzü kalıyordu.

Düzeltme: Oyun önce ekran boyutunda düz bir resim olarak çiziliyor (taşan
kısım kırpılıyor), sonra sadece bu resim eğiliyor. Dokunma, kaydırma ve
yakınlaştırmalar ekran noktasından haritadaki noktaya tam olarak
çevriliyor (`TiltedMap.toCanvas`).

## Test
- Yeni: en yakın zoom dahil (1×, 4×, 8×), haritanın ortasında ve
  köşelerinde ekranın gökyüzü değil harita gösterdiği kontrol ediliyor. Bu
  test düzeltmeden önce 8× zoomda "sadece gökyüzü" diye kırılıyordu.
- Yeni: ekran ↔ harita noktası dönüşümü birebir geri dönüyor.
- Parmakla kaydırma, iki parmakla yakınlaştırma, dokunarak seçme ve uçtan uca
  oyun testleri yeni hesapla geçiyor. Toplam 110 test geçiyor.
