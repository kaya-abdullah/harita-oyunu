# Geliştirme Planı — Afrika Haritası, Bot Zorluğu, Minik Kare Saldırılar

Kaynak: `WhatsApp Audio 2026-10-04 at 18.21.00.mp4` (sesli istek, Whisper ile yazıya döküldü).

## İstekler (ses kaydından)
1. "Harita çok kötü olmuş. Haritayı **Afrika** yapmanı istiyorum."
2. "Bota **Çok kolay, Orta, Zor** ekleyebilelim." Oyunu açıp zorluğu seçince
   Afrika haritasının **bir ucunda ben, diğer ucunda bot** olsun.
   Zor bot "güzel oynasın, heybetli" olsun.
3. "Saldırıları hiç beğenmedim." Toprak **minik kareler** olsun:
   - **Ateş Bombası** → 1 minik kare alsın
   - **Bombardıman** → 3 minik kare alsın
   - Üstünde **silah işareti olan, anında** kart (🔫 Direkt Lazer) → 5 minik kare alsın
   - **Asker Büyüsü** → asker getirsin (aynen kalır)

## Tasarım kararları
- Harita, Afrika silüetinin (kıyı poligonu, boylam/enlem) bir kare ızgaraya
  rasterize edilmesiyle üretilir: `tool/generate_africa_map.py` →
  `assets/maps/territory_graph.json` + `lib/infrastructure/map/territory_graph_data.dart`.
  Her kare bir toprak; komşuluk 4-yönlü; Madagaskar bir deniz köprüsüyle bağlı.
  Kareler ülke bölgelerine (Mısır, Nijerya, Kongo…) atanır; gerçek şehirler üs olur
  (Kahire, Lagos, Kinşasa, Nairobi, Johannesburg büyük üs; diğerleri küçük üs).
- Oyuncu kuzey-batı ucunda (Fas), bot güney ucunda (Güney Afrika) başlar.
- `kTerritoryCount` = üretilen kare sayısı. Zafer: tüm kareler ya da rakibin elenmesi.
- Yetenekler artık **kare ele geçirir**: hedef kare kendi toprağına komşu, sana ait
  olmayan bir kare olmalı; hedeften başlayarak en yakın N yabancı kare (BFS) senin
  olur (her birinde 1 asker). Mega Bomba (ses kaydında yok) → 9 kare.
- Asker geliri büyük haritaya göre ölçeklenir: 3 + (sahip olunan kare / 5).
- Zorluk (`AiDifficulty`: veryEasy / medium / hard) GameState + kayıt dosyasında saklanır.
  - Çok Kolay: turda en fazla 3 hamle, yetenek/mağaza yok, dağınık asker yerleşimi.
  - Orta: mevcut açgözlü bot (sınırlı hamle, ara sıra yetenek).
  - Zor: her hamleyi güncel duruma göre seçer, düşman üslerine yüklenir, kuvvet
    toplar, yetenekleri her tur en iyi hedefe kullanır, paket satın alır ve tur
    başına +3 asker bonusu alır.
- Flame haritası: kare karolar, ülke sınırı çizgileri, üs işaretleri, deniz arka planı,
  iki parmakla yakınlaştırma / kaydırma.
- Yeni Oyun → zorluk seçim penceresi (🐣 Çok Kolay / 🙂 Orta / 😈 Zor).

## Adımlar
1. [x] Afrika ızgara haritası üreteci + JSON/Dart veri
2. [x] Sabitler, `AiDifficulty`, GameState/SaveData alanı, başlangıç durumu
3. [x] Yetenek servisi: kare ele geçirme
4. [x] Ekonomi: ölçekli asker geliri + Zor bonusu
5. [x] Bot: adım adım planlama, zorluğa göre davranış, hızlı yürütme
6. [x] Flame: kare harita çizimi, sınırlar, zoom/pan
7. [x] Arayüz: zorluk seçimi, HUD, metinler (TR/EN), eğitim metinleri
8. [x] Testler: harita, yetenekler, zorluk, kayıt, uçtan uca oyun akışı
9. [x] `flutter analyze` + `flutter test` temiz, uygulama derlemesi

## Sonuç
- Harita: 20×21 ızgarada **227 minik kare**, 32 ülke bölgesi, 17 şehir üssü, Madagaskar deniz köprüsü.
- Bot hamle sınırı/tur: Çok Kolay 3, Orta 12, Zor 35 (insan temposuna yakın tutuldu).
- Denge simülasyonu (oyuncu da bot stratejisiyle oynatılarak, 6 tohum):
  - Çok Kolay bot, orta seviye oyuna her seferinde yenildi.
  - Orta bot, iyi oyuna ~10. turda yenildi.
  - Zor bot vasat oyunu ~10. turda yendi; iyi oyuna ~37. turda yenildi (yenilebilir ama zor).
- Testler: 107 test geçiyor (`flutter test`), `flutter analyze` temiz.
  Harita görüntüleri: `test/presentation/goldens/africa_map*.png`.
- Derleme: `flutter build apk` sistemdeki JDK 25 ile Gradle 8.12'de başarısız oluyor;
  `cd android && JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 ./gradlew assembleRelease --no-daemon`
  ile release APK başarıyla derlendi.
- Harita yeniden üretmek için: `python3 tool/generate_africa_map.py`
  (sonra `kTerritoryCount` değerini çıktıdaki kare sayısıyla eşleştir).
