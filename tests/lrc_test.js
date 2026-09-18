// LRC parser tests (includes a real excerpt of an LRCLIB response).
//   node tests/lrc_test.js
const fs = require("fs");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "..", "LrcParser.js"), "utf8")
  .replace(".pragma library", "");
const mod = {};
new Function("exports", src + "\nexports.parse = parse; exports.parsePlain = parsePlain; exports.indexAt = indexAt;")(mod);

const real = `[00:28.01] 報酬は入社後並行線で
[00:32.35] 東京は愛せど何も無い
[00:37.31] リッケン620頂戴
[01:09.35] 
[01:25.88] 最近は銀座で警官ごっこ`;

let failures = 0;
function check(name, cond, extra) {
  if (!cond) {
    failures++;
    console.log("FAIL:", name, extra ?? "");
  } else {
    console.log("ok:", name);
  }
}

// --- parsing real synced lyrics
const lines = mod.parse(real);
check("parse: line count", lines.length === 5, lines.length);
check("parse: first timestamp", Math.abs(lines[0].time - 28.01) < 0.001, lines[0].time);
check("parse: text preserved", lines[0].text === "報酬は入社後並行線で", JSON.stringify(lines[0].text));
check("parse: empty line (instrumental) kept", lines[3].time === 69.35 && lines[3].text === "", JSON.stringify(lines[3]));
check("parse: sorted", lines.every((l, i) => i === 0 || lines[i - 1].time <= l.time));

// --- multiple timestamps per line + offset + comma decimals
const multi = mod.parse("[offset:-500]\n[00:01.00][00:02,50] repeated\n[ar:Artist]\n[00:05] end");
check("parse: multiple tags", multi.length === 3, multi.length);
check("parse: offset applied", Math.abs(multi[0].time - 0.5) < 0.001, multi[0].time);
check("parse: comma separator", Math.abs(multi[1].time - 2.0) < 0.001, multi[1].time);
check("parse: metadata ignored", multi.every(l => !l.text.includes("Artist")));
check("parse: shared text", multi[0].text === "repeated" && multi[1].text === "repeated");

// --- indexAt (binary search)
const t = [10, 20, 30, 40].map(x => ({ time: x, text: "" }));
check("indexAt: before the first line", mod.indexAt(t, 5) === -1);
check("indexAt: exactly on a timestamp", mod.indexAt(t, 20) === 1);
check("indexAt: between lines", mod.indexAt(t, 39.9) === 2);
check("indexAt: after the last line", mod.indexAt(t, 999) === 3);
check("indexAt: empty list", mod.indexAt([], 10) === -1);

// --- parsePlain
const plain = mod.parsePlain("verse 1\n\nverse 2");
check("parsePlain: lines", plain.length === 3);
check("parsePlain: no timestamps", plain.every(l => l.time === -1));
check("parsePlain: empty line kept", plain[1].text === "");

console.log(failures === 0 ? "\nALL TESTS PASSED" : `\n${failures} TEST(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
