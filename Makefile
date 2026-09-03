# iPipe — generic iOS app template
# Pipeline: make build -> make install -> make launch
#
# Output layout under build/:
#   app/<arch>/$(APP_NAME).app         staged, UNSIGNED iPipe.app (+ DerivedData)
#   app/.commit_hash            git commit the staged app was built from
#
# ARCH=simulator builds for the iOS Simulator (no signing) and installs
# into the booted simulator via simctl; ARCH=device (default) keeps the
# devicectl pipeline. COOKIESFILE=<path> delivers cookies into the app's
# Documents/ after install (simctl data container on sims, house_arrest/AFC
# via pymobiledevice3 on devices).

APP_NAME := iPipe
XC_PROJECT := iPipe.xcodeproj

BUILDDIR := $(abspath build)
APPROOT := $(BUILDDIR)/app
DERIVED := $(APPROOT)/DerivedData

# Target: device (default) or simulator. Each arch stages its own app so
# switching ARCH never reuses the other's stale product.
ARCH ?= device
ifeq ($(ARCH),simulator)
  DESTINATION := generic/platform=iOS Simulator
  PRODUCT_SUBDIR := Release-iphonesimulator
  APP_PATH := $(APPROOT)/simulator/$(APP_NAME).app
else ifeq ($(ARCH),device)
  DESTINATION := generic/platform=iOS
  PRODUCT_SUBDIR := Release-iphoneos
  APP_PATH := $(APPROOT)/device/$(APP_NAME).app
else
  $(error unknown ARCH '$(ARCH)': use device or simulator)
endif

# Simulator to install/launch on (any simctl device spec; default: booted).
SIM ?= booted

# Target device for install/launch (devicectl accepts the paired device's
# name or UDID). Supply your phone's UDID via the UDID_IPHONE env var to
# target it directly; there is no hardcoded device id anywhere here.
#   make install UDID_IPHONE=<your-device-udid>
DEVICE ?= $(if $(UDID_IPHONE),$(UDID_IPHONE),iPhone)
# Single source of truth for the bundle id: passed to xcodebuild as a
# PRODUCT_BUNDLE_IDENTIFIER override, so build/install/launch always agree.
# (The value in iPipe.xcodeproj is only Xcode's fallback default.)
BUNDLE_ID ?= ax.lx.ipipe

# Apple Developer Team ID. Purely a build input: forwarded to xcodebuild as
# DEVELOPMENT_TEAM and TEAM_ID (the latter expands Info.plist's "$(TEAM_ID)"
# key, which the app reads at runtime for its keychain group). Nothing here
# signs or is signed — this repo only ever builds unsigned. Override per
# machine with:
#   make install TEAM_ID=<your-team-id>
TEAM_ID ?= A1111ABCDE

# Optional: copy this cookies file into the app's Documents directory right
# after install (as cookies.txt). The app ingests it on next startup, stores
# it in the keychain, and deletes the file. Leave empty to skip delivery.
#   make install COOKIESFILE=cookies.txt
COOKIESFILE ?=

# Python interpreter that has pymobiledevice3 (used to push cookies to real
# devices over the house_arrest/AFC service).
PMD_PYTHON ?= $(shell for p in $(HOME)/.venv/bin/python $(HOME)/.venv/bin/python3 python3; do "$$p" -c 'import pymobiledevice3' >/dev/null 2>&1 && { echo "$$p"; break; }; done)

.PHONY: help build install launch clean

help:
	@echo "Targets:"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed -e 's/^## /  /'

## build    — build Release/unsigned into build/app/<ARCH>/ (git-commit driven)
## install  — device: build + devicectl install on $(DEVICE)
##            simulator: build + simctl install on $(SIM)
##            COOKIESFILE=<path> additionally copies the file into the app's
##            Documents/ (as cookies.txt) on the installed target; the app
##            ingests it at startup and deletes it
## launch   — launch on $(DEVICE) / $(SIM)
## clean    — remove build/

