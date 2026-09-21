// Text sink guard: every Text in this plugin must declare textFormat.
//
// Lyrics, romanization and translation come from the network, and track
// metadata comes from whatever MPRIS player is running. QML's default is
// Text.AutoText, which renders such a string as rich text when it looks like
// HTML — including resource-bearing content such as <img src="http://...">,
// which the long-lived shell would then fetch. Every Text sink therefore has to
// say Text.PlainText explicitly.
//
//   node tests/qml_text_sinks.js
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const FILES = fs.readdirSync(ROOT).filter((name) => name.endsWith(".qml"));

let failures = 0;
function check(name, cond, extra) {
  if (!cond) {
    failures++;
    console.log("FAIL:", name, extra ?? "");
  } else {
    console.log("ok:", name);
  }
}

// Extracts the source of every `Text {` block: the opening line plus every
// following line until its braces balance.
function textBlocks(source) {
  const lines = source.split("\n");
  const blocks = [];
  for (let i = 0; i < lines.length; i++) {
    if (!/^\s*Text\s*\{\s*$/.test(lines[i]) && !/^\s*Text\s*\{.*\}\s*$/.test(lines[i])) continue;
    let depth = 0;
    const body = [];
    for (let j = i; j < lines.length; j++) {
      body.push(lines[j]);
      for (const ch of lines[j]) {
        if (ch === "{") depth++;
        else if (ch === "}") depth--;
      }
      if (depth === 0) break;
    }
    blocks.push({ line: i + 1, text: body.join("\n") });
  }
  return blocks;
}

let total = 0;
for (const file of FILES) {
  const source = fs.readFileSync(path.join(ROOT, file), "utf8");
  const blocks = textBlocks(source);
  total += blocks.length;
  const missing = blocks.filter((b) => !/textFormat\s*:\s*Text\.PlainText/.test(b.text));
  check(`${file}: every Text sink is plain text`, missing.length === 0,
    missing.map((b) => `${file}:${b.line}`).join(", "));
  const rich = blocks.filter((b) => /textFormat\s*:\s*Text\.(RichText|AutoText|MarkdownText)/.test(b.text));
  check(`${file}: no Text sink opts back into rich text`, rich.length === 0,
    rich.map((b) => `${file}:${b.line}`).join(", "));
}

check("found Text sinks to guard", total > 0, `scanned ${FILES.length} qml files, found ${total}`);

console.log(failures === 0 ? "\nALL TESTS PASSED" : `\n${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
