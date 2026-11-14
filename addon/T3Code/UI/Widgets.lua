-- Small builders over Blizzard's own templates so everything matches the game UI,
-- or, under the modern design, over flat layers from the theme palette.

local _, ns = ...
local Theme = ns.Theme

local UI = {}
ns.UI = UI

function UI.Tooltip(owner, title, body)
	owner:HookScript("OnEnter", function(self)
		local tip = GetAppropriateTooltip and GetAppropriateTooltip() or GameTooltip
		tip:SetOwner(self, "ANCHOR_TOP")
		local t = type(title) == "function" and title(self) or title
		tip:SetText(t or "", 1, 0.82, 0)
		local b = type(body) == "function" and body(self) or body
		if b then tip:AddLine(b, 1, 1, 1, true) end
		tip:Show()
	end)
	owner:HookScript("OnLeave", function()
		local tip = GetAppropriateTooltip and GetAppropriateTooltip() or GameTooltip
		tip:Hide()
	end)
end

function UI.Button(parent, text, width, onClick, primary)
	local theme = Theme.Get()
	if theme then
		local b = CreateFrame("Button", nil, parent)
		b:SetSize(width or 110, 24)
		local bg = Theme.Solid(b, primary and theme.accent or theme.panelAlt)
		bg:SetAllPoints()
		Theme.Edges(b, theme.hairline)
		local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		b:SetFontString(fs)
		b:SetText(text)
		local r, g, bl = 1, 1, 1
		if primary then r, g, bl = theme.onAccent[1], theme.onAccent[2], theme.onAccent[3] end
		fs:SetTextColor(r, g, bl)
		-- A disabled button says so in its label, dimmed like the game's own.
		b:SetScript("OnDisable", function() fs:SetTextColor(0.5, 0.5, 0.5) end)
		b:SetScript("OnEnable", function() fs:SetTextColor(r, g, bl) end)
		if not b:IsEnabled() then fs:SetTextColor(0.5, 0.5, 0.5) end
		local hl = Theme.Solid(b, theme.hover, "HIGHLIGHT")
		hl:SetAllPoints()
		-- A press nudges the label down a pixel, as Polestar's buttons do.
		b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then fs:AdjustPointsOffset(0, -1) end end)
		b:SetScript("OnMouseUp", function(self) if self:IsEnabled() then fs:AdjustPointsOffset(0, 1) end end)
		if onClick then b:SetScript("OnClick", onClick) end
		return b
	end
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 110, 22)
	b:SetText(text)
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

-- A square button showing an atlas or texture, like the chat frame's small buttons.
function UI.IconButton(parent, icon, size, tooltip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size or 28, size or 28)
	-- A disabled icon still needs its tooltip to explain why; the client skips
	-- motion scripts on disabled buttons unless asked to keep them.
	b:SetMotionScriptsWhileDisabled(true)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	local theme = Theme.Get()
	if theme then
		Theme.Paint(bg, theme.panelAlt)
	else
		bg:SetAtlas("common-button-square-gray-up")
		if not bg:GetAtlas() then
			bg:SetTexture("Interface\\Buttons\\UI-Quickslot2")
			bg:SetTexCoord(0.18, 0.82, 0.18, 0.82)
		end
	end
	bg:SetAllPoints()
	b.Background = bg
	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("CENTER")
	tex:SetSize((size or 28) - 10, (size or 28) - 10)
	if C_Texture.GetAtlasInfo(icon) then tex:SetAtlas(icon) else tex:SetTexture(icon) end
	b.Icon = tex
	if theme then
		local hl = Theme.Solid(b, theme.hover, "HIGHLIGHT")
		hl:SetAllPoints()
	else
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	end
	b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.Icon:AdjustPointsOffset(1, -1) end end)
	b:SetScript("OnMouseUp", function(self) if self:IsEnabled() then self.Icon:AdjustPointsOffset(-1, 1) end end)
	if tooltip then UI.Tooltip(b, tooltip) end
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

