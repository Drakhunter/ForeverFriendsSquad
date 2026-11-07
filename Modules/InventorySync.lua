-- =========================================================================
-- Modules/InventorySync.lua
-- Priority 1 (Mandatory): Shared Squad Inventory, Bank, Twinks, Gold,
-- Profession/Recipe Browser, Item Tooltip Hooks, and Smart Trade Helper.
-- Target Client: World of Warcraft: Forever (Interface: 16001)
-- =========================================================================
local addonName, ns = ...

local Inventory = {}
ns.Inventory = Inventory

local bankIsOpen = false
local scanPending = false
local broadcastPending = false

-- -------------------------------------------------------------------------
-- Item Metadata Resolution & Caching
-- -------------------------------------------------------------------------
function Inventory:GetItemMetadata(itemID)
    itemID = ns.SafeNumber(itemID, 0)
    if itemID <= 0 then return nil end

    ns.db.itemMeta = ns.db.itemMeta or {}
    local cached = ns.db.itemMeta[itemID]

    local name, link, quality, icon, classID, subClassID
    if C_Item and C_Item.GetItemInfo then
        local n, l, q, _, _, _, _, _, _, tex, _, cID, scID = C_Item.GetItemInfo(itemID)
        if not ns.IsSecret(n) and n then
            name, link, quality, icon, classID, subClassID = n, l, q, tex, cID, scID
        end
    elseif GetItemInfo then
        local n, l, q, _, _, _, _, _, _, tex, _, cID, scID = GetItemInfo(itemID)
        if not ns.IsSecret(n) and n then
            name, link, quality, icon, classID, subClassID = n, l, q, tex, cID, scID
        end
    end

    if not icon and C_Item and C_Item.GetItemIconByID then
        local tex = C_Item.GetItemIconByID(itemID)
        if not ns.IsSecret(tex) then icon = tex end
    end

    if name and name ~= "" then
        cached = {
            name = ns.SafeString(name, "Item #" .. itemID),
            link = ns.SafeString(link, nil),
            quality = ns.SafeNumber(quality, 1),
            icon = icon or (cached and cached.icon) or "Interface\\Icons\\INV_Misc_QuestionMark",
            classID = ns.SafeNumber(classID, 0),
            subClassID = ns.SafeNumber(subClassID, 0),
        }
        ns.db.itemMeta[itemID] = cached
        return cached
    end

    if cached then
        return cached
    end

    return {
        name = "Item #" .. itemID,
        quality = 1,
        icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        classID = 0,
        subClassID = 0,
    }
end

-- -------------------------------------------------------------------------
-- Container & Equipment Scanner
-- -------------------------------------------------------------------------
local function GetNumSlots(bagID)
    if C_Container and C_Container.GetContainerNumSlots then
        return ns.SafeNumber(C_Container.GetContainerNumSlots(bagID), 0)
    elseif GetContainerNumSlots then
        return ns.SafeNumber(GetContainerNumSlots(bagID), 0)
    end
    return 0
end

local function GetSlotItemInfo(bagID, slotID)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagID, slotID)
        if info and not ns.IsSecret(info) then
            local itemID = ns.SafeNumber(info.itemID, 0)
            local count = ns.SafeNumber(info.stackCount, 1)
            local link = ns.SafeString(info.hyperlink, nil)
            local icon = info.iconFileID
            local quality = ns.SafeNumber(info.quality, nil)
            if itemID > 0 then
                return itemID, count, link, icon, quality
            end
        end
    elseif GetContainerItemInfo then
        local icon, count, _, quality, _, _, link, _, _, itemID = GetContainerItemInfo(bagID, slotID)
        itemID = ns.SafeNumber(itemID, 0)
        if itemID == 0 and link and not ns.IsSecret(link) then
            itemID = tonumber(link:match("item:(%d+)")) or 0
        end
        if itemID > 0 then
            return itemID, ns.SafeNumber(count, 1), ns.SafeString(link, nil), icon, ns.SafeNumber(quality, nil)
        end
    end
    return nil
end

function Inventory:ScanBagsAndEquipment(silent)
    if not ns.db or not ns.db.inventory or not ns.db.inventory.enabled then return end
    local rec = ns.EnsureCurrentCharacterRecord()
    if not rec then return end

    -- 1. Scan Bags (0..4, plus 5 if ReagentBag)
    local bags = {}
    local freeSlots = 0
    local totalSlots = 0
    local maxBag = (NUM_TOTAL_EQUIPPED_BAG_SLOTS and ns.SafeNumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS, 4)) or 4

    for bagID = 0, maxBag do
        local numSlots = GetNumSlots(bagID)
        if numSlots > 0 then
            totalSlots = totalSlots + numSlots
            for slot = 1, numSlots do
                local itemID, count, link, icon, quality = GetSlotItemInfo(bagID, slot)
                if itemID and itemID > 0 then
                    bags[itemID] = (bags[itemID] or 0) + count
                    local meta = self:GetItemMetadata(itemID)
                    if meta then
                        if icon and not ns.IsSecret(icon) then meta.icon = icon end
                        if quality then meta.quality = quality end
                        if link and not meta.link then meta.link = link end
                    end
                else
                    freeSlots = freeSlots + 1
                end
            end
        end
    end

    rec.bags = bags
    rec.bagFree = freeSlots
    rec.bagTotal = totalSlots

    -- 2. Scan Equipped Items (1..19)
    local equip = {}
    for invSlot = 1, 19 do
        local itemID = GetInventoryItemID and GetInventoryItemID("player", invSlot)
        itemID = ns.SafeNumber(itemID, 0)
        if itemID > 0 then
            equip[itemID] = (equip[itemID] or 0) + 1
            self:GetItemMetadata(itemID)
        end
    end
    rec.equip = equip

    -- 3. Scan Gold & Level
    rec.money = ns.SafeNumber(GetMoney and GetMoney(), rec.money or 0)
    rec.level = ns.GetPlayerLevel()
    rec.updatedAt = time()

    -- 4. Scan Bank if currently open
    if bankIsOpen then
        self:ScanBank()
    end

    if not silent then
        ns.SendMessage("INVENTORY_UPDATED", rec.key)
    end
