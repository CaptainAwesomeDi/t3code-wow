-- Small builders over Blizzard's own templates so everything matches the game UI,
-- or, under the modern design, over flat layers from the theme palette.

local _, ns = ...
local Theme = ns.Theme

local UI = {}
ns.UI = UI

-- Line icons drawn for the modern design.
-- The classic design keeps the game's own atlases and item icons.
local LINE_ICONS = {
	["common-icon-backarrow"] = "chevron-left",
	["common-dropdown-icon-back"] = "chevron-left",
	["common-icon-redx"] = "x",
	["voicechat-icon-mic"] = "mic",
	["voicechat-icon-speaker"] = "speaker",
	["Interface\\Icons\\INV_Misc_Spyglass_03"] = "camera",
	["Interface\\Icons\\INV_Misc_Book_09"] = "book",
	["common-icon-forwardarrow"] = "arrow-right",
	["common-icon-undo"] = "refresh",
	["common-icon-checkmark"] = "check",
	["common-button-list-plus"] = "plus",
	["common-button-list-minus"] = "minus",
}

function UI.LineIcon(name)
	return ns.media .. "icons\\" .. name
end

-- Put a line icon on `tex` when the modern design is on and `icon` is one of the
-- game icons it stands in for. Otherwise leave the game's atlas or texture.
function UI.SetIcon(tex, icon, size)
	local theme = Theme.Get()
	local line = theme and LINE_ICONS[icon]
	if line then
		tex:SetTexture(UI.LineIcon(line))
		tex:SetVertexColor(theme.text[1], theme.text[2], theme.text[3], 1)
		if size then tex:SetSize(size, size) end
		return true
	end
	if icon and C_Texture.GetAtlasInfo(icon) then tex:SetAtlas(icon) else tex:SetTexture(icon) end
	if size then tex:SetSize(size, size) end
end

-- The search box template brings the game's magnifier, and its "Search" hint is
-- drawn from the left edge, so the word sits under the icon.
local SEARCH_INSET = 30

function UI.UseLineSearch(search)
	local theme = Theme.Get()
	if not theme or search.LineIcon then return end
	search.lineInset = SEARCH_INSET
	if search.searchIcon then
		search.searchIcon:Hide()
		search.searchIcon:SetAlpha(0)
	end
	local icon = search:CreateTexture(nil, "OVERLAY")
	icon:SetTexture(UI.LineIcon("search"))
	icon:SetSize(13, 13)
	icon:SetPoint("LEFT", 10, 0)
	icon:SetVertexColor(theme.muted[1], theme.muted[2], theme.muted[3], 1)
	search.LineIcon = icon
	search:SetTextInsets(SEARCH_INSET, 8, 0, 0)
	local hint = search.Instructions
	if hint then
		hint:ClearAllPoints()
		hint:SetPoint("LEFT", SEARCH_INSET, 0)
		hint:SetPoint("RIGHT", -8, 0)
		hint:SetJustifyH("LEFT")
		Theme.SetText(hint, theme.muted)
		if hint.SetDrawLayer then hint:SetDrawLayer("OVERLAY") end
	end
	-- The template's own magnifier is an atlas texture on the box. Ours replaces it.
	for _, region in ipairs({ search:GetRegions() }) do
		if region ~= icon and region ~= hint and region.GetAtlas and region:GetAtlas() then region:Hide() end
	end
	search:HookScript("OnTextChanged", function(box)
		if box.searchIcon then box.searchIcon:Hide() end
	end)
end

-- A thin track and thumb for the modern design. The game's bar is a wide thumb
-- with arrow buttons, and on the settings page it sits on top of the rows.
local function HideBarPiece(w)
	if not w then return end
	w:SetAlpha(0)
	if w.EnableMouse then w:EnableMouse(false) end
end

