-- The two looks the window can wear. "classic" is Blizzard's own ornate templates,
-- used exactly as the game draws them. "modern" is a flat, dark design drawn
-- entirely in code: a dark ground, hairline
-- borders, square corners, near-white titles, muted explanations, and a single
-- accent that marks only what is selected or on. Every modern surface is a
-- plain colored texture, so no art ships and nothing depends on an atlas resolving.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

-- `accent` as WoW font markup. Headings and the bridge's markdown use the game's
-- gold (|cffffd100); in this window that gold means the accent.
Theme.ACCENT_HEX = "ff7fd2b3"

-- The colors Settings offers. Verdigris is the default. Each rgb is the fill
-- (Start, selection bars, switches) and hex is the same color in font markup.
Theme.ACCENTS = {
	{ value = "verdigris", label = "Verdigris", rgb = { 0.498, 0.824, 0.702, 1.00 }, hex = "ff7fd2b3" },
	{ value = "ice", label = "Ice", rgb = { 0.455, 0.776, 0.871, 1.00 }, hex = "ff74c6de" },
	{ value = "copper", label = "Copper", rgb = { 0.894, 0.690, 0.541, 1.00 }, hex = "ffe4b08a" },
	{ value = "gold", label = "Gold", rgb = { 0.902, 0.729, 0.400, 1.00 }, hex = "ffe6ba66" },
}

-- Dusk ground. Notices use this color and opacity. The window paints the
-- same navy flat, so the title isn't a see-through strip. Night was darker.
Theme.MODERN = {
	windowBg = { 0.095, 0.115, 0.178, 0.94 }, -- dusk bg, the world shows through
	panel =    { 0.110, 0.133, 0.203, 0.98 }, -- cards and the composer
	panelAlt = { 0.139, 0.166, 0.249, 1.00 }, -- buttons and dropdowns
	overlay =  { 0.055, 0.071, 0.110, 1.00 }, -- #0e1220 popups over everything
	hairline = { 1.000, 1.000, 1.000, 0.10 }, -- borders and rules
	hover =    { 1.000, 1.000, 1.000, 0.07 }, -- a row under the mouse
	selected = { 1.000, 1.000, 1.000, 0.12 }, -- the chosen row
	accent =   { 0.498, 0.824, 0.702, 1.00 }, -- #7fd2b3 verdigris, until a choice is applied
	onAccent = { 0.039, 0.051, 0.086, 1.00 }, -- the ground, on an accent fill
	track =    { 0.000, 0.000, 0.000, 0.40 }, -- the empty part of a progress bar
	text =     { 0.929, 0.937, 0.953, 1.00 }, -- titles and setting names
	muted =    { 0.620, 0.663, 0.753, 1.00 }, -- the line under a title
	knob =     { 0.965, 0.953, 0.910, 1.00 }, -- the thumb of a switch
	switchOff = { 0.071, 0.086, 0.133, 1.00 }, -- the track of a switch that is off
}

-- Copy the chosen accent onto the palette. An unknown id uses verdigris.
function Theme.UseAccent(id)
	local pick = Theme.ACCENTS[1]
	for _, a in ipairs(Theme.ACCENTS) do
		if a.value == id then pick = a break end
	end
	local dst = Theme.MODERN.accent
	dst[1], dst[2], dst[3], dst[4] = pick.rgb[1], pick.rgb[2], pick.rgb[3], pick.rgb[4] or 1
	Theme.ACCENT_HEX = pick.hex
	return pick
end

-- The palette for the chosen design; nil means the game's own templates.
function Theme.Get()
	if ns.db and ns.db.settings.theme == "modern" then
		Theme.UseAccent(ns.db.settings.accent)
		return Theme.MODERN
	end
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

-- Blizzard gold inside a string the window is about to draw. Left alone on the
-- classic look, where that gold matches the game's frames.
function Theme.Markup(text)
	if not text or not Theme.Get() then return text end
	return (text:gsub("|c" .. ns.COLORS.gold, "|c" .. Theme.ACCENT_HEX))
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