end

function Inventory:ScanBank()
    if not bankIsOpen or not ns.db then return end
    local rec = ns.EnsureCurrentCharacterRecord()
    if not rec then return end

    local bank = {}
    local bankContainers = { -1, 5, 6, 7, 8, 9, 10, 11 }
    if NUM_BAG_SLOTS and NUM_BANKBAGSLOTS then
        bankContainers = { -1 }
        local startBag = ns.SafeNumber(NUM_BAG_SLOTS, 4) + 1
        local endBag = startBag + ns.SafeNumber(NUM_BANKBAGSLOTS, 7) - 1
        for b = startBag, endBag do
            bankContainers[#bankContainers + 1] = b
        end
    end

    local foundAny = false
    for _, bagID in ipairs(bankContainers) do
        local numSlots = GetNumSlots(bagID)
        if numSlots > 0 then
            foundAny = true
            for slot = 1, numSlots do
                local itemID, count, link, icon, quality = GetSlotItemInfo(bagID, slot)
                if itemID and itemID > 0 then
                    bank[itemID] = (bank[itemID] or 0) + count
                    local meta = self:GetItemMetadata(itemID)
                    if meta then
                        if icon and not ns.IsSecret(icon) then meta.icon = icon end
                        if quality then meta.quality = quality end
                        if link and not meta.link then meta.link = link end
                    end
                end
            end
        end
    end

    if foundAny then
        rec.bank = bank
        rec.bankUpdatedAt = time()
        ns.SendMessage("INVENTORY_UPDATED", rec.key)
    end
end

-- -------------------------------------------------------------------------
-- Professions & Recipes Scanner (Modern C_TradeSkillUI + Classic Fallback)
-- -------------------------------------------------------------------------
function Inventory:ScanOpenTradeSkill()
    if not ns.db or not ns.db.inventory or not ns.db.inventory.scanProfessionsAutomatically then return end
    local rec = ns.EnsureCurrentCharacterRecord()
    if not rec then return end
    rec.professions = rec.professions or {}

    -- Path A: C_TradeSkillUI (Modern / Retail-backed Client)
    if C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady and C_TradeSkillUI.IsTradeSkillReady() then
        local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
        local profName = info and ns.SafeString(info.professionName, nil)
        local skillLevel = info and ns.SafeNumber(info.skillLevel, 0) or 0
        local maxSkill = info and ns.SafeNumber(info.maxSkillLevel, 0) or 0

        if profName and profName ~= "" and profName ~= "UNKNOWN" then
            local profRec = rec.professions[profName] or {
                name = profName,
                rank = skillLevel,
                maxRank = maxSkill,
                recipes = {},
            }
            profRec.rank = skillLevel
            profRec.maxRank = maxSkill
            profRec.recipes = profRec.recipes or {}

            local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetAllRecipeIDs()
            if type(recipeIDs) == "table" then
                for _, recipeID in ipairs(recipeIDs) do
                    local rInfo = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
                    if rInfo and not ns.IsSecret(rInfo) and rInfo.learned then
                        local rName = ns.SafeString(rInfo.name, nil)
                        local itemLink = C_TradeSkillUI.GetRecipeItemLink and C_TradeSkillUI.GetRecipeItemLink(recipeID)
                        local itemID = 0
                        if itemLink and not ns.IsSecret(itemLink) then
                            itemID = tonumber(itemLink:match("item:(%d+)")) or 0
                        end
                        if rName and rName ~= "" then
                            local reagents = {}
                            if C_TradeSkillUI.GetRecipeSchematic then
                                local okS, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
                                if okS and type(schematic) == "table" and type(schematic.reagentSlotSchematics) == "table" then
                                    for _, slot in ipairs(schematic.reagentSlotSchematics) do
                                        local reqQty = ns.SafeNumber(slot.quantityRequired, 1)
                                        local firstReagent = type(slot.reagents) == "table" and slot.reagents[1]
                                        local rItemID = firstReagent and ns.SafeNumber(firstReagent.itemID, 0) or 0
                                        if rItemID > 0 and reqQty > 0 then
                                            local rMeta = self:GetItemMetadata(rItemID)
                                            reagents[#reagents + 1] = {
                                                id = rItemID,
                                                name = rMeta and rMeta.name or ("Item #" .. rItemID),
                                                count = reqQty,
                                                icon = rMeta and rMeta.icon,
                                            }
                                        end
                                    end
                                end
                            elseif C_TradeSkillUI.GetRecipeNumReagents then
                                local numReagents = ns.SafeNumber(C_TradeSkillUI.GetRecipeNumReagents(recipeID), 0)
                                for rIdx = 1, numReagents do
                                    local rMatName, rMatIcon, rMatCount = C_TradeSkillUI.GetRecipeReagentInfo(recipeID, rIdx)
                                    local rLink = C_TradeSkillUI.GetRecipeReagentItemLink and C_TradeSkillUI.GetRecipeReagentItemLink(recipeID, rIdx)
                                    local rItemID = 0
                                    if rLink and not ns.IsSecret(rLink) then
                                        rItemID = tonumber(rLink:match("item:(%d+)")) or 0
                                    end
                                    rMatCount = ns.SafeNumber(rMatCount, 1)
                                    if (rItemID > 0 or (rMatName and not ns.IsSecret(rMatName))) and rMatCount > 0 then
                                        reagents[#reagents + 1] = {
                                            id = rItemID > 0 and rItemID or nil,
                                            name = ns.SafeString(rMatName, rItemID > 0 and ("Item #" .. rItemID) or "Material"),
                                            count = rMatCount,
                                            icon = not ns.IsSecret(rMatIcon) and rMatIcon or nil,
                                        }
                                        if rItemID > 0 then self:GetItemMetadata(rItemID) end
                                    end
                                end
                            end

                            local key = itemID > 0 and ("item:" .. itemID) or ("recipe:" .. recipeID)
                            local existing = profRec.recipes[key]
                            profRec.recipes[key] = {
                                name = rName,
                                recipeID = recipeID,
                                itemID = itemID > 0 and itemID or nil,
                                icon = rInfo.icon,
                                reagents = #reagents > 0 and reagents or (existing and existing.reagents) or nil,
                            }
                            if itemID > 0 then self:GetItemMetadata(itemID) end
                        end
                    end
                end
            end

            profRec.updatedAt = time()
            rec.professions[profName] = profRec
            ns.SendMessage("PROFESSIONS_UPDATED", rec.key, profName)
            if ns.Sync and ns.Sync.MarkDirty then
                ns.Sync:MarkDirty("PROF", 3.0)
            end
            return
        end
    end

    -- Path B: Classic GetTradeSkillLine / GetNumTradeSkills
    if GetTradeSkillLine and GetNumTradeSkills then
        local profName, rank, maxRank = GetTradeSkillLine()
        profName = ns.SafeString(profName, nil)
        if profName and profName ~= "" and profName ~= "UNKNOWN" then
            local profRec = rec.professions[profName] or {
                name = profName,
                rank = ns.SafeNumber(rank, 0),
                maxRank = ns.SafeNumber(maxRank, 0),
                recipes = {},
            }
            profRec.rank = ns.SafeNumber(rank, profRec.rank)
            profRec.maxRank = ns.SafeNumber(maxRank, profRec.maxRank)
            profRec.recipes = profRec.recipes or {}

            local numSkills = ns.SafeNumber(GetNumTradeSkills(), 0)
            for i = 1, numSkills do
                local skillName, skillType = GetTradeSkillInfo(i)
                skillName = ns.SafeString(skillName, nil)
                if skillName and skillType ~= "header" and skillType ~= "subheader" then
                    local link = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
                    local itemID = 0
                    if link and not ns.IsSecret(link) then
                        itemID = tonumber(link:match("item:(%d+)")) or 0
                    end
                    local icon = GetTradeSkillIcon and GetTradeSkillIcon(i)
                    local reagents = {}
                    if GetTradeSkillNumReagents and GetTradeSkillReagentInfo then
                        local numReagents = ns.SafeNumber(GetTradeSkillNumReagents(i), 0)
                        for rIdx = 1, numReagents do
                            local rMatName, rMatIcon, rMatCount = GetTradeSkillReagentInfo(i, rIdx)
                            local rLink = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, rIdx)
                            local rItemID = 0
                            if rLink and not ns.IsSecret(rLink) then
                                rItemID = tonumber(rLink:match("item:(%d+)")) or 0
                            end
                            rMatCount = ns.SafeNumber(rMatCount, 1)
                            if (rItemID > 0 or (rMatName and not ns.IsSecret(rMatName))) and rMatCount > 0 then
                                reagents[#reagents + 1] = {
                                    id = rItemID > 0 and rItemID or nil,
                                    name = ns.SafeString(rMatName, rItemID > 0 and ("Item #" .. rItemID) or "Material"),
                                    count = rMatCount,
                                    icon = not ns.IsSecret(rMatIcon) and rMatIcon or nil,
                                }
                                if rItemID > 0 then self:GetItemMetadata(rItemID) end
                            end
                        end
                    end

                    local key = itemID > 0 and ("item:" .. itemID) or ("skill:" .. skillName)
                    local existing = profRec.recipes[key]
                    profRec.recipes[key] = {
                        name = skillName,
                        itemID = itemID > 0 and itemID or nil,
                        icon = not ns.IsSecret(icon) and icon or nil,
                        reagents = #reagents > 0 and reagents or (existing and existing.reagents) or nil,
                    }
                    if itemID > 0 then self:GetItemMetadata(itemID) end
                end
            end

            profRec.updatedAt = time()
            rec.professions[profName] = profRec
            ns.SendMessage("PROFESSIONS_UPDATED", rec.key, profName)
            if ns.Sync and ns.Sync.MarkDirty then
                ns.Sync:MarkDirty("PROF", 3.0)
            end
        end
    end
