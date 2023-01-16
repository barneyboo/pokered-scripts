urand            = assert(io.open('/dev/urandom', 'rb'))
rand             = assert(io.open('/dev/random', 'rb'))
local Vector     = require("vector")
local Luafinding = require("luafinding")
statusSocket     = nil

function stopSocket()
    if not statusSocket then return end
    console:log("Socket Test: Shutting down")
    statusSocket:close()
    statusSocket = nil
end

function socketError(err)
    console:error("Socket Test Error: " .. err)
    stopSocket()
end

function socketReceived()
    while true do
        local p, err = statusSocket:receive(1024)
        if p then
            console:log("Socket Test Received: " .. p:match("^(.-)%s*$"))
        else
            if err ~= socket.ERRORS.AGAIN then
                console:error("Socket Test Error: " .. err)
                stopSocket()
            end
            return
        end
    end
end

function sendMessage(messageType, content)
    if statusSocket then
        statusSocket:send(messageType .. "||" .. content .. "\n")
    end
end

function startSocket()
    console:log("Socket Test: Connecting to 127.0.0.1:8888...")
    statusSocket = socket.tcp()
    statusSocket:add("received", socketReceived)
    statusSocket:add("error", socketError)
    if statusSocket:connect("127.0.0.1", 8888) then
        console:log("Socket Test: Connected")
        lastkeys = nil
    else
        console:log("Socket Test: Failed to connect")
        stopSocket()
    end
end

function RNG(b, m, r)
    b = b or 4
    m = m or 256
    r = r or urand
    local n, s = 0, r:read(b)

    for i = 1, s:len() do
        n = m * n + s:byte(i)
    end

    return n
end

function setupBuffer()
    botBuffer = console:createBuffer("Bot Player")
    cameraBuffer = console:createBuffer("Camera")
    tileMapBuffer = console:createBuffer("Map")
    pathfindBuffer = console:createBuffer("Pathfinder")
    debugBuffer = console:createBuffer("Debug")
    debugBuffer:setSize(100, 80)
    tileMapBuffer:setSize(100, 100)
    pathfindBuffer:setSize(100, 100)
    doMove()
end

lastKey = 0

-- distribution data
-- https://docs.google.com/spreadsheets/d/1F3KdDepPo3Yr4NyIqU6J1_4IVH8qrvaCNZJkFm5yWOk/edit#gid=0
-- UP	105557	10.72%
-- DOWN	92478	9.39%
-- LEFT	76644	7.78%
-- RIGHT	80543	8.18%

-- A	131723	13.37%
-- B	69233	7.03%

-- ANARCHY	59907	6.08%
-- SUBONLY	41928	4.26%

-- START	29759	3.02%
-- SELECT	13778	1.40%

UP_TRIGGER = 22
DOWN_TRIGGER = 40
LEFT_TRIGGER = 56
RIGHT_TRIGGER = 74
A_TRIGGER = 100
B_TRIGGER = 114
START_TRIGGER = 120
SELECT_TRIGGER = 122

table_keys = { "A", "B", "SELECT", "START", "RIGHT", "LEFT", "UP", "DOWN", "R", "L" }

inBattleLoc = 0x3003529
cameraXLoc = 0x0300506C
cameraYLoc = 0x03005068
fieldCameraLoc = 0x03005050

VMapLayoutLoc = 0x03005040
MapWidthLoc = VMapLayoutLoc
MapHeightLoc = VMapLayoutLoc + 4
MapLayoutData = VMapLayoutLoc + 8
SaveBlockLoc = 0x03005008 -- see SaveBlock1 def
LockFieldLoc = 0x03000F9C


isNaive = false
isFollowTarget = true
stuckCount = 0
stuckLimit = 250
zoneFailLimit = 10
zoneFailCount = 0
isSimplePathFollow = false
isMapEventsFollow = true
nextPathElement = {}


