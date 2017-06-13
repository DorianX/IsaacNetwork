import socket
import select
import json
import re
from parse import *

IsaacClients = {}
ClientState = {}
IP_to_CID = {}
IP_to_buffer = {}

file = open("config.json", "r")
file = file.read()
config = json.loads(file)

seed = config['seed']
buffer_limit = config['bufferMax']

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, True)
server.bind(('', config['port']))
server.listen(config['maxClient'])

num_clients = 0

server_launched = True
connected_clients = []


def CloseConnection(client):
    connected_clients.remove(client)
    ClientState[IP_to_CID[client.getpeername()]] = "'Disconnected'"
    client.close()


def InitiateConnections(connections_asked):
    global num_clients
    for connection in connections_asked:  # connect the clients
        if num_clients < config['maxClient']:
            connection_client, info_client = connection.accept()
            print()

            connected_clients.append(connection_client)
            print("Sending Seed")

            num_clients += 1

            connection_client.sendall((seed + str(num_clients) + "\n").encode())  # sends the string plus the client ID
            IP_to_CID[info_client] = num_clients
            IP_to_buffer[info_client] = b""
            ClientState[num_clients] = "'Connected'"


def ReceiveLastFrame(client):
    continue_to_recv = True
    last_frame = b""
    receive_counter = 0
    buffer_flushed = False
    while continue_to_recv:
        if client._closed is False:
            try:
                buffer_index = client.getpeername()
                IP_to_buffer[buffer_index] += client.recv(1024)  # let's receive
            except socket.error:
                CloseConnection(client)
                pass
            else:
                if client._closed is False:
                    receive_counter += 1
                    if len(IP_to_buffer[buffer_index]) > buffer_limit: # flush the buffer on size limit
                        IP_to_buffer[buffer_index] = b""
                    if receive_counter > 10: # if it takes too long, go take care of another client
                        continue_to_recv = False
                        last_frame = b"[UNFINISHED]"
                    if b"[END]" in IP_to_buffer[buffer_index]: # if the clients want to end the connection
                        CloseConnection(client)
                        continue_to_recv = False
                        last_frame = b"[END]"
                    elif b"\n" in IP_to_buffer[buffer_index]: # on EOL : a new frame begins, and the preceding one ends

                        lines = IP_to_buffer[buffer_index].split(b"\n")
                        IP_to_buffer[buffer_index] = lines[len(lines) - 1] # place what's after the EOL in the buffer

                        if buffer_flushed is False: # if the buffer wasn't flush because it was too big, the preceding frame sucessfully ended (check if
                            last_frame = lines[len(lines) - 2]
                            continue_to_recv = False
        else :
            continue_to_recv = False
            last_frame = b"[CLOSED]"

    return last_frame.decode()


def BuildServerFrame():
    frame = "{"  # start the generation of the JSON table that will be sent
    for player in IsaacClients.values():
        if ClientState[int(player['ID'])] != "'Disconnected'":
            frame = frame \
                    + "'" + player['ID'] \
                    + "':{'ID':" + player['ID'] \
                    + ", 'STATE':" + ClientState[int(player['ID'])] \
                    + ",'PLUGINDATA':" + player['PluginData'] \
                    + "},"
    if frame[len(frame)-1] == ',':
        frame = frame[:len(frame) - 1] + "}\n"
    else:
        frame += "}\n"
    return frame


def SendFrame(wlist, frame):
    for client_to_send in wlist:
        if (client_to_send is not server and client_to_send._closed is False):
            try:
                rtrn = client_to_send.sendall(frame.encode())
            except socket.error:
                CloseConnection(client_to_send)
                pass
            else:
                print(rtrn)


while server_launched:

    connections_asked, wlist, xlist = select.select([server],
                                                    [], [], 0.01)

    InitiateConnections(connections_asked)

    clients_to_read = []
    try:
        clients_to_read, wlist, xlist = select.select(connected_clients, connected_clients, [],
                                                      0.01)  # see who to read from and who to send
    except select.error:
        pass
    else:
        for client in clients_to_read:
            if client._closed is False:
                line = ReceiveLastFrame(client)
                print(line)
                data = parse("[ID]{ID}[PLUGINDATA]{PluginData}", line)
                if data is not None:
                    IsaacClients[data['ID']] = data
                    if int(data['ID']) in ClientState:
                        if ClientState[int(data['ID'])] != "'Disconnected'":
                            ClientState[int(data['ID'])] = "'Connected'"
                    else:
                        ClientState[int(data['ID'])] = "'Connected'"

        frame_to_send = BuildServerFrame()
        print(frame_to_send)
        SendFrame(wlist, frame_to_send)
        print("Table Sent")
        print(ClientState)

print("Server closing")
for client in connected_clients:
    client.close()
