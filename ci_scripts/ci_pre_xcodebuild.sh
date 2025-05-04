#!/bin/bash
set -e

echo "🔧 Generating TestFlight notes from last commit…"

# 1) Ordner anlegen, wenn noch nicht da
mkdir -p TestFlight

# 2) Letzte Commit-Message aus Git holen
git fetch --deepen 1
LAST_MSG=$(git log -1 --pretty=format:"%B")

# 3) In die richtige Datei schreiben – hier US-English
echo "$LAST_MSG" > TestFlight/WhatToTest.en-US.txt