map_lookup = {
    "Pallet Town",
    "Viridian City",
    "Pewter City",
    "Cerulean City",
    "Lavender Town",
    "Vermilion City",
    "Celadon City",
    "Fuchsia City",
    "Cinnabar Island",
    "Indigo Plateau",
    "Saffron City",
    "Route 4 Pokémon Center",
    "Route 10 Pokémon Center",
    "Route 1",
    "Route 2",
    "Route 3",
    "Route 4",
    "Route 5",
    "Route 6",
    "Route 7",
    "Route 8",
    "Route 9",
    "Route 10",
    "Route 11",
    "Route 12",
    "Route 13",
    "Route 14",
    "Route 15",
    "Route 16",
    "Route 17",
    "Route 18",
    "Route 19",
    "Route 20",
    "Route 21",
    "Route 22",
    "Route 23",
    "Route 24",
    "Route 25",
    "Viridian Forest",
    "Mt. Moon",
    "S.S. Anne",
    "Underground Path",
    "Underground Path 2",
    "Diglett's Cave",
    "Victory Road",
    "Team Rocket Hideout",
    "Silph Co.",
    "Pokémon Mansion",
    "Safari Zone",
    "Pokémon League",
    "Rock Tunnel",
    "Seafoam Islands",
    "Pokémon Tower",
    "Cerulean Cave",
    "Power Plant"
}

-- get the metatiles for this map and identify which ones are water
-- mark these as collisions to avoid trying to walk over them
-- TODO: detect if got Surf before forcing these to be collision tiles
-- function setWaterCollisions()
--     for x = 0, mapWidth - 1 do
--         for y = 0, mapHeight - 1 do
--             a = 1
--         end
--     end

-- end

---
MapHeaderLoc = 0x02036DFC
MapEventsPointerLoc = MapHeaderLoc + 0x04
MapConnectionsPointerLoc = MapHeaderLoc + 0x0C
kantoMapSections = 0x58
function getCurrentLocationName()
    regionMapSecId = emu:read8(MapHeaderLoc + 0x14) - kantoMapSections
    sendMessage("map.name", map_lookup[regionMapSecId + 1])
    -- status_file:seek("set", 0)
    -- status_file:write("                                        ")
    -- status_file:seek("set", 0)
    -- status_file:write(map_lookup[regionMapSecId + 1])
    -- status_file:flush()
end

gotTargetNeedPath = false
needNewEventTarget = false
connectionDirections = { 'south', 'north', 'west', 'east' }
forceRoutableAtTarget = false

function addObjectsToCollisionMap()
    mapEventsPointer = emu:read32(MapEventsPointerLoc)
    objectEventCount = emu:read8(mapEventsPointer)
    objectEventsPointer = emu:read32(mapEventsPointer + 0x04)
    objEventSize = 24
    for objectEventIdx = 0, objectEventCount do
        objectEventOffset = objectEventsPointer + (objEventSize * objectEventIdx)
        objEventX = emu:read8(objectEventOffset + 4) + 7
        objEventY = emu:read8(objectEventOffset + 6) + 7
        pathfindBuffer:moveCursor(objEventX, objEventY)
        pathfindBuffer:print("1")
        map[objEventX][objEventY] = false
        debugBuffer:print(string.format("🧱 Adding object collision %d at %d,%d\n", objectEventIdx,
            objEventX, objEventY))
    end



end

