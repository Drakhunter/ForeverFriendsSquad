-- =========================================================================
-- Core/SyncEngine.lua
-- Taint-free, high-performance multi-channel synchronization engine for
-- Client 16001 using AceComm-3.0, LibSerialize + LibDeflate compression,
-- and safe Party / Raid / Guild / Online-Friend Whisper routing.
-- Target Client: World of Warcraft: Forever (Interface: 16001)
-- =========================================================================
local addonName, ns = ...

local Sync = {}
ns.Sync = Sync
Sync.offlineCache = {} -- [lowerShortName] = timestamp when server reported offline

if ns.Libs.AceComm then
    ns.Libs.AceComm:Embed(Sync)
end

-- -------------------------------------------------------------------------
-- Lockdown & Restriction Check (Client 16001 Best Practice)
-- -------------------------------------------------------------------------
function Sync:IsMessagingLocked()
    if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and not ns.IsSecret(locked) and locked == true then
            return true
        end
    end
    if C_RestrictedActions and type(C_RestrictedActions.IsAddOnRestrictionActive) == "function" then
        -- 5 = Chat restriction
        local ok, active = pcall(C_RestrictedActions.IsAddOnRestrictionActive, 5)
        if ok and active == true then
            return true
        end
    end
    return false
end

-- -------------------------------------------------------------------------
-- Payload Compression & Serialization (LibSerialize + LibDeflate + Fallback)
-- -------------------------------------------------------------------------
function Sync:EncodePayload(msgType, data)
    local envelope = {
        v = ns.PROTOCOL_VERSION,
        t = msgType,
        s = ns.GetPlayerKey(),
        n = ns.GetPlayerShortName(),
        c = ns.GetPlayerClass(),
        l = ns.GetPlayerLevel(),
        f = ns.GetPlayerFaction(),
        ts = time(),
        d = data or {},
    }

    local LS = ns.Libs.LibSerialize
    local LD = ns.Libs.LibDeflate
    if LS and LD then
        local okSer, serialized = pcall(LS.Serialize, LS, envelope)
        if okSer and serialized then
            local okComp, compressed = pcall(LD.CompressDeflate, LD, serialized, { level = 4 })
            if okComp and compressed then
                local okEnc, encoded = pcall(LD.EncodeForWoWAddonChannel, LD, compressed)
                if okEnc and encoded then
                    return "Z:" .. encoded
                end
            end
        end
    end

    local AS = ns.Libs.AceSerializer
    if AS then
        local ok, serialized = pcall(AS.Serialize, AS, envelope)
        if ok and serialized then
            return "S:" .. serialized
        end
    end

    return nil
end

function Sync:DecodePayload(raw)
    if type(raw) ~= "string" or ns.IsSecret(raw) or #raw < 3 then return nil end
    local prefix = raw:sub(1, 2)
    local body = raw:sub(3)

    if prefix == "Z:" then
        local LS = ns.Libs.LibSerialize
        local LD = ns.Libs.LibDeflate
        if LS and LD then
            local okDec, compressed = pcall(LD.DecodeForWoWAddonChannel, LD, body)
            if okDec and compressed then
                local okDecomp, serialized = pcall(LD.DecompressDeflate, LD, compressed)
                if okDecomp and serialized then
                    local okDeser, success, envelope = pcall(LS.Deserialize, LS, serialized)
                    if okDeser and success and type(envelope) == "table" then
                        return envelope
                    end
                end
            end
        end
    elseif prefix == "S:" then
        local AS = ns.Libs.AceSerializer
        if AS then
            local ok, success, envelope = pcall(AS.Deserialize, AS, body)
            if ok and success and type(envelope) == "table" then
                return envelope
            end
        end
    end

    return nil
end

-- -------------------------------------------------------------------------
-- Legacy Chat Channel Cleanup (Frees /1 if ForeverSquadSync was joined earlier)
-- All sync traffic uses pure invisible Addon-Only channels (C_ChatInfo.SendAddonMessage:
-- PARTY / RAID / INSTANCE_CHAT / GUILD / WHISPER) which NEVER occupy /1../10!
-- -------------------------------------------------------------------------
function Sync:GetCustomChannelId()
    return 0
