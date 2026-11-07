-- =========================================================================
-- Modules/QuestSync.lua
-- Priority 2 (Important): Real-time Squad Quest Log & Objective Progress
-- Synchronization, Missing-Quest Detection, and 1-Click Quest Sharing.
-- Target Client: World of Warcraft: Forever (Interface: 16001)
-- =========================================================================
local addonName, ns = ...

local Quests = {}
ns.Quests = Quests

local questScanPending = false
local questBroadcastPending = false

-- -------------------------------------------------------------------------
-- Active Quest Log & Objective Progress Scanner (Client 16001 + Classic)
-- -------------------------------------------------------------------------
function Quests:ScanQuestLog(silent)
    if not ns.db or not ns.db.quests or not ns.db.quests.enabled then return end
    local rec = ns.EnsureCurrentCharacterRecord()
    if not rec then return end

    local numEntries = 0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        numEntries = ns.SafeNumber(C_QuestLog.GetNumQuestLogEntries(), 0)
    elseif GetNumQuestLogEntries then
        numEntries = ns.SafeNumber(GetNumQuestLogEntries(), 0)
    end

    if numEntries <= 0 then
        rec.quests = {}
        if not silent then ns.SendMessage("QUESTS_UPDATED", rec.key) end
        return
    end

    local currentZone = ns.GetPlayerLocationData()
    local currentHeader = currentZone
    local activeQuests = {}

    for i = 1, numEntries do
        local title, questID, level, isHeader, isComplete = nil, 0, 0, false, false

        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info and not ns.IsSecret(info) then
                title = ns.SafeString(info.title, nil)
                questID = ns.SafeNumber(info.questID, 0)
                level = ns.SafeNumber(info.difficultyLevel or info.level, 0)
                isHeader = ns.SafeBoolean(info.isHeader)
                if not isHeader and questID > 0 and C_QuestLog.IsComplete then
                    isComplete = ns.SafeBoolean(C_QuestLog.IsComplete(questID))
                end
            end
        elseif GetQuestLogTitle then
            local qTitle, qLevel, _, qIsHeader, _, qIsComplete, _, qID = GetQuestLogTitle(i)
            title = ns.SafeString(qTitle, nil)
            level = ns.SafeNumber(qLevel, 0)
            isHeader = ns.SafeBoolean(qIsHeader)
            isComplete = (qIsComplete == 1 or qIsComplete == true)
            questID = ns.SafeNumber(qID, 0)
        end

        if isHeader and title and title ~= "" then
            currentHeader = title
        elseif not isHeader and title and title ~= "" then
            local qKey = questID > 0 and ("q:" .. questID) or ("qt:" .. title:lower())
            local objectives = {}

            if questID > 0 and C_QuestLog and C_QuestLog.GetQuestObjectives then
                local ok, objList = pcall(C_QuestLog.GetQuestObjectives, questID)
                if ok and type(objList) == "table" then
                    for _, obj in ipairs(objList) do
                        if obj and not ns.IsSecret(obj) then
                            local text = ns.SafeString(obj.text, "")
                            local cur = ns.SafeNumber(obj.numFulfilled, 0)
                            local req = ns.SafeNumber(obj.numRequired, 0)
                            local done = ns.SafeBoolean(obj.finished)
                            objectives[#objectives + 1] = {
                                text = text,
                                cur = cur,
                                req = req,
                                done = done,
                            }
                        end
                    end
                end
            elseif GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
                local numObj = ns.SafeNumber(GetNumQuestLeaderBoards(i), 0)
                for o = 1, numObj do
                    local text, _, done = GetQuestLogLeaderBoard(o, i)
                    text = ns.SafeString(text, "")
                    local cur, req = text:match("(%d+)%s*/%s*(%d+)")
                    objectives[#objectives + 1] = {
                        text = text,
                        cur = tonumber(cur) or (done and 1 or 0),
                        req = tonumber(req) or 1,
                        done = ns.SafeBoolean(done),
                    }
                end
            end

            if #objectives > 0 and not isComplete then
                local allDone = true
                for _, obj in ipairs(objectives) do
                    if not obj.done then
                        allDone = false
                        break
                    end
                end
                if allDone then isComplete = true end
            end

            activeQuests[qKey] = {
                key = qKey,
                questID = questID,
                logIndex = i,
                title = title,
                level = level,
                zone = currentHeader or currentZone,
                isComplete = isComplete,
                objectives = objectives,
                updatedAt = time(),
            }
        end
    end

    rec.quests = activeQuests
    if not silent then
        ns.SendMessage("QUESTS_UPDATED", rec.key)
    end
end

-- -------------------------------------------------------------------------
-- Network Broadcast & Receive
-- -------------------------------------------------------------------------
function Quests:QueueScanAndSync()
    if questScanPending then return end
    questScanPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.8, function()
            questScanPending = false
            self:ScanQuestLog(false)
            if ns.db and ns.db.sync and ns.db.sync.autoBroadcastQuests then
                self:QueueBroadcast()
            end
        end)
    else
        questScanPending = false
        self:ScanQuestLog(false)
    end
