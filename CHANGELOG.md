# ForeverFriends [Squad Hub] — Changelog

## v1.0.0

### Highlights
- **Initial Release for World of Warcraft: Forever (`Interface: 16001`)**
- **Shared Squad Inventory, Bank, Alts & Gold Tracker:**
  - Live synchronization of bags, bank, equipment, and gold across your own characters (twinks) and your friend group.
  - Faction-separated gold breakdown (`[H]` Horde vs. `[A]` Alliance) and instant item tooltips showing who owns or can craft any item.
  - Shared **Wishlist** (`[*]` right-click any item) and automatic **Quick-Trade Bar** when opening the trade window with a friend.
- **Professions, Recipes & Material Availability Browser (`Mats-Check`):**
  - Automatically scans learned recipes and required reagents when opening a profession window.
  - Filter by profession (`Alchemie`, `Schmiedekunst`, `Kochen`, etc.) and by **Material Availability**:
    - Craftable right now by your **active character** (`Du`)
    - Craftable using materials across your **own characters / twinks** (`Twinks`)
    - Craftable using combined materials across the **entire Squad Database** (`DB/Squad`)
  - Detailed hover tooltip breaking down every required reagent (`Have / Needed`) and which character holds it.
- **Live Quest & Leveling Sync:**
  - Compare active quests and objective progress across your squad in real time.
  - Filter by current zone and see which same-faction friends are still missing a quest.
- **World Map Squad Radar & Instant (<1s) Death / SOS Alerts:**
  - Class-colored friend pins on the World Map (works both solo and in a party).
  - Compact, movable **Squad Radar HUD** with live HP/Mana bars, current zone, and rolling **5/hour Instance Lockout Tracker**.
  - Direct Fast-Path `ALERT` transmission (`<1s` latency) for Death/Gank notifications and 1-click SOS emergency waypoints.
- **Global Faction & Character Filter Bar:**
  - Filter all views simultaneously by Faction (`Alle`, `[H] Horde`, `[A] Allianz`, `Eigene`) and by individual character (`Alle`, `Aktiver Charakter`, `Eigene Twinks`, `Nur Freunde`, or any single character).
- **100% Secret Addon-Only Sync Engine (Taint-Free Client 16001):**
  - Uses invisible addon communication (`PARTY`, `RAID`, `GUILD`, and online-verified `WHISPER`) with `LibSerialize` + `LibDeflate` compression. Never occupies numbered `/1..10` chat channels.
  - Full support for **WoW: Forever** two-word character names (`Vorname Nachname`).
