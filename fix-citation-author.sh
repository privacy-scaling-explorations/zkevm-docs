#!/bin/sh

# Helper script to fix citation from HackMD style to regular markdown style

sed -r -i'' 's/> \[name=([^]]*)\]/>\n> \*\*\1\*\*/g' $(find src -name "*.md")
