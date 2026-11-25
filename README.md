# Nameplates

The game's own nameplates, made readable for PvP.

For **World of Warcraft 1.12.1** with [ClassicAPI](https://github.com/brues-code/ClassicAPI).

- **Plate size.** One slider sizes every plate: its bar, its level and the area that takes clicks. It can follow the interface scale.
- **Class colours.** A player's plate shows a bar in the class colour. NPC plates keep the game's colours.
- **Health text.** The health value in the bar, on every plate (a percent where the server sends only a percent).
- **Your target.** Its plate has a warm glow, and a rogue's or druid's combo points above the name.
- **Targeting you.** A hostile NPC whose target is you says so under its bar, as soon as it turns to you.
- **Raid marks** at the size and place you choose: left of the bar, above the name or right of the level.
- **Auras on enemies.** The first crowd control from anyone and up to three of your own debuffs, with the time left.
- **Cast bars** under the plates, grey when the cast cannot be interrupted. On your target, a cast that becomes interruptible turns gold.
- **Enemy cooldowns.** The abilities an enemy player was seen using while their plate was up, newest first, with a `~` countdown: the base cooldown, without talents or items.

## Install

[Download Nameplates](https://github.com/Fostercare5988/Nameplates/releases/latest/download/Nameplates.zip) and extract it into `Interface/AddOns/`. The folder should be `Interface/AddOns/Nameplates/`.

## Use

Type **`/fnp`**, or open **Game Menu > AddOn Options > Nameplates**.

ClassicAPI's own page holds what the game does by itself: **Other Nameplate Opacity** (how much the plates other than your target fade) and which kinds of units get a plate at all (totems, pets, guardians).

## What it calls

ClassicAPI: `C_NamePlate.SetNamePlateSize`, `GetNamePlateSize` and `GetNamePlateForUnit`, the `nameplateN` unit tokens and `NAME_PLATE_UNIT_ADDED` / `_REMOVED`, `RegisterUnitEvent`, `C_UnitAuras.UnitAura`, `GetAuraSlots` and `UnitAuraBySlot` with `UNIT_AURA_DELTA`, `C_Spell.UnitCastingInfo`, `UnitChannelInfo` and `GetSpellInfo`, `GetSpellBaseCooldown`, the `UNIT_SPELLCAST_*` events, `StatusBar:SetTimerDuration` with `C_DurationUtil`, the Cooldown frame's countdown and `C_StringUtil` formatter, `AbbreviateNumbers`, `C_Timer.NewTimer` and the Settings window.

Nothing runs per frame: plates change on events only, and the one timer exists only while a cast bar is up.
