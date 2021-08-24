
.env:
	cp env.dist .env

build: .env
	cp -f Version containers/helix-swarm
	docker-compose build
	
up: build
	docker-compose up -d

stop:
	docker-compose stop

down:
	docker-compose down
	
clean:
	docker-compose rm -sf
	sudo rm -fr ./storage/redis-data/*
	sudo rm -fr ./storage/swarm-data
	mkdir -p ./storage/swarm-data

bash:
	docker exec -it `docker ps | grep helix.swarm | cut -d " " -f 1` bash

push:
	docker-compose push

	
log:
	docker logs `docker ps | grep helix.swarm | cut -d " " -f 1`


tail:
	docker logs -f `docker ps | grep helix.swarm | cut -d " " -f 1`
	
test:
	docker-compose run helix.swarm sleep 900


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
