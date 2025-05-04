#!/bin/bash

echo "🔧 Generating WhatToTest.md from latest commit..."

# Schreibe letzte Commit-Message in WhatToTest.md
echo "$(git log -1 --pretty=%B)" > WhatToTest.md
