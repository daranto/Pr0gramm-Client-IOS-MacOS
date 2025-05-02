#!/bin/bash

# Sicherstellen, dass wir im Projektverzeichnis sind
cd "$CI_WORKSPACE" || exit 1

# Letzte Commit-Message holen
commit_msg=$(git log -1 --pretty=%B)

# Datei schreiben
echo "$commit_msg" > what_to_test.txt

echo "✅ what_to_test.txt erstellt mit Inhalt:"
echo "$commit_msg"