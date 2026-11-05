APP := build/EyeRest.app
# Where runs from source keep their activity log, so their screen time and
# breaks don't add to the installed app's.
DEV_DATA := $(CURDIR)/build/dev-data

.PHONY: run demo test app install clean

# Run from source (Launch at Login is unavailable outside the .app).
run:
	EYEREST_DATA_DIR="$(DEV_DATA)" swift run EyeRest

# Try it out: a break every 15 seconds, lasting 5 seconds.
demo:
	EYEREST_DATA_DIR="$(DEV_DATA)" swift run EyeRest -workSeconds 15 -breakSeconds 5

# Run the unit tests.
test:
	swift test

# Build build/EyeRest.app.
app:
	./scripts/build-app.sh

# Copy the app to /Applications and start it, once the running copy has quit
# (open fails while it's still quitting).
install: app
	-osascript -e 'quit app "EyeRest"'
	for i in $$(seq 50); do pgrep -qf '^/Applications/EyeRest.app/Contents/MacOS/EyeRest' || break; sleep 0.1; done
	rm -rf /Applications/EyeRest.app
	cp -R $(APP) /Applications/
	open /Applications/EyeRest.app

clean:
	rm -rf .build build
