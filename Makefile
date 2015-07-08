THIS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
VETARGS?=-asmdecl -atomic -bool -buildtags -copylocks -methods \
         -nilfunc -printf -rangeloops -shift -structtags -unsafeptr

APP_NAME := consul
MODULE_SRC := src/github.com/hashicorp/consul
DOCKER_REGISTRY := registry.docker
DEFAULT_GOPATH = /tmp/gobuild-$(APP_NAME)-$(USER)
export GOPATH ?= $(DEFAULT_GOPATH)

BUILD_IMAGE := $(DOCKER_REGISTRY)/golang:1.3
UID := $(shell id -u)
GID := $(shell id -g)
USERNAME := $(shell getent passwd $(UID) | cut -d: -f1)
GROUPNAME := $(shell getent group $(GID) | cut -d: -f1)
define DOCKERFILE
FROM $(BUILD_IMAGE)  
RUN ( groupadd --gid $(GID) $(GROUPNAME) || true ) && \
    useradd --uid $(UID) --home-dir /home/$(USERNAME) $(USERNAME) -g $(GROUPNAME) && \
	mkdir -p "/go/$(MODULE_SRC)" "/home/$(USERNAME)" && \
	chown -R $(USERNAME):$(GROUPNAME) /go "/home/$(USERNAME)"
USER $(USERNAME):$(GROUPNAME)
WORKDIR /go/$(MODULE_SRC)
endef

DOCKER_MD5 := $(shell echo '$(DOCKERFILE)' | md5sum | cut -d' ' -f1)
DEV_IMAGE := gobuild-$(APP_NAME)-$(USER):$(DOCKER_MD5)
DOCKER_STAMP := $(DOCKER_MD5).stamp
BUILD_DEPS := $(DOCKER_STAMP) $(GOPATH)/$(MODULE_SRC)

export DOCKERFILE
BUILD := docker run -i --rm -v "$(GOPATH)":/go \
        -v "$(THIS_DIR)":"/go/$(MODULE_SRC)" $(DEV_IMAGE)

all: deps format | $(BUILD_DEPS)
	@mkdir -p bin/
	@$(BUILD) /bin/bash --norc -i ./scripts/build.sh

clean:
	rm -f *.stamp bin/$(APP_NAME) $(GOPATH)/$(MODULE_SRC)/*.stamp coverage.html
	rm -rf $(DEFAULT_GOPATH)

$(GOPATH)/$(MODULE_SRC):
	mkdir -p $@

$(DOCKER_STAMP): $(GOPATH)/$(MODULE_SRC)
	echo "$$DOCKERFILE" | docker build -t $(DEV_IMAGE) -
	touch $@

cov: | $(BUILD_DEPS)
	$(BUILD) gocov test ./... | gocov-html > coverage.html

deps: | $(BUILD_DEPS)
	@echo "--> Installing build dependencies"
	@$(BUILD) go get -d -v ./... $$($(BUILD) go list -f '{{range .TestImports}}{{.}} {{end}}' ./...)

updatedeps: deps | $(BUILD_DEPS)
	@echo "--> Updating build dependencies"
	@$(BUILD) go get -d -f -u ./... $$($(BUILD) go list -f '{{range .TestImports}}{{.}} {{end}}' ./...)

test: deps | $(BUILD_DEPS)
	@$(BUILD) ./scripts/verify_no_uuid.sh
	@$(BUILD) ./scripts/test.sh
	@$(MAKE) vet

integ: | $(BUILD_DEPS)
	$(BUILD) go list ./... | $(BUILD) INTEG_TESTS=yes xargs -n1 go test

cover: deps | $(BUILD_DEPS)
	$(BUILD) ./scripts/verify_no_uuid.sh
	$(BUILD) go list ./... | xargs -n1 go test --cover

format: deps | $(BUILD_DEPS)
	@echo "--> Running go fmt"
	@$(BUILD) go fmt $$($(BUILD) go list ./...)

vet: | $(BUILD_DEPS)
	@$(BUILD) go tool vet 2>/dev/null ; if [ $$? -eq 3 ]; then \
		$(BUILD) go get golang.org/x/tools/cmd/vet; \
	fi
	@echo "--> Running go tool vet $(VETARGS) ."
	@$(BUILD) go tool vet $(VETARGS) . ; if [ $$? -eq 1 ]; then \
		echo ""; \
		echo "Vet found suspicious constructs. Please check the reported constructs"; \
		echo "and fix them if necessary before submitting the code for reviewal."; \
	fi

web: | $(BUILD_DEPS)
	$(BUILD) ./scripts/website_run.sh

web-push: | $(BUILD_DEPS)
	$(BUILD) ./scripts/website_push.sh

.PHONY: all cov deps integ test vet web web-push test-nodep