function chooseEventToRouteTo()
    -- for the current map
    -- enumerate all the connections, object events, and warp events (see MapEvents)
    -- choose one at random to route to

    -- debug flags for forcing different events to be routed to
    do_first_warp_event = false
    do_first_connection = false
    do_first_obj_event = false

    mapEventsPointer = emu:read32(MapEventsPointerLoc)
    objectEventCount = emu:read8(mapEventsPointer)
    warpCount = emu:read8(mapEventsPointer + 0x01)
    coordEventCount = emu:read8(mapEventsPointer + 0x02)
    bgEventCount = emu:read8(mapEventsPointer + 0x03)
    debugBuffer:print("\n")
    -- debugBuffer:print(string.format("Map object events count: %d\n", objectEventCount))
    -- debugBuffer:print(string.format("Warp count: %d\n", warpCount))
    -- debugBuffer:print(string.format("Coord event count: %d\n", coordEventCount))
    -- debugBuffer:print(string.format("BG event count: %d\n", bgEventCount))

    connectionsPointer = emu:read32(MapConnectionsPointerLoc)
    connectionsCount = emu:read32(connectionsPointer)
    connectionSize = 12
    -- debugBuffer:print(string.format("Connections count: %d\n", connectionsCount))
    if (connectionsCount > 10) then connectionsCount = 0 end

    objectEventsPointer = emu:read32(mapEventsPointer + 0x04)
    -- debugBuffer:print(string.format("First objectEventsPointer %x\n", objectEventsPointer))

    objEventX = emu:read8(objectEventsPointer + 4) + 7
    objEventY = emu:read8(objectEventsPointer + 6) + 7
    objEventSize = 24

    bgEventSize = 12
    bgEventsPointer = emu:read32(mapEventsPointer + 0x10)

    -- debugBuffer:print(string.format("First object event is at %d,%d\n", objEventX, objEventY))

    warpEventsPointer = emu:read32(mapEventsPointer + 0x08)
    -- warpX = emu:read16(warpEventsPointer) + 7
    -- warpY = emu:read16(warpEventsPointer + 2) + 7
    warpEventSize = 8
    -- debugBuffer:print(string.format("First warp event is at %d,%d\n", warpX, warpY))

    coordEventsPointer = emu:read32(mapEventsPointer + 0x0C)
    coordEventSize = 16

    totalEventsCount = objectEventCount + warpCount + connectionsCount + bgEventCount + coordEventCount
    eventIndex = RNG(1) % totalEventsCount
    -- debugBuffer:print(string.format("Event %d of %d events\n", eventIndex, totalEventsCount))
    if eventIndex < objectEventCount then
        -- object event
        objectEventIdx = eventIndex
        objectEventOffset = objectEventsPointer + (objEventSize * objectEventIdx)
        objEventX = emu:read8(objectEventOffset + 4) + 7
        objEventY = emu:read8(objectEventOffset + 6) + 7

        jitterX = (RNG(1) % 5) - 2
        jitterY = (RNG(1) % 5) - 2
        targetX = objEventX + jitterX
        targetY = objEventY + jitterY
        debugBuffer:print(string.format("🙋 >> Routing to object event %d at %d,%d\n", objectEventIdx,
            objEventX, objEventY))
        calculatePathToTarget()
    elseif eventIndex < objectEventCount + warpCount then
        -- warp event
        warpEventIdx = eventIndex - objectEventCount
        warpEventOffset = warpEventsPointer + (warpEventSize * warpEventIdx)
        warpX = emu:read16(warpEventOffset) + 7
        warpY = emu:read16(warpEventOffset + 2) + 7

        -- jitter the target up to one tile in each direction to encourage using door/stair warps
        jitterX = (RNG(1) % 3) - 1
        jitterY = (RNG(1) % 3) - 1
        targetX = warpX + jitterX
        targetY = warpY + jitterY


        -- debugBuffer:print(string.format("Warp pointer at %x\n", warpEventOffset))
        debugBuffer:print(string.format("🚪 >> Routing to warp event %d at %d,%d\n", warpEventIdx, warpX, warpY))

        forceRoutableAtTarget = true
        gotPath = calculatePathToTarget()
    elseif eventIndex < objectEventCount + warpCount + connectionsCount then
        -- connections
        connectionIdx = eventIndex - (objectEventCount + warpCount)
        -- debugBuffer:print(string.format("connectionsPointer %x \n", connectionsPointer))
        connectionListPointer = emu:read32(connectionsPointer + 0x04)
        connectionOffset = connectionListPointer + (connectionSize * connectionIdx)
        conxDirection = emu:read8(connectionOffset)
        -- debugBuffer:print(string.format("conxDirection %x with val %x \n", connectionIdx, conxDirection))
        debugBuffer:print(string.format("🗺️ >> Routing to connection %d in direction %s\n", connectionIdx,
            connectionDirections[conxDirection]))
        if conxDirection == 1 then
            -- pick a random coordinate on the south-edge without a collision bit
            repeat
                targetX = RNG(1) % mapWidth
            until (map[targetX][mapHeight - 1] == true)
            targetY = mapHeight - 1
            calculatePathToTarget()
        end
        if conxDirection == 2 then
            -- pick a random coordinate on the south-edge without a collision bit
            repeat
                targetX = RNG(1) % mapWidth
            until (map[targetX][0] == true)
            targetY = 0
            calculatePathToTarget()
        end
        if conxDirection == 3 then
            -- pick a random coordinate on the south-edge without a collision bit
            repeat
                targetY = RNG(1) % mapHeight
            until (map[0][targetY] == true)
            targetX = 0
            calculatePathToTarget()
        end
        if conxDirection == 4 then
            -- pick a random coordinate on the south-edge without a collision bit
            repeat
                targetY = RNG(1) % mapHeight
            until (map[mapWidth - 1][targetY] == true)
            targetX = mapWidth - 1
            calculatePathToTarget()
        end

    elseif eventIndex < objectEventCount + warpCount + connectionsCount + bgEventCount then
        -- BG events
        bgIndex = eventIndex - (objectEventCount + warpCount + connectionsCount)
        bgOffset = bgEventsPointer + (bgEventSize * bgIndex)
        -- debugBuffer:print(string.format("root bg pointer %x\n", bgEventsPointer))
        -- debugBuffer:print(string.format("bgOffset %x\n", bgOffset))
        bgX = emu:read16(bgOffset) + 7
        bgY = emu:read16(bgOffset + 0x2) + 7
        jitterX = (RNG(1) % 3) - 1
        jitterY = (RNG(1) % 3) - 1
        targetX = bgX + jitterX
        targetY = bgY + jitterY
        debugBuffer:print(string.format("🪧 >> Routing to BG event %d at %d,%d\n", bgIndex,
            bgX, bgY))
        forceRoutableAtTarget = true
        calculatePathToTarget()
    elseif eventIndex < objectEventCount + warpCount + connectionsCount + bgEventCount + coordEventCount then
        -- Coord events
        coordIndex = eventIndex - (objectEventCount + warpCount + connectionsCount + bgEventCount)
        coordOffset = coordEventsPointer + (coordEventSize * coordIndex)
        debugBuffer:print(string.format("coordOffset %x\n", coordOffset))
        coordX = emu:read16(coordOffset) + 7
        coordY = emu:read16(coordOffset + 0x2) + 7
        jitterX = (RNG(1) % 3) - 1
        jitterY = (RNG(1) % 3) - 1
        targetX = coordX + jitterX
        targetY = coordY + jitterY
        debugBuffer:print(string.format("📍 >> Routing to co-ord event %d at %d,%d\n", coordIndex,
            coordX, coordY))
        calculatePathToTarget()

    end




    if (do_first_warp_event and warpCount > 0) then
        targetX = warpX
        targetY = warpY
        calculatePathToTarget()
    end

    if (do_first_connection and connectionsCount > 0) then
        conxPointer = emu:read8(connectionsPointer + 0x04)
        conxDirection = emu:read8(conxPointer)
        debugBuffer:print(string.format("connectionsPointer loc %x\n", connectionsPointer))
        debugBuffer:print(string.format("First connection direction is %d %s\n", conxDirection,
            connectionDirections[conxDirection]))
        if conxDirection == 1 then
            -- pick a random coordinate on the south-edge without a collision bit
            targetX = RNG(1) % mapWidth
            targetY = mapHeight - 1
            calculatePathToTarget()
        end
        if conxDirection == 2 then
            -- pick a random coordinate on the south-edge without a collision bit
            targetX = RNG(1) % mapWidth
            targetY = 0
            calculatePathToTarget()
        end
        if conxDirection == 3 then
            -- pick a random coordinate on the south-edge without a collision bit
            targetY = RNG(1) % mapHeight
            targetX = 0
            calculatePathToTarget()
        end
        if conxDirection == 4 then
            -- pick a random coordinate on the south-edge without a collision bit
            targetY = RNG(1) % mapHeight
            targetX = mapWidth
            calculatePathToTarget()
        end
    end

    if (do_first_obj_event and objectEventCount > 0) then
        targetX = objEventX
        targetY = objEventY
        calculatePathToTarget()
    end

    if (path) then needNewTarget = false end
