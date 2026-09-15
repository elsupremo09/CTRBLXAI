# CTRBLXAI — Future Visual Design Notes

Created: 2026-09-14

## Implemented (Slice 7)
- ParticleEmitters: damage impact, heal, status burst, KO puff, DOT tick (VFXController.lua)
- Post-processing: Bloom + ColorCorrection + SunRays (VFXController.Init)
- Atmosphere: 11 biome presets (VFXController.Init)
- Highlights: active/target/KO/guard/channel on unit tokens (VFXController)
- Beam: ranged attack flash between caster-target (VFXController.RangedBeam)
- Trail: melee slash projectile with trail (VFXController.MeleeSlash)
- BVC wiring: 10 event handlers connected

## Future — UIShadow + Per-Corner UICorner (Native June 2026)
- Drop shadows on panels/tooltips/buttons without image assets
- Per-corner rounding for tab-shaped panels
- Apply to: BattleHUD panels, dropdown overlays, tooltip hovers
- UIShadow child of GuiObject: Offset, Radius, Color, Transparency
- UICorner now has TopLeft, TopRight, BottomLeft, BottomRight

## Future — MaterialVariant (Custom PBR)
- Replace SurfaceGui tile textures with PBR materials (lighting-reactive)
- PRO: No SurfaceGui overhead (currently 5x600=3000)
- CON: Can't change at runtime, needs PBR texture maps per terrain
- Only pursue if SurfaceGui becomes performance bottleneck

## Future — Emissive Masks (Feb 2026)
- Partial mesh glow via texture control
- Irrelevant until actual unit models exist (currently placeholder tokens)
- When ready: Magic Circle runes, weapon enchantment glow, channeling pulse

## Future — PointLight / SpotLight
- Active unit: warm PointLight glow on surrounding tiles
- Magic Circle: upward SpotLight column
- Hazard tiles: colored PointLight (Molten=orange, Tainted=purple)
- Limit ~10 active lights for performance

## Future — Persistent Tile Hazard Particles
- Molten: slow embers, Rate=3-5
- Tainted Ground: dark wisps, Rate=2-3
- Deep Water: bubbles, Rate=2-4
- Ice: frost sparkles, Rate=1-2
- Magic Circle: arcane sparkles, Rate=3-5
- Create in VFXController.ApplyTerrainEffects(mapFolder)

## Future — DepthOfField
- Action zoom: shallow DoF during combat resolution
- Loadout/Victory: blur 3D background behind UI
- Optional (Settings toggle) — mobile performance concern
- Tween FocusDistance for rack-focus between units

## Future — Element-Based VFX Colors
- Server needs to send element field in UnitActed/HealingApplied events
- VFXController already has ELEMENT_COLOR map — just needs the data
- Fire=orange, Ice=blue, Electric=yellow, Holy=white, Dark=purple, Poison=green

## Future — Biome-Specific Lighting
- Extend VFXController.Init to set ClockTime, Ambient, OutdoorAmbient per biome
- Plains: bright afternoon | Forest: green-tinted | Swamp: dim murky
- Volcano: red-orange | Cave: very dark + PointLights | Tundra: cool bright
- Corrupted: purple-tinted
