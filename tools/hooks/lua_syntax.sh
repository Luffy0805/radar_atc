#!/bin/sh
# Hook PostToolUse de Claude Code (déclaré dans .claude/settings.json).
# Après chaque Edit/Write d'un fichier .lua, le compile avec LuaJIT, sans l'exécuter.
# En cas d'erreur : code 2 + message sur stderr, renvoyé à Claude qui corrige aussitôt.
# Silencieux dans tous les autres cas (autre type de fichier, luajit absent).

file=$(python3 -c 'import json, sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))
except Exception:
    pass' 2>/dev/null)

case "$file" in
  *.lua) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0
command -v luajit >/dev/null 2>&1 || exit 0

dir=$(dirname "$file")
base=$(basename "$file")
if ! err=$(cd "$dir" && luajit -bl "$base" 2>&1 >/dev/null); then
  echo "Erreur de syntaxe Lua (LuaJIT) dans $file : ${err#luajit: }" >&2
  exit 2
fi
exit 0
