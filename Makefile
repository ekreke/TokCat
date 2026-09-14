.PHONY: build release test run app dmg dump highlightcheck clean

build:
	swift build

release:
	swift build -c release

test:
	swift test

run:
	swift run TokCat

app:
	./Scripts/make-app.sh release

dmg:
	./Scripts/make-dmg.sh

dump:
	swift run TokCat dump

highlightcheck:
	swift run TokCat highlightcheck

clean:
	rm -rf .build build
