-- Faces for long replies. The game's Friz Quadrata is fine for titles and poor for
-- paragraphs, so a reply can use a font shipped in this addon. A font set by
-- file drops the client's per-script fallback (Chinese and Korean come out as
-- boxes), so text in those scripts, and Cyrillic when the face has none, uses
-- the client's own font for that script. The files are SIL Open Font License;
-- the license sits next to each one.

local _, ns = ...

local Fonts = {}
ns.Fonts = Fonts

Fonts.LINE_CHARS = 96

local BODY_SIZE = 14
local BODY_SPACING = 4
local MONO_SIZE = 13
local MONO_SPACING = 3

-- Fenced code arrives as a whole line in this color (bridge/src/format.js).
local CODE_MARK = "|cffa8c7fa"

local FACES = {
	inter = { file = "Inter-Regular.ttf", cyrillic = true },
	atkinson = { file = "AtkinsonHyperlegible-Regular.ttf", cyrillic = false },
}

local function FacePath(file)
	return ns.media .. "Fonts\\" .. file
end

function Fonts.Choice()
	local id = ns.db and ns.db.settings and ns.db.settings.readingFont
	if id ~= "inter" and id ~= "atkinson" and id ~= "game" then id = "inter" end
	return id
end

function Fonts.Custom()
	return Fonts.Choice() ~= "game"
end

-- A path when `text` needs a client font, else nil (keep the reading font).
-- UTF-8 lead bytes E3-E9 are CJK punctuation, kana and Chinese; EA-ED are Hangul.
-- D0-D4 are Cyrillic.
function Fonts.ScriptPath(text, cyrillic)
	if type(text) ~= "string" then return nil end
	local at = text:find("[\227-\237]")
	if at then
		if text:byte(at) >= 234 then return "Fonts\\2002.TTF" end
		return "Fonts\\ARKai_T.ttf"
	end
	if not cyrillic and text:find("[\208-\212]") then
		return "Fonts\\FRIZQT___CYR.TTF"
	end
end

-- Split a formatted reply into prose and fenced code. Inline code stays in the
-- prose: only a line the bridge colored entirely as code becomes its own block.
function Fonts.Split(text)
	text = text or ""
	if text == "" then return { { kind = "prose", text = "" } } end
	local blocks, buf, kind = {}, {}, nil
	local function flush()
		if not kind then return end
		blocks[#blocks + 1] = { kind = kind, text = table.concat(buf, "\n") }
		buf = {}
	end
	local pos, len = 1, #text
	while pos <= len do
		local nl = text:find("\n", pos, true)
		local line
		if nl then
			line = text:sub(pos, nl - 1)
			pos = nl + 1
		else
			line = text:sub(pos)
			pos = len + 1
		end
		local lineKind = line:sub(1, #CODE_MARK) == CODE_MARK and "code" or "prose"
		if lineKind ~= kind then
			flush()
			kind = lineKind
		end
		buf[#buf + 1] = line
	end
	flush()
	return blocks
end

function Fonts.Blocks(text)
	if not Fonts.Custom() then return { { kind = "prose", text = text or "" } } end
	return Fonts.Split(text)
end

local function UseFace(fs, path, size, spacing)
	local ok, loaded = pcall(fs.SetFont, fs, path, size, "")
	if not (ok and loaded) then return false end
	-- A drop shadow at 14px muddies the stems. Offset alone still draws it in place.
	fs:SetShadowOffset(0, 0)
	fs:SetShadowColor(0, 0, 0, 0)
	fs:SetSpacing(spacing)
	return true
end

local function GameFace(fs, role)
	if role == "note" then
		fs:SetFontObject("GameFontNormal")
		fs:SetSpacing(0)
	else
		fs:SetFontObject("GameFontHighlight")
		fs:SetSpacing(2)
	end
end

local function Paint(fs, role)
	local theme = ns.Theme.Get()
	if role == "note" then
		if theme then ns.Theme.SetText(fs, theme.text)
		else fs:SetTextColor(NORMAL_FONT_COLOR:GetRGB()) end
		return
	end
	if not Fonts.Custom() then return end
	if theme then ns.Theme.SetText(fs, theme.text)
	else fs:SetTextColor(1, 1, 1) end
end

-- `role` is "body", "note" or "mono". `text` picks a client font when the
-- reading font has no glyphs for it.
function Fonts.Apply(fs, role, text)
	role = role or "body"
	if not Fonts.Custom() then
		GameFace(fs, role)
		Paint(fs, role)
		return
	end
	local face = FACES[Fonts.Choice()]
	local file, size, spacing, cyr = face.file, BODY_SIZE, BODY_SPACING, face.cyrillic
	if role == "mono" then
		file, size, spacing, cyr = "JetBrainsMono-Regular.ttf", MONO_SIZE, MONO_SPACING, true
	end
	local script = Fonts.ScriptPath(text, cyr)
	local path = script or FacePath(file)
	if script then size, spacing = BODY_SIZE, BODY_SPACING end
	if not UseFace(fs, path, size, spacing) then
		if role == "mono" and not script and UseFace(fs, FacePath(face.file), BODY_SIZE, BODY_SPACING) then
			Paint(fs, role)
			return
		end
		GameFace(fs, role)
	end
	Paint(fs, role)
end
