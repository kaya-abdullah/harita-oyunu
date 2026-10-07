# Geliştirme Planı — Şehirler, Sürükle-Saldır, 3D Birlikler, Yeni Kartlar

Kaynak: `istekler/Ses.m4a.mp4` (6,5 dakikalık sesli istek, Whisper ile yazıya döküldü;
bozuk bölümler filtreyle tekrar döküldü).

## İstekler (ses kaydından) ve yorumları
1. "Atom bombasını eskiye çevir, böyle fotoğraf koyma, eski haline getir."
   → Giriş, fotoğraflı sürümden önceki çizimli atom bombasına döndü (ekran ve sesi).
   Fotoğraf (`nuke_badger.jpg`) silindi.
2. "Kare kare yapma, o kadar küçük de yapma, biraz büyük yap. Etrafında bizim bölgemiz
   olduğunu gösteren bir çizgi olsun, içi dolu olmasın, boş olsun." / "Ülkeleri kaldır."
   → 1163 minik kare ve ülke sınırları kalktı. Afrika, 133 gerçek şehrin çevresindeki
   bölgelere bölündü (her şehrin Voronoi hücresi, kıyıya göre kırpıldı). Orduların
   toprağının içi boş; sadece çevresinde ordunun renginde kalın bir çizgi var.
3. "Benim dört şehrim olsun." / "Şehirlerimizin üstünde ataklar yazsın: 135, 125, 110."
   → Oyuncu Fas’ta 4 komşu şehirle başlıyor (Kazablanka 135, Rabat 125, Fas 120,
   Marakeş 110 asker). Diğer şehirlerdeki asker sayıları rastgele.
   Sonradan gelen değişiklik: şehirlerin üzerine sayı **yazılmıyor**. Sayılar oyunun
   kurallarında duruyor; şehre dokununca panelde görünüyor. Haritada şehir topu
   asker sayısına göre büyüyor.
4. "Benim yakınlarıma 3 tane yapay zeka şehir koy, ama dibimde olmasın; bazı yerlere,
   botların yakınlarına da." / "4 tane daha bot ekle." / "Botlar birbirine dalabilsin."
   → Bot sayısı en fazla 10 (6 + 4). İlk 3 bot oyuncudan 2 adım uzakta başlıyor, hiçbir
   bot başka bir orduya komşu başlamıyor. Kalan botlar haritaya yayılıyor. Her bot
   2 şehirle başlıyor. Botlar herkese, birbirlerine de saldırıyor.
5. "2 kişi de oynanabilsin." (Uzaktan oynama fikrini kayıtta kendisi geri aldı.)
   → Yeni Oyun’da "1 kişi / 2 kişi". İki kişi aynı telefonda sırayla oynuyor; ikinci
   oyuncu Güney Afrika’da (Cape Town) başlıyor, sıra değişince "Telefonu ver" mesajı.
6. "Bazı yerlere 3 orman ekle." → Kisangani, Ouesso, Monrovia ormanlık: ağaçlar
   çiziliyor, buradaki savunma %25 güçlü.
7. "Kartlar kalsın." / "Yan tarafta tam silah dükkanı kalsın; Mega Bomba falan hepsi,
   oyuna girdiğimiz gibi yazsın, satın alabilelim."
   → Silah Dükkanı haritanın yanında hep açık. Bütün kartlar, tank ve bombardıman
   uçağı ilk turdan satılıyor.
8. "Saldırı ya da kart çekme tuşu olsun." → "Saldır" ve "Kart Çek" düğmeleri.
   Kart Çek her tur bir bedava rastgele kart veriyor.
9. "Askerlerini sevk etmek için elinle tut, sürükle, sevk edeceğin yere götür, sonra
   savaşsınlar." → Kendi şehrinden parmakla tut, komşu şehre sürükle: askerler (ve
   tank) yürüyerek gidiyor, sonra savaş oluyor. Dokunarak saldırı da duruyor.
10. "3D tanklar, 3D askerler, 3D bombardıman uçakları. 4 bombardıman uçağı, 5 tank,
    her şehirde 15 asker." → Gölgeli, ışıklı 3D görünümlü asker, tank ve uçak
    çizimleri (yürüyen askerler, uçan uçak, patlama, mantar bulutu). Her ordu 5 tank
    ve 4 bombardıman uçağıyla başlıyor. "Her şehirde 15 asker" haritada, her şehrin
    yanında duran asker figürleri olarak yorumlandı; şehirlerin asker sayıları
    135/125/120/110 olarak kaldı.
