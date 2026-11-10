# Dev-lsptidy edit log 2026-11-09

time | file | line | change | lines
20:45:41 | source/ReplicatedStorage/CTRBLXAI/UI/LoadoutScreen.lua | L4410 | delete unused augDef (pure lookup) | -1 lines +0 lines
20:45:41 | source/ReplicatedStorage/CTRBLXAI/UI/LoadoutScreen.lua | L4509 | LocalShadow: rename inner disabled/disabledReason | -1 lines +1 lines
20:45:41 | source/ReplicatedStorage/CTRBLXAI/UI/LoadoutScreen.lua | L4514 | shadow rename use | -1 lines +1 lines
20:45:41 | source/ReplicatedStorage/CTRBLXAI/UI/LoadoutScreen.lua | L4517 | shadow rename use | -1 lines +1 lines
20:45:41 | source/ReplicatedStorage/CTRBLXAI/UI/LoadoutScreen.lua | L4524 | shadow rename uses | -2 lines +2 lines
20:45:41 | source/ReplicatedStorage/CTRBLXAI/UI/LoadoutScreen.lua | L4534 | shadow rename use | -1 lines +1 lines
20:45:41 | source/ReplicatedStorage/CTRBLXAI/UI/LoadoutScreen.lua | L4542 | shadow rename use | -1 lines +1 lines
20:45:41 | source/ReplicatedStorage/CTRBLXAI/UI/LoadoutScreen.lua | L4545 | shadow rename use | -2 lines +2 lines
20:45:41 | source/ReplicatedStorage/CTRBLXAI/UI/LoadoutScreen.lua | L6080 | rename only _dismissBtn (call creates X button) | -1 lines +1 lines
20:46:01 | source/ReplicatedStorage/CTRBLXAI/UI/PartiesTab.lua | L107 | delete unused fmtDate (pure) | -7 lines +0 lines
20:46:01 | source/ReplicatedStorage/CTRBLXAI/UI/RuneforgeScreen.lua | L286 | delete unused findItem (pure) | -8 lines +0 lines
20:46:01 | source/ReplicatedStorage/CTRBLXAI/UI/RuneforgeScreen.lua | L799 | rename only effRep -> _effRep (call kept) | -1 lines +1 lines
20:46:01 | source/ReplicatedStorage/CTRBLXAI/UI/Theme.lua | L1241 | delete unused normalY | -1 lines +0 lines
20:46:01 | source/ReplicatedStorage/CTRBLXAI/UI/BattleHUD.lua | L370 | delete unused makeButton | -22 lines +0 lines
20:46:01 | source/ReplicatedStorage/CTRBLXAI/Shared/GameConstants.lua | L307 | delete unused terrainId (pure lookup) | -2 lines +1 lines
20:46:01 | source/ReplicatedStorage/CTRBLXAI/Shared/GameConstants.lua | L3714 | delete unused weaponDefense | -1 lines +0 lines
20:46:16 | source/ReplicatedStorage/CTRBLXAI/UI/UILayoutCoordinator.lua | L33 | delete unused h | -1 lines +0 lines
20:46:49 | source/StarterPlayer/StarterPlayerScripts/GuildMenu.client.lua | L108 | delete unused selectedParty + partyEdit decls | -2 lines +0 lines
20:46:49 | source/StarterPlayer/StarterPlayerScripts/GuildMenu.client.lua | L1761 | delete selectedParty assignment (never read) | -2 lines +1 lines
20:46:49 | source/StarterPlayer/StarterPlayerScripts/GuildMenu.client.lua | L1950 | delete selectedParty assignment (never read) | -2 lines +1 lines
20:46:49 | source/StarterPlayer/StarterPlayerScripts/GuildMenu.client.lua | L502 | delete unused act + its comment | -12 lines +0 lines
20:46:49 | source/StarterPlayer/StarterPlayerScripts/BattleVisualClient.client.lua | L95 | delete unused ELEVATION_STEP + its comment | -4 lines +0 lines
20:46:49 | source/StarterPlayer/StarterPlayerScripts/BattleVisualClient.client.lua | L4120 | delete unused uName | -2 lines +1 lines
20:46:49 | source/StarterPlayer/StarterPlayerScripts/BattleVisualClient.client.lua | L6301 | LocalShadow: rename inner mf -> tileMapFolder | -2 lines +2 lines
20:46:49 | source/StarterPlayer/StarterPlayerScripts/BattleVisualClient.client.lua | L6308 | shadow rename use | -1 lines +1 lines
20:46:49 | source/StarterPlayer/StarterPlayerScripts/BattleVisualClient.client.lua | L6409 | delete unused actorName (+targetName, only used by removed summary) | -4 lines +0 lines
20:46:49 | source/StarterPlayer/StarterPlayerScripts/BattleVisualClient.client.lua | L6452 | delete unused summary block (log line is server-authored) | -15 lines +0 lines
20:47:06 | source/StarterPlayer/StarterPlayerScripts/CameraController.lua | L27 | delete unused StarterGui | -1 lines +0 lines
20:47:06 | source/StarterPlayer/StarterPlayerScripts/CameraController.lua | L727 | rename write-only classification/tapEmitted -> _ | -2 lines +2 lines
20:47:06 | source/StarterPlayer/StarterPlayerScripts/CameraController.lua | L733 | rename writes | -2 lines +2 lines
20:47:06 | source/StarterPlayer/StarterPlayerScripts/CameraController.lua | L736 | rename write | -1 lines +1 lines
20:47:06 | source/StarterPlayer/StarterPlayerScripts/CameraController.lua | L738 | rename write | -1 lines +1 lines
20:47:06 | source/StarterPlayer/StarterPlayerScripts/UI/UIController.client.lua | L12 | delete unused Players (follow-on) + RunService | -2 lines +0 lines
20:47:06 | source/StarterPlayer/StarterPlayerScripts/UI/UIController.client.lua | L14 | delete unused player | -2 lines +0 lines
20:47:06 | source/StarterPlayer/StarterPlayerScripts/UI/UIController.client.lua | L25 | delete unused UIConstants require (pure data module, no load-time effects) | -1 lines +0 lines
20:47:06 | source/StarterPlayer/StarterPlayerScripts/UI/UIController.client.lua | L45 | delete never-read currentLayout decl | -1 lines +0 lines
20:47:06 | source/StarterPlayer/StarterPlayerScripts/UI/UIController.client.lua | L96 | delete never-read currentLayout write | -2 lines +0 lines
20:47:15 | source/StarterPlayer/StarterPlayerScripts/UnitInspectorPanel.client.lua | L81 | delete never-read currentTab decl | -1 lines +0 lines
20:47:15 | source/StarterPlayer/StarterPlayerScripts/UnitInspectorPanel.client.lua | L1572 | delete never-read currentTab write | -1 lines +0 lines
20:47:15 | source/StarterPlayer/StarterPlayerScripts/DeploymentUI.client.lua | L76 | delete unused ELEVATION_STEP + its comment | -5 lines +0 lines
20:47:15 | source/StarterPlayer/StarterPlayerScripts/QuestBoardUI.client.lua | L356 | rename unused show -> _show (deleting it would orphan populateCard) | -1 lines +1 lines
20:47:43 | source/StarterPlayer/StarterPlayerScripts/DeploymentUI.client.lua | L75 | restore blank line removed with ELEVATION_STEP (whitespace only) | -3 lines +4 lines
20:47:43 | source/ServerScriptService/Game/ElevationPass.lua | L113 | delete unused bMin | -1 lines +0 lines
20:47:43 | source/ServerScriptService/Game/TargetingService.lua | L203 | delete unused BASE_MOVEMENT_RANGE | -2 lines +0 lines
20:47:43 | source/ServerScriptService/Game/TargetingService.lua | L1940 | delete unused actorElev (pure read; elevation check done by isMeleeElevationLegal) | -2 lines +0 lines
20:47:43 | source/ServerScriptService/Game/UnitSchema.lua | L62 | delete unused DEFAULT_RT | -1 lines +0 lines
20:47:43 | source/ServerScriptService/Game/EquipmentService.lua | L154 | delete empty if-block (condition is a pure race check) | -5 lines +0 lines
20:47:43 | source/ServerScriptService/Game/ArmorPassiveService.lua | L92 | rename unused hasAllyInRange -> _ | -1 lines +1 lines
20:47:56 | source/ServerScriptService/Game/AugmentEffectService.lua | L299 | rename unused removeAllBuffs -> _ (kept for future purge) | -1 lines +1 lines
20:47:56 | source/ServerScriptService/Game/AugmentEffectService.lua | L616 | delete unused family (pure lookup) | -4 lines +3 lines
20:48:14 | source/ServerScriptService/Game/FeaturePass.lua | L884 | rename only blobSet -> _blobSet in placeCorruptionSpread (call kept) | -8 lines +8 lines
20:48:15 | source/ServerScriptService/Game/FeaturePass.lua | L2826 | delete unused dy | -2 lines +1 lines
20:48:15 | source/ServerScriptService/Game/FeaturePass.lua | L2950 | delete unused dy | -2 lines +1 lines
20:48:15 | source/ServerScriptService/Game/FeaturePass.lua | L3077 | delete unused dy | -2 lines +1 lines
20:48:31 | source/ServerScriptService/Game/TileEffectService.lua | L413 | MultiLineStatement: indent warn() continuation lines one level (whitespace only) | -5 lines +5 lines
20:48:31 | source/ServerScriptService/Game/MerchantService.lua | L75 | delete unused Game + ServerScriptService (follow-on) | -3 lines +0 lines
20:48:31 | source/ServerScriptService/Game/EnemyGenerator.lua | L31 | delete unused TraitEffectService require (no load-time effects) | -1 lines +0 lines
20:48:31 | source/ServerScriptService/Game/EnemyGenerator.lua | L40 | delete unused DoctrineData + SkillData requires (data modules) | -2 lines +0 lines
20:48:31 | source/ServerScriptService/Game/EnemyGenerator.lua | L657 | delete unused egModBaseRt/egLukFactor (pre-StatCalcService leftovers, pure reads) + stale comment | -5 lines +0 lines
20:48:31 | source/ServerScriptService/Game/ObjectEffectService.lua | L38 | delete unused InventoryService + ItemGenerator requires (no load-time effects) | -2 lines +0 lines
20:48:31 | source/ServerScriptService/Game/BattleVisualBroadcaster.lua | L787 | drop ignored syncHp args | -1 lines +1 lines
20:48:31 | source/ServerScriptService/Game/BattleVisualBroadcaster.lua | L821 | drop ignored syncHp args | -1 lines +1 lines
20:48:31 | source/ServerScriptService/Game/BattleVisualBroadcaster.lua | L856 | drop ignored syncHp args | -1 lines +1 lines
20:48:31 | source/ServerScriptService/Game/BattleVisualBroadcaster.lua | L1099 | drop ignored syncHp args | -1 lines +1 lines
20:48:31 | source/ServerScriptService/Game/BattleVisualBroadcaster.lua | L1433 | drop ignored syncHp args (2 calls) | -2 lines +2 lines
20:48:42 | source/ServerScriptService/Main.server.lua | L2993 | LocalShadow: drop inner re-require of RaceData (same module as top-level RaceData, require is cached) | -3 lines +2 lines
20:48:42 | source/ServerScriptService/Main.server.lua | L4731 | delete never-read anyEnemyStanding decl | -2 lines +1 lines
20:48:42 | source/ServerScriptService/Main.server.lua | L4743 | delete never-read anyEnemyStanding write (else branch) | -4 lines +2 lines
20:49:04 | source/ServerScriptService/Game/BattleTurnController.lua | L17 | delete unused require TraitEffectService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:04 | source/ServerScriptService/Game/BattleTurnController.lua | L18 | delete unused require ItemGenerator (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:04 | source/ServerScriptService/Game/BattleTurnController.lua | L18 | delete unused require InventoryService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:04 | source/ServerScriptService/Game/BattleTurnController.lua | L18 | delete unused require EquipmentService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:04 | source/ServerScriptService/Game/BattleTurnController.lua | L18 | delete unused require PersistentStateService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:04 | source/ServerScriptService/Game/BattleTurnController.lua | L18 | delete unused require SaveService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:04 | source/ServerScriptService/Game/BattleTurnController.lua | L18 | delete unused require RewardService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:04 | source/ServerScriptService/Game/BattleTurnController.lua | L18 | delete unused require DisplacementService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:04 | source/ServerScriptService/Game/BattleTurnController.lua | L18 | delete unused require TileEffectService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:04 | source/ServerScriptService/Game/BattleTurnController.lua | L18 | delete unused require TileCrossEffectService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:04 | source/ServerScriptService/Game/BattleTurnController.lua | L18 | delete unused require RacePassiveService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:14 | source/ServerScriptService/Game/BattleTurnController.lua | L21 | delete unused require MapService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:14 | source/ServerScriptService/Game/BattleTurnController.lua | L21 | delete unused require MapRenderer (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:14 | source/ServerScriptService/Game/BattleTurnController.lua | L21 | delete unused require EnemyGenerator (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:14 | source/ServerScriptService/Game/BattleTurnController.lua | L21 | delete unused require TraitRoller (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:14 | source/ServerScriptService/Game/BattleTurnController.lua | L22 | delete unused require WeatherService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:14 | source/ServerScriptService/Game/BattleTurnController.lua | L23 | delete unused require ItemDisplay (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:14 | source/ServerScriptService/Game/BattleTurnController.lua | L27 | delete 8 unused Slice-6 service requires (Currency..Progression; no load-time effects; Main loads CurrencyService first at its L65) + stale load-order comment | -11 lines +0 lines
20:49:23 | source/ServerScriptService/Game/BattleTurnController.lua | L31 | delete unused require UGCService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:23 | source/ServerScriptService/Game/BattleTurnController.lua | L31 | delete unused require UGCOutfitService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:23 | source/ServerScriptService/Game/BattleTurnController.lua | L32 | delete unused require UGCRatingService (no load-time effects; Main loads it first) | -1 lines +0 lines
20:49:23 | source/ServerScriptService/Game/BattleTurnController.lua | L44 | delete unused TraitData require (data module) | -5 lines +0 lines
20:49:23 | source/ServerScriptService/Game/BattleTurnController.lua | L55 | delete unused BonusData + ArmorData requires (data modules) | -11 lines +0 lines
20:49:23 | source/ServerScriptService/Game/BattleTurnController.lua | L55 | delete unused AugmentData require (data module) | -6 lines +0 lines
20:49:23 | source/ServerScriptService/Game/BattleTurnController.lua | L62 | delete unused PortraitData require + its comment | -7 lines +0 lines
