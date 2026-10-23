APP := build/EyeRest.app

.PHONY: run demo app install clean

# Run from source (Launch at Login is unavailable outside the .app).
run:
	swift run EyeRest

# Try it out: a break every 15 seconds, lasting 5 seconds.
demo:
	swift run EyeRest -workSeconds 15 -breakSeconds 5

# Build build/EyeRest.app.
app:
	./scripts/build-app.sh

# Copy the app to /Applications and start it.
install: app
	-osascript -e 'quit app "EyeRest"'
	rm -rf /Applications/EyeRest.app
	cp -R $(APP) /Applications/
	open /Applications/EyeRest.app

clean:
	rm -rf .build build
