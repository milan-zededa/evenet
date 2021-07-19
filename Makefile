.PHONY: images
images:
	cd images/vswitch/ && docker build -t evenet/vswitch .
	cd images/app/ && docker build -t evenet/app .
	cd images/ovs/ && docker build -t evenet/ovs .

.PHONY: start-multi-ns
start-multi-ns: images stop-multi-ns
	docker-compose -f proposal/multi-ns/docker-compose.yaml up -d
	./proposal/multi-ns/configure.sh

.PHONY: stop-multi-ns
stop-multi-ns:
	docker-compose -f proposal/multi-ns/docker-compose.yaml down

.PHONY: start-multi-vrf
start-multi-vrf: images stop-multi-vrf
	docker-compose -f proposal/multi-vrf/docker-compose.yaml up -d
	./proposal/multi-vrf/configure.sh

.PHONY: stop-multi-vrf
stop-multi-vrf:
	docker-compose -f proposal/multi-vrf/docker-compose.yaml down

.PHONY: start-ovs
start-ovs: images stop-ovs
	docker-compose -f proposal/ovs/docker-compose.yaml up -d

.PHONY: stop-ovs
stop-ovs:
	docker-compose -f proposal/ovs/docker-compose.yaml down -v