-- A selector that looks like the game's dropdown but just steps through choices:
-- click (or A on a controller) for the next one, right-click or wheel to go back.
-- It deliberately avoids Blizzard's menu system: menus built by an addon taint the
-- gamepad UI's menu handling and get "blocked from an action" errors.
function UI.Cycler(parent, width, onChange)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 220, 26)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local theme = Theme.Get()
	local bg = b:CreateTexture(nil, "BACKGROUND")
	if theme then
		Theme.Paint(bg, theme.panelAlt)
	else
		bg:SetAtlas("common-dropdown-textholder")
	end
	bg:SetAllPoints()
	if not theme and not bg:GetAtlas() then
		bg:SetColorTexture(0, 0, 0, 0.6)
	end
	local arrow = b:CreateTexture(nil, "ARTWORK")
	arrow:SetAtlas("common-dropdown-a-button")
	arrow:SetSize(22, 22)
	arrow:SetPoint("RIGHT", -3, 0)
	b.Arrow = arrow
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	if theme then
		Theme.Paint(hl, theme.hover)
	else
		hl:SetAtlas("common-dropdown-textholder")
		hl:SetBlendMode("ADD")
		hl:SetAlpha(0.25)
	end
	hl:SetAllPoints()
	local text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	text:SetPoint("LEFT", 10, 0)
	text:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	b.Text = text
	b.options = {}

	function b:SetOptions(options, value)
		self.options = options
		if value ~= nil then self.value = value end
		self:Update()
	end
	-- Options are { value, label, text? }: `text` is what the button shows when it
	-- differs from the list row. Rows with `header` set only title a group.
	function b:Update()
		local label, first
		for _, o in ipairs(self.options) do
			if not o.header then
				first = first or o
				if o.value == self.value then label = o.text or o.label end
			end
		end
		self.Text:SetText(label or (first and (first.text or first.label)) or "")
	end
	function b:Step(delta)
		local choices = {}
		for _, o in ipairs(self.options) do if not o.header then table.insert(choices, o) end end
		local n = #choices
		if n == 0 then return end
		local current = 0
		for i, o in ipairs(choices) do if o.value == self.value then current = i end end
		local nextIndex = ((current - 1 + delta) % n) + 1
		if current == 0 then nextIndex = delta > 0 and 1 or n end
		self.value = choices[nextIndex].value
		self:Update()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		if onChange then onChange(self.value) end
	end
	b:SetScript("OnClick", function(self, button) self:Step(button == "RightButton" and -1 or 1) end)
	b:EnableMouseWheel(true)
	b:SetScript("OnMouseWheel", function(self, delta) self:Step(delta > 0 and -1 or 1) end)
	UI.Tooltip(b, function(self) return self.Text:GetText() end, function(self) return self.tipBody or "Click to choose. Scroll to step through." end)
	return b
end

