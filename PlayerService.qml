import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "LrcParser.js" as Lrc

// Lyrics service: follows an MPRIS player (Spotify preferred) and fetches the
// synced lyrics from LRCLIB (https://lrclib.net — free, no API key needed).
//
// Public API:
//   player        MprisPlayer in use (null when nothing is playing)
//   lines         [{ time, text }] — time in seconds (-1 = unsynced lyrics)
//   currentIndex  index of the active line (-1 before the first line / unsynced)
//   clock         current position in seconds (interpolated between MPRIS updates)
//   progress      0..1 through the track
//   status        "noplayer" | "loading" | "synced" | "plain" | "notfound" | "error"
//   load()        (re)load the lyrics of the current track
//   seekTo(t)     jump to time t when the player allows it
QtObject {
  id: root

  // ------------------------------------------------------------------ player
  // Follows any MPRIS player: the configured source when set, otherwise
  // whichever player is playing, otherwise the first one available.
  property string source: "Auto"

  readonly property var players: Mpris.players.values

  readonly property var player: {
    const all = Mpris.players.values
    if (all.length === 0) return null

    const wanted = root.source
    if (wanted !== "" && wanted !== "Auto") {
      for (let i = 0; i < all.length; i++) {
        const p = all[i]
        if (p.dbusName === wanted || p.identity === wanted || p.desktopEntry === wanted) return p
      }
    }

    for (let i = 0; i < all.length; i++) if (all[i].isPlaying) return all[i]
    return all[0]
  }

  // Changes whenever the track changes.
  readonly property string trackKey: {
    const p = root.player
    if (!p || p.trackTitle === "") return ""
    return p.trackTitle + "\u241f" + p.trackArtist + "\u241f" + p.trackAlbum + "\u241f" + Math.round(p.length)
  }

  readonly property string trackTitle: root.player ? root.player.trackTitle : ""
  readonly property string trackArtist: root.player ? root.player.trackArtist : ""
  readonly property string trackArtUrl: root.player ? root.player.trackArtUrl : ""
  readonly property real length: root.player ? root.player.length : 0

  // ----------------------------------------------------------- media control
  // Thin wrappers so the bar, the popup and the IPC handlers share one path.
  readonly property real volume: root.player ? root.player.volume : 0
  readonly property bool volumeSupported: root.player !== null && root.player.volumeSupported
  readonly property bool canGoNext: root.player !== null && root.player.canGoNext
  readonly property bool canGoPrevious: root.player !== null && root.player.canGoPrevious
  readonly property bool canSeek: root.player !== null && root.player.canSeek
  readonly property bool canTogglePlaying: root.player !== null && root.player.canTogglePlaying
  readonly property bool playing: root.player !== null && root.player.isPlaying
  property real lastVolume: 0.5

  function setVolume(value) {
    const p = root.player
    if (!p || !p.volumeSupported) return
    const clamped = Math.max(0, Math.min(1, value))
    p.volume = clamped
    if (clamped > 0.001) root.lastVolume = clamped
  }

  // MPRIS has no mute, so remember the last audible volume instead.
  function toggleMute() {
    if (root.volume > 0.001) {
      root.lastVolume = root.volume
      root.setVolume(0)
    } else {
      root.setVolume(root.lastVolume > 0.001 ? root.lastVolume : 0.5)
    }
  }

  function volumeBy(delta) { root.setVolume(root.volume + delta) }

  function togglePlaying() {
    const p = root.player
    if (p && p.canTogglePlaying) p.togglePlaying()
  }

  function next() {
    const p = root.player
    if (p && p.canGoNext) p.next()
  }

  function previous() {
    const p = root.player
    if (p && p.canGoPrevious) p.previous()
  }

  // ------------------------------------------------------------------- state
  property var lines: []
  property int currentIndex: -1
  property real clock: 0
  property string status: "noplayer"
  readonly property real progress: root.length > 0 ? Math.min(1, root.clock / root.length) : 0
  readonly property string currentLine: root.status === "synced" && root.currentIndex >= 0 ? root.lines[root.currentIndex].text : ""

  property var cache: ({})   // trackKey -> { synced: [...], plain: "..." }
  property int requestId: 0  // drops replies that belong to a previous track
  property int attempts: 0   // network retries for the current track

  // The shell outlives thousands of tracks, so both caches keep the newest
  // entries only.
  readonly property int maxCachedTracks: 20

  function trimCache(cache) {
    const keys = Object.keys(cache)
    while (keys.length > root.maxCachedTracks) delete cache[keys.shift()]
  }

  // ------------------------------------------------------------------- clock
  // MPRIS only refreshes the position every ~0.5 s; a local clock interpolates
  // in between so the highlighted line does not jump around.
  readonly property real mprisPosition: root.player ? root.player.position : 0

  onMprisPositionChanged: root.anchorClock()
  // The initial value of a binding fires no change handler, so anchor when the
  // player shows up too (e.g. a shell restart with the track paused).
  onPlayerChanged: root.anchorClock()

  function anchorClock() {
    // Resync only on a big jump (seek, track loop, restart). Small differences
    // are noise and would make the highlight flicker at line boundaries.
    if (Math.abs(root.mprisPosition - root.clock) <= 1.5) return
    root.clock = root.mprisPosition
    // The tick timer only runs while playing, so paused tracks would otherwise
    // keep the highlight where it was.
    root.updateIndex()
  }

  property Timer clockTimer: Timer {
    interval: 100
    repeat: true
    running: root.player !== null && root.player.isPlaying
    onTriggered: {
      root.clock += interval / 1000
      root.updateIndex()
    }
  }

  // ---------------------------------------------------------------- romanize
  // Set by the host from the widget settings: "Off" | "Replace" | "Below".
  // "Replace" shows only the romanized line, "Below" shows it under the
  // original one.
  property string romanize: "Off"
  property bool romanizedApplied: false
  property string romanizeTool: "" // detected once: "kakasi" | "uconv" | "none"

  readonly property string currentRomanizedLine: {
    const line = root.currentIndex >= 0 ? root.lines[root.currentIndex] : null
    return line && line.romanized ? line.romanized : ""
  }

  onRomanizeChanged: root.scheduleRomanize()
  onLinesChanged: {
    root.scheduleRomanize()
    root.scheduleTranslate()
  }

  property Process romanizeProcess: Process {
    id: romanizeProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyRomanized(text)
    }
  }

  // Detects which transliterator is available (only used for the settings hint).
  property Process toolProcess: Process {
    running: true
    command: ["bash", "-c", "python3 \"" + root.romanizeHelper + "\" --tool 2>/dev/null || echo none"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.romanizeTool = String(text).trim()
    }
  }

  function scheduleRomanize() {
    if (root.romanize === "Off") {
      if (root.romanizedApplied) root.clearRomanized()
      return
    }
    if (root.lines.length === 0 || root.romanizedApplied || romanizeProcess.running) return
    romanizeProcess.command = ["bash", "-c", root.romanizeScript(), "super-player", root.lyricsText()]
    romanizeProcess.running = true
  }

  function lyricsText() {
    const parts = []
    for (let i = 0; i < root.lines.length; i++) parts.push(root.lines[i].text)
    return parts.join("\n")
  }

  // Path of the helper script shipped next to this file.
  readonly property string romanizeHelper: String(Qt.resolvedUrl("romanize.py")).replace("file://", "")

  // The lyrics arrive as $1 (an argv entry, so no shell quoting issues).
  // romanize.py picks pykakasi > kakasi > ICU; if Python is unavailable, fall
  // back to plain ICU transliteration.
  function romanizeScript() {
    return "printf '%s' \"$1\" | python3 \"" + root.romanizeHelper + "\" 2>/dev/null "
      + "|| printf '%s' \"$1\" | uconv -x 'Any-Latin' 2>/dev/null "
      + "|| printf '%s' \"$1\""
  }

  function applyRomanized(text) {
    if (root.romanize === "Off" || root.lines.length === 0) return
    const out = String(text || "").split("\n")
    const next = []
    for (let i = 0; i < root.lines.length; i++) {
      const line = root.lines[i]
      const romanized = out[i] !== undefined ? out[i].trim() : ""
      next.push({ time: line.time, text: line.text, romanized: romanized, translated: line.translated })
    }
    root.romanizedApplied = true
    root.lines = next
  }

  function clearRomanized() {
    const next = []
    for (let i = 0; i < root.lines.length; i++) {
      const line = root.lines[i]
      next.push({ time: line.time, text: line.text, translated: line.translated })
    }
    root.romanizedApplied = false
    root.lines = next
  }

  // -------------------------------------------------------------- translate
  // Target language code ("pt-BR", "en", ...) or "Off". Set by the host.
  property string translate: "Off"
  property bool translatedApplied: false
  property string translateStatus: "" // "" | "loading" | "ok" | "error"
  property var translationCache: ({})
  property int translateRequestId: 0

  readonly property string currentTranslatedLine: {
    const line = root.currentIndex >= 0 ? root.lines[root.currentIndex] : null
    return line && line.translated ? line.translated : ""
  }

  onTranslateChanged: root.scheduleTranslate()

  function scheduleTranslate() {
    if (root.translate === "Off" || root.translate === "") {
      if (root.translatedApplied) root.clearTranslated()
      return
    }
    if (root.lines.length === 0 || root.translatedApplied) return

    const key = root.trackKey + "|" + root.translate
    if (root.translationCache[key] !== undefined) {
      root.translateStatus = "ok"
      root.applyTranslated(root.translationCache[key])
      return
    }
    root.requestTranslation(key)
  }

  // One request per track: Google keeps the line breaks of a multi line query.
  function requestTranslation(key) {
    const rid = ++root.translateRequestId
    root.translateStatus = "loading"
    const url = "https://clients5.google.com/translate_a/t?client=dict-chrome-ex"
      + "&sl=auto&tl=" + encodeURIComponent(root.translate)
      + "&q=" + encodeURIComponent(root.lyricsText())

    // Same bounded request path as the lyrics lookup: a stalled or oversized
    // reply fails closed instead of hanging the shell or growing the cache.
    root.get(url, function (status, body) {
      if (rid !== root.translateRequestId) return // stale reply
      const translated = status === 200 ? root.parseTranslation(body) : ""
      if (translated === "") {
        root.translateStatus = "error"
        return
      }
      root.translationCache[key] = translated
      root.trimCache(root.translationCache)
      root.translateStatus = "ok"
      root.applyTranslated(translated)
    })
  }

  // Response shape: [["translated text", "source language"], ...] — one entry
  // per query, or a single entry whose text keeps the original line breaks.
  function parseTranslation(body) {
    try {
      const data = JSON.parse(body)
      if (!Array.isArray(data)) return ""
      const parts = []
      for (let i = 0; i < data.length; i++) {
        const entry = data[i]
        if (Array.isArray(entry) && typeof entry[0] === "string") parts.push(entry[0])
      }
      return parts.join("\n")
    } catch (e) {
      console.log("super-player: invalid translation response:", e)
      return ""
    }
  }

  function applyTranslated(text) {
    if (root.translate === "Off" || root.lines.length === 0) return
    const out = String(text || "").split("\n")
    const next = []
    for (let i = 0; i < root.lines.length; i++) {
      const line = root.lines[i]
      next.push({
        time: line.time,
        text: line.text,
        romanized: line.romanized,
        translated: out[i] !== undefined ? out[i].trim() : ""
      })
    }
    root.translatedApplied = true
    root.lines = next
  }

  function clearTranslated() {
    const next = []
    for (let i = 0; i < root.lines.length; i++) {
      const line = root.lines[i]
      next.push({ time: line.time, text: line.text, romanized: line.romanized })
    }
    root.translatedApplied = false
    root.lines = next
  }

  // ---------------------------------------------------------------- fetching
  onTrackKeyChanged: {
    // A brand new track starts at 0, but a player that only just appeared (or a
    // track that was already playing) has a real position, so take it from MPRIS.
    root.clock = root.mprisPosition > 0 ? root.mprisPosition : 0
    root.currentIndex = -1
    root.requestId++
    root.attempts = 0
    root.romanizedApplied = false
    root.translatedApplied = false

    if (root.trackKey === "") {
      root.lines = []
      root.status = root.player ? "notfound" : "noplayer"
      return
    }

    root.lines = []
    root.status = "loading"
    debounce.restart() // let Spotify finish publishing the new metadata
  }

  property Timer debounce: Timer {
    interval: 250
    onTriggered: root.load()
  }

  // Automatic retry on network failures (LRCLIB occasionally drops a HTTP/2
  // connection for no apparent reason).
  property Timer retryTimer: Timer {
    interval: 1500
    onTriggered: root.load()
  }

  function load() {
    const p = root.player
    if (!p || root.trackKey === "") {
      root.status = p ? "notfound" : "noplayer"
      return
    }

    const cached = root.cache[root.trackKey]
    if (cached) {
      root.applyLyrics(cached.synced, cached.plain)
      return
    }

    const rid = ++root.requestId
    root.status = "loading"

    // Players like mpv report no artist, and LRCLIB's exact lookup requires
    // one, so go straight to the free text search in that case.
    if (p.trackArtist.trim() === "") {
      root.searchFreeText(rid)
      return
    }

    // First attempt: exact match (artist + track + album + duration).
    const url = "https://lrclib.net/api/get"
      + "?artist_name=" + encodeURIComponent(p.trackArtist)
      + "&track_name=" + encodeURIComponent(p.trackTitle)
      + "&album_name=" + encodeURIComponent(p.trackAlbum)
      + "&duration=" + Math.round(p.length)

    root.get(url, function (status, body) {
      if (rid !== root.requestId) return // stale reply
      if (status === 200) {
        root.applyFromApi(root.parseJson(body))
      } else if (status === 0) {
        if (root.attempts < 2) {
          root.attempts++
          root.retryTimer.restart()
        } else {
          root.status = "error"
        }
      } else {
        root.search(rid) // 404 or a validation error: try the search endpoints
      }
    })
  }

  function search(rid) {
    const p = root.player
    if (!p) {
      root.status = "notfound"
      return
    }

    // LRCLIB rejects an empty artist (players like mpv often report none), so
    // go straight to the free text search in that case.
    if (p.trackArtist.trim() === "") {
      root.searchFreeText(rid)
      return
    }

    const url = "https://lrclib.net/api/search"
      + "?track_name=" + encodeURIComponent(p.trackTitle)
      + "&artist_name=" + encodeURIComponent(p.trackArtist)

    root.get(url, function (status, body) {
      if (rid !== root.requestId) return
      if (status !== 200) {
        root.searchFreeText(rid)
        return
      }

      const results = root.parseJson(body)
      const best = root.pickBest(Array.isArray(results) ? results : [])
      if (best) root.applyFromApi(best)
      else root.searchFreeText(rid) // last resort: free text search
    })
  }

  function searchFreeText(rid) {
    const p = root.player
    if (!p) {
      root.status = "notfound"
      return
    }

    const url = "https://lrclib.net/api/search?q="
      + encodeURIComponent(p.trackTitle + " " + p.trackArtist)

    root.get(url, function (status, body) {
      if (rid !== root.requestId) return
      if (status === 0 && root.attempts < 2) {
        root.attempts++
        root.retryTimer.restart()
        return
      }
      if (status !== 200) {
        root.status = "notfound"
        return
      }

      const results = root.parseJson(body)
      const best = root.pickBest(Array.isArray(results) ? results : [])
      if (best) root.applyFromApi(best)
      else root.status = "notfound"
    })
  }

  // Picks the best search candidate: synced lyrics first, then a duration close
  // to the playing track. A large duration gap usually means a different
  // version (live, remix) whose timings would not match the audio.
  function pickBest(results) {
    const target = root.length
    let bestSynced = null
    let bestSyncedDelta = Infinity
    let bestPlain = null
    let bestPlainDelta = Infinity

    for (let i = 0; i < results.length; i++) {
      const r = results[i]
      const delta = Math.abs((r.duration || 0) - target)

      if (r.syncedLyrics) {
        if (delta < bestSyncedDelta) {
          bestSyncedDelta = delta
          bestSynced = r
        }
      } else if (r.plainLyrics) {
        if (delta < bestPlainDelta) {
          bestPlainDelta = delta
          bestPlain = r
        }
      }
    }

    if (bestSynced && (target <= 0 || bestSyncedDelta <= 25)) return bestSynced
    if (bestPlain && (target <= 0 || bestPlainDelta <= 10)) return bestPlain
    return null
  }

  function parseJson(body) {
    try {
      return JSON.parse(body)
    } catch (e) {
      console.log("super-player: invalid JSON:", e)
      return null
    }
  }

  // ----------------------------------------------------------- remote limits
  // Every reply is bounded: a connection that stalls must not hang the fetch,
  // and an oversized body must never be parsed or cached. Real LRCLIB replies
  // measure ~6 KiB for an exact lookup and ~150 KiB for a 20-result search, so
  // 512 KiB is far above any legitimate payload and far below a memory hazard.
  readonly property int requestTimeoutMs: 8000
  readonly property int maxResponseBytes: 524288

  // One deadline per in-flight request. Qt's own XMLHttpRequest.timeout does not
  // fire when the server never answers, so the deadline is a real timer.
  property Component requestDeadline: Component {
    Timer {
      property var expire
      repeat: false
      onTriggered: if (expire) expire()
    }
  }

  // GET with a hard deadline and a response size cap. Every failure — timeout,
  // network error, refused or oversized reply — reaches the callback as status 0
  // with an empty body, so the callers keep their existing network-failure paths.
  function get(url, callback) {
    const xhr = new XMLHttpRequest()
    xhr.open("GET", url)
    // LRCLIB asks for a User-Agent identifying the client.
    xhr.setRequestHeader("User-Agent", "omarchy-super-player/1.0.0")

    let settled = false
    let deadline = root.requestDeadline.createObject(root, {
      interval: root.requestTimeoutMs,
      running: true,
      expire: function () { finish(0, "", "timeout") }
    })

    function finish(status, body, reason) {
      if (settled) return
      settled = true
      if (deadline) {
        deadline.stop()
        deadline.destroy()
        deadline = null
      }
      if (reason === undefined) {
        callback(status, body)
        return
      }
      console.log("super-player: dropped a " + reason + " reply from " + url)
      // Aborting from inside the readyState handler makes Qt's XMLHttpRequest
      // crash while it is still reading the reply, so the transfer is cancelled
      // on the next event loop turn instead. The reply is already refused.
      Qt.callLater(function () { xhr.abort() })
      callback(0, "")
    }

    xhr.onreadystatechange = function () {
      if (settled) return

      // A reply that declares an oversize body is refused before any of it is read.
      if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
        const declared = Number(xhr.getResponseHeader("Content-Length"))
        if (declared > root.maxResponseBytes) {
          finish(0, "", "oversized")
          return
        }
      }

      // A body of unknown length (chunked) is cut off as soon as it overflows.
      if (xhr.readyState === XMLHttpRequest.LOADING
          && (xhr.responseText || "").length > root.maxResponseBytes) {
        finish(0, "", "oversized")
        return
      }

      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (xhr.status !== 200) {
        finish(xhr.status, "")
        return
      }
      const body = xhr.responseText || ""
      if (body.length > root.maxResponseBytes) {
        finish(0, "", "oversized")
        return
      }
      finish(200, body)
    }

    xhr.onerror = function () { finish(0, "", "failed") }
    xhr.send()
  }

  function applyFromApi(data) {
    if (!data) {
      root.status = "error"
      return
    }
    root.attempts = 0
    const synced = data.syncedLyrics ? Lrc.parse(data.syncedLyrics) : []
    const plain = data.plainLyrics || ""
    root.cache[root.trackKey] = { synced: synced, plain: plain }
    root.trimCache(root.cache)
    root.applyLyrics(synced, plain)
  }

  function applyLyrics(synced, plain) {
    if (synced && synced.length > 0) {
      root.lines = synced
      root.status = "synced"
    } else if (plain && plain.trim() !== "") {
      root.lines = Lrc.parsePlain(plain)
      root.status = "plain"
    } else {
      root.lines = []
      root.status = "notfound"
    }
    root.currentIndex = -1
    root.updateIndex()
  }

  function updateIndex() {
    if (root.status !== "synced" || root.lines.length === 0) {
      if (root.currentIndex !== -1) root.currentIndex = -1
      return
    }
    const idx = Lrc.indexAt(root.lines, root.clock)
    if (idx !== root.currentIndex) root.currentIndex = idx
  }

  function seekTo(t) {
    const p = root.player
    if (!p || t < 0 || !p.canSeek) return
    p.position = t
    root.clock = t
    root.updateIndex()
  }

  // Reloads ignoring the cache (used by the "Try again" button).
  function reload() {
    if (root.trackKey !== "") delete root.cache[root.trackKey]
    root.load()
  }
}
