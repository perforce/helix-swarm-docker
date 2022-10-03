
REPO    := perforce
IMAGE   := helix-swarm-development
TAG     := DEV-BUILD
ARGS    := 
NAME    := helix-swarm

-include build.mk
	

.env:
	cp env.dist .env

build: .env
	docker build $(ARGS) --tag $(REPO)/$(IMAGE):$(TAG) --tag $(REPO)/$(IMAGE):latest .

build-clean: .env
	docker build $(ARGS) --no-cache --tag $(REPO)/$(IMAGE):$(TAG) --tag $(REPO)/$(IMAGE):latest .

push: build
	docker push $(REPO)/$(IMAGE):$(TAG)
	docker push $(REPO)/$(IMAGE):latest
	
run: build
	-docker network create helix
	-docker run -d --name helix-redis --network helix --network-alias helix-redis \
		redis redis-server --protected-mode no --port 7379

	docker run -d --name helix-swarm --network helix --network-alias helix-swarm \
		--env-file .env -p 80:80 $(REPO)/$(IMAGE):$(TAG)

clean:
	-docker stop helix-swarm
	-docker stop helix-redis
	-docker rm -f helix-swarm
	-docker rm -f helix-redis

bash:
	docker exec -it `docker ps | grep $(NAME) | cut -d " " -f 1` bash


log:
	docker logs `docker ps | grep $(NAME) | cut -d " " -f 1`


tail:
	docker logs -f `docker ps | grep $(NAME) | cut -d " " -f 1`

swarm-log:
	docker exec -it `docker ps | grep $(NAME) | cut -d " " -f 1` tail -f /opt/perforce/swarm/data/log

swarm-config:
	docker exec -it `docker ps | grep $(NAME) | cut -d " " -f 1` cat /opt/perforce/swarm/data/config.php


#
# Helper commands to upgrade the version file.
#
VERSION := $(shell cat Version)
MAJOR   := $(shell cut -d "." -f 1 Version)
MINOR   := $(shell cut -d "." -f 2 Version)
PATCH   := $(shell cut -d "." -f 3 Version)

patch:
	@echo "Patch upgrade from $(VERSION)"
	$(eval PATCH=$(shell echo $$(($(PATCH)+1))))
	echo $(MAJOR).$(MINOR).$(PATCH) > Version

minor:
	@echo "Minor upgrade from $(VERSION)"
	$(eval MINOR=$(shell echo $$(($(MINOR)+1))))
	echo $(MAJOR).$(MINOR).0 > Version

major:
	echo "Major upgrade from $(VERSION)"
	$(eval MAJOR=$(shell echo $$(($(MAJOR)+1))))
	echo $(MAJOR).0.0 > Version