end

function Quests:QueueBroadcast()
    if questBroadcastPending then return end
    questBroadcastPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(2.0, function()
            questBroadcastPending = false
            self:BroadcastQuests()
        end)
    else
        questBroadcastPending = false
        self:BroadcastQuests()
    end
end

function Quests:BroadcastQuests(whisperTarget)
    if not ns.Sync or not ns.db or not ns.db.quests or not ns.db.quests.enabled then return end
    local rec = ns.EnsureCurrentCharacterRecord()
    if not rec then return end

    ns.Sync:Broadcast("QUEST", {
        key = rec.key,
        name = rec.name,
        class = rec.class,
        level = rec.level,
        faction = rec.faction,
        quests = rec.quests or {},
    }, "NORMAL", whisperTarget)
end

function Quests:OnReceiveQuests(charKey, peer, data)
    if not ns.db or type(data) ~= "table" then return end
    ns.db.squadCharacters = ns.db.squadCharacters or {}

    local targetKey = ns.NormalizeCharKey(data.key or charKey)
    if targetKey:lower() == ns.GetPlayerKey():lower() or ns.IsSelfName(targetKey) then return end
    local rec = ns.db.squadCharacters[targetKey] or {
        key = targetKey,
        owner = peer.shortName or ns.ShortName(targetKey),
        name = ns.SafeString(data.name, ns.ShortName(targetKey)),
        class = ns.SafeString(data.class, peer.class or "WARRIOR"),
        level = ns.SafeNumber(data.level, peer.level or 1),
        faction = ns.NormalizeFaction(data.faction or peer.faction),
    }
    rec.faction = ns.NormalizeFaction(data.faction or peer.faction or rec.faction)

    local oldQuests = rec.quests or {}
    local newQuests = type(data.quests) == "table" and data.quests or {}

    -- Check for newly completed quests by this friend to show a live notification
    if ns.db.quests and ns.db.quests.showObjectiveNotifications and next(oldQuests) then
        local myRec = ns.EnsureCurrentCharacterRecord()
        local myQuests = (myRec and myRec.quests) or {}
        for qKey, qNew in pairs(newQuests) do
            local qOld = oldQuests[qKey]
            if myQuests[qKey] and qNew.isComplete and (not qOld or not qOld.isComplete) then
                ns.Print(string.format(
                    "%s hat die gemeinsame Quest |cffffd100[%s]|r abgeschlossen!",
                    ns.ColorByClass(rec.name, rec.class),
                    ns.SafeString(qNew.title, "Quest")
                ))
            end
        end
    end

    rec.quests = newQuests
    rec.updatedAt = time()
    ns.db.squadCharacters[targetKey] = rec
    ns.SendMessage("QUESTS_UPDATED", targetKey)
end

-- -------------------------------------------------------------------------
-- Share Quest Helper
-- -------------------------------------------------------------------------
function Quests:ShareQuest(questKeyOrID)
    local rec = ns.EnsureCurrentCharacterRecord()
    if not rec or not rec.quests then return end

    local q = rec.quests[questKeyOrID]
    if not q then
        for _, entry in pairs(rec.quests) do
            if entry.questID == questKeyOrID or entry.title == questKeyOrID then
                q = entry
                break
            end
        end
    end

    if not q then
        ns.Print("Du hast diese Quest aktuell nicht in deinem eigenen Questlog.")
        return
    end

    if not IsInGroup or not IsInGroup() then
        ns.Print("Du musst in einer Gruppe sein, um eine Quest direkt zu teilen.")
        return
    end

    if C_QuestLog and C_QuestLog.SetSelectedQuest and q.questID and q.questID > 0 then
        pcall(C_QuestLog.SetSelectedQuest, q.questID)
    end
    if SelectQuestLogEntry and q.logIndex then
        pcall(SelectQuestLogEntry, q.logIndex)
    end
    if QuestLogPushQuest then
        pcall(QuestLogPushQuest)
        ns.Print("Teile Quest mit der Gruppe: |cffffd100[" .. ns.SafeString(q.title, "Quest") .. "]|r")
    end
end

