--!strict
-- PreviewIdle.lua
-- CTRBLXAI | Idle animation for the 3D unit previews (2026-11-09).
--
-- The Loadout Outfit tab (UGCOutfitTab) and the battle inspector Outfit tab
-- (UGCInspectorOutfit) show a client-side copy of the server's PreviewModel inside a
-- ViewportFrame + WorldModel. The server anchors EVERY part of that model (display
-- only), so the copy stood in a T-pose. This plays the same base idle the battle units
-- use (AnimationRegistry.Assets.Idle — UnitAnimController.StartBaseIdle and the
-- deployment idle) on the LOCAL copy only.
--
-- Visual only (NET-001 / ARC-001): never touches the server model. The copy must already
-- be inside a WorldModel (a ViewportFrame only animates models under one). The caller owns
-- cleanup: call PreviewIdle.Stop(track) when the preview closes or rebuilds (PRF-004).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationRegistry = require(
	(ReplicatedStorage:WaitForChild("CTRBLXAI", 10) :: Instance)
		:WaitForChild("Shared", 10)
		:WaitForChild("AnimationRegistry", 10) :: ModuleScript
) :: any

local PreviewIdle = {}

local FADE_SEC = 0.2

--- Start the looped base idle on a preview copy that is already parented into a
--- WorldModel. Unanchors every part except the root so the Motor6D joints can move the
--- limbs (a WorldModel runs no physics, so nothing falls; the root stays anchored).
--- Returns the AnimationTrack, or nil when the model has no Humanoid / root or the
--- animation could not load (the model then stays in its rest pose, as before).
function PreviewIdle.Play(model: Model): AnimationTrack?
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not root:IsA("BasePart") then
		return nil
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			d.Anchored = false
		end
	end
	root.Anchored = true
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = hum
		animator = created
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = AnimationRegistry.Assets.Idle
	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if not ok or not result then
		warn(`[PreviewIdle] Could not load the idle animation: {tostring(result)}`)
		return nil
	end
	local track = result :: AnimationTrack
	track.Priority = AnimationRegistry.Priority.Idle
	track.Looped = true
	track:Play(FADE_SEC)
	return track
end

--- Stop and free a track returned by Play. Nil-safe.
function PreviewIdle.Stop(track: AnimationTrack?)
	if track then
		track:Stop(0)
		track:Destroy() -- MEM-002
	end
end

return table.freeze(PreviewIdle)
