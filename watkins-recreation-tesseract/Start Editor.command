#!/bin/zsh
cd "${0:A:h}"
open "http://127.0.0.1:8774/Editor.html"
exec '/Users/akhilkonduru/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3' '.tesseract-work/editor_server.py'
