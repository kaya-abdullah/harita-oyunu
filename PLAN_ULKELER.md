# Geliştirme Planı — v1.6.0: Ülkeler ve her ülkede 4 şehir

Kaynak: `istekler/WhatsApp Image 2026-10-09 at 17.18.03.jpeg` (Mustafa'nın elle
yazdığı not ve çizdiği Afrika haritası).

## Not (okunduğu gibi)
> Yerleri [minik kareler] değil de [ülkeler] böyle, ve içine şehir ekle.
> Her ülkeye 4 şehir ekle. Şehirlerin üstünde asker sayısı yazsın, görsün.
> Her ülkede 50'den aşağı olmayan askerler olsun, 70'i geçmesin bu kadar.
> Bir de boş toprak alamasın. Bir de kendisi ülke olsun. Yakınlarında bot
> şehirler olsun. 1 asker, şehirlerin dediğim asker sayısının arkasında
> gözüksün.

## İstekler ve yapılanlar
1. "Kareler değil, ülkeler; içine şehir ekle; her ülkeye 4 şehir."
   → 1163 minik kare kalktı. Harita Afrika'nın 50 gerçek ülkesi; her ülkede
   4 gerçek şehir var (çok küçük ülkelerde 2–3: Gambiya, Esvatini, Lesotho,
   Cibuti, Ruanda, Burundi, Ekvator Ginesi, Gine-Bissau 2; Togo, Sierra Leone
   3). Toplam 182 şehir. Ülke, şehirleri arasında bölündü (her yer en yakın
   şehrine ait). Ülke sınırları kalın beyaz, şehir sınırları ince çizgi.
2. "Şehirlerin üstünde asker sayısı yazsın." / "1 asker, sayının arkasında
   gözüksün." → Her şehrin üstünde koyu bir etiket: küçük bir asker resmi ve
   yanında asker sayısı. Etiket hep görünür; şehir noktası sahibinin renginde.
3. "Her ülkede 50'den aşağı, 70'ten yukarı olmasın." → Kimsenin olmayan her
   şehirde oyun başında 50–70 arası (rastgele) asker var.
4. "Boş toprak alamasın." → Haritada boş toprak yok; her yer bir şehre ait
   ve şehri ancak askerle saldırıp alabilirsin. Savunan şehir hiç boş kalmaz
   (en az 1 asker). Bombalar da artık toprak almıyor, sadece asker öldürüyor
   (şehir en az 1 askerle kalır); sonra saldırıp alıyorsun.
5. "Kendisi ülke olsun." → Oyuncu Fas'ın 4 şehriyle başlıyor (her birinde 60
   asker, 20 yedek asker).
6. "Yakınlarında bot şehirler olsun." → 1. bot Moritanya'da başlıyor (Batı
   Sahra'nın öbür yanı, 2 adım ötede). Diğer botlar: Tunus, Nijer, Mısır,
   Güney Afrika, Kenya. Başlangıç ülkeleri birbirine değmiyor.

## Kurallar (yeni)
- Savaş askere asker: saldıranlar savunanlardan fazlaysa şehir alınır ve
  farkı kadar asker kalır (80 askerle 60'lık şehre → 20 asker). Değilse
  savunan da farkı kadar askerle kalır (en az 1).
- Tur sonu: 80 Elmas + 15 asker + sahip olunan her şehir için 4 asker
  (Zor bot +4).
- Kartlar: Ateş Bombası 1 şehirde 30, Bombardıman 2 şehirde 40, Mega Bomba
  3 şehirde 60 asker öldürür (toprağının yanında). Atom Bombası 4 şehirde 80,
  Nükleer Bomba 6 şehirde 100 (haritanın her yerinde). Asker Büyüsü +30.
- Altın madeni: 13 büyük başkent (sarı taç). Elmas madeni: gerçek elmas
  bölgelerindeki 14 şehir.
- Oyun Fas'a yakınlaştırılmış açılıyor (sayılar okunur); iki parmakla
  uzaklaştırınca bütün Afrika görünüyor.
- Eski kayıtlar (kareli harita) açılmıyor, yeni oyun başlıyor.

## Test
- `flutter analyze` temiz, `flutter test` 108 test geçiyor.
- Yeni / güncellenen: harita (50 ülke, 182 şehir, her şehir kendi ülkesinin
  içinde, sınır çizgileri, Madagaskar deniz yolu, başlangıç ülkeleri),
  50–70 asker kuralı, askere asker savaş, boş toprak olmaması, bomba kartları,
  botlar, görüntü karşılaştırma (Fas'a yakın açılış), uçtan uca oyun (şehir
  seç → yedek asker koy → komşu şehri al → Ateş Bombası → dükkân → botların
  turu → menü → Devam Et).
