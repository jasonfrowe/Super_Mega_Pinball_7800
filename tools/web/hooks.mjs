// Node module hooks so js7800's core (written for webpack + a browser) loads
// headless: .pal files become data URLs (as url-loader makes them) and the
// browser-only web/ modules become stubs.
import { readFileSync } from "node:fs";
const STUBS = {
  "mouse.js": "export function enableMouseTracking(){} export function isLeftButtonDown(){return false} export function getLightGunScanline(){return 0} export function getLightGunCycle(){return 0}",
  "audio.js": "export function reinit(){}",
};
export async function load(url, context, next) {
  if (url.endsWith(".pal")) {
    const b64 = readFileSync(new URL(url)).toString("base64");
    return { format: "module", shortCircuit: true,
             source: `export default "data:application/octet-stream;base64,${b64}";` };
  }
  const m = url.match(/\/web\/(mouse|audio)\.js$/);
  if (m) return { format: "module", shortCircuit: true, source: STUBS[m[1] + ".js"] };
  return next(url, context);
}
