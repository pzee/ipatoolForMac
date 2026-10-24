.PHONY: generate build test open clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project IpaToolMac.xcodeproj -scheme IpaToolMac -configuration Debug -derivedDataPath build

test: generate
	xcodebuild -project IpaToolMac.xcodeproj -scheme IpaToolMac -configuration Debug -derivedDataPath build test

open: generate
	open IpaToolMac.xcodeproj

clean:
	rm -rf build IpaToolMac.xcodeproj
