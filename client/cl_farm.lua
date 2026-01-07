-- cl_farm.lua (fixed)
local QBCore = exports['qb-core']:GetCoreObject()

local spawnedProps = {}      -- key -> entity
local targetIds = {}         -- key -> targetId
local harvestedTrees = {}    -- key -> timestamp
local spawnedAnimals = {}    -- key -> ped
local farmingBlips = {}
local radiusBlips = {}
local garamBlip = nil
local isHarvesting = false

local function IsFarmer()
    local PlayerData = QBCore.Functions.GetPlayerData()
    return PlayerData.job and PlayerData.job.name == "farmer"
end

local function makeKeyFromCoords(type, coords)
    -- Round coords to 2 decimal for stable key
    return string.format('%s_%.2f_%.2f_%.2f', type, coords.x, coords.y, coords.z)
end

local function PlayCustomHarvestAnim(type)
    local ped = PlayerPedId()
    local dict, anim

    if type == 'kayu' then
        dict = 'melee@large_wpn@streamed_core'
        anim = 'ground_attack_on_spot'
        -- play chopping sound on server (ensure InteractSound resource exists)
        TriggerServerEvent('InteractSound_SV:PlayWithinDistance', 3.0, 'chopwood', 0.6)
    elseif type == 'daging' or type == 'susu' or type == 'kulit' or type == 'milk' then
        dict = 'mini@repair'
        anim = 'fixing_a_ped'
    else
        dict = 'amb@world_human_gardener_plant@male@idle_a'
        anim = 'idle_a'
    end

    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(10) end
    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 1, 0, false, false, false)
end

local function HasKnife()
    local playerPed = PlayerPedId()
    return HasPedGotWeapon(playerPed, GetHashKey("weapon_knife"), false)
end

local function safeRemoveTarget(key)
    local id = targetIds[key]
    if id then
        pcall(function()
            exports.ox_target:removeZone(id)
        end)
        targetIds[key] = nil
    end
end

local function addPlantTarget(key, type, coords, size)
    size = size or vec3(0.8, 0.8, 1.2)
    -- remove existing to avoid duplicates
    safeRemoveTarget(key)

    local id = exports.ox_target:addBoxZone({
        coords = coords,
        size = size,
        rotation = 0,
        debug = false,
        options = {
            {
                name = 'harvest_' .. key,
                label = 'Panen ' .. type,
                icon = 'fas fa-seedling',
                onSelect = function()
                    HarvestPlant(type, coords)
                end,
            }
        }
    })
    targetIds[key] = id
end

local function addAnimalTarget(key, type, ped, coords)
    -- remove existing to avoid duplicates
    safeRemoveTarget(key)

    local id = exports.ox_target:addLocalEntity(ped, {
        {
            name = 'harvest_' .. key,
            label = 'Perah & potong sapi',
            icon = 'fas fa-cow',
            distance = 1.5,
            onSelect = function()
                if HasKnife() then
                    HarvestAnimal(type, coords)
                else
                    TriggerEvent('QBCore:Notify', 'Kamu membutuhkan Pisau', 'error')
                end
            end,
        }
    })
    targetIds[key] = id
end

function SpawnEntity(type, coords)
    if not IsFarmer() then return end
    local key = makeKeyFromCoords(type, coords)

    -- cleanup if already exists
    if spawnedProps[key] and DoesEntityExist(spawnedProps[key]) then
        DeleteEntity(spawnedProps[key])
        spawnedProps[key] = nil
    end
    if spawnedAnimals[key] and DoesEntityExist(spawnedAnimals[key]) then
        DeleteEntity(spawnedAnimals[key])
        spawnedAnimals[key] = nil
    end
    safeRemoveTarget(key)

    -- Animal?
    if Config.Farming.Animals and Config.Farming.Animals[type] then
        local model = Config.Farming.Animals[type]
        local hash = GetHashKey(model)
        RequestModel(hash)
        while not HasModelLoaded(hash) do Wait(0) end

        local randomHeading = math.random() * 360.0
        local ped = CreatePed(28, hash, coords.x, coords.y, coords.z, randomHeading, false, true)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)

        spawnedAnimals[key] = ped
        addAnimalTarget(key, type, ped, coords)
    else
        -- Plant prop
        local propModel = Config.Farming.Props and Config.Farming.Props[type]
        if propModel then
            local modelHash = GetHashKey(propModel)
            RequestModel(modelHash)
            local timeout = GetGameTimer() + 2000
            while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do Wait(0) end

            local obj = CreateObject(modelHash, coords.x, coords.y, coords.z - 1.0, false, false, false)
            PlaceObjectOnGroundProperly(obj)
            FreezeEntityPosition(obj, true)
            spawnedProps[key] = obj
        end

        addPlantTarget(key, type, coords)
    end
