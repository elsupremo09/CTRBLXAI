# Session change log
2026-11-09 ~15:30 | Main-Quick-UAT | STUDIO (read-only playtest) | Full Studio test of Nov 9 batch; 1 Test Arena battle won (+1 battles completed); test loadouts restored from DataStore version 06:17Z and saved; no source/docs/place edits. Report: workspace artifacts/studio_full_2026-11-09.md
2026-11-09 15:36 | Dev-studiobugs | BattleCoordinator, BattleTurnController, AugmentEffectService, CombatResolver, Main.server | B1 battle ends right after the action that wipes a side (player+AI loops, new IsSideWiped); B2 Vortex Strike no longer moves the unit on the centre tile; B3 one 'immune to Poison' line per hit + Barrier on Hit no longer adds caster 'uses X on self/+Shield' lines; B4 inspector Stats tab Max HP/MP = unit max (display only). Backups: _codebackup_studiobugs_20261109. Not Studio-tested.
2026-11-09 ~16:45 | Main-Quick-UAT2 | STUDIO (no file edits) | Final Studio test: B1-B4, S10/S11, Spear, Vortex collision, Blood Price, Mana Leech. 3 Test Arena battles (wins). Temp party p1 created then deleted; loadouts verified identical; claim released.
2026-11-09 18:01 | Dev-lspA | source/ReplicatedStorage/CTRBLXAI/UI/LoadoutScreen.lua, source/ReplicatedStorage/CTRBLXAI/UI/UGCItemWidgets.lua | A1: tapping current portrait now clears it (if-then-else at L5961); A2: removed dead setclipboard path, Copy button goes straight to Select fallback (L427-430)

