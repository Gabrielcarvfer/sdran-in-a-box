#! /usr/bin/env python3
# -*- Mode: python; py-indent-offset: 4; indent-tabs-mode: nil; coding: utf-8; -*-
#
# Copyright (c) 2021 Universidade de Brasília
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation;
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# Author: Gabriel Ferreira <gabrielcarvfer@gmail.com>


import argparse
import socket
from functools import partial
import json
import sys
import time
BUFFSIZE = 4096#65536  # 64kB


class TrafficProfile:
    def __init__(self, file):
        self.address_offset = {}
        with open(file, "r") as f:
            self.traffic = json.load(f)
            if type(self.traffic['packet_size']) == list:
                self.traffic['len'] = len(self.traffic['packet_size'])
            else:
                self.traffic['len'] = 1
                self.traffic['packet_size'] = [self.traffic['packet_size']]

    def get_msg(self, address):
        if address not in self.address_offset:
            self.address_offset[address] = [0, time.time()]

        # end of line
        if self.address_offset[address][0] >= self.traffic['len']:
            return None

        msg_to_send = self.traffic['packet_size'][self.address_offset[address][0]]
        msg_to_send = ("0"*msg_to_send).encode()
        self.address_offset[address][0] += 1 if self.traffic['len'] > 1 else 0

        diff = time.time() - self.address_offset[address][1]
        self.address_offset[address][1] += diff

        if type(self.traffic['time_between_packets']) != list:
            time_between_packets = self.traffic['time_between_packets']
        else:
            time_between_packets = self.traffic['time_between_packets'][self.address_offset[address][0]]

        if diff < time_between_packets:
            time.sleep(time_between_packets - diff)
        return msg_to_send


def server(port, socket_type, operation):
    if socket_type == "tcp":
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.bind(("172.250.255.254", port))
        #sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, "oaitun_ue1".encode())

        sock.setblocking(False)
        sock.listen(10)
        clients = {}

        while 1:
            # Accept connections and start responding them
            try:
                (clientsocket, address) = sock.accept()
                clients[address] = (clientsocket, address)
            except:
                pass

            for client in clients.values():
                try:
                    operation(client)
                except TimeoutError:
                    clients.pop(client)
                except:
                    pass
    else:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(("172.250.255.254", port))
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, "oaitun_ue1".encode())
        sock.setblocking(True)
        sock.settimeout(0.001)

        while 1:
            try:
                operation(sock)
            except Exception as e:
                pass


def client(server_address, port, socket_type, operation):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM if socket_type == "tcp" else socket.SOCK_DGRAM)
    #sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, "oaitun_ue1".encode())

    if socket_type == "udp":
        sock.bind(sock.getsockname())

    sock.connect((server_address, port))

    if socket_type == "udp":
        sock.setblocking(True)
        sock.settimeout(0.001)
    else:
        sock.setblocking(False)
        sock.settimeout(0)

    while 1:
        try:
            operation((sock, server_address))
        except Exception as e:
            pass


def main(argv):

    parser = argparse.ArgumentParser(description="Eros traffic injection script")
    parser.add_argument('role', choices=["server", "client"], action="store", default="server")
    parser.add_argument('port', action="store", type=int, default=8123)
    parser.add_argument('type', choices=["tcp", "udp"], action="store", default="tcp")
    parser.add_argument('--server_address', action="store", type=str, default="127.0.0.1")
    parser.add_argument('--traffic_profile', action="store", type=str, default="sink",
                        help="Set to Sink to consume packages, Echo to send back, or point to a .json file")
    args, unknown_args = parser.parse_known_args(argv)

    if args.traffic_profile.lower() == "sink":
        def func_tcp(buffer_size, clientsocket_and_address_tup):
            msg = clientsocket_and_address_tup[0].recv(buffer_size)

        def func_udp(buffer_size, clientsocket):
            try:
                msg, address = clientsocket.recvfrom(buffer_size)
                if msg is None:
                    exit(0)
            except Exception as e:
                pass
        operation = partial(func_tcp if args.type == "tcp" else func_udp, BUFFSIZE)
    elif args.traffic_profile.lower() == "echo":
        def func_tcp(buffer_size, clientsocket_and_address_tup):
            try:
                msg = clientsocket_and_address_tup[0].recv(buffer_size)
                if msg is None:
                    exit(0)
                clientsocket_and_address_tup[0].send(msg)
            except:
                pass

        def func_udp(buffer_size, clientsocket):
            try:
                msg, address = clientsocket.recvfrom(buffer_size)
                if msg is None:
                    exit(0)
                clientsocket.sendto(msg, address)
            except Exception as e:
                pass
        operation = partial(func_tcp if args.type == "tcp" else func_udp, BUFFSIZE)
    else:
        # In this case, we load the json file to get the traffic to be injected
        traffic = TrafficProfile(args.traffic_profile)

        def func_tcp(traffic, clientsocket_and_address_tup):
            while True:
                try:
                    msg = clientsocket_and_address_tup[0].recv(BUFFSIZE)
                except:
                    break
            msg = traffic.get_msg(clientsocket_and_address_tup[1])
            if msg is None:
                exit(0)
            n = len(msg)//BUFFSIZE
            r = len(msg) % BUFFSIZE
            if r > 0:
                n += 1
            while n > 0:
                n -= 1
                clientsocket_and_address_tup[0].send(msg[:BUFFSIZE if n != 0 and r != 0 else r])

        def func_udp(traffic, clientsocket_and_address_tup):
            while True:
                try:
                    msg, address = clientsocket_and_address_tup[0].recvfrom(BUFFSIZE)
                except Exception as e:
                    break
            msg = traffic.get_msg("")
            if msg is None:
                exit(0)
            n = len(msg)//BUFFSIZE
            r = len(msg) % BUFFSIZE
            if r > 0:
                n += 1
            while n > 0:
                n -= 1
                clientsocket_and_address_tup[0].sendto(msg[:BUFFSIZE if n != 0 and r != 0 else r], (clientsocket_and_address_tup[1], args.port))

        operation = partial(func_tcp if args.type == "tcp" else func_udp, traffic)

    if args.role.lower() == "server":
        server(args.port, args.type, operation)
    else:
        client(args.server_address, args.port, args.type, operation)


def test():
    import multiprocessing as mp
    processes = [mp.Process(target=main, args=[("server",
                                                "8135",
                                                "udp",
                                                "--traffic_profile=echo")]),                                                           #"--traffic_profile=backhaul_dl_workload0_10s.json"
                 mp.Process(target=main, args=[("client",
                                                "8135",
                                                "udp",
                                                "--server_address=127.0.0.1",
                                                "--traffic_profile=stream_workload0_2mbps_100s.json")])    #"--traffic_profile=stream_workload0_2mbps_100s.json")])
                 ]
    # inicia os dois processos (pode olhar no gerenciador de tarefas,
    #    que lá estarão
    for process in processes:
        process.start()

    # espera pela finalização dos processos filhos
    #   (em Sistemas operacionais verão o que isso significa)
    for process in processes:
        process.join()
    exit(0)


if __name__ == "__main__":
    #test()
    main(sys.argv[1:])