end

function HarvestPlant(type, coords)
    if isHarvesting then return end
    if not IsFarmer() then
        QBCore.Functions.Notify('Kamu bukan petani!', 'error')
        return
    end

    local key = makeKeyFromCoords(type, coords)

    -- cooldown for persistent trees
    if Config.Farming.TreePersistent and Config.Farming.TreePersistent[type] then
        if harvestedTrees[key] and GetGameTimer() - harvestedTrees[key] < 60000 then
            QBCore.Functions.Notify('Pohon ini sudah kamu panen, tunggu 60 Detik.', 'error')
            return
        end
    end

    -- Skillcheck khusus kayu dan garam
    if type == 'kayu' or type == 'garam' then
        if not lib or not lib.skillCheck then
            -- fallback: no skillcheck available
            print('[farm_system] warning: lib.skillCheck missing - skipping skillcheck')
        else
            local success = lib.skillCheck({'easy'}, {'w', 'a', 's', 'd'})
            if not success then
                QBCore.Functions.Notify('Kamu gagal memanen.', 'error')
                return
            end
        end
    end

    isHarvesting = true
    PlayCustomHarvestAnim(type)

    -- remove target while progress running
    safeRemoveTarget(key)

    local duration = (type == 'jeruk') and 12500 or 7000

    QBCore.Functions.Progressbar('harvest_plant', 'Memanen ' .. type .. '...', duration, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function() -- on finish
        ClearPedTasks(PlayerPedId())

        local amount = 1
            if type == 'kayu' then
                amount = math.random(1, 3)
            elseif type == 'garam' then
                amount = math.random(1, 4)
            elseif type == 'apel' then
                amount = math.random(1, 6)
            elseif type == 'jeruk' then
                amount = math.random(1, 6)     
            elseif type == 'strawberry' then
                amount = math.random(1, 6)                                
            elseif type == 'biji_kopi' then
                amount = math.random(1, 4)
            elseif type == 'tebu' then
                amount = math.random(1, 5)                                
            elseif type == 'padi' then
                amount = math.random(1, 4) -- contoh hasil panen padi
            end
        TriggerServerEvent('farm_system:server:GiveRaw', type, amount)

        if Config.Farming.TreePersistent and Config.Farming.TreePersistent[type] then
            harvestedTrees[key] = GetGameTimer()
        end

        -- if non-persistent and not wood/salt -> delete prop and respawn later
        if type ~= 'kayu' and type ~= 'garam' and not (Config.Farming.TreePersistent and Config.Farming.TreePersistent[type]) then
            local prop = spawnedProps[key]
            if prop and DoesEntityExist(prop) then
                DeleteEntity(prop)
                spawnedProps[key] = nil
            end

            targetIds[key] = nil

            SetTimeout(20000, function()
                SpawnEntity(type, coords)
            end)
        else
            -- re-add target for persistent or wood/salt
            addPlantTarget(key, type, coords, vec3(2.0, 2.0, 2.0))
        end

        isHarvesting = false
    end, function() -- on cancel
        ClearPedTasks(PlayerPedId())
        isHarvesting = false
        -- re-add target so player can try again
        addPlantTarget(key, type, coords, vec3(2.0, 2.0, 2.0))
    end)
end

