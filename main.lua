StartDebug()
socket = require("socket")
json = require('json')

-- Network variables (don't touch) --
	IsaacNetwork = {}

	local client

	local Behaviour = {}
	Behaviour.IDLE = 0
	Behaviour.CLIENT = 1

	local clientID = 0
	IsaacNetwork.clientID = clientID

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

local Mod = RegisterMod("Isaac Networking", 1)

local game = Game();

-- Network functions (don't touch) --

	local function RegisterNetworkPlugin(name, sender, processor)
		Plugins.Names[#Plugins.Names+1]=name
		Plugins.Senders[name]=sender
		Plugins.Processors[name]=processor
	end
	IsaacNetwork.RegisterNetworkPlugin = RegisterNetworkPlugin

	local function BuildPluginDataTable()
		local DataTable = {}
		for k,v in pairs(Plugins.Names) do
			local sender = Plugins.Senders[v]
			DataTable[v] = sender()
		end
		return DataTable
	end

	local function SendDataToPlugins()
		local PluginDatas = {}
		for k,v in pairs(connectedClients) do
			PluginDatas[k] = v.PLUGINDATA
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

	local function ClientThread()
			if currentBehaviour == Behaviour.CLIENT then
					local player = Game():GetPlayer(0)
					local roomindex = Game():GetLevel():GetCurrentRoomIndex()
					local JSONString = json.encode(BuildPluginDataTable())
					Network.SendData("[ID]"..clientID.."[PLUGINDATA]"..JSONString) -- Transmit all interesting information to the server
					client:settimeout(0)
					local playertable = Network.Read(client)
					if playertable ~= nil then
						connectedClients = json.decode(playertable)
            IsaacNetwork.connectedClients = connectedClients;
						SendDataToPlugins()
					end
					client:settimeout(loopTimeout)
			end
	end

	local rBuf = "";
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
						--Isaac.DebugString(l)
						lastLine = l
				end
			end
			return lastLine
	end

	function Network.SendData(data)
			if currentBehaviour == Behaviour.CLIENT then
					client:send(data.."\n")
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
						clientID = tonumber(ClID)
						IsaacNetwork.clientID = clientID
					end
			end
	end

	function Network.CloseConnection()
			if currentBehaviour ~= Behaviour.IDLE then
					if currentBehaviour == Behaviour.CLIENT then
							Network.SendData("[END]"..clientID)
							local ack = client:receive()
							Isaac.DebugString(ack)
							client:close()
							clientID = 0
							IsaacNetwork.clientID = clientID
							connectedClients = {}
							IsaacNetwork.connectedClients = connectedClients;
					end
					currentBehaviour = Behaviour.IDLE
			end
	end
  IsaacNetwork.CloseConnection = function() Network.CloseConnection() end;

function Mod:RenderLoop()
		if (Input.IsButtonTriggered(Keyboard.KEY_F5, 0)) then
						Network.StartClient()
				elseif (Input.IsButtonTriggered(Keyboard.KEY_F7, 0)) then
						Network.CloseConnection()
		end
		ClientThread()

		Isaac.RenderText(connectIP, 50, 60, 1, 1, 1, 1)
		Isaac.RenderText("clientID :"..clientID, 50, 70, 1, 1, 1, 1)
end

local function getArgs(params)
	args={}
	for i in string.gmatch(params, "%S+") do
	 args[#args+1] = i
	end
	return args
end

function Mod:Command(command, params)
	args = getArgs(params)
	if clientID == 0 and command == "connect" then
		if #args >= 1 then
			connectIP = args[1];
			IsaacNetwork.connectIP = connectIP
			Network.StartClient()
		end
	end
	if command == "disconnect" then
		Network.CloseConnection()
	end
	if clientID == 0 and command == "pluginlist" then
		Isaac.ConsoleOutput( "IsaacNetwork : " )
		for k,v in pairs(Plugins.Names) do
			Isaac.ConsoleOutput("	- " .. v)
		end
	end
end

function Mod:CloseConnection(shouldSave)
	if not shouldSave then
		IsaacNetwork.CloseConnection();
	end
end

Mod:AddCallback(ModCallbacks.MC_POST_RENDER, Mod.RenderLoop)
Mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, Mod.Command)
Mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, Mod.CloseConnection)

-- PLUGINS --

local function BasicInfoBuilder()
	local player = Isaac.GetPlayer(0);
	local table = {}
	table.Seed = game:GetSeeds():GetStartSeed();
	table.Level = game:GetLevel():GetAbsoluteStage();
	table.Room = game:GetLevel():GetCurrentRoomIndex();
	table.PositionX = player.Position.X;
	table.PositionY = player.Position.Y;
	table.Name = player:GetName();
	return table
end

local function BasicInfoProcessor(table)

end

IsaacNetwork.RegisterNetworkPlugin("BasicInfo", BasicInfoBuilder, BasicInfoProcessor)
