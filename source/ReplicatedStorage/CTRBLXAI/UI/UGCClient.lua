--!strict
-- UGCClient.lua
-- CTRBLXAI | UGC Rental & Ownership — client helper for the Customize screen,
-- the UGC merchant and the inspector "worn items" list.
--
-- Thin, display-only (ARC-001 / ARC-003): every call is a request to the server
-- through UGCEvents; nothing here decides prices, ownership or access. The
-- purchase prompt on first equip is opened BY THE SERVER (UGCService.Equip), so
-- screens only need RequestEquip. The "Buy for Roblox Avatar" button is shown on
-- every item that is not owned (trial / rent / expired / locked).
--
-- Screens own the connections they create (PRF-004): OnStateChanged returns the
-- RBXScriptConnection, and buttons are destroyed with their parent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10) :: Instance
local UI = CTRBLXAI:WaitForChild("UI", 10) :: Instance
local Remotes = CTRBLXAI:WaitForChild("Remotes", 10) :: Instance
local Theme = require(UI:WaitForChild("Theme", 10) :: ModuleScript) :: any
local UIComponents = require(UI:WaitForChild("UIComponents", 10) :: ModuleScript) :: any
local UGCEvents = require(Remotes:WaitForChild("UGCEvents", 10) :: ModuleScript) :: any

local UGCClient = {}

export type Result = { ok: boolean, error: string?, data: any }

local BUY_TEXT = "Buy for Roblox Avatar"
local OWNED_TEXT = "Owned"

-- Status -> colour (Theme tokens only, DAT-001). "expired" is red per ugc_rules on_expiry.
local STATUS_COLOR_KEY: { [string]: string } = {
	owned = "Success",
	trial = "Info",
	rent = "TextGold",
	expired = "Danger",
	locked = "TextDisabled",
}

--------------------------------------------------
-- REQUESTS
--------------------------------------------------

local function invoke(name: string, ...: any): Result
	local remote = UGCEvents[name]
	if not remote then
		return { ok = false, error = "UGC unavailable", data = nil }
	end
	local ok, res = pcall(remote.InvokeServer, remote, ...)
	if not ok or type(res) ~= "table" then
		warn(`[UGCClient] {name} failed: {res}`)
		return { ok = false, error = "Request failed", data = nil }
	end
	return res :: Result
end

function UGCClient.GetView(unitId: string?): Result return invoke("GetUGCView", unitId) end
function UGCClient.GetWornItems(unitId: string): Result return invoke("GetUnitWornUGC", unitId) end
function UGCClient.StartTrial(assetId: number): Result return invoke("RequestUGCTrial", assetId) end
function UGCClient.Rent(assetId: number): Result return invoke("RequestUGCRent", assetId) end
function UGCClient.Equip(unitId: string, assetId: number): Result return invoke("RequestUGCEquip", unitId, assetId) end
function UGCClient.Unequip(unitId: string, slot: string): Result return invoke("RequestUGCUnequip", unitId, slot) end
function UGCClient.SetMarked(assetId: number, isMarked: boolean): Result return invoke("RequestUGCWishlist", assetId, isMarked) end
function UGCClient.Rate(assetId: number, vote: number): Result return invoke("RequestUGCRate", assetId, vote) end
function UGCClient.Buy(assetId: number): Result return invoke("RequestUGCPurchase", assetId) end

-- callback({ reason = "purchased" | "expired", assetIds = { number } })
function UGCClient.OnStateChanged(callback: (any) -> ()): RBXScriptConnection?
	local ev = UGCEvents.UGCStateChanged
	if not ev then return nil end
	return ev.OnClientEvent:Connect(callback)
end

--------------------------------------------------
-- DISPLAY HELPERS
--------------------------------------------------

function UGCClient.GetStatusColor(status: string): Color3
	local key = STATUS_COLOR_KEY[status] or "TextSecondary"
	return Theme.Colors[key]
end

-- Short label for an item tile, e.g. "Trial: 3 left", "Expired".
function UGCClient.GetStatusLabel(item: any): string
	local s = item.status
	if s == "owned" then return OWNED_TEXT end
	if s == "trial" then return `Trial: {item.remaining} left` end
	if s == "rent" then return `Rented: {item.remaining} left` end
	if s == "expired" then return "Expired" end
	return "Locked"
end

-- Always-visible Buy button for any item the player does not own (ugc_rules buy_button).
-- Returns nil for owned items. onResult(result) is optional.
function UGCClient.CreateBuyButton(parent: Instance, item: any, onResult: ((Result) -> ())?): GuiButton?
	if item.status == "owned" then return nil end
	local btn = UIComponents.PrimaryButton({
		name = "UGCBuyButton",
		text = BUY_TEXT,
		color = Theme.Colors.Success,
		onPress = function()
			local res = UGCClient.Buy(item.assetId)
			if onResult then onResult(res) end
		end,
	})
	btn.Parent = parent
	return btn
end

-- "Owned" badge (ugc_rules owned_badge): inspector worn-items rows and merchant tiles.
function UGCClient.CreateOwnedBadge(parent: Instance, isOwned: boolean): TextLabel?
	if not isOwned then return nil end
	local badge = Instance.new("TextLabel")
	badge.Name = "UGCOwnedBadge"
	badge.Text = OWNED_TEXT
	badge.Font = Theme.Font.PrimaryBold
	badge.TextSize = Theme.Text.Badge()
	badge.TextColor3 = Theme.Colors.TextPrimary
	badge.BackgroundColor3 = Theme.Colors.Success
	badge.BackgroundTransparency = 0
	badge.BorderSizePixel = 0
	badge.AutomaticSize = Enum.AutomaticSize.XY
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.sm
	corner.Parent = badge
	badge.Parent = parent -- NET-004: properties before Parent
	return badge
end

return UGCClient
