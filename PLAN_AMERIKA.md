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
