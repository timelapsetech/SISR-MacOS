.PHONY: project test run release clean

project:
	python3 scripts/generate_xcodeproj.py

test:
	cd Packages/SISRKit && swift test

# Build the native SwiftUI app and launch it (no Xcode GUI required).
run: project
	@chmod +x scripts/run-app.sh
	@./scripts/run-app.sh

release:
	chmod +x scripts/release/macos-swift-build-sign-notarize.sh
	./scripts/release/macos-swift-build-sign-notarize.sh

clean:
	rm -rf .derivedData build dist Packages/SISRKit/.build
