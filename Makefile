# claude-code-usage-monitor-macos Makefile

# Variables
APP_NAME = Claude Code Usage Monitor
EXEC_NAME = claude-monitor-macos

BUILD = .build
BUILD_ARM64 = .build_arm64
BUILD_X86_64 = .build_x86_64

EXEC = $(BUILD)/$(EXEC_NAME)
EXEC_ARM64 = $(BUILD_ARM64)/release/$(EXEC_NAME)
EXEC_X86_64 = $(BUILD_X86_64)/release/$(EXEC_NAME)

OUTPUT_DIR = output
BUNDLE_DIR = $(OUTPUT_DIR)/$(APP_NAME).app

SOUCES = $(wildcard src/*.swift)

# Default target
.PHONY: all
all: build

# Build for ARM64 architecture
$(EXEC_ARM64): $(SOUCES)
	@swift build --arch arm64 --configuration release --build-path $(BUILD_ARM64)

# Build for x86_64 architecture
$(EXEC_X86_64): $(SOUCES)
	@swift build --arch x86_64 --configuration release --build-path $(BUILD_X86_64)

# Build universal binary
.PHONY: build
build: $(EXEC_ARM64) $(EXEC_X86_64)
	@mkdir -p $(BUILD)
	@lipo -create -output $(EXEC) \
		$(EXEC_ARM64) \
		$(EXEC_X86_64)
	@lipo -info $(EXEC)

# Create .app bundle
.PHONY: bundle
bundle: build
	@mkdir -p $(OUTPUT_DIR)
	@rm -rf "$(BUNDLE_DIR)"
	@mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	@cp .build/$(EXEC_NAME) "$(BUNDLE_DIR)/Contents/MacOS/"
	@cp Info.plist "$(BUNDLE_DIR)/Contents/"
	@# Ad-hoc sign for local testing (required for macOS security)
	@codesign --force --deep --sign - "$(BUNDLE_DIR)"
	@echo "$(BUNDLE_DIR)"

# Create distribution package
.PHONY: dist
dist: bundle
	@cd $(OUTPUT_DIR) && \
		ditto -c -k --sequesterRsrc --keepParent "$(APP_NAME).app" "$(APP_NAME).zip"
	@echo "$(OUTPUT_DIR)/$(APP_NAME).zip ($$(du -h "$(OUTPUT_DIR)/$(APP_NAME).zip" | cut -f1))"

# Sign with Developer ID
.PHONY: sign
sign: bundle
	@if [ -z "$(DEVELOPER_ID)" ]; then \
		echo "Error: DEVELOPER_ID not set"; \
		echo "Usage: make sign DEVELOPER_ID=\"Developer ID Application: Your Name (XXXXXXXXXX)\""; \
		exit 1; \
	fi
	@codesign --force --deep --sign "$(DEVELOPER_ID)" --options runtime "$(BUNDLE_DIR)"
	@codesign --verify --deep --strict "$(BUNDLE_DIR)"

# Notarize the signed app
.PHONY: notarize
notarize: sign
	@if [ -z "$(APPLE_ID)" ] || [ -z "$(TEAM_ID)" ]; then \
		echo "Error: Missing credentials"; \
		echo "Usage: make notarize APPLE_ID=your@email.com TEAM_ID=XXXXXXXXXX"; \
		exit 1; \
	fi
	@echo "Notarizing..."
	@ditto -c -k --sequesterRsrc --keepParent "$(BUNDLE_DIR)" $(OUTPUT_DIR)/.notarize-temp.zip
	@xcrun notarytool submit $(OUTPUT_DIR)/.notarize-temp.zip \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(TEAM_ID)" \
		--wait
	@rm $(OUTPUT_DIR)/.notarize-temp.zip
	@xcrun stapler staple "$(BUNDLE_DIR)"

# Create signed distribution package
.PHONY: dist-signed
dist-signed: notarize
	@ditto -c -k --sequesterRsrc --keepParent "$(BUNDLE_DIR)" "$(OUTPUT_DIR)/$(APP_NAME).zip"
	@echo "$(OUTPUT_DIR)/$(APP_NAME).zip"

# Clean build artifacts
.PHONY: clean
clean:
	@swift package clean
	@rm -rf $(BUILD)
	@rm -rf $(BUILD_ARM64)
	@rm -rf $(BUILD_X86_64)
	@rm -rf $(OUTPUT_DIR)

