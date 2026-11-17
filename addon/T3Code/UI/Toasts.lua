-- Notices when a thread finishes or needs you: a small gold-bordered toast at the
-- top of the screen, or a dusk card under the modern design. A sound, a chat line,
-- and optionally the reply read aloud.

local _, ns = ...
local Theme = ns.Theme

local N = {}
ns.Toasts = N

local MAX = 3
local WIDTH = 380
local TEXT_W = WIDTH - 62 - 16
local LIFETIME = 7

local function Sound(kind)
	if not ns.db.settings.sounds then return end
	local id
	if kind == "input" then id = SOUNDKIT.READY_CHECK
	elseif kind == "failed" then id = SOUNDKIT.IG_QUEST_FAILED or SOUNDKIT.RAID_WARNING
	else id = SOUNDKIT.IG_QUEST_LIST_COMPLETE end
	if id then PlaySound(id, "Master") end
end

local function Flat(fs, size)
	local font, cur = fs:GetFont()
	fs:SetFont(font or "Fonts\\FRIZQT__.TTF", size or cur or 12, "")
	fs:SetShadowOffset(0, 0)
end

local function Ink(token, text)
	local function byte(n) return math.floor((n or 1) * 255 + 0.5) end
	return string.format("|cff%02x%02x%02x%s|r", byte(token[1]), byte(token[2]), byte(token[3]), text)
end

-- The border treatment for the current design. The frames live in a pool, so a
-- design switch re-styles the ones already made.
local function StyleToast(f)
	local theme = Theme.Get()
	if theme then
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
		-- The same dusk ground as the window, so the world shows through.
		f:SetBackdropColor(theme.windowBg[1], theme.windowBg[2], theme.windowBg[3], theme.windowBg[4])
		if not f.Bar then
			f.Bar = f:CreateTexture(nil, "ARTWORK")
			f.Bar:SetWidth(3)
			f.Bar:SetPoint("TOPLEFT")
			f.Bar:SetPoint("BOTTOMLEFT")
		end
		Theme.Paint(f.Bar, theme.accent)
		f.Bar:Show()
		if not f.Edge then
			local top, bottom, _, right = Theme.Edges(f, theme.hairline, true)
			f.Edge = { top, bottom, right }
		end
		for _, edge in ipairs(f.Edge) do edge:Show() end
		Flat(f.Title, 13)
		Theme.SetText(f.Title, theme.accent)
		Flat(f.Text, 11)
	else
		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
			tile = true, tileSize = 32, edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 },
		})
		if f.Bar then f.Bar:Hide() end
		if f.Edge then for _, edge in ipairs(f.Edge) do edge:Hide() end end
		f.Title:SetFontObject("GameFontNormal")
		f.Text:SetFontObject("GameFontHighlightSmall")
		f.Title:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
		f.Title:SetShadowOffset(1, -1)
		f.Text:SetShadowOffset(1, -1)
	end
end

local function Fill(f, t, kind)
	f.payload, f.kind = t, kind
	f.Title:SetText(t.title)
	local theme = Theme.Get()
	if theme then
		local word = ({ input = "Needs you", plan = "Plan ready", failed = "Failed", open = "Finished" })[kind] or ""
		local mark = (kind == "input" or kind == "plan") and theme.accent or (kind == "failed" and { 0.90, 0.35, 0.32 } or theme.muted)
		local line = Ink(mark, word) .. Ink(theme.muted, "  ·  " .. ns.Store:ProjectName(t.p))
		if t.last then line = line .. "\n" .. Ink(theme.text, t.last) end
		f.Text:SetText(line)
	else
		local headline = ({ input = ns.Color("orange", "Needs you"), plan = ns.Color("orange", "Plan ready"),
			failed = ns.Color("red", "Failed"), open = ns.Color("green", "Finished") })[kind] or ""
		f.Text:SetText(headline .. ns.Color("grey", "  ·  " .. ns.Store:ProjectName(t.p)) .. (t.last and ("\n" .. t.last) or ""))
	end
end

local function CreateToast(i)
	local f = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
	f:SetSize(WIDTH, 64)
	f:SetFrameStrata("DIALOG")
	f.Icon = f:CreateTexture(nil, "ARTWORK")
	f.Icon:SetSize(40, 40)
	f.Icon:SetPoint("TOPLEFT", 12, -12)
	f.Icon:SetTexture(ns.media .. "portrait")
	f.Title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.Title:SetPoint("TOPLEFT", f.Icon, "TOPRIGHT", 10, -2)
	f.Title:SetWidth(TEXT_W)
	f.Title:SetJustifyH("LEFT")
	f.Title:SetWordWrap(false)
	f.Text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.Text:SetPoint("TOPLEFT", f.Title, "BOTTOMLEFT", 0, -4)
	f.Text:SetJustifyH("LEFT")
	f.Text:SetMaxLines(4)
	f.Text:SetWidth(TEXT_W)
	f.Text:SetWordWrap(true)
	StyleToast(f)
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f:SetScript("OnClick", function(self, button)
		if button == "LeftButton" and self.threadId then ns.Main:SelectThread(self.threadId, { show = true }) end
		self:Hide()
	end)
	f.fade = f:CreateAnimationGroup()
	local a = f.fade:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0)
	a:SetDuration(0.6)
	f.fade:SetScript("OnFinished", function() f:Hide() end)
	f:SetScript("OnHide", function() N:Layout() end)
	f:Hide()
	return f
