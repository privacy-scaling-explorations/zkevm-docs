#!/bin/sh

sed -r -i'' 's/> \[name=([^]]*)\]/>\n> \*\*\1\*\*/g' $(find src -name "*.md")
