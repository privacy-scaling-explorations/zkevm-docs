#!/bin/sh

# Helper script to fix how MathJax LaTeX works in mdbook VS how it works in markdown.

sed -r -i'' 's/ \\\\\\hline/ \\\\\\\\\\hline/g' $(find src -name "*.md")
sed -r -i'' 's/\$([^ ]+)\$/\\\\(\1\\\\)/g' $(find src -name "*.md")