end

N.frames = {}

-- Restyle the pooled notices after a design switch.
function N:ApplyTheme()
	for _, f in ipairs(self.frames) do
		StyleToast(f)
		if f.payload then Fill(f, f.payload, f.kind) end
	end
end

-- The newest notice still on screen, so a shortcut press can open its thread.
function N:VisibleThread()
	local newest
	for _, f in ipairs(self.frames) do
		if f:IsShown() and f.threadId and (not newest or (f.shownAt or 0) > (newest.shownAt or 0)) then newest = f end
	end
	return newest and newest.threadId
end

function N:Layout()
	local y = -120
	for _, f in ipairs(self.frames) do
		if f:IsShown() then
			f:ClearAllPoints()
			f:SetPoint("TOP", UIParent, "TOP", 0, y)
			y = y - f:GetHeight() - 6
		end
	end
end

function N:Show(t, kind)
	local f
	for i = 1, MAX do
		self.frames[i] = self.frames[i] or CreateToast(i)
		if not self.frames[i]:IsShown() then
			f = self.frames[i]
			break
		end
	end
	f = f or self.frames[1]
	f.threadId = t.id
	f.shownAt = GetTime()
	StyleToast(f)
	Fill(f, t, kind)
	-- Grow the frame to fit the text (up to four lines of the reply).
	local h = 14 + f.Title:GetStringHeight() + 4 + f.Text:GetStringHeight() + 14
	f:SetHeight(math.max(64, math.ceil(h)))
	f.fade:Stop()
	f:SetAlpha(1)
	f:Show()
	self:Layout()
	if f.timer then f.timer:Cancel() end
	f.timer = C_Timer.NewTimer(LIFETIME, function() if f:IsShown() then f.fade:Play() end end)
end

-- A sample of the popup, so Settings can show the current design without waiting
-- for a thread to finish.
function N:Preview()
	local t = ns.viewId and ns.Store:Thread(ns.viewId)
	local projects = ns.Store.data.projects or {}
	self:Show({
		id = t and t.id or "preview",
		title = t and t.title or "A thread finished",
		p = t and t.p or (projects[1] and projects[1].id),
		last = (t and t.last) or "This is how a notice looks.",
	}, "open")
end

local VERBS = { input = "needs your input", plan = "has a plan ready", failed = "failed", open = "finished" }

N.held = {}

local function Notify(t, kind, quietSound)
	local s = ns.db.settings
	if not quietSound then Sound(kind) end
	local viewing = ns.windowOpen and ns.viewId == t.id
	if s.toasts and not viewing then N:Show(t, kind) end
	-- Desktop voice is handled by the bridge (flag "r"); the game's voice here.
	if s.autoRead and ns.SpeechEngine() == "game" then
		ns.Speak(t.title .. " " .. VERBS[kind] .. ". " .. (t.last or ""))
	end
end

ns:On("ThreadTransition", function(t, before, after)
	-- Waiting (on a watched PR, another thread) isn't done yet: tell the player when the wait ends.
	local finished = (before == "working" or before == "waiting") and (after == "open" or after == "failed")
	local needsYou = (after == "input" or after == "plan") and before ~= after
	if not finished and not needsYou then return end
	local kind = after
	ns.Print(ns.Color("white", t.title) .. " " .. VERBS[kind] .. ".")
	if ns.IsQuiet() then
		-- In a fight (or a quiet instance): hold the pop-up and voice until after.
		for i = #N.held, 1, -1 do
			if N.held[i].t.id == t.id then table.remove(N.held, i) end
		end
		table.insert(N.held, { t = t, kind = kind })
		while #N.held > 3 do table.remove(N.held, 1) end
		return
	end
	Notify(t, kind)
end)

local function Flush()
	if #N.held == 0 or ns.IsQuiet() then return end
	local held = N.held
	N.held = {}
	for i, h in ipairs(held) do
		local current = ns.Store:Thread(h.t.id) or h.t
		-- Only one sound for the batch.
		Notify(current, h.kind, i > 1)
	end
end

ns:On("Combat", function(inCombat) if not inCombat then C_Timer.After(1, Flush) end end)
ns:On("EnteringWorld", function() C_Timer.After(3, Flush) end)
