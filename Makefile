BINARY := whistle-hotkey
TARGET := whistle
LABEL := com.patrickyu17.whistle-hotkey
BUILD_DIR := build.noindex
APP := $(BUILD_DIR)/Whistle-Hotkey.app
RELEASE := .build/release/$(TARGET)
SOURCES := $(wildcard Sources/WhistleCore/*.swift) $(wildcard Sources/whistle/*.swift) Package.swift
PREFIX ?= /opt/homebrew
BINDIR := $(PREFIX)/bin
ALIASES := whk whistlehk whistle-hk

.PHONY: app run test install uninstall clean

app: $(APP)

$(APP): $(RELEASE) Resources/Info.plist LICENSE
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(RELEASE) $(APP)/Contents/MacOS/$(BINARY)
	strip -x $(APP)/Contents/MacOS/$(BINARY)
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp LICENSE $(APP)/Contents/Resources/LICENSE
	codesign --force --deep -s - $(APP)

$(RELEASE): $(SOURCES)
	swift build -c release --product whistle

run: app
	open $(APP)

test:
	swift build && swift run whistle-tests

install: $(RELEASE)
	install -d $(BINDIR)
	install -m 755 $(RELEASE) $(BINDIR)/$(BINARY)
	strip -x $(BINDIR)/$(BINARY)
	for alias in $(ALIASES); do \
		if [ -L $(BINDIR)/$$alias ] && [ "$$(readlink $(BINDIR)/$$alias)" = "$(BINARY)" ]; then \
			ln -sf $(BINARY) $(BINDIR)/$$alias; \
		elif [ -e $(BINDIR)/$$alias ] || [ -L $(BINDIR)/$$alias ]; then \
			echo "whistle: $(BINDIR)/$$alias already exists, not replacing"; \
		else \
			ln -s $(BINARY) $(BINDIR)/$$alias; \
		fi; \
	done

uninstall:
	-$(BINDIR)/$(BINARY) uninstall
	rm -f $(HOME)/Library/LaunchAgents/$(LABEL).plist
	for alias in $(ALIASES); do \
		if [ -L $(BINDIR)/$$alias ] && [ "$$(readlink $(BINDIR)/$$alias)" = "$(BINARY)" ]; then \
			rm -f $(BINDIR)/$$alias; \
		fi; \
	done
	rm -f $(BINDIR)/$(BINARY)

clean:
	rm -rf .build $(BUILD_DIR)
