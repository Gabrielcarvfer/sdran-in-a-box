# Copyright 2020-present Open Networking Foundation
# SPDX-License-Identifier: Apache-2.0

# PHONY definitions
TEST_PHONY					:= test-user-plane test-kpimon test-pci

test-user-plane: | $(M)/omec $(M)/oai-ue
	@echo "*** T1: Internal network test: ping $(shell echo $(CORE_GATEWAY) | awk -F '/' '{print $$1}') (Internal router IP) ***"; \
	#sudo tshark -i oaitun_ue1 -w output.pcap -a duration:30 &
	#sleep 10
	ping -c 10 $(shell echo $(CORE_GATEWAY) | awk -F '/' '{print $$1}') -I oaitun_ue1; \
	echo "*** T2: Internet connectivity test: ping to 8.8.8.8 ***"; \
	ping -c 10 8.8.8.8 -I oaitun_ue1; \
	echo "*** T3: DNS test: ping to google.com ***"; \
	ping -c 10 google.com -I oaitun_ue1;

test-kpimon: | $(M)/ric
	@echo "*** Get KPIMON result through CLI ***"; \
	kubectl exec -it deploy/onos-cli -n riab -- onos kpimon list metrics;

test-pci: | $(M)/ric
	@echo "*** Get PCI result through CLI ***"; \
	kubectl exec -it deployment/onos-cli -n riab -- onos pci get resolved;

test-mlb: | $(M)/ric
	@echo "*** Get MLB result through CLI ***"; \
	kubectl exec -it deployment/onos-cli -n riab -- onos mlb list ocns;

test-rnib: | $(M)/ric
	@echo "*** Get R-NIB result through CLI ***"; \
	kubectl exec -it deployment/onos-cli -n riab -- onos topo get entity -v;

test-uenib: | $(M)/ric
	@echo "*** Get UE-NIB result through CLI ***"; \
	kubectl exec -it deployment/onos-cli -n riab -- onos uenib get ues -v;

test-e2-connection: | $(M)/ric
	@echo "*** Get E2 connections through CLI ***"; \
	kubectl exec -it deployment/onos-cli -n riab -- onos e2t get connections;

test-e2-subscription: | $(M)/ric
	@echo "*** Get E2 subscriptions through CLI ***"; \
	kubectl exec -it deployment/onos-cli -n riab -- onos e2t get subscriptions;

test-rsm-dataplane: $(M)/ric $(M)/omec $(M)/oai-ue
	@echo "*** Test downlink traffic (UDP) ***"
	sudo apt install -y iperf3
	kubectl exec -it router -- apt install -y iperf3
	iperf3 -s -B $$(ip a show oaitun_ue1 | grep inet | grep -v inet6 | awk '{print $$2}' | awk -F '/' '{print $$1}') -p 5001 > /dev/null &
	kubectl exec -it router -- iperf3 -u -c $$(ip a show oaitun_ue1 | grep inet | grep -v inet6 | awk '{print $$2}' | awk -F '/' '{print $$1}') -p 5001 -b 20M -l 1450 -O 2 -t 12 --get-server-output
	pkill -9 -ef iperf3
	@echo "*** Test downlink traffic (TCP) ***"
	iperf3 -s -B $$(ip a show oaitun_ue1 | grep inet | grep -v inet6 | awk '{print $$2}' | awk -F '/' '{print $$1}') -p 5001 > /dev/null &
	kubectl exec -it router -- iperf3 -c $$(ip a show oaitun_ue1 | grep inet | grep -v inet6 | awk '{print $$2}' | awk -F '/' '{print $$1}') -p 5001 -b 20M -l 1450 -O 2 -t 12 --get-server-output
	pkill -9 -ef iperf3

#test-bigbuckbunny-dataplane: $(M)/ric $(M)/omec $(M)/oai-ue
#	@echo "*** Test downlink traffic (UDP) ***"
#	sudo apt install -y vlc tshark
#	kubectl exec -it router -- apt install -y vlc
#	sudo tshark -w output.pcap -a duration:15 &
#	sleep 1
#	cvlc ./BigBuckBunny.mp4 --loop --sout '#transcode{vcodec=h264,acodec=mpga,vb=125k,ab=64k,deinterlace,scale=0.25,threads=2}:http{mux=ts,dst=172.250.255.254:5001}' &
#	#kubectl exec -it router -- userdel vlc
#	#kubectl exec -it router -- useradd -m vlc
#	#kubectl exec -it router -- passwd vlc -p 1
#	kubectl exec -it router -- vlc http://172.250.255.254:5001 --sout="#duplicate{dst=std{access=file,mux=avi,dst=stream.avi},dst=nodisplay}" &
#	sleep 10
#	kubectl exec -it router -- pkill -9 -ef vlc
#	pkill -9 -ef cvlc

	#sudo tshark -w output.pcap -a duration:100 &
	#kubectl exec -it router -- ./inject_eros_traffic.py server 8123 tcp &
	#./inject_eros_traffic.py client 8123 tcp --server_address=192.168.250.1 --traffic_profile=stream_workload0_2mbps_100s.json &