2026-11-09 18:10 | Designer-portrait | docs/CTRBLXAI.db, docs/CTRBLXAI_Game_Rules.xlsx | Added loadout_ui_spec 119-120 (portrait picker: tap-again removes, stays removed across rejoins, random race face only for never-set units; instant top bar/unit list refresh). NOT BUILT.
2026-11-09 19:20 | Dev-portrait | LoadoutRequestHandlers, SaveService, Main.server, GuildMenuService, LoadoutScreen | Removed portrait stays removed after rejoin (new saved marker pcl / portraitCleared, old saves unchanged) + [Portrait] cleared print; Loadout top bar/unit list reload roster after portrait set/clear
2026-11-09 19:25 | Main-Quick | source/ServerScriptService/Game/_delidx.json | moved leftover Oct scratch file to _codebackup_othersession_bak_20261109 (user OK 7:14 PM)
2026-11-09 20:45 | Dev-lsptidy | LoadoutScreen.lua | UI-1 LoadoutScreen: removed unused augDef; renamed inner disabled/disabledReason to rowDisabled/rowDisabledReason (shadow); dismissBtn -> _dismissBtn (call kept)
2026-11-09 20:46 | Dev-lsptidy | PartiesTab.lua | UI-2 PartiesTab: removed unused fmtDate
2026-11-09 20:46 | Dev-lsptidy | RuneforgeScreen.lua | UI-3 RuneforgeScreen: removed unused findItem; effRep -> _effRep (call kept)
2026-11-09 20:46 | Dev-lsptidy | Theme.lua | UI-4 Theme: removed unused normalY (LinkStyleSheet left as instructed)
2026-11-09 20:46 | Dev-lsptidy | BattleHUD.lua | UI-5 BattleHUD: removed unused makeButton
2026-11-09 20:46 | Dev-lsptidy | GameConstants.lua | UI-7 GameConstants: removed unused terrainId, weaponDefense
2026-11-09 20:46 | Dev-lsptidy | UILayoutCoordinator.lua | UI-6 UILayoutCoordinator: removed unused h
2026-11-09 20:46 | Dev-lsptidy | GuildMenu.client.lua | UI-8 GuildMenu: removed unused selectedParty (decl+2 writes), partyEdit, act()
2026-11-09 20:46 | Dev-lsptidy | BattleVisualClient.client.lua | UI-9 BattleVisualClient: removed unused ELEVATION_STEP, uName, actorName, targetName, summary block; inner mf renamed tileMapFolder (shadow)
2026-11-09 20:47 | Dev-lsptidy | CameraController.lua | UI-10 CameraController: removed unused StarterGui; write-only classification/tapEmitted renamed with _
2026-11-09 20:47 | Dev-lsptidy | UIController.client.lua | UI-11 UIController: removed unused Players/RunService/player/UIConstants require/currentLayout
2026-11-09 20:47 | Dev-lsptidy | UnitInspectorPanel.client.lua | UI-12a UnitInspectorPanel: removed never-read currentTab
2026-11-09 20:47 | Dev-lsptidy | DeploymentUI.client.lua | UI-12b DeploymentUI: removed unused ELEVATION_STEP
2026-11-09 20:47 | Dev-lsptidy | QuestBoardUI.client.lua | UI-12c QuestBoardUI: unused show() renamed _show (kept: delete would orphan populateCard)
2026-11-09 20:47 | Dev-lsptidy | DeploymentUI.client.lua | UI-12b-fix DeploymentUI: whitespace: restored blank line
2026-11-09 20:47 | Dev-lsptidy | ElevationPass.lua | S-1 ElevationPass: removed unused bMin
2026-11-09 20:47 | Dev-lsptidy | TargetingService.lua | S-3 TargetingService: removed unused BASE_MOVEMENT_RANGE, actorElev
2026-11-09 20:47 | Dev-lsptidy | UnitSchema.lua | S-4 UnitSchema: removed unused DEFAULT_RT
2026-11-09 20:47 | Dev-lsptidy | EquipmentService.lua | S-5 EquipmentService: removed empty if-block (Titan 2H check that did nothing)
2026-11-09 20:47 | Dev-lsptidy | ArmorPassiveService.lua | S-7 ArmorPassiveService: hasAllyInRange -> _hasAllyInRange
2026-11-09 20:47 | Dev-lsptidy | AugmentEffectService.lua | S-6 AugmentEffectService: removeAllBuffs -> _removeAllBuffs; removed unused family
2026-11-09 20:48 | Dev-lsptidy | FeaturePass.lua | S-2 FeaturePass: blobSet -> _blobSet (call kept); removed 3 unused dy
2026-11-09 20:48 | Dev-lsptidy | TileEffectService.lua | S-10 TileEffectService: indent-only fix of multi-line warn() (SameLineStatement handled by .luaurc)
2026-11-09 20:48 | Dev-lsptidy | MerchantService.lua | S-11 MerchantService: removed unused Game and ServerScriptService
2026-11-09 20:48 | Dev-lsptidy | EnemyGenerator.lua | S-12 EnemyGenerator: removed unused TraitEffectService/DoctrineData/SkillData requires and egModBaseRt/egLukFactor
2026-11-09 20:48 | Dev-lsptidy | ObjectEffectService.lua | S-13 ObjectEffectService: removed unused InventoryService/ItemGenerator requires
2026-11-09 20:48 | Dev-lsptidy | BattleVisualBroadcaster.lua | S-15 BattleVisualBroadcaster: syncHp calls: dropped the 2 extra args the function ignores (6 calls)
2026-11-09 20:48 | Dev-lsptidy | Main.server.lua | M-1 Main.server: removed inner RaceData re-require (shadow, same cached module) and never-read anyEnemyStanding
2026-11-09 20:49 | Dev-lsptidy | BattleTurnController.lua | BTC-1 BattleTurnController: removed 11 unused requires (lines 17,19-28)
2026-11-09 20:49 | Dev-lsptidy | BattleTurnController.lua | BTC-2 BattleTurnController: removed 14 unused requires (Map..ItemDisplay, Currency..Progression) + stale comment
2026-11-09 20:49 | Dev-lsptidy | BattleTurnController.lua | BTC-3 BattleTurnController: removed 8 unused requires (UGCService/UGCOutfitService/UGCRatingService + 5 data modules); GuildMenuService + UGCRemoteHandler kept as instructed
2026-11-09 20:50 | Dev-lsptidy | .luaurc (project root, not synced) | new config: turns off only the SameLineStatement lint (94 warnings). NOTE check.bat copies only source\ to C:\luaucheck, so it will not see this file until check.bat also copies .luaurc. Report: workspace artifacts/dev_lsptidy_2026-11-09.md
2026-11-09 21:56 | Main-Quick-UAT3 | STUDIO | LSP tidy smoke test: boot 0 errors, Guild/Loadout/UGC remotes OK, portrait clear+restore OK, Test Arena battle (attack, enemy hit, 2 items, AI turns, Instant Win end) 0 errors; Studio back in Edit
2026-11-09 22:22 | Main-Quick-detailsfix | source/ReplicatedStorage/CTRBLXAI/UI/UGCItemWidgets.lua | Details popup crash: Theme.Font.Bold (nil) -> Theme.Font.PrimaryBold (line 392)
2026-11-09 22:29 | Main-Quick-UAT4 | STUDIO | Details popup opened on client with test item, no error (read-only, user's Play session not interrupted)

2026-11-09 22:35 | Designer-portrait2 | docs/CTRBLXAI.db, docs/CTRBLXAI_Game_Rules.xlsx | loadout rule 119 dropped (superseded, remove code dormant); rule 120 marked BUILT pending visual check; new open decision: 4 missing Theme names
2026-11-09 22:35 | Main-Quick-ugcfix | source/ServerScriptService/Game/UGCOutfitService.lua, source/ReplicatedStorage/CTRBLXAI/UI/UGCItemWidgets.lua | Preview model Humanoid name tag hidden; Details popup Copy button removed (user 10:34 PM)
2026-11-09 23:47 | Dev-uipolish | UI/PreviewIdle.lua (new), UI/UGCOutfitTab.lua, UI/UGCInspectorOutfit.lua, UI/LoadoutScreen.lua, UI/Theme.lua | Outfit previews play the battle base idle (local copy, track stopped on close/rebuild); equipped consumable slots + Gears inventory tiles now use Theme.MakeItemTile portrait (Lv/E/NEW/count/slot no. overlays kept); MakeItemTile AutoButtonColor off (rule 243). Backups _codebackup_uipolish_20261109\
2026-11-10 00:24 | Dev-tileunify | UI/MerchantInspector.lua, UI/RuneforgeGemGrid.lua, UI/MerchantScreen.lua, UI/BlacksmithScreen.lua, UI/ApothecaryScreen.lua, UI/CrucibleScreen.lua, UI/TavernScreen.lua, UI/TrainingGroundsScreen.lua, StarterPlayerScripts/BlackMarket.client.lua | All guild item grids now use the Loadout Gears tile (portrait MakeItemTile, Theme.ItemTileCell size from grid height + refit, Loadout spacing, Lv.N label, E/NEW markers); price badge drops to row 2 on narrow tiles; callers pass GridHeightHint. Backups: _codebackup_tileunify_20261110. Studio check pending.

2026-11-10 01:06 | Designer-facing | docs/CTRBLXAI.db, docs/CTRBLXAI_Game_Rules.xlsx | Facing choice rulings 2026-11-10: new project_rules 257; notes added to core_stats 22 (Guard), 25 (Wait), project_rules 92; xlsx 01!B91, 01 row 254, 02!D23, 02!D26. Not built.
2026-11-10 01:12 | Dev-facingtiles | source/StarterPlayer/StarterPlayerScripts/BattleVisualClient.client.lua, source/ServerScriptService/Game/BattleTurnController.lua | Facing choice is now tap-one-of-8-tiles (siege: 4 straight tiles) via processTileClick, green-arrow ring removed, teardown at BattleEnded; Guard prompts facing only when it ends the turn (rule 257). Backups: _codebackup_facingtiles_20261110. Not Studio-tested.

2026-11-10T01:17+08:00 | Designer-257fix | docs/CTRBLXAI.db, docs/CTRBLXAI_Game_Rules.xlsx | Rule 257: siege-aim 4-tile sentence superseded (briefing error), Ballista open note removed, build status added

2026-11-21 18:13 | Dev-ptbugs | UI/BattleHUD.lua, StarterPlayerScripts/BattleVisualClient.client.lua, Game/BattleTurnController.lua, Game/CommandService.lua, sim/bugs.db | Playtest PT-02 (move preview RT from server rtCost), PT-03 (tile panel follows acting unit), PT-04 (unit name fit+truncate, no marquee), PT-08 (prompt applies IsActionBlocked to attack targets + [CommandService] Attack rejected warn). PT-01 not changed (label is phase countdown; design decision). Bugs BUG-076..079. Backups: _sessions\*.bak_ptbugs_20261121. Studio-verified. Not committed.
