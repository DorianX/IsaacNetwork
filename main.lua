StartDebug()
socket = require("socket")
json = require('json')

IsaacNetwork = {}

local Mod = RegisterMod("IsaacNetwork", 1)
local client
local remote --remote client
local server

local Behaviour = {}
Behaviour.IDLE = 0
Behaviour.CLIENT = 1

local ClientID = 0
IsaacNetwork.clientID = ClientID

local lastStr = ""
local connectedClients = {}
IsaacNetwork.connectedClients = connectedClients

local currentBehaviour = 0 -- current behaviour : client/idle
IsaacNetwork.currentBehaviour = currentBehaviour

local connectIP = ""
IsaacNetwork.connectIP = connectIP
local currentPort = 21666

local loopTimeout = 10;

local Network = {} -- my own network API, to simplify things



local Plugins = {}
Plugins.Names = {}
Plugins.Senders = {}
Plugins.Processors = {}

local RegisterNetworkPlugin
function RegisterNetworkPlugin(name, sender, processor)
  Plugins.Names[#Plugins.Names+1]=name
  Plugins.Senders[name]=sender
  Plugins.Processors[name]=processor
end
IsaacNetwork.RegisterNetworkPlugin = RegisterNetworkPlugin

local BuildPluginDataTable
function BuildPluginDataTable()
  local DataTable = {}
  for k,v in pairs(Plugins.Names) do
    local sender = Plugins.Senders[v]
    DataTable[v] = sender()
  end
  return DataTable
end

local SendDataToPlugins
function SendDataToPlugins()
  local PluginDatas = {}
  for k,v in pairs(connectedClients) do
    PluginDatas[k] = json.decode(v.PLUGINDATA)
  end

    for i,NAME in pairs(Plugins.Names) do
      local DataToGive = {}
      for CID,DATA in pairs(PluginDatas) do
        DataToGive[CID] = DATA[NAME]
      end
      local proc = Plugins.Processors[NAME]
      proc(DataToGive)
    end

end
local ClientThread
function ClientThread()
    if currentBehaviour == Behaviour.CLIENT then
        local player = Game():GetPlayer(0)
        local roomindex = Game():GetLevel():GetCurrentRoomIndex()
        local JSONString = json.encode(BuildPluginDataTable())
        Isaac.DebugString("Sending string")
        Network.SendData("[ID]"..ClientID.."[PLUGINDATA]"..JSONString) -- Transmit all interesting information to the server
        Isaac.DebugString("Start reading")
        client:settimeout(0)
        local playertable = Network.Read(client)
        if playertable ~= nil then
          Isaac.DebugString(playertable)
          func = load("return "..playertable)
          connectedClients = func()
          lastStr = playertable
          SendDataToPlugins()
        end
        client:settimeout(loopTimeout)
    end
end

local rBuf = ""
function Network.Read(socket)
    local l, err
    local lastLine
    l = ""
    while l ~= nil do
      l, err, rBuf = socket:receive("*l", rBuf)
      if not l then
          if err ~= "timeout" then
            Network.CloseConnection()
            Isaac.DebugString("Read error:"..err)
          end
        else
          Isaac.DebugString(l)
          lastLine = l
      end
    end
    return lastLine
end

function Network.SendData(data)
    if currentBehaviour == Behaviour.CLIENT then
        client:send(data.."\n")
        Isaac.DebugString(data)
    end
end

function Network.StartClient()
    if currentBehaviour == Behaviour.IDLE then
        client = assert(socket.tcp())
        client:connect(connectIP,currentPort)
        currentBehaviour = Behaviour.CLIENT
        client:settimeout(loopTimeout) -- set the connection timeout

        local CID,err,prt = client:receive()
        if err~="timeout" and err~=nil then
          Network.CloseConnection();
          Isaac.DebugString("CID error:"..err);
        elseif err=="timeout" then
          Network.CloseConnection();
          Isaac.DebugString("timeout at CID :"..(CID or "")..(prt or ""));
        elseif err==nil then
          seed = CID:sub(1,9)
          ClID = CID:sub(10)
          Isaac.DebugString("CID : "..ClID);
          Isaac.DebugString("Seed : "..seed);
          Isaac.ExecuteCommand("seed "..seed)
          ClientID = tonumber(ClID)
        end

    end
end

function Network.CloseConnection()
    if currentBehaviour ~= Behaviour.IDLE then
        if currentBehaviour == Behaviour.CLIENT then
            Network.SendData("[END]"..ClientID)
            local ack = client:receive()
            Isaac.DebugString(ack)
              client:close()
              ClientID = 0
              lastStr = ""
              connectedClients = {}
        end
        currentBehaviour = Behaviour.IDLE
    end
end


function Mod:RenderLoop()
    if (Input.IsButtonTriggered(Keyboard.KEY_F5, 0)) then
            Network.StartClient()
        elseif (Input.IsButtonTriggered(Keyboard.KEY_F7, 0)) then
            Network.CloseConnection()
    end
    ClientThread()

    Isaac.RenderText (connectIP, 50, 50, 1, 1, 1, 1)
    --Isaac.RenderText ("Behaviour :"..currentBehaviour, 50, 60, 1, 1, 1, 1) -- For debugging purposes
    Isaac.RenderText ("ClientID :"..ClientID, 50, 70, 1, 1, 1, 1)
    --Isaac.RenderText ("Received :"..lastStr, 50, 80, 1, 1, 1, 1) -- For debugging purposes

    -- Everything below is an example of how to use the data contained in the connectedClients table,
    -- anything outside of this file MUST use IsaacNetwork.connectedClients instead.
    --             \/
    -- if connectedClients ~= nil then
    --   for k, v in pairs(connectedClients) do
    --     if (v.FLOOR == Game():GetLevel():GetStage() and v.ROOM == Game():GetLevel():GetCurrentRoomIndex() ) then
    --       local x = v.POS.x
    --       local y = v.POS.y
    --       local worldPos = Vector(x,y)
    --       local screenPos = Game():GetRoom():WorldToScreenPosition(worldPos)
    --       Isaac.DebugString(screenPos.X..";"..screenPos.Y)
    --       Isaac.RenderText(v.ID..":"..v.CHAR, screenPos.X, screenPos.Y, 1, 1, 1, 1)
    --     end
    --   end
    -- end
end

local getArgs
function getArgs(params)
  args={}
  for i in string.gmatch(params, "%S+") do
   args[#args+1] = i
  end
  return args
end

function Mod:Command(command, params)
  args = getArgs(params)
  if command == "connect" then
    if #args >= 1 then
      connectIP = args[1]
      Network.StartClient()
    end
  end
  if command == "disconnect" then
    Network.CloseConnection()
  end
  if command == "pluginlist" then
    Isaac.ConsoleOutput( "IsaacNetwork : " )
    for k,v in pairs(Plugins.Names) do
      Isaac.ConsoleOutput("  - " .. v)
    end

  end
end

Mod:AddCallback(ModCallbacks.MC_POST_RENDER, Mod.RenderLoop)
Mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, Mod.Command)

function PositionSyncBuilder()
  local player = Isaac.GetPlayer(0);
  local table = {}
  table.PositionX = player.Position.X;
  table.PositionY = player.Position.Y;
  table.Name = player:GetName();
  return table
end

function PositionSyncProcessor(table)
  for ID,Data in pairs(table) do
    --if ID ~= clientID then
      local worldPos = Vector(Data['PositionX'], Data['PositionY'])
      local screenPos = Game():GetRoom():WorldToScreenPosition(worldPos)
      Isaac.RenderText(ID..": "..Data['Name'], screenPos.X, screenPos.Y, 1, 1, 1, 1)
    --end
  end
end


IsaacNetwork.RegisterNetworkPlugin("PositionSync", PositionSyncBuilder, PositionSyncProcessor)
