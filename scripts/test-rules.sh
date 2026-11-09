#!/bin/zsh
# Runs the on-device rules against the agreed test set. Usage: ./scripts/test-rules.sh
set -e
cd "$(dirname "$0")/.."
out=$(mktemp -d)
swiftc -o "$out/rules" Stead/Engine/TextCleaner.swift Stead/Engine/RulesEngine.swift scripts/rules-test/main.swift
"$out/rules"
