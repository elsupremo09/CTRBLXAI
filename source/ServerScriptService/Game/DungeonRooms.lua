--!strict
-- DungeonRooms.lua
-- CTRBLXAI | Dungeon mode — Event and Merchant room logic, split out of DungeonService (2026-11-14,
-- step 7b: DungeonService had passed 1,000 lines). Behaviour unchanged. Server-only. No require of
-- DungeonService (no cycle): DungeonService calls Rooms.Bind(ctx) with its private helpers and hooks.

local DungeonRules = require(script.Parent:WaitForChild("DungeonRules"))
local DungeonEvents = require(script.Parent:WaitForChild("DungeonEvents"))
local DungeonSilver = require(script.Parent:WaitForChild("DungeonSilver")) -- silver step 2 (requires only DungeonRules)
local DungeonBag = require(script.Parent:WaitForChild("DungeonBag")) -- silver step 2: Bag-full check on Merchant buys
local DungeonCourier = require(script.Parent:WaitForChild("DungeonCourier")) -- steps 4-5: EV-17 Courier's Rest (requires no Dungeon service: no cycle)
local D = DungeonRules.Data
local E = D.Ev

local Rooms = {}
local C: any = nil

--- ctx = { stateOf, nodeById, effType, currentRoom, persist, isInt, addLoot, healer(), eventHooks(), merchant(), grantEventRelic }.
function Rooms.Bind(ctx: any) C = ctx end

--------------------------------------------------
-- EVENT ROOMS (build step 7a, 2026-11-14; project_rules 272). Picked on first look (seeded by run seed +
-- room, no repeats in a run, facility good/bad odds), resolved server-side, applied once, saved.
--------------------------------------------------

-- EV-11: sorted race / doctrine ids present in the party (event hook unitInfo; nil-safe).
local function kinLists(run: any): ({ string }, { string })
	local h = C.eventHooks()
	local rs, ds = {}, {}
	if not (h and h.unitInfo) then return {}, {} end
	for _, id in run.party do
		local ok, info = pcall(h.unitInfo, id)
		if ok and type(info) == "table" then
			if type(info.raceId) == "string" then rs[info.raceId] = true end
			if type(info.doctrineId) == "string" then ds[info.doctrineId] = true end
		end
	end
	local races, docs = {}, {}
	for k in rs do table.insert(races, k) end
	for k in ds do table.insert(docs, k) end
	table.sort(races); table.sort(docs)
	return races, docs
end

