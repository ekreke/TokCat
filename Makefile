.PHONY: build release test run app dump clean

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

dump:
	swift run TokCat dump

clean:
	rm -rf .build build