function UI.StyleScrollBar(bar)
	local theme = Theme.Get()
	if not theme or not bar then return end
	HideBarPiece(bar.Back)
	HideBarPiece(bar.Forward)
	HideBarPiece(bar.ScrollUpButton)
	HideBarPiece(bar.ScrollDownButton)
	if bar.SetWidth then bar:SetWidth(6) end

	local track = bar.Track
	if track then
		track:ClearAllPoints()
		track:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, 0)
		track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 0)
		if not track.Line then
			local bg = track:CreateTexture(nil, "BACKGROUND")
			bg:SetColorTexture(theme.muted[1], theme.muted[2], theme.muted[3], 0.28)
			bg:SetWidth(2)
			bg:SetPoint("TOP", 0, 0)
			bg:SetPoint("BOTTOM", 0, 0)
			track.Line = bg
		end
		local thumb = track.Thumb
		if thumb then
			for _, region in ipairs({ thumb:GetRegions() }) do
				if region ~= thumb.Line and region.SetAlpha then region:SetAlpha(0) end
			end
			if not thumb.Line then
				local t = thumb:CreateTexture(nil, "OVERLAY")
				t:SetColorTexture(theme.muted[1], theme.muted[2], theme.muted[3], 0.95)
				t:SetAllPoints()
				thumb.Line = t
			end
			if thumb.SetWidth then thumb:SetWidth(4) end
		end
	elseif not bar.Line then
		local bg = bar:CreateTexture(nil, "BACKGROUND")
		bg:SetColorTexture(theme.muted[1], theme.muted[2], theme.muted[3], 0.28)
		bg:SetWidth(2)
		bg:SetPoint("TOP", 0, 0)
		bg:SetPoint("BOTTOM", 0, 0)
		bar.Line = bg
		local tex = bar.GetThumbTexture and bar:GetThumbTexture()
		if tex and tex.SetColorTexture then
			tex:SetColorTexture(theme.muted[1], theme.muted[2], theme.muted[3], 0.95)
		end
	end
end

-- The template's bar is a black trough with arrow buttons. The modern pages
-- scroll with the wheel instead, so that bar stays hidden.
function UI.PlaceScrollBar(scroll)
	local bar = scroll and scroll.ScrollBar
	if not bar or not Theme.Get() then return end
	bar:Hide()
	if bar.EnableMouse then bar:EnableMouse(false) end
	bar:HookScript("OnShow", function(self) self:Hide() end)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange() or 0
		local cur = self:GetVerticalScroll() or 0
		local y = cur - (delta or 0) * 48
		if y < 0 then y = 0 elseif y > range then y = range end
		self:SetVerticalScroll(y)
	end)
end

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
		if primary then
			r, g, bl = theme.onAccent[1], theme.onAccent[2], theme.onAccent[3]
			-- GameFontHighlight draws a drop shadow. On the accent fill that shadow
			-- muddies the dark letters, so the face is the same font with it off.
			local path, size = fs:GetFont()
			fs:SetFont(path or "Fonts\\FRIZQT__.TTF", size or 12, "")
			fs:SetShadowOffset(0, 0)
		end
		fs:SetTextColor(r, g, bl)
		-- A disabled button says so in its label, dimmed like the game's own.
		b:SetScript("OnDisable", function() fs:SetTextColor(0.5, 0.5, 0.5) end)
		b:SetScript("OnEnable", function() fs:SetTextColor(r, g, bl) end)
		if not b:IsEnabled() then fs:SetTextColor(0.5, 0.5, 0.5) end
		local hl = Theme.Solid(b, theme.hover, "HIGHLIGHT")
		hl:SetAllPoints()
		-- A press nudges the label down a pixel.
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