end

-- -------------------------------------------------------------------------
-- Network Sync Broadcast & Receive (With Strict Content Hash Guard!)
-- -------------------------------------------------------------------------
local function SerializeMapSorted(tbl)
    if type(tbl) ~= "table" then return "" end
    local parts = {}
    for k, v in pairs(tbl) do
        parts[#parts + 1] = tostring(k) .. ":" .. tostring(v)
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

function Inventory:ComputeInventoryHash(rec)
    if type(rec) ~= "table" then return "" end
    -- Bucket money by Gold (10000 copper) so looting 3 copper doesn't trigger a full inventory broadcast
    local goldBucket = math.floor(ns.SafeNumber(rec.money, 0) / 10000)
    return string.format(
        "G:%d|B:%s|K:%s|E:%s",
        goldBucket,
        SerializeMapSorted(rec.bags),
        SerializeMapSorted(rec.bank),
        SerializeMapSorted(rec.equip)
    )
end

function Inventory:ComputeProfessionsHash(rec)
    if type(rec) ~= "table" or type(rec.professions) ~= "table" then return "" end
    local pParts = {}
    for pName, prof in pairs(rec.professions) do
        if type(prof) == "table" then
            local rKeys = {}
            for rKey, rInfo in pairs(prof.recipes or {}) do
                local rgCnt = (type(rInfo.reagents) == "table") and #rInfo.reagents or 0
                rKeys[#rKeys + 1] = tostring(rKey) .. "#" .. rgCnt
            end
            table.sort(rKeys)
            pParts[#pParts + 1] = string.format("%s:%d:%d:[%s]", pName, prof.rank or 0, prof.maxRank or 0, table.concat(rKeys, ","))
        end
    end
    table.sort(pParts)
    return table.concat(pParts, "|")
end

function Inventory:QueueScanAndSync()
    if scanPending then return end
    scanPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(1.5, function()
            scanPending = false
            self:ScanBagsAndEquipment(false)
            if ns.db and ns.db.sync and ns.db.sync.autoBroadcastInventory then
                self:QueueBroadcast()
            end
        end)
    else
        scanPending = false
        self:ScanBagsAndEquipment(false)
    end
end

function Inventory:QueueBroadcast()
    if ns.Sync and ns.Sync.MarkDirty then
        ns.Sync:MarkDirty("INV", 5.0)
    end
end

function Inventory:BroadcastInventory(whisperTarget, force)
    if not ns.Sync or not ns.db then return end
    local rec = ns.EnsureCurrentCharacterRecord()
    if not rec then return end

    local invHash = self:ComputeInventoryHash(rec)
    local isTargeted = (whisperTarget ~= nil and whisperTarget ~= "")
    if not isTargeted and not ns.Sync:HasStateChanged("INV", invHash, force) then
        return -- Content unchanged (e.g. only sorted bag slots) -> 0 packets sent!
    end

    ns.Sync:Broadcast("INV", {
        key = rec.key,
        name = rec.name,
        realm = rec.realm,
        class = rec.class,
        level = rec.level,
        faction = rec.faction,
        money = rec.money,
        bagFree = rec.bagFree,
        bagTotal = rec.bagTotal,
        bags = rec.bags,
        bank = rec.bank,
        equip = rec.equip,
    }, "BULK", whisperTarget)

    if not isTargeted then
        ns.Sync:CommitSentHash("INV", invHash)
    end
end

function Inventory:BroadcastProfessions(whisperTarget, force)
    if not ns.Sync or not ns.db then return end
    local rec = ns.EnsureCurrentCharacterRecord()
    if not rec or not rec.professions or not next(rec.professions) then return end

    local profHash = self:ComputeProfessionsHash(rec)
    local isTargeted = (whisperTarget ~= nil and whisperTarget ~= "")
    if not isTargeted and not ns.Sync:HasStateChanged("PROF", profHash, force) then
        return -- Professions & recipes unchanged -> 0 packets sent!
    end

    -- Compact profession payload (strip redundant icon paths & reagent names over the wire)
    local compactProfs = {}
    for profName, prof in pairs(rec.professions) do
        if type(prof) == "table" then
            local cRecipes = {}
            for rKey, rInfo in pairs(prof.recipes or {}) do
                local cReagents = nil
                if type(rInfo.reagents) == "table" and #rInfo.reagents > 0 then
                    cReagents = {}
                    for _, rg in ipairs(rInfo.reagents) do
                        cReagents[#cReagents + 1] = {
                            id = rg.id,
                            count = rg.count,
                            name = (not rg.id) and rg.name or nil,
                        }
                    end
                end
                cRecipes[rKey] = {
                    name = rInfo.name,
                    itemID = rInfo.itemID,
                    recipeID = rInfo.recipeID,
                    reagents = cReagents,
                }
            end
            compactProfs[profName] = {
                name = prof.name or profName,
                rank = prof.rank,
                maxRank = prof.maxRank,
                recipes = cRecipes,
            }
        end
    end

    ns.Sync:Broadcast("PROF", {
        key = rec.key,
        name = rec.name,
        class = rec.class,
        level = rec.level,
        faction = rec.faction,
        professions = compactProfs,
    }, "BULK", whisperTarget)

    if not isTargeted then
        ns.Sync:CommitSentHash("PROF", profHash)
    end
end

function Inventory:OnReceiveInventory(charKey, peer, data)
    if not ns.db or type(data) ~= "table" then return end
    ns.db.squadCharacters = ns.db.squadCharacters or {}
    ns.db.itemMeta = ns.db.itemMeta or {}

    if type(data.meta) == "table" then
        for itemID, info in pairs(data.meta) do
            if type(info) == "table" and info[1] then
                local existing = ns.db.itemMeta[itemID] or {}
                existing.name = existing.name or info[1]
                if existing.name:find("^Item #") then existing.name = info[1] end
                existing.icon = existing.icon or info[2] or "Interface\\Icons\\INV_Misc_QuestionMark"
                existing.quality = existing.quality or info[3] or 1
                ns.db.itemMeta[itemID] = existing
            end
        end
    end

    local targetKey = ns.NormalizeCharKey(data.key or charKey)
    if targetKey:lower() == ns.GetPlayerKey():lower() or ns.IsSelfName(targetKey) then return end
    local rec = ns.db.squadCharacters[targetKey] or {}
    rec.key = targetKey
    rec.owner = peer.shortName or ns.ShortName(targetKey)
    rec.name = ns.SafeString(data.name, ns.ShortName(targetKey))
    rec.realm = ns.SafeString(data.realm, "")
    rec.class = ns.SafeString(data.class, peer.class or "WARRIOR")
    rec.level = ns.SafeNumber(data.level, peer.level or 1)
    rec.faction = ns.SafeString(data.faction, "Neutral")
    rec.money = ns.SafeNumber(data.money, rec.money or 0)
    rec.bagFree = ns.SafeNumber(data.bagFree, 0)
    rec.bagTotal = ns.SafeNumber(data.bagTotal, 0)
    rec.bags = type(data.bags) == "table" and data.bags or (rec.bags or {})
    rec.bank = type(data.bank) == "table" and data.bank or (rec.bank or {})
    rec.equip = type(data.equip) == "table" and data.equip or (rec.equip or {})
    rec.updatedAt = time()

    ns.db.squadCharacters[targetKey] = rec
    ns.SendMessage("INVENTORY_UPDATED", targetKey)
end

function Inventory:OnReceiveProfessions(charKey, peer, data)
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

    if type(data.professions) == "table" then
        rec.professions = data.professions
    end
    rec.updatedAt = time()
    ns.db.squadCharacters[targetKey] = rec
    ns.SendMessage("PROFESSIONS_UPDATED", targetKey)
end

-- -------------------------------------------------------------------------
-- Item Query Engine (Used by Tooltips & Inventory UI)
-- -------------------------------------------------------------------------
function Inventory:GetItemHolders(itemID, applyGlobalFilter)
    itemID = ns.SafeNumber(itemID, 0)
    if itemID <= 0 or not ns.db then return {}, {}, 0, 0, {} end

    local ownList = {}
    local squadList = {}
    local ownTotal = 0
    local squadTotal = 0
    local crafters = {}

    local function checkChar(rec, isOwn)
        if type(rec) ~= "table" then return end
        local charName = rec.name or ns.ShortName(rec.key)
        local charFaction = ns.ResolveCharacterFaction(charName, rec.faction)
        if applyGlobalFilter and not ns.MatchesGlobalFilter(rec, isOwn, charFaction) then
            return
        end

        local bagCount = (rec.bags and ns.SafeNumber(rec.bags[itemID], 0)) or 0
        local bankCount = (rec.bank and ns.SafeNumber(rec.bank[itemID], 0)) or 0
        local equipCount = (rec.equip and ns.SafeNumber(rec.equip[itemID], 0)) or 0
        local total = bagCount + bankCount + equipCount

        if total > 0 then
            local entry = {
                key = rec.key,
                name = charName,
                class = rec.class or "WARRIOR",
                faction = charFaction,
                bags = bagCount,
                bank = bankCount,
                equip = equipCount,
                total = total,
                isOwn = isOwn,
            }
            if isOwn then
                ownList[#ownList + 1] = entry
                ownTotal = ownTotal + total
            else
                squadList[#squadList + 1] = entry
                squadTotal = squadTotal + total
            end
        end

        -- Check if this character can craft this itemID
        if type(rec.professions) == "table" then
            local recipeKey = "item:" .. itemID
            for profName, prof in pairs(rec.professions) do
                if type(prof) == "table" and type(prof.recipes) == "table" then
                    if prof.recipes[recipeKey] then
                        crafters[#crafters + 1] = {
                            name = charName,
                            class = rec.class or "WARRIOR",
                            faction = charFaction,
                            profName = profName,
                            rank = prof.rank or 0,
                        }
                    else
                        for _, r in pairs(prof.recipes) do
                            if type(r) == "table" and r.itemID == itemID then
                                crafters[#crafters + 1] = {
                                    name = charName,
                                    class = rec.class or "WARRIOR",
                                    faction = charFaction,
                                    profName = profName,
                                    rank = prof.rank or 0,
                                }
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    for _, rec in pairs(ns.db.characters or {}) do
        checkChar(rec, true)
    end

    local myCharKeys = ns.db.characters or {}
    for key, rec in pairs(ns.db.squadCharacters or {}) do
        if not myCharKeys[key] and not ns.IsSelfName(rec.name or key) then
            checkChar(rec, false)
        end
    end

    return ownList, squadList, ownTotal, squadTotal, crafters
end

-- -------------------------------------------------------------------------
-- Recipe Reagent / Material Availability Evaluator
-- Checks how many times a recipe can be crafted from:
-- 1) Active Character (bags + bank)
-- 2) All Own Characters / Twinks (bags + bank)
-- 3) Entire Database / Squad (own + friends respecting global filter)
-- -------------------------------------------------------------------------
function Inventory:GetItemHoldersByName(itemName, applyGlobalFilter)
    local targetLower = strtrim(ns.SafeString(itemName, "")):lower()
    if targetLower == "" or not ns.db then return {}, {}, 0, 0 end

    if ns.db.itemMeta then
        for id, m in pairs(ns.db.itemMeta) do
            if type(m) == "table" and m.name and m.name:lower() == targetLower then
                return self:GetItemHolders(id, applyGlobalFilter)
            end
        end
    end
    return {}, {}, 0, 0
end

function Inventory:EvaluateRecipeMaterials(reagents)
    if type(reagents) ~= "table" or #reagents == 0 then
        return nil
    end

    local myActiveRec = ns.EnsureCurrentCharacterRecord()
    local craftableActive = nil
    local craftableOwn = nil
    local craftableDB = nil
    local readyActive = 0
    local readyOwn = 0
    local readyDB = 0
    local details = {}

    for _, req in ipairs(reagents) do
        local reqCount = math.max(1, ns.SafeNumber(req.count, 1))
        local rID = ns.SafeNumber(req.id, 0)
        local rName = ns.SafeString(req.name, rID > 0 and ("Item #" .. rID) or "Material")

        if rID > 0 then
            local meta = self:GetItemMetadata(rID)
            if meta and meta.name and not meta.name:find("^Item #") then
                rName = meta.name
            end
        end

        local ownList, squadList, ownTotal, squadTotal
        if rID > 0 then
            ownList, squadList, ownTotal, squadTotal = self:GetItemHolders(rID, true)
        else
            ownList, squadList, ownTotal, squadTotal = self:GetItemHoldersByName(rName, true)
        end

        local activeHave = 0
        if myActiveRec and rID > 0 then
            local b = (myActiveRec.bags and ns.SafeNumber(myActiveRec.bags[rID], 0)) or 0
            local bk = (myActiveRec.bank and ns.SafeNumber(myActiveRec.bank[rID], 0)) or 0
            activeHave = b + bk
        else
            for _, h in ipairs(ownList) do
                if ns.IsSelfName(h.name) then
                    activeHave = activeHave + (h.total or 0)
                end
            end
        end

        local dbTotal = ownTotal + squadTotal

        local possibleActive = math.floor(activeHave / reqCount)
        local possibleOwn = math.floor(ownTotal / reqCount)
        local possibleDB = math.floor(dbTotal / reqCount)

        if possibleActive >= 1 then readyActive = readyActive + 1 end
        if possibleOwn >= 1 then readyOwn = readyOwn + 1 end
        if possibleDB >= 1 then readyDB = readyDB + 1 end

        craftableActive = (craftableActive == nil) and possibleActive or math.min(craftableActive, possibleActive)
        craftableOwn = (craftableOwn == nil) and possibleOwn or math.min(craftableOwn, possibleOwn)
        craftableDB = (craftableDB == nil) and possibleDB or math.min(craftableDB, possibleDB)

        details[#details + 1] = {
            id = rID,
            name = rName,
            required = reqCount,
            activeHave = activeHave,
            ownHave = ownTotal,
            squadHave = squadTotal,
            dbHave = dbTotal,
            ownList = ownList,
            squadList = squadList,
        }
    end

    return {
        totalReagents = #reagents,
        readyActive = readyActive,
        readyOwn = readyOwn,
        readyDB = readyDB,
        craftableActive = craftableActive or 0,
        craftableOwn = craftableOwn or 0,
        craftableDB = craftableDB or 0,
        details = details,
    }
end

-- -------------------------------------------------------------------------
-- Item Tooltip Integration (Client 16001 TooltipDataProcessor + Fallback)
-- -------------------------------------------------------------------------
local function FormatBreakdown(entry)
    local parts = {}
    if entry.bags > 0 then parts[#parts + 1] = "Tasche: " .. entry.bags end
    if entry.bank > 0 then parts[#parts + 1] = "Bank: " .. entry.bank end
    if entry.equip > 0 then parts[#parts + 1] = "An: " .. entry.equip end
    return string.format("|cffffffff%d|r |cff94a3b8(%s)|r", entry.total, table.concat(parts, ", "))
end

local function AppendSquadInventoryToTooltip(tooltip, itemID)
    if not tooltip or not itemID or itemID <= 0 then return end
    if not ns.db or not ns.db.inventory or not ns.db.inventory.enabled or not ns.db.inventory.showTooltip then
        return
    end

    -- Prevent duplicate injection on the same tooltip pass
    if tooltip._ffLastItemID == itemID and tooltip._ffLastTime == GetTime() then
        return
    end
    tooltip._ffLastItemID = itemID
    tooltip._ffLastTime = GetTime()

    local ownList, squadList, ownTotal, squadTotal, crafters = Inventory:GetItemHolders(itemID, false)
    local grandTotal = ownTotal + squadTotal
    local showOwn = ns.db.inventory.tooltipShowOwnChars
    local showSquad = ns.db.inventory.tooltipShowSquadChars
    local showCrafters = ns.db.inventory.tooltipShowCraftableBy
    local maxLines = ns.SafeNumber(ns.db.inventory.tooltipMaxLines, 12)

    local hasLines = (showOwn and #ownList > 0) or (showSquad and #squadList > 0) or (showCrafters and #crafters > 0)
    if not hasLines and not ns.db.inventory.tooltipShowZeroCount then
        return
    end

    local theme = ns.GetActiveTheme and ns.GetActiveTheme() or ns.THEMES.OBSIDIAN
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(
        "|cff" .. theme.accentHex .. "ForeverFriends Inventar|r",
        grandTotal > 0 and string.format("|cff34d399Gesamt: %dx|r", grandTotal) or "|cff94a3b80x im Squad|r"
    )

    local linesShown = 0

    if showOwn and #ownList > 0 then
        for _, entry in ipairs(ownList) do
            if linesShown < maxLines then
                linesShown = linesShown + 1
                tooltip:AddDoubleLine(
                    "  " .. ns.FormatCharacterDisplay(entry.name, entry.class, entry.faction, true) .. " |cff64748b(Du)|r",
                    FormatBreakdown(entry)
                )
            end
        end
    end

    if showSquad and #squadList > 0 then
        for _, entry in ipairs(squadList) do
            if linesShown < maxLines then
                linesShown = linesShown + 1
                tooltip:AddDoubleLine(
                    "  " .. ns.FormatCharacterDisplay(entry.name, entry.class, entry.faction, true) .. " |cff38bdf8(Freund)|r",
                    FormatBreakdown(entry)
                )
            end
        end
    end

    if showCrafters and #crafters > 0 then
        local craftNames = {}
        for i = 1, math.min(4, #crafters) do
            local c = crafters[i]
            craftNames[#craftNames + 1] = string.format("%s |cff94a3b8(%s)|r", ns.FormatCharacterDisplay(c.name, c.class, c.faction, true), c.profName)
        end
        tooltip:AddDoubleLine("  |cffffd100Herstellbar von:|r", table.concat(craftNames, ", "))
    end

    if ns.db.wishlist and ns.db.wishlist[itemID] then
        local w = ns.db.wishlist[itemID]
        tooltip:AddDoubleLine(
            "  |cfffbbf24[*] Squad-Wunschliste:|r",
            string.format("|cffffffffGesucht von %s|r", ns.SafeString(w.requestedBy, "Squad"))
        )
    end

    tooltip:Show()
end

local function SetupTooltipHooks()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if not tooltip or not data or ns.IsSecret(data) then return end
            local itemID = ns.SafeNumber(data.id, 0)
            if itemID > 0 then
                AppendSquadInventoryToTooltip(tooltip, itemID)
            end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
            local _, link = tooltip:GetItem()
            if link and not ns.IsSecret(link) then
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID then
                    AppendSquadInventoryToTooltip(tooltip, itemID)
                end
            end
        end)
    end
end

-- -------------------------------------------------------------------------
-- Smart Trade Helper Bar on TradeFrame
-- -------------------------------------------------------------------------
local tradeBar = nil

local function FindHelpfulTradeItems()
    local results = {}
    local seen = {}
    local maxBag = (NUM_TOTAL_EQUIPPED_BAG_SLOTS and ns.SafeNumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS, 4)) or 4

    for bagID = 0, maxBag do
        local numSlots = GetNumSlots(bagID)
        for slot = 1, numSlots do
            local itemID, count, link, icon = GetSlotItemInfo(bagID, slot)
            if itemID and itemID > 0 and not seen[itemID] then
                local isWishlist = ns.db and ns.db.wishlist and ns.db.wishlist[itemID]
                local meta = Inventory:GetItemMetadata(itemID)
                local name = (meta and meta.name) or "Item"
                local lower = name:lower()
                local isConsumableShare = lower:find("heiltrank") or lower:find("manatrank") or lower:find("gesundheitsstein")
                    or lower:find("healthstone") or lower:find("herbeigezaubert") or lower:find("conjured")
                    or lower:find("verband") or lower:find("bandage") or lower:find("elixier")

                if isWishlist or isConsumableShare then
                    seen[itemID] = true
                    results[#results + 1] = {
                        itemID = itemID,
                        name = name,
                        icon = icon or (meta and meta.icon) or "Interface\\Icons\\INV_Misc_QuestionMark",
                        bagID = bagID,
                        slot = slot,
                        count = count,
                        isWishlist = isWishlist ~= nil,
                    }
                end
            end
        end
    end
    return results
end

local function UpdateTradeHelperBar()
    if not TradeFrame or not TradeFrame:IsShown() then
        if tradeBar then tradeBar:Hide() end
        return
    end
    if not ns.db or not ns.db.inventory or not ns.db.inventory.enableTradeHelper then
        if tradeBar then tradeBar:Hide() end
        return
    end

    if not tradeBar then
        tradeBar = CreateFrame("Frame", "ForeverFriendsTradeBar", TradeFrame, "BackdropTemplate")
        tradeBar:SetSize(336, 46)
        tradeBar:SetPoint("TOPLEFT", TradeFrame, "BOTTOMLEFT", 2, -4)
        tradeBar:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        tradeBar:SetBackdropColor(0.06, 0.07, 0.09, 0.96)
        tradeBar:SetBackdropBorderColor(0.22, 0.74, 0.97, 0.90)

        local label = tradeBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", tradeBar, "LEFT", 10, 0)
        label:SetText("|cff38bdf8Quick-Trade:|r")
        tradeBar.label = label
        tradeBar.buttons = {}
    end

    local items = FindHelpfulTradeItems()
    for _, btn in ipairs(tradeBar.buttons) do
        btn:Hide()
    end

    if #items == 0 then
        tradeBar.label:SetText("|cff38bdf8ForeverFriends:|r |cff94a3b8Keine Wunschlisten-/Buff-Items in den Taschen|r")
        tradeBar:Show()
        return
    end

    tradeBar.label:SetText("|cff38bdf8Quick-Trade:|r")
    local xOffset = 88
    for i = 1, math.min(6, #items) do
        local entry = items[i]
        local btn = tradeBar.buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, tradeBar, "BackdropTemplate")
            btn:SetSize(32, 32)
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", 2, -2)
            tex:SetPoint("BOTTOMRIGHT", -2, 2)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.icon = tex
            tradeBar.buttons[i] = btn
        end

        btn:ClearAllPoints()
        btn:SetPoint("LEFT", tradeBar, "LEFT", xOffset + (i - 1) * 38, 0)
        btn.icon:SetTexture(entry.icon)
        if entry.isWishlist then
            btn:SetBackdropBorderColor(0.98, 0.75, 0.14, 1.0)
        else
            btn:SetBackdropBorderColor(0.25, 0.30, 0.38, 1.0)
        end

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(entry.name, 1, 1, 1)
            if entry.isWishlist then
                GameTooltip:AddLine("★ Auf der Squad-Wunschliste!", 0.98, 0.75, 0.14)
            end
            GameTooltip:AddLine("Klicken, um ins Handelsfenster zu legen", 0.22, 0.74, 0.97)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function()
            if C_Container and C_Container.UseContainerItem then
                C_Container.UseContainerItem(entry.bagID, entry.slot)
            elseif UseContainerItem then
                UseContainerItem(entry.bagID, entry.slot)
            end
        end)
        btn:Show()
    end

    tradeBar:Show()
end

-- -------------------------------------------------------------------------
-- Module Lifecycle & Event Hooks
-- -------------------------------------------------------------------------
ns.RegisterMessage("ADDON_INITIALIZED", function()
    SetupTooltipHooks()
end)

ns.RegisterMessage("PLAYER_READY", function()
    Inventory:ScanBagsAndEquipment(true)
end)

ns.RegisterEvent("BAG_UPDATE_DELAYED", function()
    Inventory:QueueScanAndSync()
end)

ns.RegisterEvent("PLAYER_MONEY", function()
    Inventory:QueueScanAndSync()
end)

ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
    Inventory:QueueScanAndSync()
end)

ns.RegisterEvent("BANKFRAME_OPENED", function()
    bankIsOpen = true
    Inventory:ScanBank()
    Inventory:QueueBroadcast()
end)

ns.RegisterEvent("BANKFRAME_CLOSED", function()
    bankIsOpen = false
end)

ns.RegisterEvent("TRADE_SKILL_SHOW", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.4, function() Inventory:ScanOpenTradeSkill() end)
    else
        Inventory:ScanOpenTradeSkill()
    end
end)

ns.RegisterEvent("TRADE_SKILL_LIST_UPDATE", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.4, function() Inventory:ScanOpenTradeSkill() end)
    end
end)

ns.RegisterEvent("TRADE_SHOW", UpdateTradeHelperBar)
ns.RegisterEvent("TRADE_CLOSED", function()
    if tradeBar then tradeBar:Hide() end
end)
