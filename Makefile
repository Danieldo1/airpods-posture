.PHONY: build debug run install clean

BIN_DIR := $(shell swift build -c release --disable-sandbox --show-bin-path)

build:
	./build.sh release

debug:
	./build.sh debug

run: build
	open "$(BIN_DIR)/AirPosture.app"

install: build
	rm -rf /Applications/AirPosture.app
	cp -R "$(BIN_DIR)/AirPosture.app" /Applications/AirPosture.app
	open /Applications/AirPosture.app

clean:
	rm -rf .build
