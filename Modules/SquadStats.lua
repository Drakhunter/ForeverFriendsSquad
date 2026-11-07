-- =========================================================================
-- Modules/SquadStats.lua
-- Priority 5: Squad Hall of Fame / Shame Statistics (Deaths, Repair Gold,
-- Quests Completed, Epic 100-Rolls & 1-Roll Fails) + Safe Repair Tracking.
-- Target Client: World of Warcraft: Forever (Interface: 16001)
-- =========================================================================
local addonName, ns = ...

local Stats = {}
ns.Stats = Stats

local pendingRepairCost = 0

function Stats:EnsurePlayerStats()
    local rec = ns.EnsureCurrentCharacterRecord()
    if not rec then return nil end
    rec.stats = rec.stats or {}
    rec.stats.deaths = ns.SafeNumber(rec.stats.deaths, 0)
    rec.stats.repairCopper = ns.SafeNumber(rec.stats.repairCopper, 0)
    rec.stats.questsCompleted = ns.SafeNumber(rec.stats.questsCompleted, 0)
    rec.stats.highRolls = ns.SafeNumber(rec.stats.highRolls, 0)
    rec.stats.onesRolled = ns.SafeNumber(rec.stats.onesRolled, 0)
    return rec.stats, rec
end

function Stats:RecordDeath()
    if not ns.db or not ns.db.stats or not ns.db.stats.enabled or not ns.db.stats.trackDeaths then return end
    local st = self:EnsurePlayerStats()
    if not st then return end
    st.deaths = (st.deaths or 0) + 1
    self:BroadcastStats()
    ns.SendMessage("STATS_UPDATED")
end

function Stats:RecordQuestCompleted()
    if not ns.db or not ns.db.stats or not ns.db.stats.enabled or not ns.db.stats.trackQuests then return end
    local st = self:EnsurePlayerStats()
    if not st then return end
    st.questsCompleted = (st.questsCompleted or 0) + 1
    self:BroadcastStats()
    ns.SendMessage("STATS_UPDATED")
end

function Stats:RecordRepairCost(copper)
    if not ns.db or not ns.db.stats or not ns.db.stats.enabled or not ns.db.stats.trackRepairs then return end
    copper = ns.SafeNumber(copper, 0)
    if copper <= 0 then return end
    local st = self:EnsurePlayerStats()
    if not st then return end
    st.repairCopper = (st.repairCopper or 0) + copper
    self:BroadcastStats()
    ns.SendMessage("STATS_UPDATED")
end

function Stats:BroadcastStats(whisperTarget)
    if not ns.Sync or not ns.db or not ns.db.stats or not ns.db.stats.enabled then return end
    local st, rec = self:EnsurePlayerStats()
    if not st or not rec then return end

    ns.Sync:Broadcast("STATS", {
        key = rec.key,
        name = rec.name,
        class = rec.class,
        level = rec.level,
        faction = rec.faction,
        stats = st,
    }, "NORMAL", whisperTarget)
end

function Stats:OnReceiveStats(charKey, peer, data)
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

    if type(data.stats) == "table" then
        rec.stats = data.stats
    end
    rec.updatedAt = time()
    ns.db.squadCharacters[targetKey] = rec
    ns.SendMessage("STATS_UPDATED", targetKey)
end

-- -------------------------------------------------------------------------
-- Roll Parser & Taint-Free Repair Tracker
-- -------------------------------------------------------------------------
ns.RegisterEvent("CHAT_MSG_SYSTEM", function(_, msg)
    if not ns.db or not ns.db.stats or not ns.db.stats.enabled or not ns.db.stats.trackRolls then return end
    if ns.IsSecret(msg) or type(msg) ~= "string" then return end

    local roller, rollVal, minR, maxR = msg:match("^(.+)%s+w%S*rfelt%.%s*Ergebnis:%s*(%d+)%s*%((%d+)%-(%d+)%)")
    if not roller then
        roller, rollVal, minR, maxR = msg:match("^(.+)%s+rolls%s+(%d+)%s*%((%d+)%-(%d+)%)")
    end

    if roller and ns.IsSelfName(roller) and tonumber(minR) == 1 and tonumber(maxR) == 100 then
        local val = tonumber(rollVal)
        local st = Stats:EnsurePlayerStats()
        if not st then return end
        if val == 100 then
            st.highRolls = (st.highRolls or 0) + 1
            ns.Print("|cffffd100[EPISCHE 100!]|r Dein 100er-Wurf wurde in der Squad-Ruhmeshalle verewigt!")
            Stats:BroadcastStats()
            ns.SendMessage("STATS_UPDATED")
        elseif val == 1 then
            st.onesRolled = (st.onesRolled or 0) + 1
            ns.Print("|cfff87171[KRITISCHE 1!]|r Dein 1er-Wurf wurde für die Ewigkeit notiert...")
            Stats:BroadcastStats()
            ns.SendMessage("STATS_UPDATED")
        end
    end
end)

ns.RegisterEvent("MERCHANT_SHOW", function()
    if not CanMerchantRepair or not CanMerchantRepair() then
        pendingRepairCost = 0
        return
    end
    local repairCost, canRepair = GetRepairAllCost()
    repairCost = ns.SafeNumber(repairCost, 0)
    if not canRepair or repairCost <= 0 then
        pendingRepairCost = 0
        return
    end

    pendingRepairCost = repairCost
end)

ns.RegisterEvent("UPDATE_INVENTORY_DURABILITY", function()
    if pendingRepairCost > 0 and CanMerchantRepair and CanMerchantRepair() then
        local newCost = GetRepairAllCost and ns.SafeNumber(GetRepairAllCost(), 0) or 0
        if newCost == 0 then
            Stats:RecordRepairCost(pendingRepairCost)
            pendingRepairCost = 0
        end
    end
end)

ns.RegisterEvent("MERCHANT_CLOSED", function()
    pendingRepairCost = 0
end)
