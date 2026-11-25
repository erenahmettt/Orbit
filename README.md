# Orbit — Kişisel Çalışma Alanı

SwiftUI + SwiftData ile yazılmış, tamamen yerel (local-first) bir macOS üretkenlik uygulaması.
Uygulama boş başlar ve ilk açılışta karşılama ekranı gösterir. Veriler `~/Library/Application Support/Orbit/` altında saklanır; internet gerekmez, her değişiklik otomatik kaydedilir.

## Çalıştırma

```bash
./build.sh install    # derler, /Applications/Orbit.app olarak kurar ve açar
./build.sh            # sadece derler → build.noindex/Orbit.app
```

Geliştirirken: `swift run` ya da `open Package.swift` ile Xcode'da aç. (Bildirimler yalnızca `.app` paketiyle çalışır.)

## Modüller
- **Home**: karşılama + canlı saat, hızlı görev/not, Today's Focus (ilerleme halkası), Schedule (zaman çizelgesi), Upcoming/gecikmiş, aktif projeler, Quick Notes
- **Tasks**: durum (Inbox/To Do/In Progress/Completed), öncelik (Low→Urgent), başlangıç/teslim, tahmini süre, proje, etiket, alt görev, hatırlatıcı, tekrar (her gün/hafta/ay, belirli günler, özel aralık), ilişkili notlar. List / Kanban / Calendar / Priority / Project görünümleri; sürükle-bırak ile tarih/durum/öncelik/proje değiştirme; erteleme (Tomorrow…); animasyonlu tamamlama + geri al
- **Calendar**: Day / Week / Month / Agenda, saatli görevler, etkinlik oluşturma (çift tık), renk, proje, çakışma gösterimi, görev/etkinlikleri sürükleyerek taşıma, Apple Calendar (salt-okunur, Ayarlar'dan)
- **Projects**: renk/ikon/tarih/durum, sekmeler: Overview, Tasks, Notes, Activity (Slack benzeri akış + güncelleme yazma), Resources
- **Notes**: yazı tipi (SF Pro / New York / Rounded / Mono), boyut, satır aralığı ve okunabilir genişlik ayarlı Markdown editör (H1–H3, kalın/italik/altı çizili, listeler, checkbox, kod, alıntı, link, görsel, dosya), Düzenle/Bölünmüş/Önizleme, klasörler, etiketler, favori/sabitleme, `[[Not Başlığı]]` bağlantıları + geri bağlantılar
- **Journal**: her gün otomatik sayfa, hedefler, yapılanlar, tamamlanan görevler, serbest yazı, ruh hali + değerlendirme, yarın için notlar, alışkanlık takibi (seri sayacı)
- **Focus (Pomodoro)**: odak / kısa mola / uzun mola, görev bağlama, süre ayarları, günlük ve haftalık istatistik, menü çubuğunda geri sayım, bitişte bildirim ve ses
- **Masaüstü widget'ları**: "Orbit · Bugün" (küçük/orta/büyük: ilerleme, görevler, program) ve "Orbit · Odak" (canlı pomodoro sayacı). Masaüstüne sağ tık → *Widget'ları Düzenle* → Orbit
- **⌘K Komut paleti**: görev/not/proje/etiket/günlük içeriklerinde tam metin arama + komutlar
- **Menü çubuğu**: hızlı görev/not, bugünün görevleri, uygulamayı aç
- **Bildirimler**: hatırlatıcılar, son teslim, günlük planlama hatırlatması

## Kısayollar
⌘N yeni not · ⇧⌘N yeni görev · ⌘K arama · ⌘1 Home · ⌘2 Today · ⌘3 Calendar · ⌘4 Tasks · ⌘5 Notes · ⌘6 Journal · ⌘7 Projects · ⌘8 Focus · ⇧⌘P pomodoro başlat/duraklat · Esc kapat

Hızlı görev sözdizimi: `Rapor yaz yarın 14:00 !high #software` (`!low/!normal/!high/!urgent`, `#proje` ya da `#etiket`)

## Proje yapısı
- `Sources/Orbit/` — uygulama (SwiftUI + SwiftData)
- `Sources/Orbit/Shared/` — uygulama ile widget'ın ortak kullandığı veri özeti
- `Widget/` — WidgetKit uzantısı (build.sh ile `Orbit.app/Contents/PlugIns` içine derlenir)
- `scripts/make_icon.swift` — uygulama ikonunu üretir
