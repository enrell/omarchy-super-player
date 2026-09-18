.pragma library

// Parser for LRC synced lyrics (the format LRCLIB returns).
// Accepted input:
//   [mm:ss.xx] line              (also [mm:ss], [mm:ss.x], [mm:ss.xxx], comma separator)
//   [mm:ss.xx][mm:ss.yy] line    (several timestamps on one line)
//   [ar:...] [ti:...] [offset:±ms] (metadata; offset shifts every timestamp)

const TIME_TAG = /\[(\d{1,3}):(\d{1,2}(?:[.,]\d{1,3})?)\]/g;
const META_TAG = /^\[(ar|ti|al|by|re|ve|length|offset):(.*)\]$/i;

// Converts LRC text into an ordered list of { time: seconds, text: string }.
function parse(text) {
  const lines = [];
  let offset = 0;

  const rawLines = String(text).split(/\r?\n/);
  for (let i = 0; i < rawLines.length; i++) {
    const line = rawLines[i].trim();
    if (line === "") continue;

    const meta = line.match(META_TAG);
    if (meta) {
      if (meta[1].toLowerCase() === "offset") offset = (parseInt(meta[2], 10) || 0) / 1000;
      continue;
    }

    TIME_TAG.lastIndex = 0;
    const times = [];
    let m;
    while ((m = TIME_TAG.exec(line)) !== null) {
      const minutes = parseInt(m[1], 10);
      const seconds = parseFloat(String(m[2]).replace(",", "."));
      times.push(minutes * 60 + seconds);
    }
    if (times.length === 0) continue;

    TIME_TAG.lastIndex = 0;
    const content = line.replace(TIME_TAG, "").trim();

    for (let j = 0; j < times.length; j++) lines.push({ time: Math.max(0, times[j] + offset), text: content });
  }

  lines.sort((a, b) => a.time - b.time);
  return lines;
}

// Unsynced lyrics: one line per verse, no timestamps.
function parsePlain(text) {
  const out = [];
  const rawLines = String(text).split(/\r?\n/);
  for (let i = 0; i < rawLines.length; i++) out.push({ time: -1, text: rawLines[i].trim() });
  return out;
}

// Index of the last line with time <= t, or -1 when t is before the first line.
// Binary search — the service calls this ~10x per second.
function indexAt(lines, t) {
  let lo = 0;
  let hi = lines.length - 1;
  let found = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (lines[mid].time <= t) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return found;
}
