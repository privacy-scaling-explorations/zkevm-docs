#!/bin/sh

sed -r -i'' 's/ \\\\\\hline/ \\\\\\\\\\hline/g' $(find src -name "*.md")
