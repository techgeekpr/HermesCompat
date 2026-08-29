# HermesCompat

A tiny **API-shim addon** for playing on a **1.12 (vanilla) server through a Hermes-style proxy with a modern 1.14 Classic Era client**.

Modern addons and WeakAuras assume game APIs that exist on the 1.14 client's *era* but aren't actually wired up when you're bridged to a 1.12 server — so they throw Lua errors (`attempt to call ... a nil value`, `C_Container`/`C_Spell` missing, vehicle API nil, etc.). HermesCompat fills in the missing pieces so those addons stop erroring, **without touching the addons themselves**.

It only ever **adds what's missing** — it never overrides anything the client already provides.

## What it fixes

| Missing API | What HermesCompat does |
|---|---|
| **`C_Container`** namespace (GetContainerItemInfo, GetContainerNumSlots, …) | Auto-maps each `C_Container.X` to its classic global `X`, with table-return wrappers for `GetContainerItemInfo` / `GetContainerItemQuestInfo` (bag addons like AdiBags, Bagnon). |
| **`C_Spell.IsSpellInRange`** | Maps to the classic global `IsSpellInRange`, converting numeric spell IDs to names via `GetSpellInfo` and returning a boolean (WeakAuras range checks). |
| **Vehicle API** (`UnitHasVehicleUI`, `UnitInVehicle`, `CanExitVehicle`, …) | Stubbed to "no vehicle" — correct for a 1.12 server. |
| **`UIPanelScrollFrame_OnLoad`** | FrameXML helper some scroll templates reference in XML `OnLoad` (e.g. NovaWorldBuffs). |
| **`region:SetStatusBarTextureLSM(name)`** on WeakAuras aurabar regions | Added to every aurabar region, resolving the LibSharedMedia texture and applying it. |
| **Battleground scoreboard faction** shown wrong (Horde/Alliance mixed up) | Wraps `GetBattlefieldScore` and re-derives each row's faction from its race. **Partial workaround** — see the note below. |

…plus a few smaller shims. See [`HermesCompat.lua`](HermesCompat.lua) — every fix is commented with *why* it exists.

### Note on the Battleground scoreboard fix (partial)

This one can't be fully fixed from the client, and here's the honest reason (confirmed by the Jim'sProxy devs):

Vanilla PvP-log rows carry **no** race/class/faction — the proxy fills them from a player-name cache. On a **cache miss** it *fabricates* the row as **Human / Warrior / Horde**, so any player the client hasn't name-resolved yet shows as a Human Warrior on the Horde side. Rows "heal" as the cache fills over the course of a match.

Because this addon re-derives faction from **race**:

- **Cached rows** → no-op (the proxy already derived faction from race correctly). ✅
- **Uncached rows** → the race is the fabricated *Human*, so the wrap flips them to **Alliance** — correct for uncached Alliance players, still wrong for uncached Horde ones, until the row heals.

So it **shifts** which uncached rows are wrong rather than fully fixing them — a client addon can't tell a fabricated Human-Warrior from a real one. The proper fix is proxy-side (name-query the unknown GUIDs on a cache miss instead of fabricating an identity). Once that ships, this wrap becomes a harmless no-op.

## Install

1. Download this repo as a folder named **`HermesCompat`**.
2. Drop it into your `Interface\AddOns\` directory.
3. Restart WoW (tick **"Load out of date AddOns"** if needed).

That's it — it runs automatically at load. It's safe to leave enabled on a normal client too (it no-ops when the APIs already exist).

## When you'd want this

You're on something like **Kronos / a 1.12 server** using a **1.14 Classic Era client via a translation proxy (Hermes / Jim's Proxy / etc.)**, and modern addons or WeakAuras packs are throwing "nil value" API errors. HermesCompat is the compatibility layer that quiets them.

## Contributing

Hitting a *different* missing-API error? Paste the Lua error (the `attempt to call/index ... a nil value` line and which addon), and the shim is usually a few lines: guard with `if not X then …`, map to the classic equivalent, and add a comment explaining why. PRs welcome.

## License

MIT — do whatever you like with it.
