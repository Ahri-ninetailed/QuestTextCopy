-- Quest Text Copy for WoW: Forever
-- Opens a window with the quest text already selected, so Ctrl+C copies it.
-- WoW does not let addons write to the system clipboard directly,
-- so the last step (Ctrl+C) is always yours.

local ADDON_NAME = ...

local isRu = (GetLocale() == "ruRU")
local function T(en, ru) return isRu and ru or en end

BINDING_HEADER_QUESTTEXTCOPY = "Quest Text Copy"
BINDING_NAME_QUESTTEXTCOPY_OPEN = T("Copy text (quest, NPC, book)", "Скопировать текст (квест, NPC, книга)")

local PREFIX = "|cff66ccffQuestTextCopy:|r "
local function say(msg) print(PREFIX .. msg) end

---------------------------------------------------------------------------
-- Safe API helpers: the Forever client mixes classic and modern APIs,
-- so every call is checked and wrapped.
---------------------------------------------------------------------------
local unpack = unpack or table.unpack

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local res = { pcall(fn, ...) }
	if res[1] then return unpack(res, 2) end
	return nil
end

local function clean(s)
	if type(s) ~= "string" or s == "" then return nil end
	s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
	s = s:gsub("|r", "")
	s = s:gsub("|T.-|t", "")
	s = s:gsub("|A.-|a", "")
	s = s:gsub("|n", "\n")
	s = s:gsub("\r\n", "\n")
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then return nil end
	return s
end