-- A pill switch on the right of a CheckButton. The round ends are in the texture:
-- this client draws a mask as a square. Gold when on, dark when off, and the thumb
-- slides. The whole row is the hit target. `Fill` is the thumb.
function UI.PaintSwitch(b)
	local theme = Theme.Get()
	local holder = CreateFrame("Frame", nil, b)
	holder:SetSize(36, 16)
	holder:SetPoint("RIGHT", -12, 0)
	holder:EnableMouse(false) -- the row behind it receives the click
	b.Switch = holder
	local track = holder:CreateTexture(nil, "ARTWORK")
	track:SetAllPoints()
	track:SetTexture(UI.LineIcon("switch-track"))
	local knob = holder:CreateTexture(nil, "OVERLAY")
	knob:SetTexture(UI.LineIcon("switch-knob"))
	knob:SetSize(12, 12)
	knob:SetVertexColor(theme.knob[1], theme.knob[2], theme.knob[3], 1)
	b.Fill = knob
	-- A bare check button would draw the game's yellow tick. Keep the button, hide the tick.
	local blank = b:CreateTexture(nil, "ARTWORK")
	blank:SetColorTexture(0, 0, 0, 0)
	blank:SetAllPoints()
	b:SetCheckedTexture(blank)
	function b:Sync()
		local on = self:GetChecked() and true or false
		local c = on and theme.accent or theme.switchOff
		track:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		self.Fill:ClearAllPoints()
		self.Fill:SetPoint(on and "RIGHT" or "LEFT", holder, on and "RIGHT" or "LEFT", on and -2 or 2, 0)
	end
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
	local line = theme and LINE_ICONS[icon]
	if line then
		-- No button plate: the stroke sits on the window.
		bg:SetColorTexture(0, 0, 0, 0)
		tex:SetTexture(UI.LineIcon(line))
		tex:SetVertexColor(theme.text[1], theme.text[2], theme.text[3], 1)
		tex:SetSize((size or 28) - 6, (size or 28) - 6)
	else
		tex:SetSize((size or 28) - 10, (size or 28) - 10)
		if C_Texture.GetAtlasInfo(icon) then tex:SetAtlas(icon) else tex:SetTexture(icon) end
	end
	b.Icon = tex
	if theme then
		local hl = Theme.Solid(b, theme.hover, "HIGHLIGHT")
		hl:SetAllPoints()
		-- A white line can't be desaturated, so a disabled button dims its stroke.
		b:SetScript("OnDisable", function(self) self.Icon:SetAlpha(0.35) end)
		b:SetScript("OnEnable", function(self) self.Icon:SetAlpha(1) end)
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
	if theme then
		arrow:SetTexture(UI.LineIcon("chevron-down"))
		arrow:SetVertexColor(theme.muted[1], theme.muted[2], theme.muted[3], 1)
		arrow:SetSize(12, 12)
		arrow:SetPoint("RIGHT", -7, 0)
		Theme.Edges(b, theme.hairline)
	else
		arrow:SetAtlas("common-dropdown-a-button")
		arrow:SetSize(22, 22)
		arrow:SetPoint("RIGHT", -3, 0)
	end
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
	UI.UseLineSearch(search)

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
				-- A line check at the right edge of the chosen row.
				row.Check = row:CreateTexture(nil, "ARTWORK")
				row.Check:SetTexture(UI.LineIcon("check"))
				row.Check:SetVertexColor(theme.text[1], theme.text[2], theme.text[3], 1)
				row.Check:SetSize(12, 12)
				row.Check:SetPoint("RIGHT", -8, 0)
				row.Check:Hide()
			else
				row.Check = row:CreateTexture(nil, "ARTWORK")
				row.Check:SetAtlas("common-icon-checkmark")
				row.Check:SetSize(14, 14)
				row.Check:SetPoint("LEFT", 4, 0)
			end
			row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			row.Text:SetPoint("LEFT", theme and 10 or 22, 0)
			row.Text:SetPoint("RIGHT", theme and -24 or -4, 0)
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
		row.Text:SetText(ed.label)
		-- The accent stays on the selection bar. The label stays white.
		if selected and not theme then
			row.Text:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
		else
			row.Text:SetTextColor(1, 1, 1)
		end
		row:SetScript("OnClick", function() UI.PickFromList(ed.value) end)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
	UI.StyleScrollBar(bar)
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