-- -------------------------------------------------------------------------
-- Aggregated Squad Quest Comparison (For UI Quest Tab)
-- -------------------------------------------------------------------------
function Quests:GetAggregatedQuests(searchQuery, currentZoneOnly)
    local results = {}
    local byTitle = {}
    local myRec = ns.EnsureCurrentCharacterRecord()
    local myZone = ns.GetPlayerLocationData()
    local query = ns.SafeString(searchQuery, ""):lower()

    local activePlayers = {}
    local seenPlayerLower = {}

    local function tryAddPlayer(rec, isOwn)
        if type(rec) ~= "table" or type(rec.quests) ~= "table" then return end
        local pName = rec.name or ns.ShortName(rec.key)
        local lower = ns.ShortName(pName):lower()
        if lower == "" or lower == "unbekannt" or seenPlayerLower[lower] then return end
        local pFaction = ns.ResolveCharacterFaction(pName, rec.faction)
        if not ns.MatchesGlobalFilter(rec, isOwn, pFaction) then return end

        local isActiveMe = ns.IsSelfName(pName)
        if not isActiveMe and not next(rec.quests) then return end

        seenPlayerLower[lower] = true
        activePlayers[#activePlayers + 1] = {
            key = rec.key or pName,
            name = pName,
            class = rec.class or "WARRIOR",
            faction = pFaction,
            quests = rec.quests or {},
            isMe = isActiveMe,
            isOwn = isOwn,
        }
    end

    if myRec then
        tryAddPlayer(myRec, true)
    end
    for _, cRec in pairs(ns.db and ns.db.characters or {}) do
        tryAddPlayer(cRec, true)
    end
    local myCharKeys = ns.db and ns.db.characters or {}
    for key, sRec in pairs(ns.db and ns.db.squadCharacters or {}) do
        if not myCharKeys[key] and not ns.IsSelfName(sRec.name or key) then
            tryAddPlayer(sRec, false)
        end
    end

    for _, p in ipairs(activePlayers) do
        for qKey, q in pairs(p.quests) do
            local title = ns.SafeString(q.title, "Unbekannte Quest")
            local normTitle = title:lower()
            local zone = ns.SafeString(q.zone, "Allgemein")

            local passZone = (not currentZoneOnly) or (zone:lower() == myZone:lower())
            local passSearch = (query == "")
                or normTitle:find(query, 1, true)
                or zone:lower():find(query, 1, true)
                or p.name:lower():find(query, 1, true)

            if passZone and passSearch then
                local agg = byTitle[normTitle]
                if not agg then
                    agg = {
                        key = qKey,
                        questID = q.questID or 0,
                        title = title,
                        level = q.level or 0,
                        zone = zone,
                        faction = p.faction,
                        holders = {},
                        holderMap = {},
                        iHaveIt = false,
                    }
                    byTitle[normTitle] = agg
                    results[#results + 1] = agg
                end

                if p.isMe then
                    agg.iHaveIt = true
                    agg.myLogIndex = q.logIndex
                    agg.questID = (q.questID and q.questID > 0) and q.questID or agg.questID
                end

                -- Format concise objective summary for this player
                local progSummary = ""
                if q.isComplete then
                    progSummary = "|cff34d399Fertig!|r"
                elseif type(q.objectives) == "table" and #q.objectives > 0 then
                    local parts = {}
                    for _, obj in ipairs(q.objectives) do
                        if obj.req and obj.req > 0 then
                            local col = obj.done and "34d399" or "fbbf24"
                            parts[#parts + 1] = string.format("|cff%s%d/%d|r", col, obj.cur or 0, obj.req)
                        elseif obj.text and obj.text ~= "" then
                            parts[#parts + 1] = obj.text
                        end
                    end
                    progSummary = table.concat(parts, " · ")
                else
                    progSummary = "|cff94a3b8Aktiv|r"
                end

                agg.holderMap[p.key] = true
                agg.holders[#agg.holders + 1] = {
                    key = p.key,
                    name = p.name,
                    class = p.class,
                    faction = p.faction,
                    isMe = p.isMe,
                    isComplete = q.isComplete,
                    progressText = progSummary,
                    objectives = q.objectives or {},
                }
            end
        end
    end

    -- Determine which active squad players of the SAME faction are missing each quest
    for _, agg in ipairs(results) do
        agg.missingPlayers = {}
        for _, p in ipairs(activePlayers) do
            if not agg.holderMap[p.key] and (p.faction == agg.faction or agg.faction == "Neutral" or p.faction == "Neutral") then
                agg.missingPlayers[#agg.missingPlayers + 1] = {
                    name = p.name,
                    class = p.class,
                    faction = p.faction,
                    isMe = p.isMe,
                }
            end
        end
    end

    table.sort(results, function(a, b)
        if a.zone ~= b.zone then return a.zone < b.zone end
        return a.title < b.title
    end)

    return results
end

-- -------------------------------------------------------------------------
-- Events
-- -------------------------------------------------------------------------
ns.RegisterMessage("PLAYER_READY", function()
    Quests:ScanQuestLog(true)
end)

ns.RegisterEvent("QUEST_LOG_UPDATE", function()
    Quests:QueueScanAndSync()
end)

ns.RegisterEvent("QUEST_ACCEPTED", function()
    Quests:QueueScanAndSync()
end)

ns.RegisterEvent("QUEST_TURNED_IN", function()
    if ns.Stats and ns.Stats.RecordQuestCompleted then
        ns.Stats:RecordQuestCompleted()
    end
    Quests:QueueScanAndSync()
end)

ns.RegisterEvent("QUEST_REMOVED", function()
    Quests:QueueScanAndSync()
end)