function HarvestAnimal(type, coords)
    if not IsFarmer() then
        QBCore.Functions.Notify('Kamu bukan petani!', 'error')
        return
    end

    local key = makeKeyFromCoords(type, coords)

    PlayCustomHarvestAnim(type)

    -- remove target while cutting
    safeRemoveTarget(key)

    QBCore.Functions.Progressbar('harvest_animal', 'Memotong sapi...', 6500, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function()
        ClearPedTasks(PlayerPedId())
        TriggerServerEvent('farm_system:server:GiveRaw', type)

        local ped = spawnedAnimals[key]
        if ped and DoesEntityExist(ped) then
            DeleteEntity(ped)
            spawnedAnimals[key] = nil
        end

        targetIds[key] = nil

        SetTimeout(30000, function()
            SpawnEntity(type, coords)
        end)
    end, function() -- cancel
        ClearPedTasks(PlayerPedId())
        -- re-add animal target if still exists
        if spawnedAnimals[key] and DoesEntityExist(spawnedAnimals[key]) then
            addAnimalTarget(key, type, spawnedAnimals[key], coords)
        end
    end)
end

-- Spawning on player load / job update
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(1000)
    -- spawn entities
    if Config and Config.Farming and Config.Farming.Plants then
        for type, coordsList in pairs(Config.Farming.Plants) do
            for _, coords in pairs(coordsList) do
                SpawnEntity(type, coords)
            end
        end
    end
    -- create blips
    RemoveFarmingBlips()
    CreateFarmingBlips()
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    Wait(500)
    -- if switched to farmer, spawn; else cleanup
    if job and job.name == 'farmer' then
        if Config and Config.Farming and Config.Farming.Plants then
            for type, coordsList in pairs(Config.Farming.Plants) do
                for _, coords in pairs(coordsList) do
                    SpawnEntity(type, coords)
                end
            end
        end
        RemoveFarmingBlips()
        CreateFarmingBlips()
    else
        -- cleanup when leaving job
        for k, ent in pairs(spawnedProps) do
            if ent and DoesEntityExist(ent) then DeleteEntity(ent) end
            spawnedProps[k] = nil
        end
        for k, ped in pairs(spawnedAnimals) do
            if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
            spawnedAnimals[k] = nil
        end
        for k, id in pairs(targetIds) do
            safeRemoveTarget(k)
        end
        RemoveFarmingBlips()
    end
end)

-- Blip functions
function CreateFarmingBlips()
    if not IsFarmer() then return end

    local blipData = {
        {coords = vector3(2062.19, 4907.79, 41.11), label = 'Ladang Padi'},
        {coords = vector3(2038.33, 4935.9, 40.96), label = 'Kebun Jeruk'},
        {coords = vector3(2051.75, 4949.46, 41.07), label = 'Kebun Apel'},
        {coords = vector3(1955.19, 4805.1, 43.68), label = 'Perkebunan Kopi'},
        {coords = vector3(1914.33, 4769.66, 43.11), label = 'Perkebunan Teh'},
        {coords = vector3(1869.24, 4816.6, 45.02), label = 'Perkebunan Tebu'},
        {coords = vector3(2425.76, 4751.43, 34.3), label = 'Kandang Sapi'},
        {coords = vector3(-476.21, 5376.33, 80.52), label = 'Hutan Kayu'},
    }

    for _, data in pairs(blipData) do
        local blip = AddBlipForCoord(data.coords)
        SetBlipSprite(blip, 515)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, 0.8)
        SetBlipColour(blip, 2)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(data.label)
        EndTextCommandSetBlipName(blip)

        local radius = AddBlipForRadius(data.coords, 30.0)
        SetBlipColour(radius, 2)
        SetBlipAlpha(radius, 100)

        table.insert(farmingBlips, blip)
        table.insert(radiusBlips, radius)
    end

    -- Blip garam
    garamBlip = AddBlipForCoord(2223.51, 4578.88, 31.4)
    SetBlipSprite(garamBlip, 515)
    SetBlipDisplay(garamBlip, 4)
    SetBlipScale(garamBlip, 0.8)
    SetBlipColour(garamBlip, 3)
    SetBlipAsShortRange(garamBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Ladang Garam')
    EndTextCommandSetBlipName(garamBlip)
end

function RemoveFarmingBlips()
    for _, blip in ipairs(farmingBlips) do
        RemoveBlip(blip)
    end
    for _, radius in ipairs(radiusBlips) do
        RemoveBlip(radius)
    end
    if garamBlip then
        RemoveBlip(garamBlip)
        garamBlip = nil
    end
    farmingBlips = {}
    radiusBlips = {}
end