# Build only when the working tree differs from HEAD (or no staged app
# exists yet, or BUNDLE_ID changed since the last build); then commit that
# exact source state and record its hash + bundle id in build/app/.
# Clean tree = fast reuse of the previous build.
# set -e guards every step: a failed toolchain must abort BEFORE
# xcodebuild/staging/git commit, otherwise a broken tree gets committed and
# future builds silently reuse it.
build:
	@set -e; \
	stored_bid="$$(cat "$(APPROOT)/.bundle_id" 2>/dev/null || true)"; \
	if [ -n "$$(git status --porcelain)" ] || [ ! -d "$(APP_PATH)" ] || [ "$$stored_bid" != "$(BUNDLE_ID)" ]; then \
		mkdir -p "$$(dirname "$(APP_PATH)")"; \
		echo "=== Building $(APP_NAME) (Release, unsigned, $(BUNDLE_ID)) ==="; \
		xcodebuild -project $(XC_PROJECT) -scheme $(APP_NAME) \
			-configuration Release -derivedDataPath $(DERIVED) \
			-destination "$(DESTINATION)" \
			CODE_SIGNING_ALLOWED=NO \
			DEVELOPMENT_TEAM=$(TEAM_ID) \
			TEAM_ID=$(TEAM_ID) \
			PRODUCT_BUNDLE_IDENTIFIER=$(BUNDLE_ID) build > $(BUILDDIR)/xcodebuild.log 2>&1 || { \
			echo "ERROR: xcodebuild failed. Last 20 lines:"; tail -20 $(BUILDDIR)/xcodebuild.log; exit 1; }; \
		echo "xcodebuild OK ($(BUILDDIR)/xcodebuild.log)"; \
		rm -rf "$(APP_PATH)"; \
		cp -R "$(DERIVED)/Build/Products/$(PRODUCT_SUBDIR)/$(APP_NAME).app" "$(APP_PATH)"; \
		echo "$(BUNDLE_ID)" > "$(APPROOT)/.bundle_id"; \
		git add -A; \
		git diff --cached --quiet || git commit -q -m "build $$(date '+%Y-%m-%d %H:%M:%S')"; \
	else \
		echo "=== Tree clean; reusing $(APP_PATH) ==="; \
	fi
	@git rev-parse --short=12 HEAD > "$(APPROOT)/.commit_hash"
	@echo "=== Commit: $$(cat "$(APPROOT)/.commit_hash") ==="

ifneq ($(ARCH),simulator)
install: build
	@echo "=== Installing $(APP_PATH) on $(DEVICE) ==="
	xcrun devicectl device install app "$(APP_PATH)" --device "$(DEVICE)"
ifneq ($(strip $(COOKIESFILE)),)
	@set -e; \
	case "$(DEVICE)" in \
	  *[!0-9A-Fa-f-]*) udid=$$(xcrun devicectl list devices 2>/dev/null | awk -v n="$(DEVICE)" 'NR>2 && index($$0,n)==1 && /available/ {print $$3; exit}');; \
	  *) udid="$(DEVICE)";; \
	esac; \
	[ -n "$$udid" ] || { echo "ERROR: device '$(DEVICE)' not found/available"; exit 1; }; \
	echo "=== Delivering cookies -> $(DEVICE) ($$udid) Documents/cookies.txt ==="; \
	$(PMD_PYTHON) $(CURDIR)/tools/push_cookies.py \
		--udid "$$udid" --bundle-id "$(BUNDLE_ID)" --local "$(COOKIESFILE)"
endif

launch:
	@echo "=== Launching $(BUNDLE_ID) on $(DEVICE) ==="
	xcrun devicectl device process launch --terminate-existing \
		--device "$(DEVICE)" "$(BUNDLE_ID)"
else
install: build
	@echo "=== Installing $(APP_PATH) on simulator $(SIM) ==="
	xcrun simctl install "$(SIM)" "$(APP_PATH)"
ifneq ($(strip $(COOKIESFILE)),)
	@set -e; \
	container=$$(xcrun simctl get_app_container "$(SIM)" "$(BUNDLE_ID)" data); \
	mkdir -p "$$container/Documents"; \
	echo "=== Delivering cookies -> simulator $(SIM) Documents/cookies.txt ==="; \
	cp "$(COOKIESFILE)" "$$container/Documents/cookies.txt"
endif

launch:
	@echo "=== Launching $(BUNDLE_ID) on simulator $(SIM) ==="
	xcrun simctl launch --terminate-running-process "$(SIM)" "$(BUNDLE_ID)"
endif

clean:
	rm -rf $(BUILDDIR)