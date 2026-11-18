// Run a ROM in js7800's emulator core, headless.
//   node tools/web/jsrun.mjs ROM OUTDIR script.txt
// The script uses tools/emu/play.lua's format for: press/release (P1 Up/Down/
// Left/Right, P1 Button 1/2, Reset, Select, Pause), snap, peek ADDR N,
// poke ADDR BYTES..., exit. Snaps are OUTDIR/NNNN.png; the log is OUTDIR/play.txt;
// the sound is OUTDIR/sound.wav (31440 Hz mono), and play.txt ends with how
// much each POKEY played.
import { register } from "node:module";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { deflateSync } from "node:zlib";
import { pathToFileURL } from "node:url";
register("./hooks.mjs", import.meta.url);

const JS7800 = process.env.JS7800 || `${process.env.HOME}/Software/js7800`;
const P = (m) => import(pathToFileURL(`${JS7800}/src/js/${m}`).href);
const Events = await P("events.js");
const ProSystem = await P("prosystem/ProSystem.js");
const Cartridge = await P("prosystem/Cartridge.js");
const Database = await P("prosystem/Database.js");
const Region = await P("prosystem/Region.js");
const Maria = await P("prosystem/Maria.js");
const Memory = await P("prosystem/Memory.js");
const Sound = await P("prosystem/Sound.js");
const Pokey = await P("prosystem/Pokey.js");

const [romPath, outDir, scriptPath] = process.argv.slice(2);
mkdirSync(outDir, { recursive: true });
const log = [];

const W = 320, H = 300;
const surface = new Array(W * H).fill(0);
Maria.SetSurface(surface);
const keys = new Array(19).fill(0);
Events.fireEvent("init", { keyboardData: keys, Region, debug: false });

const cart = new Uint8Array(readFileSync(romPath));
Cartridge.Load(cart, cart.length);
Database.Load(Cartridge.GetDigest());
Events.fireEvent("onCartridgeLoaded", Cartridge);   // as js7800.js does: the modules read the cart's flags
log.push(`cart pokey=${Cartridge.IsPokeyEnabled()} pokey450=${Cartridge.IsPokey450Enabled()} pokey440=${Cartridge.IsPokey440Enabled ? Cartridge.IsPokey440Enabled() : "-"} math=${Cartridge.IsMathUnit ? Cartridge.IsMathUnit() : "-"} type=${Cartridge.GetType()}`);

const RATE = 31440;
Sound.SetSampleRate(RATE);
const audio = [];
Sound.SetStoreSoundCallback((sample, ym, length) => {
  for (let i = 0; i < length; i++) audio.push(sample[i] / 255);
});
const pokeyBusy = [0, 0];     // samples where each POKEY was not silent
function countPokeys() {
  const bufs = [Pokey.buffer, Pokey.pokey1 ? Pokey.pokey1.buffer : null];
  bufs.forEach((b, k) => { if (b) for (let i = 0; i < 524; i++) if (b[i]) pokeyBusy[k]++; });
}
function wav(path) {
  const n = audio.length, out = Buffer.alloc(44 + n * 2);
  out.write("RIFF", 0); out.writeUInt32LE(36 + n * 2, 4); out.write("WAVEfmt ", 8);
  out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22);
  out.writeUInt32LE(RATE, 24); out.writeUInt32LE(RATE * 2, 28); out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34);
  out.write("data", 36); out.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) out.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round((audio[i] - 0.5) * 65535 * 0.9))), 44 + i * 2);
  writeFileSync(path, out);
}

let ready = false;
ProSystem.Reset(() => { ready = true; });
for (let i = 0; i < 1000 && !ready; i++) await new Promise((r) => setTimeout(r, 1));

const pal = Region.getNtscPalette();
function png(path) {
  const top = 26 - 17, h = 248 - 26 + 1;   // Maria.js visibleArea within displayArea
  const raw = Buffer.alloc((W * 3 + 1) * h);
  let o = 0;
  for (let y = 0; y < h; y++) {
    raw[o++] = 0;
    for (let x = 0; x < W; x++) {
      const c = surface[(y + top) * W + x] & 255;
      raw[o++] = pal[c * 3]; raw[o++] = pal[c * 3 + 1]; raw[o++] = pal[c * 3 + 2];
    }
  }
  const crcT = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; return c; });
  const crc = (b) => { let c = -1; for (const v of b) c = crcT[(c ^ v) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
  const chunk = (t, d) => { const len = Buffer.alloc(4); len.writeUInt32BE(d.length);
    const td = Buffer.concat([Buffer.from(t), d]); const cr = Buffer.alloc(4); cr.writeUInt32BE(crc(td)); return Buffer.concat([len, td, cr]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  writeFileSync(path, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}

const KEY = { "P1 Right": 0, "P1 Left": 1, "P1 Down": 2, "P1 Up": 3, "P1 Button 1": 4, "P1 Button 2": 5, "Reset": 12, "Select": 13, "Pause": 14 };
const cmds = {};
for (const line of readFileSync(scriptPath, "utf8").split("\n")) {
  const t = line.trim(); if (!t || t.startsWith("#")) continue;
  const m = t.match(/^(\d+)\s+(\S+)\s*(.*)$/); if (!m) continue;
  (cmds[m[1]] ||= []).push([m[2], m[3]]);
}
const last = Math.max(...Object.keys(cmds).map(Number));
let snaps = 0;
const t0 = Date.now();
for (let f = 0; f <= last; f++) {
  for (const [verb, arg] of cmds[f] || []) {
    if (verb === "press" || verb === "release") keys[KEY[arg]] = verb === "press" ? 1 : 0;
    else if (verb === "snap") png(`${outDir}/${String(snaps++).padStart(4, "0")}.png`);
    else if (verb === "peek") { const [a, n] = arg.split(/\s+/); const A = parseInt(a, 16);
      const b = []; for (let i = 0; i < Number(n); i++) b.push(Memory.Read(A + i).toString(16).padStart(2, "0"));
      log.push(`${String(f).padStart(5)} ${a} ${b.join(" ")}`); }
    else if (verb === "poke") { const [a, ...bs] = arg.split(/\s+/); const A = parseInt(a, 16);
      bs.forEach((v, i) => Memory.Write(A + i, parseInt(v, 16))); }
    else if (verb === "exit") f = last + 1;
  }
  if (f <= last) { ProSystem.ExecuteFrame(keys); countPokeys(); Sound.Store(); }
}
wav(`${outDir}/sound.wav`);
log.push(`pokey samples playing: $0450 ${pokeyBusy[0]}, $0440 ${pokeyBusy[1]}`);
log.push(`ran ${last} frames in ${Date.now() - t0} ms`);
writeFileSync(`${outDir}/play.txt`, log.join("\n") + "\n");
console.log(log.join("\n"));