-- A horizontal slider. `value` runs from `min` to `max`. `onChange(value)` fires
-- as it moves. The number at the right is filled in by `format`.
function UI.Slider(parent, width, min, max, step, onChange, format)
	local theme = Theme.Get()
	local b = CreateFrame("Frame", nil, parent)
	b:SetSize(width, 18)
	b:EnableMouse(true)
	b:EnableMouseWheel(true)
	b.min, b.max, b.step = min, max, step or 0
	b.trackW = width - 52
	local track = b:CreateTexture(nil, "BACKGROUND")
	if theme then Theme.Paint(track, theme.track) else track:SetColorTexture(0, 0, 0, 0.55) end
	track:SetSize(b.trackW, 4)
	track:SetPoint("LEFT", 4, 0)
	local fill = b:CreateTexture(nil, "ARTWORK")
	if theme then Theme.Paint(fill, theme.accent) else fill:SetColorTexture(1, 0.82, 0, 1) end
	fill:SetHeight(4)
	fill:SetPoint("LEFT", track, "LEFT", 0, 0)
	local thumb = b:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(8, 14)
	if theme then Theme.Paint(thumb, theme.knob) else thumb:SetColorTexture(1, 0.82, 0, 1) end
	local text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	text:SetPoint("RIGHT", 0, 0)
	text:SetJustifyH("RIGHT")
	if theme then Theme.SetText(text, theme.muted) end
	b.Track, b.Fill, b.Thumb, b.Text = track, fill, thumb, text

	function b:SetValue(value, silent)
		value = math.max(self.min, math.min(self.max, value or self.min))
		if self.step and self.step > 0 then
			value = self.min + math.floor((value - self.min) / self.step + 0.5) * self.step
			value = math.max(self.min, math.min(self.max, value))
		end
		self.value = value
		local span = self.max - self.min
		local t = span == 0 and 0 or (value - self.min) / span
		self.Thumb:ClearAllPoints()
		self.Thumb:SetPoint("CENTER", self.Track, "LEFT", t * self.trackW, 0)
		self.Fill:SetWidth(math.max(1, t * self.trackW))
		self.Text:SetText(format and format(value) or tostring(value))
		if not silent and onChange then onChange(value) end
	end
	function b:GetValue() return self.value end

	local function atCursor(self)
		local scale = self:GetEffectiveScale() or 1
		local x = GetCursorPosition() / scale
		local left = (self:GetLeft() or 0) + 4
		local t = self.trackW > 0 and (x - left) / self.trackW or 0
		if t < 0 then t = 0 elseif t > 1 then t = 1 end
		return self.min + t * (self.max - self.min)
	end
	b:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		self:SetValue(atCursor(self))
		self:SetScript("OnUpdate", function(self)
			if not IsMouseButtonDown("LeftButton") then self:SetScript("OnUpdate", nil) return end
			self:SetValue(atCursor(self))
		end)
	end)
	b:SetScript("OnMouseWheel", function(self, delta)
		local step = (self.step and self.step > 0) and self.step or ((self.max - self.min) / 20)
		self:SetValue((self.value or self.min) + (delta > 0 and step or -step))
	end)
	-- The controller's D-pad: a twentieth of the range a press.
	function b:PadStep(dir)
		local step = math.max(self.step or 0, (self.max - self.min) / 20)
		self:SetValue((self.value or self.min) + dir * step)
	end
	b:SetValue(min, true)
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
	local mark = collapsed and "common-button-list-plus" or "common-button-list-minus"
	if not UI.SetIcon(button.Icon, mark, 12) then button.Icon:SetAtlas(mark, true) end
end

function UI.ProgressBar(parent)
	local theme = Theme.Get()
	local holder
	if theme then
		holder = CreateFrame("Frame", nil, parent)
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
	local barParent = holder
	local text
	if theme then
		-- A solid track with the fill the same height, and the percent beside it.
		-- A hairline with the number on top looks empty until the fill is almost full.
		text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("RIGHT", 0, 0)
		local track = CreateFrame("Frame", nil, holder)
		track:SetHeight(8)
		track:SetPoint("LEFT", 0, 0)
		track:SetPoint("RIGHT", text, "LEFT", -10, 0)
		local bg = Theme.Solid(track, theme.panelAlt)
		bg:SetAllPoints()
		barParent = track
	end
	local bar = CreateFrame("StatusBar", nil, barParent)
	if theme then
		bar:SetAllPoints()
	else
		bar:SetPoint("TOPLEFT", 4, -4)
		bar:SetPoint("BOTTOMRIGHT", -4, 4)
	end
	bar:SetStatusBarTexture(theme and "Interface\\Buttons\\WHITE8X8" or "Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(0.1, 0.7, 0.15)
	bar:SetMinMaxValues(0, 100)
	if not text then
		-- The bar is its own frame, so it paints over the holder's text. A frame above it
		-- keeps the percent readable.
		local label = CreateFrame("Frame", nil, holder)
		label:SetAllPoints()
		label:EnableMouse(false)
		label:SetFrameLevel(bar:GetFrameLevel() + 2)
		text = label:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("CENTER")
	end
	holder.Bar, holder.Text = bar, text
	function holder:SetPercent(p)
		p = math.max(0, math.min(100, p or 0))
		bar:SetValue(p)
		if p >= 90 then bar:SetStatusBarColor(0.8, 0.15, 0.1)
		elseif p >= 70 then bar:SetStatusBarColor(0.85, 0.6, 0.1)
		elseif theme then bar:SetStatusBarColor(theme.accent[1], theme.accent[2], theme.accent[3])
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
