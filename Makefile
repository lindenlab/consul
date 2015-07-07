APP_NAME := consul
SRC_DIR := src/github.com/hashicorp
APP_DIR := $(SRC_DIR)/$(APP_NAME)

REGISTRY := registry.docker
BUILD_IMAGE := $(REGISTRY)/golang
APP_IMAGE := $(REGISTRY)/hashicorp/$(APP_NAME)
DOCKER_RUN := docker run -i --rm -v "$(shell pwd)":/go $(BUILD_IMAGE)
UID := $(shell id -u)
GID := $(shell id -g)

all: test binary

$(APP_DIR):
	mkdir -p $(SRC_DIR)
	ln -s ../../../ $(APP_DIR)

deps: $(APP_DIR)

binary: deps
	$(DOCKER_RUN) bash -c "cd /go/$(APP_DIR); go get && go install"
	$(MAKE) chown

test: deps
	$(DOCKER_RUN) bash -c "cd /go/$(APP_DIR); go get && go test"
	$(MAKE) chown

docker: binary 
	docker build -t $(APP_IMAGE) .

push: docker
	docker push $(APP_IMAGE)

chown:
	$(DOCKER_RUN) chown -R $(UID):$(GID) /go/bin /go/pkg /go/src 
	test -f $(APP_NAME) && $(DOCKER_RUN) chown -R $(UID):$(GID) /go/$(APP_NAME) || true

clean:
	$(MAKE) chown || true
	$(DOCKER_RUN) rm -rf /go/bin /go/pkg /go/src /go/$(APP_NAME)

.PHONY: all binary test chown clean