end

function Sync:EnsureCustomChannel()
    -- No numbered chat channel is used; all traffic runs over secret Addon-Only channels.
end

function Sync:LeaveCustomChannel(customName)
    if not GetChannelName or not LeaveChannelByName then return end
    local candidates = { "ForeverSquadSync" }
    if customName and customName ~= "" and customName ~= "ForeverSquadSync" then
        candidates[#candidates + 1] = customName
    end
    if ns.db and ns.db.sync and ns.db.sync.channelName and ns.db.sync.channelName ~= "" then
        candidates[#candidates + 1] = ns.db.sync.channelName
    end
    for _, chName in ipairs(candidates) do
        local ok, id = pcall(GetChannelName, chName)
        if ok and type(id) == "number" and not ns.IsSecret(id) and id > 0 then
            pcall(LeaveChannelByName, chName)
        end
    end
end

-- -------------------------------------------------------------------------
-- Online Friend Detection (Prevents whispering offline players!)
-- Supports WoW: Forever 2-word character names (Vorname + Nachname).
-- -------------------------------------------------------------------------
Sync.lastWhisperSentAt = {} -- [lowerNameOrFirstWord] = GetTime()

local function GetFirstWordLower(name)
    local s = strtrim(ns.SafeString(name, "")):lower()
    return s:match("^(%S+)") or s
end

function Sync:IsTargetWhisperBlocked(targetName)
    local short = ns.ShortName(targetName)
    if short == "" or short == "Unbekannt" then return true end
    if ns.IsSelfName(short) then return true end

    local lower = short:lower()
    local firstWord = GetFirstWordLower(short)
    local now = time()

    if self.offlineCache[lower] and (now - self.offlineCache[lower]) < 600 then
        return true
    end
    if firstWord ~= "" and self.offlineCache[firstWord] and (now - self.offlineCache[firstWord]) < 600 then
        return true
    end
    return false
end

function Sync:GetConfirmedOnlineFriends()
    local onlineMap = {} -- [lowerShort] = exactShortName
    local now = time()

    -- 1. Check Character Friend List (C_FriendList)
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local ok, numFriends = pcall(C_FriendList.GetNumFriends)
        numFriends = ok and ns.SafeNumber(numFriends, 0) or 0
        for i = 1, numFriends do
            local okInfo, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
            if okInfo and info and not ns.IsSecret(info) then
                local isConn = ns.SafeBoolean(info.connected)
                local fName = ns.SafeString(info.name, "")
                if isConn and fName ~= "" then
                    local short = ns.ShortName(fName)
                    local lower = short:lower()
                    if not ns.IsSelfName(short) and not self:IsTargetWhisperBlocked(short) then
                        onlineMap[lower] = short
                    end
                end
            end
        end
    end

    -- 2. Check Battle.net Friends playing on WoW
    if C_BattleNet and C_BattleNet.GetNumFriends and C_BattleNet.GetFriendAccountInfo then
        local ok, numBNet = pcall(C_BattleNet.GetNumFriends)
        numBNet = ok and ns.SafeNumber(numBNet, 0) or 0
        for i = 1, numBNet do
            local okAcc, acc = pcall(C_BattleNet.GetFriendAccountInfo, i)
            if okAcc and acc and not ns.IsSecret(acc) and acc.gameAccountInfo and not ns.IsSecret(acc.gameAccountInfo) then
                local g = acc.gameAccountInfo
                if ns.SafeBoolean(g.isOnline) then
                    local charName = ns.SafeString(g.characterName, "")
                    if charName ~= "" then
                        local short = ns.ShortName(charName)
                        local lower = short:lower()
                        if not ns.IsSelfName(short) and not self:IsTargetWhisperBlocked(short) then
                            onlineMap[lower] = short
                        end
                    end
                end
            end
        end
    end

    -- 3. Check actively verified peers from ns.onlinePeers (who aren't marked offline)
    for _, peer in pairs(ns.onlinePeers or {}) do
        local short = ns.ShortName(peer.shortName or peer.name)
        local lower = short:lower()
        if lower ~= "" and lower ~= "unbekannt" and not ns.IsSelfName(short) then
            -- Only include peers with full 2-word names (Vorname + Nachname) or confirmed WHISPER distribution
            if (short:find(" ", 1, true) or peer.distribution == "WHISPER")
                and not self:IsTargetWhisperBlocked(short)
                and (now - (peer.lastSeen or 0)) < 120 then
                onlineMap[lower] = short
            end
        end
    end

    return onlineMap
end

-- -------------------------------------------------------------------------
-- Smart Taint-Free Multi-Transport Routing
-- Includes Direct Fast-Path for ALERT packets (Death / SOS) so they never
-- wait behind BULK inventory/profession queues in ChatThrottleLib!
-- -------------------------------------------------------------------------
local function TryDirectAddonSend(prefix, encoded, distribution, target)
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false, false end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, prefix, encoded, distribution, target)
    if not ok then return false, false end
    -- Enum.SendAddonMessageResult: 0 = Success, 3 = AddonMessageThrottle, 8 = ChannelThrottle
    if res == true or res == 0 or res == nil then
        return true, false
    end
    local throttled = (res == 3 or res == 8)
    return false, throttled
end

function Sync:SendCommSafe(encoded, distribution, target, prio)
    if not encoded then return false end
    prio = prio or "NORMAL"

    -- Only allow safe, unrestricted addon distributions in Client 16001
    if distribution ~= "PARTY" and distribution ~= "RAID" and distribution ~= "INSTANCE_CHAT"
        and distribution ~= "GUILD" and distribution ~= "OFFICER" and distribution ~= "WHISPER" then
        return false
    end

    if distribution == "WHISPER" then
        if not target or target == "" then return false end
        local short = ns.ShortName(target)
        if self:IsTargetWhisperBlocked(short) then
            return false
        end
        -- In WoW: Forever every character has Vor- und Nachname (2 words).
        -- Never whisper a truncated 1-word name unless it is explicitly in C_FriendList.
        if not short:find(" ", 1, true) then
            return false
        end
        local lower = short:lower()
        local firstWord = GetFirstWordLower(short)
        local nowGT = GetTime and GetTime() or 0
        self.lastWhisperSentAt[lower] = nowGT
        self.lastWhisperSentAt[firstWord] = nowGT
        target = short
    end

    -- FAST-PATH for ALERT (Death / SOS): Bypass ChatThrottleLib queue so alerts arrive in < 1s!
    if prio == "ALERT" and #encoded <= 255 and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        -- Briefly pause ChatThrottleLib background queues so BULK packets don't steal the server token bucket
        if _G.ChatThrottleLib and _G.ChatThrottleLib.avail then
            _G.ChatThrottleLib.avail = math.min(_G.ChatThrottleLib.avail, -900)
        end

        if not self:IsMessagingLocked() then
            local sent, throttled = TryDirectAddonSend(ns.COMM_PREFIX, encoded, distribution, target)
            if sent then
                return true
            end
            if not throttled then
                return false
            end
        end

        -- If locked on the exact frame of death or server-token throttled, retry after 1.05s & 2.1s
        if C_Timer and C_Timer.After then
            C_Timer.After(1.05, function()
                if _G.ChatThrottleLib and _G.ChatThrottleLib.avail then
                    _G.ChatThrottleLib.avail = math.min(_G.ChatThrottleLib.avail, -600)
                end
                local sentRetry = TryDirectAddonSend(ns.COMM_PREFIX, encoded, distribution, target)
                if not sentRetry then
                    C_Timer.After(1.10, function()
                        TryDirectAddonSend(ns.COMM_PREFIX, encoded, distribution, target)
                    end)
                end
            end)
        end
        return true
    end

    if self:IsMessagingLocked() then return false end

    if self.SendCommMessage then
        local ok = pcall(self.SendCommMessage, self, ns.COMM_PREFIX, encoded, distribution, target, prio)
        return ok
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        if #encoded <= 250 then
            local ok = pcall(C_ChatInfo.SendAddonMessage, ns.COMM_PREFIX, encoded, distribution, target)
            return ok
        end
    end
    return false
end

function Sync:Broadcast(msgType, data, prio, whisperTarget)
    if not ns.db or not ns.db.sync or not ns.db.sync.enabled then return end
    if self:IsMessagingLocked() then return end

    local encoded = self:EncodePayload(msgType, data)
    if not encoded then return end

    prio = prio or "NORMAL"
    local onlineFriends = self:GetConfirmedOnlineFriends()

    -- Direct targeted whisper if requested and confirmed online
    if whisperTarget and whisperTarget ~= "" then
        local shortTarget = ns.ShortName(whisperTarget)
        local lower = shortTarget:lower()
        if not ns.IsSelfName(shortTarget) and onlineFriends[lower] then
            self:SendCommSafe(encoded, "WHISPER", onlineFriends[lower], prio)
        end
        return
    end

    -- 1. Party / Raid / Instance Group
    local sentGroup = false
    if ns.db.sync.usePartyRaid then
        if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then
            sentGroup = self:SendCommSafe(encoded, "INSTANCE_CHAT", nil, prio)
        elseif IsInRaid and IsInRaid() then
            sentGroup = self:SendCommSafe(encoded, "RAID", nil, prio)
        elseif IsInGroup and IsInGroup() then
            sentGroup = self:SendCommSafe(encoded, "PARTY", nil, prio)
        end
    end

    -- 2. Guild Channel (Reaches all guild friends automatically without whispers!)
    local sentGuild = false
    if ns.db.sync.useGuild and IsInGuild and IsInGuild() then
        sentGuild = self:SendCommSafe(encoded, "GUILD", nil, prio)
    end

    -- 3. Direct Whisper ONLY to confirmed ONLINE friends who are NOT already reached via Party/Raid or Guild
    for lowerName, shortName in pairs(onlineFriends) do
        local isRosterOrFriend = true
        if ns.db.sync.onlyTrustedRoster and ns.db.squadRoster then
            isRosterOrFriend = (ns.db.squadRoster[shortName] ~= nil or ns.db.squadRoster[lowerName] ~= nil)
        end
        if isRosterOrFriend then
            local inGroup = sentGroup and ((UnitInParty and UnitInParty(shortName)) or (UnitInRaid and UnitInRaid(shortName)))
            local peerKey = ns.NormalizeCharKey(shortName)
            local peer = ns.onlinePeers and (ns.onlinePeers[peerKey] or ns.onlinePeers[shortName])
            local reachedViaGuild = sentGuild and peer and peer.distribution == "GUILD"
            if not inGroup and not reachedViaGuild then
                self:SendCommSafe(encoded, "WHISPER", shortName, prio)
            end
        end
    end
end

-- -------------------------------------------------------------------------
-- Self-Purge & 1-Word Legacy Migration Helper
-- -------------------------------------------------------------------------
function Sync:PurgeSelfFromPeers()
    local myShort = ns.GetPlayerShortName()
    local myKey = ns.GetPlayerKey()
    if not myShort or myShort == "" or myShort == "Player" or myShort == "Unknown" then return end
    local myKeyLower = myKey:lower()

    for k, peer in pairs(ns.onlinePeers or {}) do
        local pShort = ns.ShortName(peer.shortName or peer.name or k)
        if k:lower() == myKeyLower or ns.IsSelfName(pShort) or pShort:lower() == "unbekannt" then
            ns.onlinePeers[k] = nil
        end
    end

    if ns.db and ns.db.squadCharacters then
        for k, rec in pairs(ns.db.squadCharacters) do
            local rShort = ns.ShortName(rec.name or k)
            if k:lower() == myKeyLower or ns.IsSelfName(rShort) then
                ns.db.squadCharacters[k] = nil
            end
        end
    end

    -- Also clean up any legacy 1-word entry in ns.db.characters if our full 2-word name is now known
    if ns.db and ns.db.characters and myShort:find(" ", 1, true) then
        local firstWord = ns.GetPlayerFirstName():lower()
        for k, rec in pairs(ns.db.characters) do
            local rShort = ns.ShortName(rec.name or k):lower()
            if k ~= myKey and rShort == firstWord then
                ns.db.characters[k] = nil
            end
        end
    end
end

-- -------------------------------------------------------------------------
-- Incoming Packet Router (Supports 2-Word Surnames in WoW: Forever)
-- -------------------------------------------------------------------------
function Sync:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= ns.COMM_PREFIX then return end
    if not ns.db or not ns.db.sync or not ns.db.sync.enabled then return end

    local envelope = self:DecodePayload(message)
    if not envelope or type(envelope.d) ~= "table" then return end

    local payloadShort = ns.ShortName(envelope.n or envelope.s)
    local rawSenderShort = (not ns.IsSecret(sender)) and ns.ShortName(sender) or ""

    -- Prefer the full 2-word name (Vorname + Nachname) from CHAT_MSG_ADDON 'sender' whenever available!
    local shortSender = payloadShort
    if rawSenderShort ~= "" and rawSenderShort ~= "Unbekannt" then
        if rawSenderShort:find(" ", 1, true) or shortSender == "" or shortSender == "Unbekannt" then
            shortSender = rawSenderShort
        end
    end

    if shortSender == "" or shortSender == "Unbekannt" then
        return
    end

    -- If this packet is our own echo and rawSenderShort has our full 2-word name, learn it!
    if ns.IsSelfName(payloadShort) or ns.IsSelfName(rawSenderShort) then
        if rawSenderShort:find(" ", 1, true) then
            ns.LearnSelfFullName(rawSenderShort)
            ns.EnsureCurrentCharacterRecord()
        end
        self:PurgeSelfFromPeers()
        return
    end

    local charKey = ns.NormalizeCharKey(shortSender)
    if charKey:lower() == ns.GetPlayerKey():lower() then
        return
    end

    if not ns.IsSquadOrFriend(shortSender) then
        return
    end

    -- If we now have a 2-word name (e.g. "Giacomo Nachname"), remove any stale 1-word peer entry ("Giacomo")
    if shortSender:find(" ", 1, true) then
        local senderFirst = GetFirstWordLower(shortSender)
        for k, existingPeer in pairs(ns.onlinePeers or {}) do
            local exShort = ns.ShortName(existingPeer.shortName or existingPeer.name or k)
            if k ~= charKey and not exShort:find(" ", 1, true) and exShort:lower() == senderFirst then
                ns.onlinePeers[k] = nil
            end
        end
        if ns.db and ns.db.squadCharacters then
            for k, existingRec in pairs(ns.db.squadCharacters) do
                local exShort = ns.ShortName(existingRec.name or k)
                if k ~= charKey and not exShort:find(" ", 1, true) and exShort:lower() == senderFirst then
                    ns.db.squadCharacters[k] = nil
                end
            end
        end
    end

    -- Only clear offline cache if the packet actually arrived via WHISPER
    if distribution == "WHISPER" then
        self.offlineCache[shortSender:lower()] = nil
        self.offlineCache[GetFirstWordLower(shortSender)] = nil
    end

    local msgType = envelope.t
    local data = envelope.d

    -- Normalize envelope fields so downstream modules store the full 2-word character name
    data.key = charKey
    data.name = shortSender

    -- Update live peer presence table
    local peer = ns.onlinePeers[charKey] or {}
    local peerFaction = ns.NormalizeFaction(envelope.f or data.faction or peer.faction or ns.GetPlayerFaction())
    peer.key = charKey
    peer.name = shortSender
    peer.shortName = shortSender
    peer.class = ns.SafeString(envelope.c, peer.class or "WARRIOR")
    peer.level = ns.SafeNumber(envelope.l, peer.level or 1)
    peer.faction = peerFaction
    peer.lastSeen = time()
    peer.distribution = distribution
    ns.onlinePeers[charKey] = peer

    data.faction = peerFaction

    -- Dispatch to feature modules
    if msgType == "HELLO" then
        self:HandleHello(charKey, peer, data, distribution)
    elseif msgType == "REQ_SYNC" then
        local replyWhisper = (distribution == "WHISPER") and shortSender or nil
        self:BroadcastFullState(false, replyWhisper)
    elseif msgType == "GPS" then
        if ns.Radar and ns.Radar.OnReceiveGPS then
            ns.Radar:OnReceiveGPS(charKey, peer, data)
        end
    elseif msgType == "INV" then
        if ns.Inventory and ns.Inventory.OnReceiveInventory then
            ns.Inventory:OnReceiveInventory(charKey, peer, data)
        end
    elseif msgType == "PROF" then
        if ns.Inventory and ns.Inventory.OnReceiveProfessions then
            ns.Inventory:OnReceiveProfessions(charKey, peer, data)
        end
    elseif msgType == "QUEST" then
        if ns.Quests and ns.Quests.OnReceiveQuests then
            ns.Quests:OnReceiveQuests(charKey, peer, data)
        end
    elseif msgType == "ALERT" then
        if ns.Radar and ns.Radar.OnReceiveAlert then
            ns.Radar:OnReceiveAlert(charKey, peer, data)
        end
    elseif msgType == "STATS" then
        if ns.Stats and ns.Stats.OnReceiveStats then
            ns.Stats:OnReceiveStats(charKey, peer, data)
        end
    end

    ns.SendMessage("PEER_UPDATED", charKey, msgType)
end

function Sync:HandleHello(charKey, peer, data, distribution)
    peer.zone = ns.SafeString(data.zone, peer.zone or "Unbekannt")
    peer.subzone = ns.SafeString(data.subzone, peer.subzone or "")
    peer.mapID = ns.SafeNumber(data.mapID, peer.mapID or 0)
    peer.x = ns.SafeNumber(data.x, peer.x or 0)
    peer.y = ns.SafeNumber(data.y, peer.y or 0)
    peer.lockouts = ns.SafeNumber(data.lockouts, peer.lockouts or 0)

    if data.wantReply then
        -- Reply over shared channel (GUILD/PARTY/RAID) unless the HELLO came via direct WHISPER
        local replyWhisper = (distribution == "WHISPER") and peer.shortName or nil
        self:SendHello(false, replyWhisper)
        local nowGT = GetTime and GetTime() or 0
        if replyWhisper or (nowGT - (self.lastAutoFullSyncAt or 0)) > 25 then
            self.lastAutoFullSyncAt = nowGT
            self:BroadcastFullState(false, replyWhisper)
        end
    end
end

function Sync:SendHello(wantReply, whisperTarget)
    local zone, subzone, mapID, x, y = ns.GetPlayerLocationData()
    local lockouts = (ns.QoL and ns.QoL.GetActiveLockoutCount and ns.QoL:GetActiveLockoutCount()) or 0
    self:Broadcast("HELLO", {
        zone = zone,
        subzone = subzone,
        mapID = mapID,
        x = x,
        y = y,
        lockouts = lockouts,
        wantReply = wantReply == true,
    }, "NORMAL", whisperTarget)
end

function Sync:RequestSquadSync()
    self:Broadcast("REQ_SYNC", { ts = time() }, "NORMAL")
end

function Sync:BroadcastFullState(verbose, whisperTarget)
    if not ns.db or not ns.db.sync or not ns.db.sync.enabled then
        if verbose then ns.Print("Synchronisation ist in den Einstellungen deaktiviert.") end
        return
    end

    self:PurgeSelfFromPeers()

    if ns.Inventory then
        ns.Inventory:ScanBagsAndEquipment(true)
        ns.Inventory:BroadcastInventory(whisperTarget)
        ns.Inventory:BroadcastProfessions(whisperTarget)
    end

    if ns.Quests then
        ns.Quests:ScanQuestLog(true)
        ns.Quests:BroadcastQuests(whisperTarget)
    end

    if ns.Radar then
        ns.Radar:BroadcastGPS(whisperTarget)
    end

    if ns.Stats then
        ns.Stats:BroadcastStats(whisperTarget)
    end

    if verbose then
        ns.Print("Vollständiger Gruppen-Sync gesendet (Inventar, Berufe, Quests, GPS & Statistik).")
    end
end

-- -------------------------------------------------------------------------
-- Offline Player System Message Tracker & Chat-Spam Guard
-- -------------------------------------------------------------------------
ns.RegisterEvent("CHAT_MSG_SYSTEM", function(_, msg)
    if ns.IsSecret(msg) or type(msg) ~= "string" then return end
    local offlineName = msg:match("Spieler mit dem Namen '([^']+)'")
        or msg:match("No player named '([^']+)'")
    if offlineName and offlineName ~= "" then
        local short = ns.ShortName(offlineName)
        local lower = short:lower()
        local firstWord = GetFirstWordLower(short)
        local now = time()
        Sync.offlineCache[lower] = now
        if firstWord ~= "" then
            Sync.offlineCache[firstWord] = now
        end
        for k, peer in pairs(ns.onlinePeers or {}) do
            local pShort = ns.ShortName(peer.shortName or peer.name or k)
            local pLower = pShort:lower()
            if pLower == lower or ( not pShort:find(" ", 1, true) and GetFirstWordLower(pShort) == firstWord ) then
                peer.lastSeen = 0
                ns.onlinePeers[k] = nil
            end
        end
        ns.SendMessage("PEER_UPDATED")
    end
end)

if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg, ...)
        if ns.IsSecret(msg) or type(msg) ~= "string" then return false end
        local offlineName = msg:match("Spieler mit dem Namen '([^']+)'")
            or msg:match("No player named '([^']+)'")
        if offlineName and offlineName ~= "" then
            local short = ns.ShortName(offlineName)
            local lower = short:lower()
            local firstWord = GetFirstWordLower(short)
            local nowGT = GetTime and GetTime() or 0
            local sentAt = Sync.lastWhisperSentAt[lower] or Sync.lastWhisperSentAt[firstWord]
            if sentAt and (nowGT - sentAt) < 4.0 then
                Sync.offlineCache[lower] = time()
                if firstWord ~= "" then
                    Sync.offlineCache[firstWord] = time()
                end
                return true -- Suppress addon-triggered offline whisper notice
            end
        end
        return false
    end)
end

-- -------------------------------------------------------------------------
-- Initialization
-- -------------------------------------------------------------------------
ns.RegisterMessage("ADDON_INITIALIZED", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, ns.COMM_PREFIX)
    end
    if Sync.RegisterComm then
        Sync:RegisterComm(ns.COMM_PREFIX, "OnCommReceived")
    end
end)

ns.RegisterMessage("PLAYER_READY", function()
    Sync:PurgeSelfFromPeers()
    Sync:LeaveCustomChannel()
    if C_FriendList and C_FriendList.ShowFriends then
        pcall(C_FriendList.ShowFriends)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(2.0, function()
            Sync:PurgeSelfFromPeers()
            Sync:LeaveCustomChannel()
            Sync:SendHello(true)
        end)
        C_Timer.After(4.5, function()
            Sync:BroadcastFullState(false)
        end)
    else
        Sync:SendHello(true)
    end
end)

ns.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(1.5, function()
            Sync:SendHello(false)
        end)
    end
end)

ns.RegisterEvent("FRIENDLIST_UPDATE", function()
    Sync:PurgeSelfFromPeers()
end)