end

function doMove()

    -- if not isSimplePathFollow then
    --     emu:clearKeys(0x3FF)
    -- end
    shouldMove = RNG(1)
    if shouldMove < 0xBB then
        return
    end
    emu:clearKeys(0x3FF)
    if isSimplePathFollow then
        emu:clearKeys(0x3FF)
    end
    isInBattle = emu:read8(inBattleLoc)
    lockedFieldControls = emu:read8(LockFieldLoc) -- probably in a menu

    moveWeight = RNG(1)
    mapWidth = emu:read16(MapWidthLoc)
    mapHeight = emu:read16(MapHeightLoc)

    if isNaive then
        emu:clearKeys(0x3FF)

        mapWidth = emu:read16(MapWidthLoc)
        mapHeight = emu:read16(MapHeightLoc)
        nextKey = RNG(1) % 8
        emu:addKey(nextKey)
        botBuffer:print(string.format("Now pressing %s\n", table_keys[nextKey + 1]))
        botBuffer:print(string.format("Camera at %d,%d\n", posX, posY))
        botBuffer:print(string.format("Map size %d x %d\n", mapWidth, mapHeight))
        return
    end

    -- botBuffer:print(string.format("Locked field controls? %s\n", lockedFieldControls))

    -- use pathfinding algo
    if path and nextPathElement and not isSimplePathFollow and isFollowTarget and isInBattle == 0 and
        lockedFieldControls == 0 then
        nextKey = -1
        botBuffer:print(string.format("at %d,%d\n", vPosX, vPosY))
        botBuffer:print(string.format("next step: %s\n", nextPathElement))
        emu:clearKeys(0x3FF)
        possKeys = {}
        if vPosX < nextPathElement.x then
            table.insert(possKeys, 4)
        end
        if vPosX > nextPathElement.x then
            table.insert(possKeys, 5)
        end
        if vPosY < nextPathElement.y then
            table.insert(possKeys, 7)
        end
        if vPosY > nextPathElement.y then
            table.insert(possKeys, 6)
        end
        -- if #possKeys == 0 then
        --     table.insert(possKeys, RNG(1) % 5) -- press a non-directional key when at target
        -- end
        if #possKeys == 0 and vPosX == nextPathElement.x and vPosY == nextPathElement.y then
            stuckCount = 0
            if (#path == 0) then
                debugBuffer:print("✅ Successfully routed to destination! Requesting new path.\n")
                zoneFailCount = zoneFailCount - 1
                needNewTarget = true
            else nextPathElement = table.remove(path, 1) end
            table.insert(possKeys, RNG(1) % 4)
            table.insert(possKeys, 0) -- press A, to try interact with target
            -- nextKey = RNG(1) % 5
        end
        nextKey = possKeys[RNG(1) % #possKeys + 1]
        emu:addKey(nextKey)
        return
    end

    if isSimplePathFollow and isFollowTarget and isInBattle == 0 and lockedFieldControls == 0 then
        possKeys = {}
        emu:clearKeys(0x3FF)
        if vPosX < targetX then
            table.insert(possKeys, 4)
        end
        if vPosX > targetX then
            table.insert(possKeys, 5)
        end
        if vPosY < targetY then
            table.insert(possKeys, 7)
        end
        if vPosY > targetY then
            table.insert(possKeys, 6)
        end
        if #possKeys == 0 then
            table.insert(possKeys, RNG(1) % 5) -- press a non-directional key when at target
        end
        botBuffer:print(string.format("Possible keys: %s\n", #possKeys))
        nextKey = possKeys[RNG(1) % #possKeys + 1]
        emu:addKey(nextKey)
        return
    end


    -- legacy button picker:
    --
    -- -- small chance that we pick an aux button
    -- if(moveWeight < 0x10) then
    --     nextKey = RNG(1) % 4
    --     botBuffer:print(string.format("Now pressing aux key %x\n", nextKey))
    --     lastKey = nextKey
    --     emu:addKey(nextKey)
    --     return
    -- end

    -- -- reasonable chance that we pick a face button
    -- if(moveWeight > 0xD0) then
    --     nextKey = RNG(1) % 2
    --     botBuffer:print(string.format("Now pressing face key %x\n", nextKey))
    --     lastKey = nextKey
    --     emu:addKey(nextKey)
    --     return
    -- end

    -- -- if(nextKey == 2 or nextKey == 8 or nextKey == 9) then
    -- --     return
    -- nextKey = (RNG(1) % 6) + 4

    if moveWeight < UP_TRIGGER then
        nextKey = 6

    elseif moveWeight < DOWN_TRIGGER then
        nextKey = 7
    elseif moveWeight < LEFT_TRIGGER then
        nextKey = 5
    elseif moveWeight < RIGHT_TRIGGER then
        nextKey = 4
    elseif moveWeight < A_TRIGGER then
        nextKey = 0
    elseif moveWeight < B_TRIGGER then
        nextKey = 1
    elseif moveWeight < START_TRIGGER then
        nextKey = 3
    elseif moveWeight < SELECT_TRIGGER then
        nextKey = 2
    else return end

    emu:clearKeys(0x3FF)







    -- if we try to go in the opposite direction to the last key, keep going same direction
    -- only do this if not in battle
    -- if isInBattle == 0 then
    --     if lastMoveKey == 4 and nextKey == 5 then nextKey = 4 end
    --     if lastMoveKey == 5 and nextKey == 4 then nextKey = 5 end
    --     if lastMoveKey == 6 and nextKey == 7 then nextKey = 6 end
    --     if lastMoveKey == 7 and nextKey == 6 then nextKey = 7 end
    --     if nextKey > 3 and nextKey < 8 then lastMoveKey = nextKey end
    -- end


    -- if not in battle and we haven't changed tile since we last pressed a key, ban the last pressed key until our tile changes
    -- if isInBattle == 0 and nextKey == lastMoveKey then
    --     lastX = posX
    --     lastY = posY
    --     posX = emu:read16(cameraXLoc) >> 4
    --     posY = emu:read16(cameraYLoc) >> 4
    --     if isInBattle == 0 and lastX == posX and lastY == posY then
    --         botBuffer:print(string.format("Character stuck, not going %s again\n", table_keys[nextKey+1]))
    --         nextKey = nextKey+1
    --         if nextKey > 7 then nextKey = 4 end
    --         if nextKey > 3 and nextKey < 8 then lastMoveKey = nextKey end
    --     end
    -- end

    posX = (emu:read16(cameraXLoc) >> 4) + 7
    posY = (emu:read16(cameraYLoc) >> 4) + 7

    lastKey = nextKey
    emu:addKey(nextKey)
    -- botBuffer:print(string.format("Now pressing %x after roll %x\n", nextKey, moveWeight))
    botBuffer:print(string.format("Now pressing %s %x\n", table_keys[nextKey + 1], moveWeight))
    -- keys = emu:getKeys()
    -- botBuffer:print(string.format("Current keys %x\n", keys))
    -- botBuffer:print(string.format("Map size %d x %d\n", mapWidth, mapHeight))

end

lastSaveX = 0
lastSaveY = 0
lastMapWidth = 0
lastMapHeight = 0
targetX = -1
targetY = -1
borderSize = 7 -- use a border to create targets outside the playable area to encourage map transitions
vPosX = 0
vPosY = 0
vMapWidth = 0
vMapHeight = 0
collisionMap = {}


map = {}
-- GetMapGridBlockAt and MapGridGetCollisionAt in fieldmap.c have examples of working with map data
function getMapCollisions()
    collisionMap = {}
    cursorX = 0
    cursorY = 0
    mapSize = (mapWidth * mapHeight) * 2 -- each tile is 2 bytes
    -- debugBuffer:print(string.format("mapSize is %d\n", mapSize))

    -- mapPointer = 0x1FFFFF + emu:read16(MapLayoutData)
    mapPointer = emu:read32(MapLayoutData)
    -- debugBuffer:print(string.format("map pointer is at %x\n", mapPointer))
    -- debugBuffer:print(string.format("map ends at %x\n", mapPointer+(got)))


    -- // Masks/shifts for blocks in the map grid
    -- // Map grid blocks consist of a 10 bit metatile id, a 2 bit collision value, and a 4 bit elevation value
    -- // This is the data stored in each data/layouts/*/map.bin file
    -- #define MAPGRID_METATILE_ID_MASK 0x03FF // Bits 0-9
    -- #define MAPGRID_COLLISION_MASK   0x0C00 // Bits 10-11
    -- #define MAPGRID_ELEVATION_MASK   0xF000 // Bits 12-15
    -- #define MAPGRID_COLLISION_SHIFT  10
    -- #define MAPGRID_ELEVATION_SHIFT  12

    -- eg. FF03
    -- = 1111111100000011
    -- collision mask = 00
    -- elevation mask = 0011

    -- now read as many bytes as the mapSize is
    -- mapLayout = emu:readRange(mapPointer, mapSize)
    -- debugBuffer:print(string.format("got map layout! %s", mapLayout[0]))



    pathfindBuffer:clear()
    pathfindBuffer:setSize(100, 100)
    map = {}
    -- debugBuffer:print(string.format("%x",mapLayout))
    for x = 0, mapWidth - 1 do
        map[x] = {}
        for y = 0, mapHeight - 1 do
            -- tile_id = (x*mapWidth)+(y*mapHeight)
            tile_id = x + mapWidth * y



            -- debugBuffer:print(string.format("looking at tile %x\n", mapPointer+(tile_id*2)))
            mapTile = emu:read16(mapPointer + (tile_id * 2))
            pathfindBuffer:moveCursor(x, y)
            -- pathfindBuffer:print("o")

            -- is there collision data here?
            -- debugBuffer:print(string.format("tile: %d,%d, collision shifted: %x, is collision? %x\n",x,y,mapTile>>10,(mapTile & 0x0C00) >> 10))
            mapTileCollision = (mapTile & 0x0C00) >> 10


            -- if the tile is water, we also treat that as collision
            -- look at MetatileAtCoordsIsWaterTile
            -- METATILE_ATTRIBUTE_TERRAIN = 0x00003e00
            -- METATILE_ATTRIBUTE_TERRAIN_SHIFT = 9
            -- TILE_TERRAIN_WATER = 2
            -- MAPGRID_METATILE_ID_MASK = 0x03FF
            -- metaTileId = mapTile & 0x03FF;

            -- debugBuffer:print(string.format("%s",isWater))


            map[x][y] = mapTileCollision == 0
            -- debugBuffer:print(string.format('map entry %s',map[x][y]))
            pathfindBuffer:print(string.format("%x", mapTileCollision))
            table.insert(collisionMap, mapTileCollision)

            -- debugBuffer:print(string.format("%s",mapTile))

            -- pathfindBuffer:print(string.format("%s", mapLayout[(x*mapWidth)+(y*mapHeight)]))
        end
    end
    addObjectsToCollisionMap()
end

path = nil
function calculatePathToTarget()
    -- debugBuffer:print(string.format("got map %s\n", #map))
    if #map == 0 and isMapEventsFollow then
        gotTargetNeedPath = true
        return
    end

    -- update pathfind data to make it possible to route to this tile
    -- eg so player can always walk to a warp point

    if (forceRoutableAtTarget) then
        oldCollisionValue = map[targetX][targetY]
        map[targetX][targetY] = true
    end

    if (map[savePosX + 7][savePosY + 7] == false) then
        -- if player is on a collision tile, assume we're in the middle of a warp transition and hold off until player has moved
        gotTargetNeedPath = true
        debugBuffer:print(string.format("Pathing has started on a blocked tile, trying again on next frame\n"))
        return
    end

    start = Vector(savePosX + 7, savePosY + 7)
    finish = Vector(targetX, targetY)
    path = Luafinding(start, finish, map):GetPath()
    debugBuffer:print(string.format("starting at %s\n", start))
    debugBuffer:print(string.format("finishing at %s\n", finish))
    -- debugBuffer:print(string.format("path %s\n", i, path))
    if (path == nil) then
        debugBuffer:print(string.format("⛔️ Failed to route path\n"))
        return false
    end
    -- always pop the first step of the path as it causes a lot of backtracking after warps
    table.remove(path, 1)
    for i = 1, #path do
        debugBuffer:print(string.format("Path step %d: %s\n", i, path[i]))
    end
    nextPathElement = table.remove(path, 1)
    gotTargetNeedPath = false
    if (forceRoutableAtTarget) then map[targetX][targetY] = oldCollisionValue end
    forceRoutableAtTarget = false
    return true




end

function cameraLog()
    -- -- offsets init at 0,0 when loading a new map - they are not absolute positions on the current or global map
    -- posX = (emu:read16(cameraXLoc)) >> 4
    -- posY = (emu:read16(cameraYLoc)) >> 4
    mapWidth = emu:read16(MapWidthLoc)
    mapHeight = emu:read16(MapHeightLoc)

    saveBlockPointer = emu:read32(SaveBlockLoc)
    savePosX = emu:read16(saveBlockPointer);
    savePosY = emu:read16(saveBlockPointer + 2);

    vPosX = savePosX + borderSize
    vPosY = savePosY + borderSize
    vMapWidth = mapWidth + borderSize * 2
    vMapHeight = mapHeight + borderSize * 2
    if lockedFieldControls == 0 and lastSaveX == savePosX and lastSaveY == savePosY then
        stuckCount = stuckCount + 1
        -- else
        --     stuckCount = 0
    end

    if stuckCount > stuckLimit then
        debugBuffer:print("❌ Stuck trying to reach target, requesting new one.\n")
        needNewTarget = true
        possKeys = {}
        table.insert(possKeys, RNG(1) % 4)
        table.insert(possKeys, 0) -- press A, to try interact with target
        nextKey = possKeys[RNG(1) % #possKeys + 1]
        emu:addKey(nextKey)


        -- else
        --     needNewTarget = false
    end

    -- if stuckCount > stuckLimit then
    --     needNewTarget = true
    -- else
    --     needNewTarget = false
    -- end

    -- if targetX < 0 then
    --     needNewTarget = true
    --     -- getMapCollisions()
    -- end

    if isInBattle > 0 then
        stuckCount = 0
        needNewTarget = false
    end

    -- a target was set before pathfinding map was available on a previous frame
    -- so try again this frame
    if gotTargetNeedPath then calculatePathToTarget() end

    -- todo: IN ROM: heal mon on level up

    -- todo: add some pathfinding that takes into account collision tiles in map
    -- target is a connection or a script object

    if mapWidth ~= lastMapWidth or mapHeight ~= lastMapHeight then
        -- TODO: fix to only set targets in routable areas
        debugBuffer:print(string.format("🛬 === Map transition! ===\n"))
        getCurrentLocationName()
        nextPathElement = nil

        stuckCount = 0
        zoneFailCount = 0
        isSimplePathFollow = false

        getMapCollisions()
        if isMapEventsFollow then
            chooseEventToRouteTo()
        end
        if not isMapEventsFollow then
            targetX = (RNG(2) % (mapWidth))
            targetY = (RNG(2) % (mapHeight))
            gotPath = calculatePathToTarget()
            if not gotPath then needNewTarget = true end
        end
    end
    -- if lastSaveX == targetX and lastSaveY == targetY or needNewTarget then
    --     stuckCount = 0
    --     tileMapBuffer:clear()
    --     targetX = RNG(2) % mapWidth
    --     targetY = RNG(2) % mapHeight
    -- end
    if needNewTarget then
        if stuckCount > stuckLimit then
            zoneFailCount = zoneFailCount + 1
        end
        stuckCount = 0

        -- if zoneFailCount > zoneFailLimit then
        --     isSimplePathFollow = true
        -- end

        -- tileMapBuffer:clear()
        -- targetX = RNG(2) % vMapWidth
        -- targetY = RNG(2) % vMapHeight

        -- if following map events, it will fire new targets itself
        if not isMapEventsFollow then
            targetX = (RNG(2) % (mapWidth))
            targetY = (RNG(2) % (mapHeight))
            gotPath = calculatePathToTarget()
            needNewTarget = not gotPath
        end
        if isMapEventsFollow then chooseEventToRouteTo() end
        -- if not gotPath then needNewTarget = true

    end

    lastMapWidth = mapWidth
    lastMapHeight = mapHeight



    -- this is expensive to update so only do this about once a second
    should_update_map = RNG(1)
    should_update_map = 6
    if should_update_map < 2 then

        if (#collisionMap >= mapWidth * mapHeight) then
            tileMapBuffer:clear()
            tile_inc = 0
            for x = 0, mapWidth - 1 do
                for y = 0, mapHeight - 1 do
                    tile_inc = tile_inc + 1
                    tile_id = x + mapWidth * y
                    tileMapBuffer:moveCursor(x, y)
                    if (x == savePosX + 7 and y == savePosY + 7) then
                        tileMapBuffer:print("o")
                    elseif (x == targetX and y == targetY) then
                        tileMapBuffer:print("?")
                    elseif (collisionMap[tile_inc] == 1) then
                        tileMapBuffer:print("X")
                    else
                        tileMapBuffer:print("_")
                    end
                end
            end
        end
    end
    tileMapBuffer:moveCursor(0, mapHeight)
    tileMapBuffer:print(string.format("stuck count: %d\n", stuckCount))
    tileMapBuffer:print(string.format("zone fail count: %d\n", zoneFailCount))




    -- tileMapBuffer:moveCursor(vPosX, vPosY)
    -- tileMapBuffer:print("x")
    -- tileMapBuffer:moveCursor(targetX, targetY)
    -- tileMapBuffer:print("?")



    lastSaveX = savePosX
    lastSaveY = savePosY

    -- warp format
    -- 8            8       8      16  16
    -- mapgroup / mapid / warpid / x / y
    -- gLastUsedWarp tells you the map you LEFT
    -- sWarpDestination tells you where you arrived
    -- use data/maps/map_groups.json to map these


    cameraBuffer:clear()
    -- cameraBuffer:print(string.format("Camera at %d,%d\n", posX, posY))
    cameraBuffer:print(string.format("need collision map of %d, got %d\n", mapWidth * mapHeight, #collisionMap))
    cameraBuffer:print(string.format("Save camera at %d,%d\n", savePosX, savePosY))
    cameraBuffer:print(string.format("Map size %d x %d\n", mapWidth, mapHeight))
end

callbacks:add("start", setupBuffer)
callbacks:add("start", startSocket)
callbacks:add("frame", doMove)
callbacks:add("frame", cameraLog)
if emu then
    setupBuffer()
    startSocket()
end
