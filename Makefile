SWIFT ?= swift
BINARY := ./.build/release/MicCheck

.PHONY: build release test run detailed debug clean

build:
	$(SWIFT) build

release:
	$(SWIFT) build -c release

test:
	$(SWIFT) test

run:
	$(BINARY)

detailed:
	$(BINARY) --detailed

debug:
	$(BINARY) --detailed --debug

clean:
	$(SWIFT) package clean

