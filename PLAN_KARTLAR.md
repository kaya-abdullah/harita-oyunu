# Geliştirme Planı — v1.5.0: v1.4.0 geri alındı, sadece kartlar kaldı

Kaynak: kullanıcının Remote Control üzerinden ilettiği istek. Mustafa v1.4.0’ı
(`d089b43`: şehir bölgeleri, sürükle-saldır, 3D birlikler, 2 oyuncu, 10 bot, yan dükkân)
beğenmedi.

## İstekler ve yapılanlar
1. "Son değişiklikleri geri al (v1.3.0 haline dön), sadece kartlar kalsın."
   → v1.4.0 tamamen geri alındı: minik kareli harita, fotoğraflı atom bombası girişi,
   en fazla 6 bot, alttan açılan Silah Dükkanı, dokunarak saldırı yine v1.3.0’daki gibi.
   **Kart sayılanlar** (v1.4.0’dan taşındı, minik kareli haritaya uyarlandı):
   - Elde sayılı kart yapısı: her kartın elinde kaç tane olduğu yazar, oynayınca biri
     gider. Eski "tur X’te açılır, turda bir kez kullanılır" kuralı ve "paketler" kalktı.
   - Kart Çek: her tur bir bedava rastgele kart.
   - Yeni kartlar: Atom Bombası (haritanın her yerine, 25 kare), Nükleer Bomba (her
     yere, 40 kare), Haraç Kes (karenin sahibinden 200 Elmas alır).
   - Silah Dükkanı paket yerine kart satıyor (aldığın kart eline eklenir). Dükkânın
     açılış turları korundu: Ateş Bombası ve Haraç Kes baştan, Bombardıman 10,
     Asker Büyüsü 12, Atom 20, Nükleer 30, Mega Bomba 45. turda.
   - Herkes 2 Ateş Bombasıyla başlıyor. Botlar da kart çekiyor, kartları (Atom, Nükleer,
     Haraç Kes dahil) kullanıyor; turda en fazla 1 (Orta) / 2 (Zor) kart alıyor.
   Kart sayılmayanlar (geri alındı): şehir haritası, sürükleyerek saldırı, tank ve
   uçaklar, 3D birlikler, 2 kişilik mod, 10 bot, yanda hep açık dükkân, çizimli giriş.
2. "Kartların durduğu blok açılıp kapanabilir olsun."
   → Kart paneli katlanır: başlıkta ok, "Kartların (toplam)" ve Kart Çek düğmesi;
   başlığa dokununca kartlar gizlenir / görünür (harita alanı büyür).
3. "Haritada yakınlaştırma/uzaklaştırma ve kaydırma bozulmuş."
   → Testle doğrulandı: v1.3.0’da tek parmakla kaydırma haritayı hiç oynatmıyordu (Flame,
   tek parmak hareketini ölçek olayına ancak ayrı bir sürükleme dinleyicisi varsa
   çeviriyor). v1.4.0’daki düzeltme de bırakma anında sıçrayan deltalar yüzünden
   kaydırmayı bozuyordu. Yeni `MapGestureLayer` ham dokunmaları kullanıyor: tek parmak
   kaydırır, iki parmak parmakların arasındaki noktaya göre yakınlaştırır, fare tekerleği
   de yakınlaştırır; dokunarak seçme / saldırma aynen çalışır.

## Denge
- Bedava çekilen 60 karelik Nükleer Bomba, oyuncunun başlangıçtaki 20 karesini ilk turda
  siliyordu → Atom 25, Nükleer 40 kare; ikisi de Kart Çek’ten ancak 10. turdan sonra çıkar.

## Test
- `flutter analyze` temiz, `flutter test` 104 test geçiyor.
- Yeni: kart kuralları (sayılı el, her kart, hedefler, Kart Çek, ilk turlarda büyük bomba
  çıkmaması, dükkân), botların Atom ve Haraç Kes oynaması, gerçek parmak hareketleriyle
  kaydırma / iki parmak yakınlaştırma / tekerlek / dokunarak seçme, uçtan uca oyun
  (kart paneli, Kart Çek, panelin katlanması, Ateş Bombası, dükkân, botların turu, Devam Et).