local function eventRoom(run: any): (any, any, string?)
	if not run then return nil, nil, "No dungeon run in progress" end
	if not run.at then return nil, nil, "Pick a room first" end
	local n = C.nodeById(run.map, run.at)
	if not n or C.effType(n) ~= "Event" then return nil, nil, "Not an Event room" end
	local ev = run.events[n.id]
	if not ev then
		local seed = run.sseed or run.card.seed
		local races, docs = kinLists(run)
		-- EV-17 Courier's Rest (rule 261): once per stage, not on the run-long no-repeat list.
		local seen = run.seenEvents
		if run.courierStage == (run.stage or 1) then seen = table.clone(seen); seen["EV-17"] = true end
		local id = DungeonEvents.Pick(seed, n.row, n.col, run.card.facilityLevel, seen, #races + #docs > 0)
		ev = { id = id }
		-- EV-11 (stages build 2026-11-15): the kin is seeded per room and saved.
		if id == "EV-11" then ev.kin = DungeonEvents.KinFor(seed, n.row, n.col, races, docs) end
		run.events[n.id] = ev
		if id == "EV-17" then run.courierStage = run.stage or 1 else run.seenEvents[id] = true end
		C.persist()
	end
	return n, ev, nil
end

--- The current Event room's event: { id, done, fight, result }. Choices are keys; text lives on the client.
function Rooms.GetEvent(playerId: string): (boolean, any)
	local run = C.stateOf(playerId).run
	local n, ev, why = eventRoom(run)
	if not n then return false, why end
	local hasKO = false
	if C.eventHooks() and C.eventHooks().hasKO then
		local okK, v = pcall(C.eventHooks().hasKO, run.party)
		hasKO = okK and v == true
	end
	local quote: any = nil
	if ev.id == "EV-03" then -- silver step 2: Peddler refill quote at 40% of the silver tier price (rule 278)
		local q = DungeonSilver.Refill(run, E.PeddlerRefillPct, false, "peddler")
		if type(q) == "table" then quote = { cost = q.cost or 0, missing = (q.refilled or 0) + (q.skippedCharges or 0), need = q.need } end
	end
	-- EV-12 / EV-15: the bag gear the player can pick (names + rarity only; ids stay server-checked).
	local bagGear: any = nil
	if ev.id == "EV-12" or ev.id == "EV-15" then
		bagGear = {}
		for _, gid in run.bag.gear do
			local it = run.bag.gearItems[gid]
			if type(it) == "table" then
				local ok = ev.id == "EV-12" or DungeonRules.CanForge(it.rarityId)
				table.insert(bagGear, { id = gid, name = DungeonCourier.ItemName(it), rarity = it.rarityId, level = it.itemLevel, ok = ok })
			end
		end
	end
	local kinName: string? = nil
	if ev.kin and C.eventHooks() and C.eventHooks().kinName then
		local okN, v = pcall(C.eventHooks().kinName, ev.kin.kind, ev.kin.id)
		if okN and type(v) == "string" then kinName = v end
	end
	-- EV-16 Altar of Change: party units that have a perk or flaw (units with none are hidden, agent default).
	local altarUnits: any = nil
	if ev.id == "EV-16" and C.eventHooks() and C.eventHooks().traits then
		altarUnits = {}
		for _, uid in run.party do
			local okT, t = pcall(C.eventHooks().traits, uid)
			if okT and type(t) == "table" and (t.perk or t.flaw) then
				table.insert(altarUnits, { id = uid, name = t.name, level = t.level, perk = t.perk, flaw = t.flaw })
			end
		end
	end
	return true, { id = ev.id, done = ev.done == true, fight = ev.fight, result = ev.result,
		choices = DungeonEvents.Choices[ev.id], hasKO = hasKO, refill = quote,
		kin = ev.kin and { kind = ev.kin.kind, name = kinName } or nil, bagGear = bagGear,
		traded = ev.traded, altarUnits = altarUnits,
		courier = if ev.id == "EV-17" and not ev.done then DungeonCourier.Options(run) else nil } -- EV-17 picker
end

--- EV-17 Courier's Rest (rule 272): send the picked Bag items home. Every check is in DungeonCourier.Send
--- (items really in the Bag, pack size, silver). One send per room; the room is then cleared. No relic roll.
function Rooms.CourierSend(playerId: string, picks: any): (boolean, any)
	local run = C.stateOf(playerId).run
	local n, ev, why = eventRoom(run)
	if not n then return false, why end
	if ev.id ~= "EV-17" then return false, "Invalid choice" end
	if ev.done or run.cleared[n.id] then return false, "This room is already used" end
	local ok, res = DungeonCourier.Send(run, picks)
	if not ok then return false, res end
	local lines: { any } = { { k = "courier", n = res.count } }
	if res.cost > 0 then table.insert(lines, { k = "silver", n = -res.cost }) end
	ev.done, ev.choice, ev.result = true, "send", lines
	run.cleared[n.id] = true
	C.persist()
	return true, { id = ev.id, lines = lines }
end

local function realGold(): number
	if not (C.eventHooks() and C.eventHooks().gold) then return 0 end
	local ok, v = pcall(C.eventHooks().gold)
	return if ok and type(v) == "number" then v else 0
end

--- Pick a choice. Applied exactly once; the room is cleared unless it turned into a fight (then the
--- normal battle launch plays it and clears it). Returns ok, { lines = { {k, ...} } } | error.
function Rooms.ChooseEvent(playerId: string, choice: any, rank: number, gearId: any): (boolean, any)
	local run = C.stateOf(playerId).run
	local n, ev, why = eventRoom(run)
	if not n then return false, why end
	if ev.done or run.cleared[n.id] then return false, "This room is already used" end
	if type(choice) ~= "string" or #choice > 16 then return false, "Invalid choice" end
	-- EV-13 Barter Post: each of the 3 trades once per room (rule 272, fix 2026-11-15).
	local isTrade = ev.id == "EV-13" and (choice == "m2c" or choice == "c2m" or choice == "g2m")
	if isTrade and ev.traded and ev.traded[choice] then return false, "This room is already used" end
	local hasKO = false
	if C.eventHooks() and C.eventHooks().hasKO then
		local okK, v = pcall(C.eventHooks().hasKO, run.party)
		hasKO = okK and v == true
	end
	-- EV-12 / EV-15 pick a gear from the RUN BAG (server-checked; the client only names an id).
	local gid: string? = nil
	if (ev.id == "EV-12" or ev.id == "EV-15") and choice ~= "keep" and choice ~= "leave" then
		if type(gearId) ~= "string" or #gearId > 128 or type(run.bag.gearItems[gearId]) ~= "table" then return false, "Invalid choice" end
		if ev.id == "EV-15" and not DungeonRules.CanForge(run.bag.gearItems[gearId].rarityId) then return false, "Can't reforge this rarity" end
		gid = gearId
	end
	local ok, fx = DungeonEvents.Resolve(ev.id, choice, run.sseed or run.card.seed, n.row, n.col,
		{ hasKO = hasKO, realGold = realGold(), silver = DungeonSilver.Get(run), kin = ev.kin, gearId = gid })
	if not ok then return false, fx end
	local h = C.eventHooks() or {}
	local level = DungeonRules.BattleLevel(rank, run.card.difficulty, n.row, 0, run.stage)
	local mult = DungeonRules.DropMultiplier(run.battles, run.dropBonus)
	local lines: { any } = if ev.id == "EV-13" and ev.result then table.clone(ev.result) else {}
	-- Real gold is taken first; if that fails nothing else happens (pay-once, no free effects).
	for _, f in fx do
		if f.k == "realGold" and f.n < 0 then
			if not (h.pay and h.pay(-f.n)) then return false, "Not enough gold" end
		end
		-- Silver step 2 (rule 278): silver costs are paid first, all-or-nothing (EV-08 bet, EV-13 silver line).
		if f.k == "silverPay" and not DungeonSilver.Spend(run, f.n, ev.id) then return false, "Not enough silver" end
		if f.k == "trade" and f.give == "silver" then
			if not DungeonSilver.Spend(run, f.giveN, "barter") then return false, "Not enough silver" end
			local okL = C.addLoot(playerId, "normalMats", f.get, f.getN) -- the mercury goes into the Bag as normal loot (rule 272)
			if not okL then -- W2: refund the silver if the Bag hand-in failed
				run.silver = DungeonSilver.Get(run) + f.giveN
				warn("[DungeonRooms] Barter hand-in failed; refunded " .. tostring(f.giveN) .. " silver")
				return false, "Something went wrong. Try again."
			end
		-- EV-13 Barter Post: the trade is all-or-nothing on real resources (CurrencyService Debit).
		elseif f.k == "trade" then
			if not (h.trade and h.trade(f.give, f.giveN, f.get, f.getN)) then
				return false, if f.give == "gold" then "Not enough gold" elseif f.give == "mercury" then "Not enough mercury" else "Not enough crystals" -- approved 2026-11-15 10:08 AM
			end
		end
	end
	if isTrade then
		ev.traded = ev.traded or {}
		ev.traded[choice] = true
		local f = fx[1]
		local line = { k = "trade", give = f.give, giveN = f.giveN, get = f.get, getN = f.getN }
		ev.result = ev.result or {}
		table.insert(ev.result, line)
		table.insert(lines, line) -- third trade: the room finishes with all three lines
		if not (ev.traded.m2c and ev.traded.c2m and ev.traded.g2m) then
			print(`[DungeonRooms] Event EV-13 | {choice} | trade (room stays open)`)
			C.persist()
			return true, { id = ev.id, lines = { line }, done = false }
		end
	end
	if ev.id == "EV-03" then -- Peddler: refill check before marking done
		if not (C.merchant() and C.merchant().chargeSlots) then return false, "Something went wrong. Try again." end
		-- W1 (default 9:09 PM): charges missing but none affordable -> refuse like the Merchant; the room stays usable.
		for _, f in fx do
			if f.k == "refill" then
				local q = DungeonSilver.Refill(run, f.pct, false, "peddler")
				if type(q) == "table" and (q.refilled or 0) <= 0 and (q.skippedCharges or 0) > 0 then return false, "Not enough silver" end
			end
		end
	end
	ev.done = true
	ev.choice = choice
	for _, f in fx do
		if f.k == "rolls" then
			local want = f.n * mult
			local cnt = math.floor(want) + (if Random.new((run.sseed or run.card.seed) * 7 + n.row * 31 + n.col):NextNumber() < want % 1 then 1 else 0)
			if h.rolls and cnt > 0 then
				local okR, items = pcall(h.rolls, level, cnt, `dgEvent_{run.card.id}_{n.id}`)
				if okR and type(items) == "table" then
					for _, it in items do
						if type(it) == "table" and it.item then
							if C.addLoot(playerId, "gearItem", it.item) then table.insert(lines, { k = "gear", name = DungeonCourier.ItemName(it.item) }) end
						elseif type(it) == "table" and it.card then
							C.addLoot(playerId, "cards", it.card, 1)
							table.insert(lines, { k = "gear", name = tostring(it.name or "an item") })
						end
					end
				elseif not okR then warn("[DungeonRooms] event rolls failed: " .. tostring(items)) end
			end
		elseif f.k == "bagGold" then
			C.addLoot(playerId, "gold", f.n)
			table.insert(lines, { k = "bagGold", n = f.n })
		elseif f.k == "bagMat" then
			C.addLoot(playerId, "normalMats", f.id, f.n)
			table.insert(lines, { k = "mat", id = f.id, n = f.n })
		elseif f.k == "heal" then
			-- Spring heals living units only (the flask choice is the revive); KO units are skipped.
			if C.healer() then for _, id in run.party do
				if not (h.isKO and h.isKO(id)) then pcall(C.healer(), id, f.pct) end
			end end
			table.insert(lines, { k = "heal", n = f.pct })
		elseif f.k == "reviveAll" then -- EV-14 Campfire "Rest a while": every KO'd party unit back at pct% HP
			if h.reviveAll then
				local okV, names = pcall(h.reviveAll, run.party, f.pct)
				if okV and type(names) == "table" then for _, nm in names do table.insert(lines, { k = "revive", name = nm }) end end
			end
		elseif f.k == "revive" then
			if h.revive then
				local okV, name = pcall(h.revive, run.party, f.pct)
				if okV and name then table.insert(lines, { k = "revive", name = name }) end
			end
		elseif f.k == "hurtAll" or f.k == "hurtTop" then
			if h.hurt then pcall(h.hurt, run.party, f.pct, f.k == "hurtTop") end
			table.insert(lines, { k = "hurt", n = f.pct })
		elseif f.k == "realGold" then
			if f.n > 0 and h.give then h.give(f.n) end
			table.insert(lines, { k = "realGold", n = f.n })
		elseif f.k == "silver" then -- silver step 2: event silver into the purse (EV-04 / EV-07 / EV-08 win)
			table.insert(lines, { k = "silver", n = DungeonSilver.Add(run, f.n) })
		elseif f.k == "silverPay" then -- already paid above
			table.insert(lines, { k = "silver", n = -f.n })
		elseif f.k == "loseSilverPct" then -- EV-10 Cutpurse: 25% of the purse, rounded down
			table.insert(lines, { k = "silverLost", n = DungeonSilver.LosePct(run, f.pct) })
		elseif f.k == "shrine" then
			run.dropBonus = math.min(D.DropCap, (run.dropBonus or 0) + f.bonus)
			table.insert(lines, { k = "loot", mult = DungeonRules.DropMultiplier(run.battles, run.dropBonus) })
		elseif f.k == "refill" then -- EV-03 Peddler in silver (step 2): partial when short, cheapest first
			local res = DungeonSilver.Refill(run, f.pct, true, "peddler")
			if type(res) == "table" and (res.refilled or 0) > 0 and (res.cost or 0) > 0 then table.insert(lines, { k = "silver", n = -(res.cost) }) end
			if type(res) ~= "table" or (res.refilled or 0) <= 0 then table.insert(lines, { k = "nothing" }) end
		elseif f.k == "loseBagGoldPct" then
			local lose = math.floor(run.bag.gold * f.pct / 100)
			run.bag.gold -= lose
			table.insert(lines, { k = "bagGold", n = -lose })
		elseif f.k == "fight" then
			ev.fight = f.played
			table.insert(lines, { k = "fight" })
		elseif f.k == "nothing" then
			table.insert(lines, { k = "nothing" })
		-- EV-11..16 (stages build 2026-11-15, rule 272)
		elseif f.k == "kinHeal" then -- Kindred Shrine: units of that race heal (living only)
			if C.healer() and h.unitInfo then for _, id in run.party do
				local okI, info = pcall(h.unitInfo, id)
				if okI and type(info) == "table" and info.raceId == f.raceId and not (h.isKO and h.isKO(id)) then pcall(C.healer(), id, f.pct) end
			end end
			table.insert(lines, { k = "kinHeal", n = f.pct, race = (if ev.kin and h.kinName then (select(2, pcall(h.kinName, ev.kin.kind, ev.kin.id))) else nil) })
		elseif f.k == "doctrineBuff" then -- Hall of the {Doctrine}: next battle only (Main reads run.nextBattleBuff)
			run.nextBattleBuff = { doctrineId = f.doctrineId, pct = f.pct }
			table.insert(lines, { k = "buff", doctrine = (if ev.kin and h.kinName then (select(2, pcall(h.kinName, ev.kin.kind, ev.kin.id))) else nil) })
		elseif f.k == "campRefill" then -- EV-14 Campfire "Search the camp": ALL party consumable charges, free
			if h.campRefill then pcall(h.campRefill, run.party) end
			if type(run.dgLoad) == "table" then run.dgLoad.open = {} end -- step 3: opened Bag copies are full again (SB-43)
			table.insert(lines, { k = "refilled" })
		elseif f.k == "trade" then
			if not isTrade then table.insert(lines, { k = "trade", give = f.give, giveN = f.giveN, get = f.get, getN = f.getN }) end
		elseif f.k == "smith" then -- Smith's Wager: the gear leaves the bag now; the new one is owed
			local it = run.bag.gearItems[f.gearId]
			if it then
				run.bag.gearItems[f.gearId] = nil
				local ix = table.find(run.bag.gear, f.gearId)
				if ix then table.remove(run.bag.gear, ix) end
				DungeonSilver.UnmarkBought(run, "gear", f.gearId, "handed in") -- the handed-in item leaves the Bag
				run.smithOwed = { rarity = DungeonRules.NextGearRarity(it.rarityId) or it.rarityId,
					level = (tonumber(it.itemLevel) or 1) + E.SmithLevelUp, archetypeId = it.baseArchetypeId,
					seed = ((run.sseed or run.card.seed) * 13 + n.row * 401 + n.col * 37) % 2147483647 }
				table.insert(lines, { k = "smith" })
			end
		elseif f.k == "forge" then -- Forge of Chance: +1 rarity step (only up to Epic), bonus lines re-rolled
			local it = run.bag.gearItems[f.gearId]
			local nr = it and DungeonRules.NextGearRarity(it.rarityId)
			if it and nr and h.reforge then
				local okF, set = pcall(h.reforge, it.baseArchetypeId, it.itemLevel, nr, ((run.sseed or run.card.seed) * 29 + n.row * 211 + n.col) % 2147483647)
				if okF and type(set) == "table" then
					it.rarityId = nr
					DungeonSilver.UnmarkBought(run, "gear", f.gearId, "changed") -- W3: a changed bought item becomes normal Bag loot
					it.bonusLines = set.bonusLines
					it.bonusPassiveIds = set.bonusPassiveIds
					if set.displayName then it.displayName = set.displayName end
					table.insert(lines, { k = "forged", name = DungeonCourier.ItemName(it), rarity = nr })
				else warn("[DungeonRooms] reforge failed: " .. tostring(set)) end
			end
		end
	end
	-- Step 8 relics (rule 271): a GOOD event outcome rolls R x0.5. Good = the event counts as Good
	-- (rule 258 odds) and the choice did something (not "nothing"), and didn't turn into a fight
	-- (agent default). Gambler's Table never gives one (checked in DungeonRelics).
	local isGood = false
	for _, e in D.Events do if e.id == ev.id then isGood = e.good end end
	if isGood and not ev.fight and not (#lines == 1 and lines[1].k == "nothing") and C.grantEventRelic then
		local rid = C.grantEventRelic(playerId, ev.id)
		if rid then table.insert(lines, { k = "relic", id = rid }) end
	end
	ev.result = lines
	if not ev.fight then run.cleared[n.id] = true end
	print(`[DungeonRooms] Event {ev.id} | {choice} | {#lines} result(s){if ev.fight then " | fight " .. ev.fight else ""}`)
	C.persist()
	return true, { id = ev.id, lines = lines, fight = ev.fight }
end

--- EV-16 Altar of Change (USER RULING 2026-11-15 10:01 / 10:08 AM, rule 272; matches the Mutation Bench):
--- the 3 replacement options for one unit's perk or flaw. Same kind only, TraitRoller tier odds (can go up
--- or down), all different from the current trait and from each other. Seeded per stage + room + unit + kind
--- (DungeonEvents.AltarRng) so a rejoin shows the same 3. Returns ok, { unitId, kind, current, options } | err.
local function altarOptions(run: any, n: any, unitId: any, kind: any): (boolean, any)
	if type(unitId) ~= "string" or #unitId > 64 or not run.partySet[unitId] then return false, "Invalid unit selection" end
	if kind ~= "perk" and kind ~= "flaw" then return false, "Invalid choice" end
	local h = C.eventHooks() or {}
	if not (h.traits and h.rollTrait) then return false, "Something went wrong. Try again." end
	local okT, t = pcall(h.traits, unitId)
	if not okT or type(t) ~= "table" then return false, "Something went wrong. Try again." end
	local cur = t[kind]
	if not cur then return false, "This unit has no perks or flaws." end
	local rng = DungeonEvents.AltarRng(run.sseed or run.card.seed, n.row, n.col, unitId, kind)
	local opts, seen = {}, { [cur.id] = true }
	for _ = 1, 60 do
		if #opts >= E.AltarOptions then break end
		local okR, o = pcall(h.rollTrait, kind, rng)
		if okR and type(o) == "table" and o.id and not seen[o.id] then
			seen[o.id] = true
			table.insert(opts, o)
		end
	end
	if #opts == 0 then return false, "Something went wrong. Try again." end
	return true, { unitId = unitId, kind = kind, current = cur, options = opts }
end

function Rooms.GetAltarOptions(playerId: string, unitId: any, kind: any): (boolean, any)
	local run = C.stateOf(playerId).run
	local n, ev, why = eventRoom(run)
	if not n then return false, why end
	if ev.id ~= "EV-16" then return false, "Invalid choice" end
	if ev.done or run.cleared[n.id] then return false, "This room is already used" end
	return altarOptions(run, n, unitId, kind)
end

--- Apply the chosen replacement (index 1..3). PERMANENT: written to the roster unit through the trait hook,
--- kept after the run (and on wipeout). The room is used once; no undo.
function Rooms.ChooseAltar(playerId: string, unitId: any, kind: any, index: any): (boolean, any)
	local run = C.stateOf(playerId).run
	local n, ev, why = eventRoom(run)
	if not n then return false, why end
	if ev.id ~= "EV-16" then return false, "Invalid choice" end
	if ev.done or run.cleared[n.id] then return false, "This room is already used" end
	if not C.isInt(index, 1, E.AltarOptions) then return false, "Invalid choice" end
	local okO, o = altarOptions(run, n, unitId, kind)
	if not okO then return false, o end
	local pick = o.options[index]
	if not pick then return false, "Invalid choice" end
	local h = C.eventHooks() or {}
	local okS, res = pcall(h.setTrait, unitId, kind, pick.id)
	if not okS or res == false then return false, "Something went wrong. Try again." end
	ev.done, ev.choice = true, "reshape"
	local line = { k = "altar", unit = nil :: string?, old = o.current.name, new = pick.name }
	local okT, t = pcall(h.traits, unitId)
	if okT and type(t) == "table" then line.unit = t.name end
	ev.result = { line }
	run.cleared[n.id] = true
	print(`[DungeonRooms] Altar of Change | {unitId} {kind}: {o.current.id} -> {pick.id} ({tostring(pick.tier)})`)
	C.persist()
	return true, { id = ev.id, lines = ev.result }
end

--- EV-12 Smith's Wager delivery (Simulator v9 fix 5): the owed gear arrives at the next Event, Rest or
--- stage boss, or on any full-loot exit. It goes into the RUN BAG, so an early escape / wipeout loses it.
--- Called by DungeonService (MoveTo into an Event/Rest room, OnBossWin, EndRun Boss/EscapeNode).
function Rooms.DeliverSmith(playerId: string): string?
	local run = C.stateOf(playerId).run
	local o = run and run.smithOwed
	if not o then return nil end
	run.smithOwed = nil
	local h = C.eventHooks() or {}
	local item: any = nil
	if h.smithGear then
		local okS, res = pcall(h.smithGear, o.archetypeId, o.level, o.rarity, o.seed)
		if okS then item = res else warn("[DungeonRooms] smith gear failed: " .. tostring(res)) end
	end
	if type(item) == "table" and C.addLoot(playerId, "gearItem", item) then
		run.smithDelivered = DungeonCourier.ItemName(item)
		print(`[DungeonRooms] Smith delivers | {run.smithDelivered} | {o.rarity} Lv {o.level}`)
	end
	C.persist()
	return run.smithDelivered
end

--------------------------------------------------
-- MERCHANT ROOM (build step 6, project_rules 268 / 270 Q9-Q10)
-- 6 slots: 3 consumables + 3 gear, seeded by run seed + room (same room = same stock after a rejoin).
-- Silver step 2 (rules 268 / 278): priced in SILVER, fixed at every item level; paid from the run purse;
-- bought items go into the Bag, take a slot and are marked bought (SB-18 only); like any Bag item they are
-- lost on a failed run (USER RULING 2026-11-16 7:22 PM, rule 264). Bought slots are saved with the run.
--------------------------------------------------

-- Consumable tier weights for a Merchant slot. DEV DEFAULT (rule 268 says "Apothecary pool" only).
local CONSUMABLE_TIER_WEIGHTS = table.freeze({ { "Common", 60 }, { "Uncommon", 25 }, { "Rare", 12 }, { "Epic", 3 } })
local stockCache: { [string]: any } = {} -- [cardId..stage..roomId..rank] = stock (session only; rebuilt from the seed)

local function merchantStock(run: any, n: any, rank: number): { any }
	local key = run.card.id .. ":s" .. tostring(run.stage or 1) .. ":" .. n.id .. ":" .. tostring(rank) -- stage in key (fix 2026-11-15)
	if stockCache[key] then return stockCache[key] end
	local seed = ((run.sseed or run.card.seed) * 37 + n.row * 2003 + n.col * 113 + 7) % 2147483647
	local rng = Random.new(seed)
	local level = DungeonRules.BattleLevel(rank, run.card.difficulty, n.row, 0, run.stage)
	local stock = {}
	local h = C.merchant()
	-- Consumables (slots 1-3), distinct ids.
	local pool = (h and h.consumables and h.consumables()) or {}
	local used: { [string]: boolean } = {}
	for slot = 1, D.MerchantConsumableSlots do
		local roll, acc, tier = rng:NextInteger(1, 100), 0, "Common"
		for _, tw in CONSUMABLE_TIER_WEIGHTS do
			acc += tw[2]
			if roll <= acc then tier = tw[1] break end
		end
		local free = {}
		for _, e in pool do
			if e.tier == tier and not used[e.id] then table.insert(free, e) end
		end
		if #free == 0 then for _, e in pool do if not used[e.id] then table.insert(free, e) end end end
		if #free > 0 then
			local e = free[rng:NextInteger(1, #free)]
			used[e.id] = true
			table.insert(stock, { slot = slot, kind = "consumable", id = e.id, name = e.name, tier = e.tier,
				price = DungeonSilver.ConsumablePrice(e.tier) })
		end
	end
	-- Gear (slots 4-6).
	for i = 1, D.MerchantGearSlots do
		local slot = D.MerchantConsumableSlots + i
		local rarity = DungeonRules.MerchantGearRarity(rng:NextInteger(1, 100), run.card.facilityLevel)
		local itemSeed = (seed + slot * 7919) % 2147483647
		local item = h and h.gear and h.gear(level, rarity, itemSeed) or nil
		local price = item and DungeonSilver.GearPrice(item.rarityId, h.is2H ~= nil and h.is2H(item) == true) or nil -- silver, 2H x1.5
		if item and price then
			table.insert(stock, { slot = slot, kind = "gear", item = item, name = DungeonCourier.ItemName(item), rarity = item.rarityId, -- base-name fallback: Common gear has no displayName ("?" bug, 2026-11-16)
				itemLevel = item.itemLevel, price = price })
		end
	end
	stockCache[key] = stock
	return stock
end

--- Merchant room view: stock (names / rarity / level / price + the inspector detail the normal Merchant
--- sends, display only), bought flags, and the refill quote for the party (Apothecary refill x1.5).
function Rooms.GetMerchant(playerId: string, rank: number): (boolean, any)
	local run = C.stateOf(playerId).run
	local n, why = C.currentRoom(run, "Merchant")
	if not n then return false, why end
	local bought = run.bought[n.id] or {}
	local out = {}
	for _, e in merchantStock(run, n, rank) do
		table.insert(out, { slot = e.slot, kind = e.kind, id = e.id, name = e.name, tier = e.tier, rarity = e.rarity,
			itemLevel = e.itemLevel, price = e.price, bought = bought[e.slot] == true,
			instanceId = e.item and e.item.instanceId or nil,
			detail = if e.kind == "gear" then DungeonCourier.GearDetail(e.item) else DungeonCourier.ConsumableDetail(e.id) })
	end
	local plan = DungeonSilver.Refill(run, D.SilverMerchantRefillPct, false, "merchant refill") -- 60% silver (rule 278)
	-- missing = every charge the party lacks (refillable now + skipped for silver), so the panel can tell
	-- "full" apart from "can't afford" (Tester thread-7fb38fa8a88d).
	return true, { stock = out, silver = DungeonSilver.Get(run), refill = plan and { cost = plan.cost, charges = plan.refilled, need = plan.need,
		missing = (plan.refilled or 0) + (plan.skippedCharges or 0) } or nil }
end

--- Buy one Merchant slot. Server re-prices; silver first (all-or-nothing), then the item into the Bag;
--- refund if the hand-in fails. Saved.
function Rooms.BuyMerchant(playerId: string, slot: any, rank: number): (boolean, any)
	local run = C.stateOf(playerId).run
	local n, why = C.currentRoom(run, "Merchant")
	if not n then return false, why end
	if not C.isInt(slot, 1, D.MerchantConsumableSlots + D.MerchantGearSlots) then return false, "Invalid slot" end
	run.bought[n.id] = run.bought[n.id] or {}
	if run.bought[n.id][slot] then return false, "Sold out" end
	local entry
	for _, e in merchantStock(run, n, rank) do if e.slot == slot then entry = e end end
	if not entry then return false, "Sold out" end
	local key = if entry.kind == "gear" then nil else "consumables:" .. tostring(entry.id)
	-- Bag full (rule 279, only once the limit is live): a new gear piece or a new consumable stack needs a slot.
	local needsSlot = entry.kind == "gear" or ((run.bag.cards or {})[key :: string] or 0) <= 0
	if DungeonBag.IsLive() and needsSlot and DungeonBag.Free(run) <= 0 then return false, "Your bag is full" end
	if not DungeonSilver.Spend(run, entry.price, "merchant") then return false, "Not enough silver" end
	local okA, whyA: any = false, nil
	if entry.kind == "gear" then
		okA, whyA = C.addLoot(playerId, "gearItem", table.clone(entry.item))
	else
		okA, whyA = C.addLoot(playerId, "cards", key, 1)
	end
	if not okA then
		run.silver = DungeonSilver.Get(run) + entry.price -- refund
		warn("[DungeonRooms] Merchant buy hand-in failed: " .. tostring(whyA))
		return false, "Merchant not ready"
	end
	DungeonSilver.MarkBought(run, entry.kind, if entry.kind == "gear" then entry.item.instanceId else key :: string)
	run.bought[n.id][slot] = true
	C.persist()
	print(`[DungeonRooms] Merchant buy | {n.id} slot {slot} | {tostring(entry.name or entry.id)} | {entry.price} silver -> Bag{if why == "held" then " (held)" else ""}`)
	return true, { slot = slot, name = entry.name or entry.id, price = entry.price }
end

--- Refill the party's equipped consumables in silver at 60% of the tier price (rule 278). Partial when
--- silver is short: one charge at a time, cheapest first.
function Rooms.RefillMerchant(playerId: string): (boolean, any)
	local run = C.stateOf(playerId).run
	local n, why = C.currentRoom(run, "Merchant")
	if not n then return false, why end
	local plan = DungeonSilver.Refill(run, D.SilverMerchantRefillPct, false, "merchant refill")
	if not plan then return false, "Merchant not ready" end
	local missing = (plan.refilled or 0) + (plan.skippedCharges or 0)
	if missing <= 0 then return false, "Nothing to refill" end
	if (plan.refilled or 0) <= 0 then return false, "Not enough silver" end -- charges missing, none affordable
	local res = DungeonSilver.Refill(run, D.SilverMerchantRefillPct, true, "merchant refill")
	if not res then return false, "Not enough silver" end
	C.persist()
	print(`[DungeonRooms] Merchant refill: {res.refilled or 0} charge(s) for {res.cost or 0} silver`
		.. (if (res.skippedCharges or 0) > 0 then ` | {res.skippedCharges} not refilled - need {res.need or 0} silver` else ""))
	return true, { cost = res.cost, charges = res.refilled, skipped = res.skippedCharges }
end

--- DEV / TEST only (DevDungeon op "force", dev-gated in Main): make the current room a Merchant or an
--- Event room (evId = the event), not cleared. Never reachable by players.
function Rooms.DevForceRoom(playerId: string, kind: any, evId: any): boolean
	local run = C.stateOf(playerId).run
	local n = run and run.at and C.nodeById(run.map, run.at)
	if not n or (kind ~= "Merchant" and kind ~= "Event") then return false end
	n.resolved = kind
	run.cleared[n.id] = nil
	if kind == "Event" then run.events[n.id] = if type(evId) == "string" then { id = evId } else nil end
	if kind == "Merchant" then run.bought[n.id] = nil end
	return true
end

return Rooms
