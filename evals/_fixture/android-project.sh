#!/bin/bash
# Shared scaffold: a tiny Android-shaped git repository on a feature branch.
# Usage: android-project.sh [with-config|no-config]
set -eu
g() { git -c user.name=eval -c user.email=eval@example.invalid "$@"; }

mkdir -p app/src/main/kotlin/com/example/app
cat > settings.gradle.kts <<'KTS'
rootProject.name = "eval-app"
include(":app")
KTS
cat > app/src/main/kotlin/com/example/app/SettingsScreen.kt <<'KT'
package com.example.app

// The Settings screen: a title and a notifications switch.
fun settingsTitle() = "Settings"
KT
printf '#!/bin/bash\necho "BUILD SUCCESSFUL"\n' > gradlew
chmod +x gradlew
printf '.claude/android-workflow.json\n' > .gitignore

g init -q -b main
g add -A
g commit -q -m "chore: initial project"
g switch -q -c feature/eval

if [ "${1:-with-config}" = with-config ]; then
  mkdir -p .claude
  cat > .claude/android-workflow.json <<'JSON'
{
  "compileTask": ":app:compileDebugKotlin",
  "testTasks": [":app:testDebugUnitTest"],
  "runTarget": "app@debug"
}
JSON
fi