test-eros-dataplane: $(M)/ric $(M)/omec $(M)/oai-ue
	@echo "*** Test downlink traffic (UDP) ***"
	kubectl cp ./inject_eros_traffic.py default/router:/
	kubectl cp ./stream_workload0_2mbps_100s.json default/router:/
	sudo apt install -y python3 tshark at
	kubectl exec -it router -- apt install -y python3 at
	sudo tshark -i oaitun_ue1 -w output.pcap -a duration:100 &
	sudo ./inject_eros_traffic.py server 8123 tcp &
	kubectl exec -it router -- ./inject_eros_traffic.py client 8123 tcp --server_address=172.250.255.254 --traffic_profile=stream_workload0_2mbps_100s.json &
	echo "killall inject_eros_traffic.py" | at now + 1 min
	kubectl exec -it router -- echo "killall inject_eros_traffic.py" | at now + 1 min

#test-flent-dataplane: $(M)/ric $(M)/omec $(M)/oai-ue
#	@echo "*** Test downlink traffic (UDP) ***"
#	echo "deb [trusted=yes] https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu bionic main" | sudo tee -a /etc/apt/sources.list
#	sudo apt update
#	sudo apt install -y netperf python3.5 curl
#	sudo cp --force /usr/bin/python3.5 /usr/bin/python3
#	curl https://bootstrap.pypa.io/pip/3.5/get-pip.py -o get-pip.py
#	python3 get-pip.py
#	sudo pip install matplotlib flent
#	kubectl exec -it router -- echo "deb [trusted=yes] https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu bionic main" | sudo tee -a /etc/apt/sources.list
#	kubectl exec -it router -- apt update
#	kubectl exec -it router -- apt install -y netperf python3.5 curl
#	kubectl exec -it router -- cp --force /usr/bin/python3.5 /usr/bin/python3
#	kubectl exec -it router -- curl https://bootstrap.pypa.io/pip/3.5/get-pip.py -o get-pip.py
#	kubectl exec -it router -- python3 get-pip.py
#	kubectl exec -it router -- pip install matplotlib flent
#	flent --local-bind $$(ip a show oaitun_ue1 | grep inet | grep -v inet6 | awk '{print $$2}' | awk -F '/' '{print $$1}') host &
#	kubectl exec -it router -- flent rrul -p all_scaled -t "RRUL all" -l 60 -H $$(ip a show oaitun_ue1 | grep inet | grep -v inet6 | awk '{print $$2}' | awk -F '/' '{print $$1}')
#	kubectl exec -it router -- flent rrul -p ping_cdf -t "RRUL ping cdf" -l 60 -H $$(ip a show oaitun_ue1 | grep inet | grep -v inet6 | awk '{print $$2}' | awk -F '/' '{print $$1}')
#	kubectl exec -it router -- flent tcp_upload -t "TCP UP" -p totals -l 60 -H $$(ip a show oaitun_ue1 | grep inet | grep -v inet6 | awk '{print $$2}' | awk -F '/' '{print $$1}')
#	kubectl exec -it router -- flent tcp_download -t "TCP DOWN" -p totals -l 60 -H $$(ip a show oaitun_ue1 | grep inet | grep -v inet6 | awk '{print $$2}' | awk -F '/' '{print $$1}')
#	pkill -9 -ef flent

test-mho: | $(M)/ric
	@echo "*** Get MHO result through CLI - Cells ***"; \
	kubectl exec -it deployment/onos-cli -n riab -- onos mho get cells;
	@echo "*** Get MHO result through CLI - UEs ***"; \
	kubectl exec -it deployment/onos-cli -n riab -- onos mho get ues;

test-a1t: | $(M)/ric
	@echo "*** Get A1T subscriptions through CLI ***"; \
	kubectl exec -it deployment/onos-cli -n riab -- onos a1t get subscription
	@echo "*** Get A1T policy type through CLI ***"; \
	kubectl exec -it deployment/onos-cli -n riab -- onos a1t get policy type
	@echo "*** Get A1T policy objects through CLI ***"; \
	kubectl exec -it deployment/onos-cli -n riab -- onos a1t get policy object
	@echo "*** Get A1T policy status through CLI ***"; \
	kubectl exec -it deployment/onos-cli -n riab -- onos a1t get policy status