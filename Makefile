.PHONY: build debug run install clean test native-checks bust-render-check bust-lifecycle-check sound-probe ui-fixture

TEMP_ROOT ?= $(if $(TMPDIR),$(TMPDIR),/tmp/)airposture-make
SWIFT_FLAGS = --disable-sandbox \
	--cache-path "$(TEMP_ROOT)/cache" \
	--config-path "$(TEMP_ROOT)/config" \
	--security-path "$(TEMP_ROOT)/security"
CLANG_CACHE = $(TEMP_ROOT)/clang-module-cache
BIN_DIR = $(shell CLANG_MODULE_CACHE_PATH="$(CLANG_CACHE)" swift build -c release $(SWIFT_FLAGS) --show-bin-path)

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

test:
	mkdir -p "$(CLANG_CACHE)"
	CLANG_MODULE_CACHE_PATH="$(CLANG_CACHE)" swift run $(SWIFT_FLAGS) AirPostureFeatureCheck
	CLANG_MODULE_CACHE_PATH="$(CLANG_CACHE)" swift run $(SWIFT_FLAGS) AirPostureMappingCheck
	CLANG_MODULE_CACHE_PATH="$(CLANG_CACHE)" swift run $(SWIFT_FLAGS) AirPostureBustCheck
	Tests/run-native-checks.sh

bust-render-check:
	Tests/run-bust-render-checks.sh

bust-lifecycle-check:
	Tests/run-bust-lifecycle-checks.sh

native-checks:
	Tests/run-native-checks.sh

# Opt-in: this exercises the real system audio output and plays every sound.
sound-probe:
	Tests/run-native-checks.sh sound-probe

ui-fixture:
	Tests/AirPostureUIFixture/build.sh

clean:
	rm -rf .build
