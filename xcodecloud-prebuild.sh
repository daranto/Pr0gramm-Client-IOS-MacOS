#!/bin/bash

# Hole letzte Commit-Nachricht und speichere sie in WhatToTest.md
echo "$(git log -1 --pretty=%B)" > WhatToTest.md