---------------------------------------------------------------------------
-- Dropdown: the selector above, but a click opens a scrollable list (with a
-- search box when it's long). Built from plain frames and Blizzard's dropdown art
-- rather than the Menu system, which addons can't drive under the gamepad UI
-- without "blocked action" errors.

local list -- one shared popup
local listed -- UISpecialFrames only wants the name once, across rebuilds

local ROW_H = 22
local MAX_ROWS = 14

local function EnsureList()
	if list then return list end
	list = CreateFrame("Frame", "T3CodeDropdownList", UIParent)
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	list:SetToplevel(true)
	list:EnableMouse(true)
	list:SetClampedToScreen(true)
	list:Hide()
	local theme = Theme.Get()
	local bg = list:CreateTexture(nil, "BACKGROUND")
	if theme then
		Theme.Paint(bg, theme.overlay)
		bg:SetAllPoints()
		Theme.Edges(list, theme.hairline)
	else
		bg:SetAtlas("common-dropdown-bg")
		bg:SetPoint("TOPLEFT", -10, 3)
		bg:SetPoint("BOTTOMRIGHT", 10, -3)
		bg:SetAlpha(0.95)
		if not bg:GetAtlas() then bg:SetColorTexture(0.05, 0.05, 0.05, 0.95) end
	end

	local search = CreateFrame("EditBox", nil, list, "SearchBoxTemplate")
	search:SetHeight(20)
	search:SetPoint("TOPLEFT", 12, -8)
	search:SetPoint("TOPRIGHT", -8, -8)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function() UI.RefreshList() end)
	search:HookScript("OnEscapePressed", function() list:Hide() end)
	search:HookScript("OnEnterPressed", function()
		for _, o in ipairs(list.filtered or {}) do
			if not o.header then return UI.PickFromList(o.value) end
		end
	end)
	list.Search = search

	local box = CreateFrame("Frame", nil, list, "WowScrollBoxList")
	local bar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
	local view = CreateScrollBoxListLinearView(0, 0, 0, 0, 0)
	view:SetElementExtent(ROW_H)
	view:SetElementInitializer("T3CodeDropdownRowTemplate", function(row, ed)
		if not row.Text then
			row:SetHeight(ROW_H)
			local hl = row:CreateTexture(nil, "HIGHLIGHT")
			if theme then
				Theme.Paint(hl, theme.hover)
			else
				hl:SetAtlas("Options_List_Hover")
				hl:SetAlpha(0.6)
			end
			hl:SetAllPoints()
			if theme then
				-- The chosen row carries a gold bar down its left edge.
				row.Bar = row:CreateTexture(nil, "ARTWORK")
				Theme.Paint(row.Bar, theme.accent)
				row.Bar:SetWidth(2)
				row.Bar:SetPoint("TOPLEFT")
				row.Bar:SetPoint("BOTTOMLEFT")
				row.Bar:Hide()
			else
				row.Check = row:CreateTexture(nil, "ARTWORK")
				row.Check:SetAtlas("common-icon-checkmark")
				row.Check:SetSize(14, 14)
				row.Check:SetPoint("LEFT", 4, 0)
			end
			row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			row.Text:SetPoint("LEFT", theme and 10 or 22, 0)
			row.Text:SetPoint("RIGHT", -4, 0)
			row.Text:SetJustifyH("LEFT")
			row.Text:SetWordWrap(false)
		end
		if ed.header then
			-- A group title: gold in the game's look, quiet grey in the modern one.
			if row.Check then row.Check:Hide() end
			row.Text:SetPoint("LEFT", 6, 0)
			row.Text:SetText(ed.label)
			if theme then
				row.Text:SetTextColor(0.65, 0.68, 0.75)
			else
				row.Text:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
			end
			row:EnableMouse(false)
			row:SetScript("OnClick", nil)
			return
		end
		row:EnableMouse(true)
		row.Text:SetPoint("LEFT", theme and 10 or 22, 0)
		local selected = list.owner and list.owner.value == ed.value
		if row.Check then row.Check:SetShown(selected) end
		if row.Bar then row.Bar:SetShown(selected) end
		row.Text:SetText(ed.label)
		if selected then
			if theme then
				row.Text:SetTextColor(theme.accent[1], theme.accent[2], theme.accent[3])
			else
				row.Text:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
			end
		else
			row.Text:SetTextColor(1, 1, 1)
		end
		row:SetScript("OnClick", function() UI.PickFromList(ed.value) end)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
	list.Box, list.Bar = box, bar

	if not listed then
		tinsert(UISpecialFrames, "T3CodeDropdownList")
		listed = true
	end
	-- Close on a click anywhere else.
	list:SetScript("OnUpdate", function(self)
		if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
			and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
			self:Hide()
		end
		if self.owner and not self.owner:IsVisible() then self:Hide() end
	end)
	list:SetScript("OnHide", function(self)
		self.Search:SetText("")
		self.Search:ClearFocus()
		ns:Fire("DropdownClosed", self.owner)
	end)
	return list
end

function UI.RefreshList()
	local l = EnsureList()
	local owner = l.owner
	if not owner then return end
	local query = (l.Search:GetText() or ""):lower()
	local filtered, choices = {}, 0
	local header -- the group title waiting for its first matching row
	local function matches(text) return text and text:lower():find(query, 1, true) end
	for _, o in ipairs(owner.options) do
		if o.header then
			header = o
		else
			choices = choices + 1
			-- A row matches on its own text or its group's (a provider's name, say).
			if query == "" or matches(o.label) or matches(o.group) then
				if header then
					table.insert(filtered, header)
					header = nil
				end
				table.insert(filtered, o)
			end
		end
	end
	l.filtered = filtered
	local showSearch = choices > 10
	l.Search:SetShown(showSearch)
	local top = showSearch and -34 or -8
	local rows = math.min(MAX_ROWS, math.max(1, #filtered))
	l:SetSize(math.max(owner:GetWidth(), owner.listWidth or 220), -top + rows * ROW_H + 10)
	l.Box:ClearAllPoints()
	l.Box:SetPoint("TOPLEFT", 6, top)
	l.Box:SetPoint("BOTTOMRIGHT", #filtered > MAX_ROWS and -20 or -6, 8)
	l.Bar:ClearAllPoints()
	l.Bar:SetPoint("TOPLEFT", l.Box, "TOPRIGHT", 4, 0)
	l.Bar:SetPoint("BOTTOMLEFT", l.Box, "BOTTOMRIGHT", 4, 0)
	l.Bar:SetShown(#filtered > MAX_ROWS)
	l.Box:SetDataProvider(CreateDataProvider(filtered), ScrollBoxConstants.RetainScrollPosition)
end

function UI.PickFromList(value)
	local l = EnsureList()
	local owner = l.owner
	l:Hide()
	if not owner then return end
	owner.value = value
	owner:Update()
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	if owner.onChange then owner.onChange(value) end
end

function UI.OpenList(owner)
	local l = EnsureList()
	if l:IsShown() and l.owner == owner then
		l:Hide()
		return
	end
	l.owner = owner
	l:ClearAllPoints()
	if owner.listAbove then
		l:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
	elseif owner.listAlignRight then
		l:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
	else
		l:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	end
	l:Show()
	l.Search:SetText("")
	UI.RefreshList()
	-- Start scrolled to the current choice.
	for i, o in ipairs(l.filtered) do
		if o.value == owner.value then
			l.Box:ScrollToElementDataIndex(i, ScrollBoxConstants.AlignCenter, nil, true)
			break
		end
	end
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	ns:Fire("DropdownOpened", l)
end

function UI.ListOpen()
	return list and list:IsShown() and list or nil
end

-- Drop the shared popup so the next open builds it under the current design.
function UI.ResetList()
	if not list then return end
	list:Hide()
	list = nil
end

function UI.Dropdown(parent, width, onChange)
	local b = UI.Cycler(parent, width, onChange)
	b.onChange = onChange
	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then self:Step(-1) else UI.OpenList(self) end
	end)
	return b
end

function UI.Inset(parent)
	local theme = Theme.Get()
	if theme then
		local f = CreateFrame("Frame", nil, parent)
		local bg = Theme.Solid(f, theme.panel)
		bg:SetAllPoints()
		Theme.Edges(f, theme.hairline)
		return f
	end
	local f = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
	return f
end

function UI.Text(parent, font, justify, layer)
	local fs = parent:CreateFontString(nil, layer or "ARTWORK", font or "GameFontHighlight")
	fs:SetJustifyH(justify or "LEFT")
	return fs
end

-- Collapsible group header ("Working (1)").
function UI.InitGroupHeader(button)
	if button.created then return end
	button.created = true
	button:SetHeight(26)
	local theme = Theme.Get()
	if theme then
		-- No plate: just a hairline under the group's rows.
		local rule = Theme.Solid(button, theme.hairline)
		rule:SetHeight(1)
		rule:SetPoint("BOTTOMLEFT", 4, 2)
		rule:SetPoint("BOTTOMRIGHT", -4, 2)
	else
		local bg = button:CreateTexture(nil, "BACKGROUND")
		bg:SetAtlas("common-button-list-collapseExpand")
		bg:SetAllPoints()
	end
	local hl = button:CreateTexture(nil, "HIGHLIGHT")
	if theme then
		Theme.Paint(hl, theme.hover)
	else
		hl:SetAtlas("common-button-list-collapseExpand")
		hl:SetBlendMode("ADD")
		hl:SetAlpha(0.35)
	end
	hl:SetAllPoints()
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("LEFT", 10, 0)
	button.Icon = icon
	local text = button:CreateFontString(nil, "ARTWORK", "Game15Font_Shadow")
	text:SetPoint("CENTER", 6, 0)
	text:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
	button.Text = text
end

function UI.SetGroupHeader(button, label, count, collapsed)
	button.Text:SetText(string.format("%s  |cff9d9d9d(%d)|r", label, count))
	button.Icon:SetAtlas(collapsed and "common-button-list-plus" or "common-button-list-minus", true)
end

function UI.ProgressBar(parent)
	local theme = Theme.Get()
	local holder
	if theme then
		holder = CreateFrame("Frame", nil, parent)
		local bg = Theme.Solid(holder, theme.track)
		bg:SetAllPoints()
		Theme.Edges(holder, theme.hairline)
	else
		holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
		holder:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		holder:SetBackdropColor(0, 0, 0, 0.75)
		holder:SetBackdropBorderColor(0.75, 0.6, 0.3, 1)
	end
	local bar = CreateFrame("StatusBar", nil, holder)
	bar:SetPoint("TOPLEFT", 4, -4)
	bar:SetPoint("BOTTOMRIGHT", -4, 4)
	bar:SetStatusBarTexture(theme and "Interface\\Buttons\\WHITE8X8" or "Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(0.1, 0.7, 0.15)
	bar:SetMinMaxValues(0, 100)
	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	holder.Bar, holder.Text = bar, text
	function holder:SetPercent(p)
		p = math.max(0, math.min(100, p or 0))
		bar:SetValue(p)
		if p >= 90 then bar:SetStatusBarColor(0.8, 0.15, 0.1)
		elseif p >= 70 then bar:SetStatusBarColor(0.85, 0.6, 0.1)
		else bar:SetStatusBarColor(0.1, 0.7, 0.15) end
		text:SetText(string.format("%d%% used", p))
	end
	return holder
end

---------------------------------------------------------------------------
-- Gamepad glyphs ("|A:...|a" markup for the active controller's face buttons)

local GLYPHS = {
	letters = { PAD1 = "gamepad-xbox1-buttona-normal", PAD2 = "gamepad-xbox1-buttonb-normal", PAD3 = "gamepad-xbox1-buttonx-normal", PAD4 = "gamepad-xbox1-buttony-normal" },
	shapes = { PAD1 = "gamepad-ps-buttoncrox-normal", PAD2 = "gamepad-ps-buttoncircle-normal", PAD3 = "gamepad-ps-buttonsquare-normal", PAD4 = "gamepad-ps-buttontriangle-normal" },
	reverse = { PAD1 = "gamepad-switch-128x-face-b-normal", PAD2 = "gamepad-switch-128x-face-a-normal", PAD3 = "gamepad-switch-128x-face-y-normal", PAD4 = "gamepad-switch-128x-face-x-normal" },
}

local function LabelStyle()
	if not C_GamePad or not C_GamePad.GetActiveDeviceID then return "letters" end
	local id = C_GamePad.GetActiveDeviceID()
	local state = id and C_GamePad.GetDeviceMappedState(id)
	local style = state and state.labelStyle and tostring(state.labelStyle):lower() or ""
	if style:find("shape") then return "shapes" end
	if style:find("reverse") then return "reverse" end
	return "letters"
end

-- Any controller button (PADBACK, PADLTRIGGER, ...) as the game's own icon in the
-- active controller's style: Blizzard defines KEY_ABBR_<button> (generic) plus
-- _LTR (letters), _SHP (shapes) and _REV (reversed) variants.
local STYLE_SUFFIX = { letters = "_LTR", shapes = "_SHP", reverse = "_REV" }
function UI.ButtonIcon(button)
	return _G["KEY_ABBR_" .. button .. (STYLE_SUFFIX[LabelStyle()] or "")] or _G["KEY_ABBR_" .. button]
end

function UI.Glyph(key, size)
	size = size or 16
	local atlas
	if InputIconTextureSetUtility and InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture then
		local ok, a = pcall(InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture, key)
		if ok and type(a) == "string" then atlas = a end
	end
	atlas = atlas or (GLYPHS[LabelStyle()] or GLYPHS.letters)[key]
	if not atlas then return "" end
	return CreateAtlasMarkup(atlas, size, size)
end
