-- The two looks the window can wear. "classic" is Blizzard's own ornate templates,
-- used exactly as the game draws them. "modern" is a flat, dark design drawn
-- entirely in code, after Polestar (fitzforge/polestar): a dark ground, hairline
-- borders, square corners, near-white titles, muted explanations, and a single
-- gold accent that marks only what is selected or on. Every modern surface is a
-- plain colored texture, so no art ships and nothing depends on an atlas resolving.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

-- Polestar's Dusk neutrals with Polestar's own honey gold, which sits quieter on
-- the dark ground than the game's saturated yellow.
Theme.MODERN = {
	windowBg = { 0.039, 0.051, 0.086, 1.00 }, -- #0a0d16 the window's ground
	panel =    { 0.110, 0.133, 0.204, 1.00 }, -- #1c2234 insets, the composer
	panelAlt = { 0.137, 0.165, 0.247, 1.00 }, -- #232a3f buttons and dropdowns
	overlay =  { 0.055, 0.071, 0.110, 1.00 }, -- #0e1220 popups over everything
	hairline = { 1.000, 1.000, 1.000, 0.10 }, -- borders and rules
	hover =    { 1.000, 1.000, 1.000, 0.07 }, -- a row under the mouse
	selected = { 1.000, 1.000, 1.000, 0.12 }, -- the chosen row
	accent =   { 0.902, 0.729, 0.400, 1.00 }, -- #e6ba66 Polestar's gold
	onAccent = { 0.039, 0.051, 0.086, 1.00 }, -- the ground, on a gold fill
	track =    { 0.000, 0.000, 0.000, 0.40 }, -- the empty part of a progress bar
	text =     { 0.929, 0.937, 0.953, 1.00 }, -- titles and setting names
	muted =    { 0.620, 0.663, 0.753, 1.00 }, -- the line under a title
	knob =     { 0.965, 0.953, 0.910, 1.00 }, -- the thumb of a switch
	switchOff = { 0.071, 0.086, 0.133, 1.00 }, -- the track of a switch that is off
}

-- The palette for the chosen design; nil means the game's own templates.
function Theme.Get()
	if ns.db and ns.db.settings.theme == "modern" then return Theme.MODERN end
end

-- Paint a texture flat with a palette color.
function Theme.Paint(tex, token)
	tex:SetColorTexture(token[1], token[2], token[3], token[4] or 1)
	return tex
end

-- The same palette color on a font string.
function Theme.SetText(fs, token)
	fs:SetTextColor(token[1], token[2], token[3], token[4] or 1)
	return fs
end

-- A flat colored layer; the caller anchors it.
function Theme.Solid(parent, token, layer)
	return Theme.Paint(parent:CreateTexture(nil, layer or "BACKGROUND"), token)
end

-- Four 1px rules around the parent's edge: a border that stays crisp at any
-- window scale, without any art. `skipLeft` drops the left rule, for a tab that
-- grows out of the border it attaches to.
function Theme.Edges(parent, token, skipLeft)
	local function rule(vertical)
		local t = parent:CreateTexture(nil, "ARTWORK")
		Theme.Paint(t, token)
		if vertical then t:SetWidth(1) else t:SetHeight(1) end
		return t
	end
	local top, bottom = rule(false), rule(false)
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	local left
	if not skipLeft then
		left = rule(true)
		left:SetPoint("TOPLEFT")
		left:SetPoint("BOTTOMLEFT")
	end
	local right = rule(true)
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	return top, bottom, left, right
end