local function newDoc()
	local parts = {}
	local doc = {}
	function doc.add(text, header)
		text = clean(text)
		if not text then return end
		if header then text = header .. "\n" .. text end
		parts[#parts + 1] = text
	end
	function doc.result()
		if #parts == 0 then return nil end
		return table.concat(parts, "\n\n")
	end
	return doc
end

---------------------------------------------------------------------------
-- Source 1: the quest dialog with an NPC (accept / progress / reward)
---------------------------------------------------------------------------
local function shown(f) return f and f.IsShown and f:IsShown() end

-- Saved data (account-wide): the options and who gave each quest.
local DEFAULTS = {
	npcName = true,
	npcTitle = true,
	npcLevel = false,
	npcReputation = false,
	npcSide = false,
	npcLocation = false,
}

local function db()
	if type(QuestTextCopyDB) ~= "table" then QuestTextCopyDB = {} end
	return QuestTextCopyDB
end

local function options()
	local o = db().options
	if type(o) ~= "table" then
		o = {}
		db().options = o
	end
	for key, value in pairs(DEFAULTS) do
		if type(o[key]) ~= "boolean" then o[key] = value end
	end
	return o
end

-- Who is talking. Read from the NPC's tooltip, whose lines come in this
-- order: name, title (Innkeeper), level, reputation faction (Orgrimmar),
-- PvP. Quest lines and the PvP flag are dropped; the side (Horde, Alliance)
-- comes from UnitFactionGroup.
local LINE = Enum and Enum.TooltipDataLineType or {}
local SKIP_LINE = {}
for _, key in ipairs({ "UnitName", "Blank", "Separator", "UnitThreat", "QuestTitle",
	"QuestObjective", "QuestPlayer", "UnitCriteriaProgress" }) do
	if LINE[key] then SKIP_LINE[LINE[key]] = true end
end

local function isPvP(text) return text == PVP or text == "PvP" end

local function npcInfo(...)
	local unit, name
	for i = 1, select("#", ...) do
		unit = select(i, ...)
		name = clean(call(UnitName, unit))
		if name then break end
	end
	if not name then return nil end

	local info = { name = name }
	local _, side = call(UnitFactionGroup, unit)
	info.side = clean(side)

	-- Where the talk happens: the NPC stands next to the player.
	local zone, subzone = clean(call(GetZoneText)), clean(call(GetSubZoneText))
	if zone and subzone and subzone ~= zone then
		info.location = zone .. ", " .. subzone
	else
		info.location = zone or subzone
	end

	local rest = {}
	local data = C_TooltipInfo and call(C_TooltipInfo.GetUnit, unit)
	if type(data) == "table" and type(data.lines) == "table" then
		for i, line in ipairs(data.lines) do
			local text = i > 1 and type(line) == "table" and not SKIP_LINE[line.type] and clean(line.leftText)
			if text and text ~= name and not isPvP(text) then
				rest[#rest + 1] = { text = text, type = line.type }
			end
		end
	end

	-- The level line: typed as such, or holding the NPC's level (or ??).
	local level = tostring(call(UnitLevel, unit) or "")
	local function isLevel(l)
		if LINE.UnitLevel and l.type == LINE.UnitLevel then return true end
		if l.text:find("??", 1, true) then return true end
		return level ~= "" and level ~= "-1" and l.text:find("%f[%d]" .. level .. "%f[%D]") ~= nil
	end
	local levelAt
	for k, l in ipairs(rest) do
		if isLevel(l) then levelAt = k break end
	end
	if levelAt then
		info.level = rest[levelAt].text
		if levelAt > 1 then info.title = rest[1].text end
		for k = levelAt + 1, #rest do
			if rest[k].text ~= info.side then
				info.reputation = rest[k].text
				break
			end
		end
	elseif rest[1] and rest[1].text ~= info.side then
		info.title = rest[1].text
	end
	if info.title then info.title = info.title:match("^<(.*)>$") or info.title end
	return info
end

-- The NPC lines the options ask for (name and title as on the nameplate):
--   Innkeeper Grosk
--   <Innkeeper>
--   Level 30, Orgrimmar, Horde
--   Orgrimmar, Valley of Strength
local function npcText(info)
	if type(info) == "string" then
		-- Saved by v1.1.0 as finished text; its first line is the name.
		info = { name = info:match("^[^\n]+") }
	end
	if type(info) ~= "table" then return nil end
	local o = options()
	local lines, more = {}, {}
	if o.npcName and info.name then lines[#lines + 1] = info.name end
	if o.npcTitle and info.title then lines[#lines + 1] = "<" .. info.title .. ">" end
	if o.npcLevel and info.level then more[#more + 1] = info.level end
	if o.npcReputation and info.reputation then more[#more + 1] = info.reputation end
	if o.npcSide and info.side and not (o.npcReputation and info.side == info.reputation) then
		more[#more + 1] = info.side
	end
	if #more > 0 then lines[#lines + 1] = table.concat(more, ", ") end
	if o.npcLocation and info.location then lines[#lines + 1] = info.location end
	if #lines == 0 then return nil end
	return table.concat(lines, "\n")
end

local function npcHeader(...)
	return call(npcText, call(npcInfo, ...))
end

-- Who gave each quest. The quest log doesn't know, so the NPC is read
-- while the quest is offered (QUEST_DETAIL) and kept once it is accepted.
-- Raw fields are kept, so the options also apply to them later.
local offered = {} -- questID -> NPC info of the offer on screen

local function givers()
	if type(db().givers) ~= "table" then db().givers = {} end
	return db().givers
end

local function rememberOffer()
	local questID = call(GetQuestID)
	if not questID or questID == 0 then return end
	-- A quest shared by a party member: the "giver" is a player, skip it.
	if call(UnitIsPlayer, "questnpc") then
		offered[questID] = nil
		return
	end
	offered[questID] = call(npcInfo, "questnpc", "npc")
end

local function keepGiver(questID)
	local info = questID and offered[questID]
	if info then
		givers()[questID] = info
		offered[questID] = nil
	end
end

local function fromQuestDialog()
	if not shown(QuestFrame) then return nil end
	local doc = newDoc()
	doc.add(npcHeader("questnpc", "npc"))
	doc.add(call(GetTitleText))

	if shown(QuestFrameDetailPanel) then
		doc.add(call(GetQuestText))
		doc.add(call(GetObjectiveText), T("Objectives:", "Задачи:"))
	elseif shown(QuestFrameProgressPanel) then
		doc.add(call(GetProgressText))
	elseif shown(QuestFrameRewardPanel) then
		doc.add(call(GetRewardText))
	elseif shown(QuestFrameGreetingPanel) then
		doc.add(call(GetGreetingText))
		local function titles(countFn, titleFn)
			local out = {}
			local n = call(countFn) or 0
			for i = 1, n do
				local t = call(titleFn, i)
				if t and t ~= "" then out[#out + 1] = "- " .. t end
			end
			return table.concat(out, "\n")
		end
		doc.add(titles(GetNumActiveQuests, GetActiveTitle), T("Current quests:", "Текущие квесты:"))
		doc.add(titles(GetNumAvailableQuests, GetAvailableTitle), T("Available quests:", "Доступные квесты:"))
	else
		doc.add(call(GetQuestText))
		doc.add(call(GetObjectiveText), T("Objectives:", "Задачи:"))
	end

	return doc.result()
end

---------------------------------------------------------------------------
-- Source 2: the NPC conversation window (gossip)
---------------------------------------------------------------------------
local G = C_GossipInfo or {}

local function listFrom(fn, field, prefix)
	local out = {}
	local items = call(fn)
	if type(items) == "table" then
		for _, item in ipairs(items) do
			local text = type(item) == "table" and item[field]
			if text and text ~= "" then out[#out + 1] = prefix .. text end
		end
	end
	return table.concat(out, "\n")
end

local function fromGossip()
	if not shown(GossipFrame) then return nil end
	local doc = newDoc()
	doc.add(npcHeader("npc"))
	doc.add(call(G.GetText) or call(GetGossipText))
	doc.add(listFrom(G.GetActiveQuests, "title", "- "), T("Current quests:", "Текущие квесты:"))
	doc.add(listFrom(G.GetAvailableQuests, "title", "- "), T("Available quests:", "Доступные квесты:"))
	doc.add(listFrom(G.GetOptions, "name", "- "), T("Options:", "Варианты:"))
	return doc.result()
end

---------------------------------------------------------------------------
-- Source 3: readable objects and items (books, notes, diaries, plaques)
-- The game hands out one page at a time, so pages are cached as you read.
---------------------------------------------------------------------------
local bookPages, bookTitle = {}, nil

local function stripHtml(s)
	if type(s) ~= "string" then return s end
	s = s:gsub("<[Bb][Rr]%s*/?>", "\n")
	s = s:gsub("</[Pp]>", "\n")
	s = s:gsub("</?[Hh]%d[^>]*>", "\n")
	s = s:gsub("<[^>]->", "")
	s = s:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"')
	s = s:gsub("\n\n\n+", "\n\n")
	return s
end

local function cacheBookPage()
	local page = call(ItemTextGetPage) or 1
	local text = call(ItemTextGetText)
	if text and text ~= "" then bookPages[page] = stripHtml(text) end
	bookTitle = call(ItemTextGetItem) or bookTitle
end

local function fromItemText()
	if not shown(ItemTextFrame) then return nil end
	cacheBookPage()

	local maxPage = 0
	for page in pairs(bookPages) do
		if page > maxPage then maxPage = page end
	end

	local doc = newDoc()
	doc.add(bookTitle)
	for page = 1, maxPage do
		if bookPages[page] then
			doc.add(bookPages[page], maxPage > 1 and T("Page ", "Страница ") .. page .. ":" or nil)
		end
	end
	if call(ItemTextHasNextPage) and not bookPages[(call(ItemTextGetPage) or 0) + 1] then
		doc.add(T("(There are more pages: flip through them and they will be copied too.)",
			"(Дальше есть ещё страницы: пролистай их, и они тоже попадут в копию.)"))
	end
	return doc.result()
end

---------------------------------------------------------------------------
-- Source 4: the selected quest in the quest log
---------------------------------------------------------------------------
local Q = C_QuestLog or {}

local function objectiveLines(questID, logIndex)
	local lines = {}
	if questID and Q.GetQuestObjectives then
		local objs = call(Q.GetQuestObjectives, questID)
		if type(objs) == "table" then
			for _, o in ipairs(objs) do
				if type(o) == "table" and o.text and o.text ~= "" then
					lines[#lines + 1] = (o.finished and "[x] " or "[ ] ") .. o.text
				end
			end
		end
	end
	if #lines == 0 and logIndex and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
		local n = call(GetNumQuestLeaderBoards, logIndex) or 0
		for i = 1, n do
			local text, _, finished = call(GetQuestLogLeaderBoard, i, logIndex)
			if text and text ~= "" then
				lines[#lines + 1] = (finished and "[x] " or "[ ] ") .. text
			end
		end
	end
	return lines
end

local function fromQuestLog(forcedID)
	local questID = forcedID
	local logIndex

	if not questID and Q.GetSelectedQuest then
		questID = call(Q.GetSelectedQuest)
	end
	if (not questID or questID == 0) and QuestMapFrame and QuestMapFrame.DetailsFrame then
		questID = QuestMapFrame.DetailsFrame.questID
	end
	if questID == 0 then questID = nil end

	if questID and Q.GetLogIndexForQuestID then
		logIndex = call(Q.GetLogIndexForQuestID, questID)
	end
	if not logIndex and not forcedID and GetQuestLogSelection then
		logIndex = call(GetQuestLogSelection)
	end
	if logIndex == 0 then logIndex = nil end

	if not questID and not logIndex then return nil end
	if forcedID and not logIndex then return nil end -- quest is not in the log

	-- Title (+ questID for the classic API path)
	local title
	if questID and Q.GetTitleForQuestID then
		title = call(Q.GetTitleForQuestID, questID)
	end
	if not title and logIndex and Q.GetInfo then
		local info = call(Q.GetInfo, logIndex)
		if type(info) == "table" then
			title = info.title
			questID = questID or info.questID
		end
	end
	if not title and logIndex and GetQuestLogTitle then
		local t, _, _, _, _, _, _, id = call(GetQuestLogTitle, logIndex)
		title = t
		questID = questID or id
	end

	-- GetQuestLogQuestText reads the *selected* quest, so select it briefly.
	local restore
	if questID and Q.GetSelectedQuest and Q.SetSelectedQuest then
		local prev = call(Q.GetSelectedQuest)
		if prev ~= questID then
			call(Q.SetSelectedQuest, questID)
			restore = function() if prev and prev ~= 0 then call(Q.SetSelectedQuest, prev) end end
		end
	elseif logIndex and GetQuestLogSelection and SelectQuestLogEntry then
		local prev = call(GetQuestLogSelection)
		if prev ~= logIndex then
			call(SelectQuestLogEntry, logIndex)
			restore = function() if prev and prev ~= 0 then call(SelectQuestLogEntry, prev) end end
		end
	end

	local desc, obj = call(GetQuestLogQuestText)
	local lines = objectiveLines(questID, logIndex)

	if restore then restore() end

	local doc = newDoc()
	doc.add(questID and call(npcText, givers()[questID]))
	doc.add(title)
	doc.add(desc)
	doc.add(obj, T("Objectives:", "Задачи:"))
	if #lines > 0 then
		doc.add(table.concat(lines, "\n"), T("Progress:", "Прогресс:"))
	end
	if questID then
		doc.add("Quest ID: " .. tostring(questID))
	end
	return doc.result()
end

---------------------------------------------------------------------------
-- Double-click word selection (WoW edit boxes have none built in)
---------------------------------------------------------------------------
-- Split a UTF-8 string into characters: { firstByte, lastByte, codepoint }.
local function decodeChars(s)
	local chars, i, n = {}, 1, #s
	while i <= n do
		local c = s:byte(i)
		local len, cp
		if c < 0x80 then len, cp = 1, c
		elseif c >= 0xF0 then len, cp = 4, c % 0x08
		elseif c >= 0xE0 then len, cp = 3, c % 0x10
		elseif c >= 0xC0 then len, cp = 2, c % 0x20
		else len, cp = 1, c end -- stray continuation byte
		local last = math.min(i + len - 1, n)
		for j = i + 1, last do
			cp = cp * 64 + (s:byte(j) % 0x40)
		end
		chars[#chars + 1] = { i, last, cp }
		i = last + 1
	end
	return chars
end

-- Letters and digits in any script; punctuation, dashes and symbols are not.
local function isLetter(cp)
	if not cp then return false end
	if cp < 0x80 then
		return (cp >= 48 and cp <= 57) or (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122)
	end
	if cp < 0xC0 or cp == 0xD7 or cp == 0xF7 then return false end
	if cp >= 0x2000 and cp <= 0x2BFF then return false end -- dashes, quotes, arrows, symbols
	if cp >= 0x3000 and cp <= 0x303F then return false end
	return true
end

local APOSTROPHE = { [0x27] = true, [0x2019] = true } -- ' and ’

-- Byte range (start, stop) of the word around a cursor position, in the
-- form EditBox:HighlightText expects. Returns nil if the cursor is not on a word.
local function wordBounds(text, cursor)
	local chars = decodeChars(text or "")
	local function cp(k) return chars[k] and chars[k][3] end
	-- Apostrophes count only inside a word: don't, Ferauu's.
	local function inWord(k)
		local c = cp(k)
		if isLetter(c) then return true end
		return APOSTROPHE[c or -1] and isLetter(cp(k - 1)) and isLetter(cp(k + 1)) or false
	end

	-- The character just right of the cursor; if that is not part of a word
	-- (clicked at a word's right edge), try the one just left of it.
	local idx = #chars + 1
	for k, ch in ipairs(chars) do
		if ch[1] > cursor then idx = k break end
	end
	if not inWord(idx) then
		if inWord(idx - 1) then idx = idx - 1 else return nil end
	end

	local a, b = idx, idx
	while inWord(a - 1) do a = a - 1 end
	while inWord(b + 1) do b = b + 1 end
	return chars[a][1] - 1, chars[b][2]
end

---------------------------------------------------------------------------
-- Copy window
---------------------------------------------------------------------------
local frame
local DOUBLE_CLICK_TIME = 0.4

local function ensureFrame()
	if frame then return frame end

	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	frame = CreateFrame("Frame", "QuestTextCopyFrame", UIParent, template)
	frame:SetSize(540, 400)
	frame:SetPoint("CENTER")
	-- Above the world map, which a game rule may raise past DIALOG.
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)

	-- Drag only by the top strip, so clicks near the text never move the window.
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", 12, -10)
	header:SetPoint("TOPRIGHT", -36, -10)
	header:SetHeight(28)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() frame:StartMoving() end)
	header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end
	tinsert(UISpecialFrames, "QuestTextCopyFrame") -- Esc closes it

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	hint:SetPoint("TOP", 0, -18)
	hint:SetText(T("Ctrl+C copy, double-click a word, Esc close",
		"Ctrl+C — копировать, двойной клик — слово, Esc — закрыть"))

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", 18, -42)
	scroll:SetPoint("BOTTOMRIGHT", -18, 18)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = self:GetVerticalScrollRange() or 0
		local new = self:GetVerticalScroll() - delta * 40
		if new < 0 then new = 0 end
		if new > maxScroll then new = maxScroll end
		self:SetVerticalScroll(new)
	end)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(0)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(504)
	-- Inner padding: the clickable area reaches past the text edges,
	-- so starting a selection slightly left of a line still works.
	edit:SetTextInsets(16, 16, 6, 6)
	edit:SetScript("OnEscapePressed", function() frame:Hide() end)
	-- Read-only: any typing restores the original text.
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(frame.text or "")
			self:HighlightText()
		end
	end)
	-- Ctrl+C (Cmd+C on Mac): copying the whole text closes the window so you
	-- can paste straight away; copying a part (a word, a sentence) keeps it
	-- open so you can grab the next one. Ctrl+A selects everything again.
	edit:SetScript("OnKeyDown", function(self, key)
		local mod = IsControlKeyDown() or (IsMetaKeyDown and IsMetaKeyDown())
		if not mod then return end
		if key == "A" then
			self:HighlightText()
			frame.partial = false
		elseif key == "C" then
			if frame.partial then
				say(T("Copied.", "Скопировано."))
			else
				C_Timer.After(0.1, function()
					frame:Hide()
					say(T("Copied.", "Скопировано."))
				end)
			end
		end
	end)
	-- Any click changes the selection; a quick second click on the same spot
	-- selects the whole word, like in a browser.
	local lastClickTime, lastClickPos = 0, -100
	edit:SetScript("OnMouseUp", function(self, button)
		if button and button ~= "LeftButton" then return end
		frame.partial = true
		local now, pos = GetTime(), self:GetCursorPosition()
		if now - lastClickTime <= DOUBLE_CLICK_TIME and math.abs(pos - lastClickPos) <= 4 then
			lastClickTime = 0 -- a third click starts over
			-- Wait a frame so the edit box finishes its own click handling first.
			C_Timer.After(0, function()
				local s, e = wordBounds(frame.text, pos)
				if s then self:HighlightText(s, e) end
			end)
		else
			lastClickTime, lastClickPos = now, pos
		end
	end)
	scroll:SetScrollChild(edit)
	scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)

	frame.scroll = scroll
	frame.edit = edit
	frame:Hide()
	return frame
end

local function showText(text)
	local f = ensureFrame()
	f.text = text
	f.partial = false
	f.edit:SetText(text)
	f:Show()
	f.scroll:SetVerticalScroll(0)
	f.edit:SetFocus()
	f.edit:SetCursorPosition(0)
	f.edit:HighlightText()
end

---------------------------------------------------------------------------
-- Public entry point (slash command, key binding, buttons)
---------------------------------------------------------------------------
function QuestTextCopy_Open(questID)
	local text
	if questID then
		text = fromQuestLog(questID)
	else
		text = fromQuestDialog() or fromGossip() or fromItemText() or fromQuestLog()
	end
	if text then
		showText(text)
	else
		say(T("Open a quest, an NPC conversation, a book or note, or select a quest in your log first.",
			"Сначала открой квест, разговор с NPC, книгу или записку, или выбери квест в журнале."))
	end
end

---------------------------------------------------------------------------
-- Options window: Esc > Options > AddOns > Quest Text Copy, or /qcopy options.
-- Plain Blizzard checkboxes only: custom rows on Blizzard templates taint
-- the whole settings list.
---------------------------------------------------------------------------
local settingsCategory

local function buildSettings()
	local o = options()
	local category = Settings.RegisterVerticalLayoutCategory("Quest Text Copy")
	local where = T("Shown at the top of the text copied from the quest dialog, an NPC conversation and the quest log.",
		"Пишется в начале текста из окна квеста, разговора с NPC и журнала заданий.")
	local function checkbox(key, label, example)
		local setting = Settings.RegisterAddOnSetting(category, "QuestTextCopy_" .. key, key, o,
			Settings.VarType and Settings.VarType.Boolean or "boolean", label, DEFAULTS[key])
		Settings.CreateCheckbox(category, setting, where .. "\n\n" .. example)
	end
	checkbox("npcName", T("NPC name", "Имя NPC"), T("Example: Innkeeper Grosk", "Например: Innkeeper Grosk"))
	checkbox("npcTitle", T("NPC title", "Звание NPC"), T("Example: <Innkeeper>", "Например: <Innkeeper>"))
	checkbox("npcLevel", T("NPC level", "Уровень NPC"), T("Example: Level 30", "Например: Level 30"))
	checkbox("npcReputation", T("NPC reputation faction", "Фракция репутации NPC"),
		T("Example: Orgrimmar", "Например: Orgrimmar"))
	checkbox("npcSide", T("NPC side", "Сторона NPC"),
		T("Horde or Alliance; neutral NPCs have none.", "Орда или Альянс; у нейтральных NPC её нет."))
	checkbox("npcLocation", T("NPC location", "Место NPC"),
		T("The zone and subzone where you talked to the NPC (for a quest giver: where you took the quest). Example: Orgrimmar, Valley of Strength",
			"Зона и подзона, где вы говорили с NPC (у квестодателя — где вы взяли квест). Например: Orgrimmar, Valley of Strength"))
	Settings.RegisterAddOnCategory(category)
	settingsCategory = category
end

local function setupSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
		return
	end
	local ok, err = pcall(buildSettings)
	if not ok then
		say(T("could not create the options window: ", "не удалось создать окно настроек: ") .. tostring(err))
	end
end

local OPTION_WORDS = { "opt", "config", "setting", "настр" }

SLASH_QUESTTEXTCOPY1 = "/qcopy"
SLASH_QUESTTEXTCOPY2 = "/qc"
SlashCmdList.QUESTTEXTCOPY = function(msg)
	msg = (msg or ""):lower()
	for _, word in ipairs(OPTION_WORDS) do
		if msg:find(word, 1, true) then
			if settingsCategory then
				Settings.OpenToCategory(settingsCategory:GetID())
			else
				say(T("The options window is unavailable.", "Окно настроек недоступно."))
			end
			return
		end
	end
	local id = tonumber(msg:match("%d+"))
	QuestTextCopy_Open(id)
end

---------------------------------------------------------------------------
-- "Copy text" buttons inside the quest windows. Each one copies its own
-- window, even when several of them are open at once.
---------------------------------------------------------------------------
local LABEL = T("Text", "Текст")
local TOOLTIP_TITLE = T("Copy text", "Копировать текст")
local TOOLTIP_TEXT = T("Opens the text selected: press Ctrl+C.", "Открывает текст выделенным: нажми Ctrl+C.")

local function fromMapDetails()
	local details = QuestMapFrame and QuestMapFrame.DetailsFrame
	local questID = details and details.questID
	if questID == 0 then questID = nil end
	return fromQuestLog(questID)
end

local function copyFrom(source)
	local text = source()
	if text then
		showText(text)
	else
		say(T("There is no text to copy in this window.", "В этом окне нет текста для копирования."))
	end
end

local function newButton(parent, source, template)
	local b = CreateFrame("Button", nil, parent, template)
	b:SetScript("OnClick", function() copyFrom(source) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(TOOLTIP_TITLE)
		GameTooltip:AddLine(TOOLTIP_TEXT, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

-- A red button like the window's own Accept, Decline or Back, just wide
-- enough for its label.
local function textButton(parent, source)
	local b = newButton(parent, source, "UIPanelButtonTemplate")
	b:SetText(LABEL)
	local fs = b:GetFontString()
	local w = fs and fs:GetStringWidth() or 0
	b:SetSize(w > 0 and math.ceil(w) + 30 or 60, 22)
	b:SetFrameLevel(parent:GetFrameLevel() + 5)
	return b
end

-- Quest dialog and NPC conversation: in the bottom row, left of the
-- Decline / Goodbye / Cancel button that every page has in the right corner
-- (78 wide, 6 from the edge). The left corner holds Accept or Complete Quest.
local function addBottomRowButton(parent, source)
	local b = textButton(parent, source)
	b:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -88, 4)
end

-- Map quest log details: in the top row, right of the Back button. Spoken
-- Quests puts its round icons at the right end of the same row.
local function addMapButton(details)
	local header = details.BackFrame or details
	local b = textButton(header, fromMapDetails)
	if header.BackButton then
		b:SetPoint("LEFT", header.BackButton, "RIGHT", 4, 0)
	else
		b:SetPoint("TOPLEFT", details, "TOPLEFT", 105, -11)
	end
end

-- Books and notes have no free row: the page text runs to the bottom edge
-- and the page arrows fill the strip under the title. So a small icon goes
-- into the title bar, left of the close button, like the map's maximize.
local ICON = "Interface\\Icons\\INV_Misc_Note_01"

local function addTitleBarButton(parent, source)
	local b = newButton(parent, source)
	b:SetSize(20, 20)
	local close = parent.CloseButton or _G[(parent:GetName() or "") .. "CloseButton"]
	if close then
		b:SetPoint("RIGHT", close, "LEFT", -2, 0)
		b:SetFrameLevel(close:GetFrameLevel() + 1)
	else
		b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -28, -2)
	end
	b:SetNormalTexture(ICON)
	b:SetPushedTexture(ICON)
	b:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:GetPushedTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:GetPushedTexture():SetVertexColor(0.6, 0.6, 0.6)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
end

local attached = {}

local function attach(key, parent, add, source)
	if not parent or attached[key] then return end
	attached[key] = true
	add(parent, source)
end

local function tryAttach()
	attach("dialog", QuestFrame, addBottomRowButton, fromQuestDialog)
	attach("gossip", GossipFrame, addBottomRowButton, fromGossip)
	attach("itemText", ItemTextFrame, addTitleBarButton, fromItemText)
	attach("mapLog", QuestMapFrame and QuestMapFrame.DetailsFrame, addMapButton)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("ITEM_TEXT_BEGIN")
events:RegisterEvent("ITEM_TEXT_READY")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_ACCEPTED")
events:SetScript("OnEvent", function(_, event, name)
	if event == "QUEST_DETAIL" then
		rememberOffer()
	elseif event == "QUEST_ACCEPTED" then
		keepGiver(name) -- the payload is the questID
	elseif event == "ITEM_TEXT_BEGIN" then
		-- A new book or note was opened: forget the previous one.
		bookPages, bookTitle = {}, nil
	elseif event == "ITEM_TEXT_READY" then
		cacheBookPage()
	elseif event == "ADDON_LOADED" and name == ADDON_NAME then
		setupSettings()
	elseif event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
		tryAttach()
	end
end)
