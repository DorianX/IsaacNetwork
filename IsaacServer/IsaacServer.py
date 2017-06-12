import socket
import select
import json
import re
from parse import *

IsaacClients = {}
ClientState= {}
IP_to_CID = {}

file = open("config.json", "r")
file = file.read()
config = json.loads(file)

seed = config['seed']

connected_clients = []

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, True)
server.bind(('', config['port']))
server.listen(config['maxClient'])

num_clients = 0

server_launched = True


while server_launched:

    connections_asked, wlist, xlist = select.select([server],
                                                    [], [], 0.01)

    for connection in connections_asked:  # connect the clients
        connection_client, info_client = connection.accept()
        print()

        connected_clients.append(connection_client)
        print("Sending Seed")
        num_clients += 1
        check = ""
        connection_client.sendall((seed + str(num_clients) + "\n").encode())  # sends the string plus the client ID
        IP_to_CID[info_client] = num_clients
        print(connection_client.getpeername())

    clients_to_read = []
    try:
        clients_to_read, wlist, xlist = select.select(connected_clients, connected_clients, [],
                                                      0.01)  # see who to read from and who to send
    except select.error:
        pass
    else:
        for client in clients_to_read:
            try:
                msg_recved = client.recv(1024)  # let's receive
            except socket.error:
                connected_clients.remove(client)
                ClientState[IP_to_CID[client.getpeername()]] = "'Disconnected'"
                client.close()
                pass
            else:
                msg_recved = msg_recved.decode()
                print(msg_recved)
                clientID_to_close = re.search(r"(?<=\[END\])[0-9]*", msg_recved)
                if clientID_to_close:  # if the clients wants to end the connection
                    print("Try to end connection")
                    print("Parsed, END : " + clientID_to_close.group(0))
                    ackend = "[ACKEND]\n"
                    client.sendall(ackend.encode())
                    connected_clients.remove(client)
                    client.close()
                    ClientState[int(clientID_to_close.group(0))] = "'Disconnected'"
                msg_recved = msg_recved.split('\n')  # split into lines

                for line in msg_recved:
                    data = parse(
                        "[ID]{ID}[PLUGINDATA]{PluginData}",
                        line)
                    if data is not None:
                        IsaacClients[data['ID']] = data
                        if int(data['ID']) in ClientState:
                            if ClientState[int(data['ID'])] != "'Disconnected'":
                                ClientState[int(data['ID'])] = "'Connected'"
                        else:
                            ClientState[int(data['ID'])] = "'Connected'"
                
        luaTable = "{"  # start the generation of the lua table that will be sent
        for player in IsaacClients.values():
            luaTable = luaTable \
                       + "[" + player['ID'] \
                       + "]={ID=" + player['ID'] \
                       + ",PLUGINDATA=[===[" + player['PluginData'] + "]===]" \
                       + "},"
        luaTable = luaTable[:len(luaTable) - 1] + "}\n"
        print(luaTable)
        print("Sending Table")
        for client_to_send in wlist:
            if (client_to_send is not server and client_to_send._closed is False):
                print(client_to_send)
                try:
                    rtrn = client_to_send.sendall(luaTable.encode())
                except socket.error:
                    connected_clients.remove(client_to_send)
                    ClientStat[IP_to_CID[client_to_send.getpeername()]] = "'Disconnected'"
                    client_to_send.close()
                    pass
                else:
                    print(rtrn)
        print("Table Sent")
        print(ClientState)
print("Server closing")
for client in connected_clients:
    client.close()