11. "Kartlara kendi kafandan yeni şeyler ekle: Atom bombası, Nükleer bomba; rastgele
    kart çekince çıksın; haritadaki kişiye atabilelim." / "Haraç Kes kartı olsun,
    oyuncunun 200 elmasını alsın."
    → Yeni kartlar: Atom Bombası, Nükleer Bomba (haritanın her yerine atılır), Haraç Kes
    (şehrin sahibinden 200 Elmas alır). Kullanmak için karta, sonra şehre dokunuluyor.

## Kurallar
- Saldırı gücü = gönderilen askerler (+25, hazır bir tank varsa). Savunma = şehirdeki
  askerler (ormanda +%25). Asker başına asker: kazanan tarafta farkı kadar asker kalır.
  Başarısız saldırıda tank kaybolur. Her tank turda bir saldırıya katılır.
- Bombardıman uçağı: her uçak turda bir kez uçar, hedef şehirde 15 asker öldürür.
- Bomba kartları şehirlerdeki askeri öldürür, boşalan şehir kartı atanın olur:
  Ateş Bombası 1 şehirde 40, Bombardıman 2 şehirde 40, Mega Bomba 3 şehirde 60,
  Atom Bombası 4 şehirde 80, Nükleer Bomba 6 şehirde 100. Asker Büyüsü +40 asker.
- Tur sonu: 80 Elmas ve her şehre +5 asker (Zor botlar +7, Çok Kolay botlar +3).
  Elmas madeni 250, altın madeni (sarı halkalı 10 büyük başkent) 150 Elmas.
- Dükkân: Ateş 220, Bombardıman 300, Asker Büyüsü 250, Mega 500, Atom 700,
  Nükleer 1000, Haraç Kes 250, Tank 200, Bombardıman Uçağı 350.

## Denge (simülasyonla ayarlandı)
- İlk tasarımda kartlar şehri asker sayısına bakmadan alıyordu: Zor bot 220 Elmaslık
  kartla 135 askerli şehri alıyordu → kartlar asker öldürür hâle getirildi.
- Botlar 150 Elmasa Haraç Kes alıp 200 çekiyordu (para döngüsü) → fiyat 250, botlar
  turda en fazla 1 (Orta) / 2 (Zor) şey alıyor.
- Tank +25’i her saldırıda tekrar kullanılıyordu; tanklı bir yığın bir turda 10 şehir
  geçiyordu → her tank turda bir saldırı.
- Bedava Nükleer Bomba oyuncunun 4 şehrini birden alıyordu → Atom 80, Nükleer 100
  hasar; çekilme ihtimalleri %4 ve %2.
- Sonuç: Hiçbir şey yapmayan oyuncu Orta zorlukta 10 botla bile 5 tur ayakta kalıyor;
  Zor’da 3–5 turda kaybediyor. Çok Kolay’da oyuncu her bot sayısında kazanıyor.

## Test
- `flutter analyze`: temiz. `flutter test`: 68 test geçiyor.
- `test/e2e/app_flow_test.dart`: uygulamanın tamamı. Çizimli bomba girişi → menü →
  öğretici → 3 bot + Zor → yanda dükkân → Kart Çek → Saldır → haritada parmakla
  sürükleyerek saldırı (askerler yürür, şehir alınır) → Ateş Bombası kartı → Uçak →
  tank satın alma → tur sonu, botların oynaması → ana menü → Devam Et → 2 kişilik
  oyun, sıra Oyuncu 2’ye geçer.
- Kurallar, kartlar, uçak, tank, orman, madenler, tur, zafer (1 ve 2 oyuncu), harita
  (133 bölge, gerçek dış hatlar, Madagaskar deniz yolu), başlangıç yerleşimi (4 şehir,
  botlar yakın ama dipte değil, 1–10 bot), kaydet/yükle, botların kart/uçak kullanması
  ve birbirine saldırması, ekran (görüntü karşılaştırma, sürükleme hareketi).
