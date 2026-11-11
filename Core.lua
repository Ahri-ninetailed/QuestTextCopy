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

local function fromQuestDialog()
	if not shown(QuestFrame) then return nil end
	local doc = newDoc()
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
	doc.add(call(UnitName, "npc"))
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
	frame:SetFrameStrata("DIALOG")
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

SLASH_QUESTTEXTCOPY1 = "/qcopy"
SLASH_QUESTTEXTCOPY2 = "/qc"
SlashCmdList.QUESTTEXTCOPY = function(msg)
	local id = tonumber((msg or ""):match("%d+"))
	QuestTextCopy_Open(id)
end

---------------------------------------------------------------------------
-- "Copy" buttons next to the quest windows (placed just outside them)
---------------------------------------------------------------------------
local attached = {}

local function attachButton(parent, key)
	if not parent or attached[key] then return end
	attached[key] = true
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(100, 22)
	b:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, -40)
	b:SetText(T("Copy text", "Копировать"))
	b:SetScript("OnClick", function() QuestTextCopy_Open() end)
end

local function tryAttach()
	attachButton(QuestFrame, "dialog")
	attachButton(GossipFrame, "gossip")
	attachButton(ItemTextFrame, "itemText")
	attachButton(QuestLogFrame, "classicLog")
	if QuestMapFrame and QuestMapFrame.DetailsFrame then
		attachButton(QuestMapFrame.DetailsFrame, "mapLog")
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("ITEM_TEXT_BEGIN")
events:RegisterEvent("ITEM_TEXT_READY")
events:SetScript("OnEvent", function(_, event, name)
	if event == "ITEM_TEXT_BEGIN" then
		-- A new book or note was opened: forget the previous one.
		bookPages, bookTitle = {}, nil
	elseif event == "ITEM_TEXT_READY" then
		cacheBookPage()
	elseif event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and name ~= ADDON_NAME) then
		tryAttach()
	end
end)
