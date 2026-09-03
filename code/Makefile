.PHONY: generate build open clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project IpaToolMac.xcodeproj -scheme IpaToolMac -configuration Debug -derivedDataPath build

open: generate
	open IpaToolMac.xcodeproj

clean:
	rm -rf build IpaToolMac.xcodeproj
