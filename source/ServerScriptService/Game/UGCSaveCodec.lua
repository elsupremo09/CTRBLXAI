--!strict
-- UGCSaveCodec.lua
-- CTRBLXAI | UGC save payload encode / decode. Split out of UGCService on
-- 2026-10-09 (ARC-005: UGCService was over 1000 lines). Pure functions: no state
-- of its own, no services, no DataStore. UGCService.Export / Import keep their
-- signatures and call this module.
--
-- Required DIRECTLY by UGCService (not injected): save/load must never depend on
-- wiring order. A missing injection would export an empty UGC payload and wipe
-- the player's trials, rentals and cart on the next save.
--
-- Saved shape (string keys — DataStore JSON safe):
--   { v = 3,
--     r  = { ["<id>"] = { m = "t" | "r", n = remaining } },
--     c  = { ["<id>"] = paidRentalCount },
--     t  = { id, ... }  -- trial used
--     x  = { id, ... }  -- expired (red)
--     p  = { id, ... }  -- first-equip prompt shown
--     k  = { id, ... }  -- cart (v2; v1 saves had the wishlist in w -> migrated)
--     rv = { ["<id>"] = 1 | -1 },
--     lp = { ["<id>"] = lastPaidRentPrice },  -- v3: refund source, cleared once refunded (id 53)
--     e  = { [unitId] = { [slot] = id } } }
-- Ownership is NEVER saved. A paused rental of an owned item IS saved (id 44).
-- Data for items no longer curated is KEPT (so a re-curated item keeps its price
-- history) — except the cart, which drops them on decode (Tester D1 / BUG-020).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UGCCatalogData = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("UGCCatalogData"))

local UGCSaveCodec = {}

-- v3 (2026-10-08): + 'lp' last paid rent price (refund, id 53). v2: cart 'k' replaced wishlist 'w'.
UGCSaveCodec.SAVE_VERSION = 3

local function isPositiveInt(n: any): boolean
	return type(n) == "number" and n == n and n > 0 and n < 2 ^ 53 and math.floor(n) == n
end

local function idList(set: { [number]: any }): { number }
	local ids = {}
	for id in set do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function importIdSet(src: any, into: { [number]: boolean }): number
	local n = 0
	if type(src) ~= "table" then return n end
	for _, id in src do
		if isPositiveInt(id) and not into[id] then
			into[id] = true
			n += 1
		end
	end
	return n
end

-- s: a UGCService player state. keepUnit(unitId) -> boolean drops looks of
-- units the player no longer has; nil keeps every unit.
function UGCSaveCodec.Encode(s: any, keepUnit: ((string) -> boolean)?): any
	local r, c, rv, lp = {}, {}, {}, {}
	for id, rental in s.rentals do
		if rental.remaining > 0 then
			r[tostring(id)] = { m = if rental.mode == "trial" then "t" else "r", n = rental.remaining }
		end
	end
	for id, count in s.rentCount do c[tostring(id)] = count end
	for id, price in s.lastRentPrice do lp[tostring(id)] = price end
	for id, vote in s.votes do rv[tostring(id)] = vote end
	local e = {}
	for unitId, slots in s.equips do
		local isKept = true
		if keepUnit then isKept = keepUnit(unitId) end
		if isKept and next(slots) ~= nil then e[unitId] = slots end
	end
	return {
		v = UGCSaveCodec.SAVE_VERSION, r = r, c = c,
		t = idList(s.trialUsed), x = idList(s.expired), p = idList(s.prompted),
		k = idList(s.cart), rv = rv, e = e, lp = lp,
	}
end

-- Fills an already-initialised player state s from a saved payload (old saves
-- without a UGC payload are a no-op). Every value is validated (SEC-001).
function UGCSaveCodec.Decode(data: any, s: any)
	if type(data) ~= "table" then return end

	if type(data.r) == "table" then
		for k, rental in data.r do
			local id = tonumber(k)
			if id and isPositiveInt(id) and type(rental) == "table" and isPositiveInt(rental.n) then
				s.rentals[id] = { mode = if rental.m == "t" then "trial" else "rent", remaining = rental.n }
			end
		end
	end
	if type(data.c) == "table" then
		for k, count in data.c do
			local id = tonumber(k)
			if id and isPositiveInt(id) and isPositiveInt(count) then s.rentCount[id] = count end
		end
	end
	if type(data.lp) == "table" then
		for k, price in data.lp do
			local id = tonumber(k)
			if id and isPositiveInt(id) and isPositiveInt(price) then s.lastRentPrice[id] = price end
		end
	end
	if type(data.rv) == "table" then
		for k, vote in data.rv do
			local id = tonumber(k)
			if id and isPositiveInt(id) and (vote == 1 or vote == -1) then s.votes[id] = vote end
		end
	end
	importIdSet(data.t, s.trialUsed)
	importIdSet(data.x, s.expired)
	importIdSet(data.p, s.prompted)

	-- Cart (v2 'k'); v1 saves stored the wishlist in 'w' -> migrated into the cart.
	-- Tester D1 fix (BUG-020): ids no longer in the catalog are dropped, so they
	-- never count toward the cap.
	local cartSrc = if type(data.k) == "table" then data.k else data.w
	if type(cartSrc) == "table" then
		for _, id in cartSrc do
			if s.cartCount >= UGCCatalogData.CART_CAP then break end
			if isPositiveInt(id) and UGCCatalogData.Items[id] and not s.cart[id] then
				s.cart[id] = true
				s.cartCount += 1
			end
		end
	end

	if type(data.e) == "table" then
		for unitId, slots in data.e do
			if type(unitId) == "string" and type(slots) == "table" then
				local clean = {}
				for slot, id in slots do
					if type(slot) == "string" and UGCCatalogData.SLOT_SET[slot] and isPositiveInt(id) then
						clean[slot] = id
					end
				end
				if next(clean) ~= nil then s.equips[unitId] = clean end
			end
		end
	end
end

return UGCSaveCodec
