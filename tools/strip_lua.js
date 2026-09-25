#!/usr/bin/env node
// Takes the comments and indentation out of a Lua file and keeps every line
// where it was. Used by build_release_manifest.js for dist/; run on its own
// as `node tools/strip_lua.js in.lua out.lua` (tests/host_dist_build_test.lua
// does, on the cases that would trip a naive stripper).
//
// It knows exactly enough Lua to be safe: quoted strings (with escapes,
// including a backslash before a newline), long strings and long comments
// at any level, and line comments. Whitespace between tokens shrinks to one
// space and never to none, so no two tokens run together; an inline long
// comment counts as whitespace for the same reason.

function stripLua(source, name) {
  let out = "";
  let i = 0;
  let lineStart = true;
  let pendingSpace = false;
  const n = source.length;
  const longBracket = (at) => {
    if (source[at] !== "[") return -1;
    let j = at + 1;
    let level = 0;
    while (source[j] === "=") { level += 1; j += 1; }
    return source[j] === "[" ? level : -1;
  };
  const emit = (text) => {
    if (pendingSpace && !lineStart) out += " ";
    pendingSpace = false;
    lineStart = false;
    out += text;
  };
  const closing = (at, level, what) => {
    const close = `]${"=".repeat(level)}]`;
    const end = source.indexOf(close, at);
    if (end < 0) throw new Error(`${name}: unterminated long ${what}`);
    return end + close.length;
  };
  while (i < n) {
    const c = source[i];
    if (c === "\n") {
      out += "\n";
      lineStart = true;
      pendingSpace = false;
      i += 1;
    } else if (c === " " || c === "\t" || c === "\r") {
      pendingSpace = true;
      i += 1;
    } else if (c === "-" && source[i + 1] === "-") {
      const level = longBracket(i + 2);
      if (level >= 0) {
        const end = closing(i + 4 + level, level, "comment");
        const newlines = (source.slice(i, end).match(/\n/g) || []).length;
        if (newlines > 0) {
          out += "\n".repeat(newlines);
          lineStart = true;
          pendingSpace = false;
        } else {
          pendingSpace = true;
        }
        i = end;
      } else {
        while (i < n && source[i] !== "\n") i += 1;
      }
    } else if (c === "\"" || c === "'") {
      let j = i + 1;
      while (j < n && source[j] !== c) {
        if (source[j] === "\\") j += 2;
        else if (source[j] === "\n") throw new Error(`${name}: broken string`);
        else j += 1;
      }
      emit(source.slice(i, j + 1));
      i = j + 1;
    } else if (longBracket(i) >= 0) {
      const level = longBracket(i);
      const end = closing(i + 2 + level, level, "string");
      emit(source.slice(i, end));
      i = end;
    } else {
      emit(c);
      i += 1;
    }
  }
  return out;
}

module.exports = { stripLua };

if (require.main === module) {
  const fs = require("fs");
  const [input, output] = process.argv.slice(2);
  fs.writeFileSync(output, stripLua(fs.readFileSync(input, "utf8"), input));
}
