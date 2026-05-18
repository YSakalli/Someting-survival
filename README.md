# 🧛 Vampire Survival

> Godot 4 ile yapılmış 2D top-down survival oyunu.

---

## 🎮 Oyun Hakkında

Ortada durursun. Her yönden düşmanlar gelir. Hayatta kal.

Düşmanları öldürdükçe XP kazanırsın, level atlarsın ve her level'da sana özel bir güç seçersin. Zaman geçtikçe düşmanlar güçlenir — ne kadar uzun hayatta kalabilirsin?

---

## ✨ Özellikler

- **Otomatik Saldırı** — En yakın düşmana otomatik ateş eder
- **4 Farklı Mermi Tipi** — Normal, Air, Water, Wood
- **Level & Skill Sistemi** — Her level'da 3 kart arasından seçim
- **Wave Sistemi** — Her 30 saniyede düşmanlar güçlenir
- **3 Farklı Düşman** — Bat, RareBat, RareRareBat
- **Kamera Efektleri** — Hasar alınca ekran sallanır
- **XP Bar & HUD** — Canlı level, timer ve XP göstergesi

---

## 🔫 Mermi Tipleri

| Mermi | Özellik |
|-------|---------|
| **Normal** | Düz gider, tek düşmana çarpar |
| **Air** | Düşmanı takip eder, 2 kez çarpar ve seker |
| **Water** | Düşmanın üstüne düşer, dondutur |
| **Wood** | Düşmanı geri iter, sekebilir |

---

## 🃏 Skill Sistemi

Level atladığında 3 rastgele kart gelir:

- 🏃 **Hareket Hızı** — Speed +30
- ⚡ **Saldırı Hızı** — Fire rate artar
- ⚔️ **Saldırı Gücü** — Damage +10
- ❤️ **Can Artışı** — Max HP +50
- 🎯 **Çift Saldırı** — İki hedefe birden ateş
- 💨 **Air** — Takip eden mermi açılır
- 💧 **Water** — Dondurma saldırısı açılır
- 🪵 **Wood** — İtici mermi açılır

---

## 🛠️ Teknik Yapı

```
Godot 4.x — GDScript
```

### Sahne Yapısı

```
Main (Node2D)
├── Player (CharacterBody2D)
│   ├── AnimationPlayer
│   ├── Camera2D
│   └── DamageFlash
├── GameManager (Node)
├── EnemySpawner (Node2D)
├── SkillMenu (CanvasLayer)
└── HUD (CanvasLayer)
```

### Dosya Yapısı

```
res://
├── Player/
│   ├── Player.tscn
│   └── Player.gd
├── Enemy/
│   ├── Bat/
│   ├── RareBat/
│   └── RareRareBat/
├── Bullets/
│   ├── Bulletfire.tscn
│   ├── Air.tscn
│   ├── Water.tscn
│   └── Wood.tscn
├── GameManager.gd
├── EnemySpawner.gd
├── SkillMenu.gd
└── HUD.gd
```

---

## 🚀 Nasıl Oynanır

| Tuş | Eylem |
|-----|-------|
| `WASD` / `Ok Tuşları` | Hareket |
| `Scroll` | Zoom in/out |
| Otomatik | Ateş etme |

---

## 📦 Kurulum

```bash
git clone https://github.com/kullaniciadi/vampire-survival
```

1. Godot 4'ü aç
2. Projeyi import et
3. `Main.tscn`'yi ana sahne olarak ayarla
4. Çalıştır

---

## 🗺️ Yol Haritası

- [ ] Boss düşmanlar
- [ ] Daha fazla mermi tipi
- [ ] Ses efektleri
- [ ] Ana menü ekranı
- [ ] Highscore sistemi
- [ ] Mobil destek

---

## 👤 Geliştirici

Godot 4 öğrenirken yapılan bir proje.

---

*Hayatta kal. Level atla. Güçlen.*
