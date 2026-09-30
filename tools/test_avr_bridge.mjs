// Runs the compiled web emulator (web/avr_bridge.js) in Node against real
// firmware, so the artefact the browser loads is tested, not only the Dart it
// was built from. Usage: node tools/test_avr_bridge.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = fileURLToPath(new URL('..', import.meta.url));
vm.runInThisContext(readFileSync(root + 'web/avr_bridge.js', 'utf8'), { filename: 'avr_bridge.js' });
const avr = globalThis.AVR8;
if (!avr) throw new Error('avr_bridge.js did not define AVR8');

let failures = 0;
const check = (name, ok, detail) => {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`);
  if (!ok) failures++;
};
const CLOCK = 16e6;

// 1. Calls before any program is loaded answer defaults instead of throwing.
check('safe before load', avr.getPinState(13) === false && avr.getCycles() === 0);

// 2. I2C reads, read-back and NACK, through the real Wire library.
{
  const lines = [];
  avr.setSerialPrint((line) => lines.push(line));
  avr.loadHex(readFileSync(root + 'packages/pinbench_sim/test/fixtures/i2c_read/i2c_read.hex', 'utf8'));
  avr.serveI2c(0x68, 256, 1);
  avr.setI2cRegisters(0x68, 0x75, new Int32Array([0x68]));
  avr.setI2cRegisters(0x68, 0x3b, new Int32Array([0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc]));
  for (let i = 0; i < 200 && !lines.includes('DONE'); i++) avr.tick(160000);
  const want = ['WHO=68', 'ACC=123456789ABC', 'BACK=5A', 'ABSENT=2', 'DONE'];
  check('I2C reads', want.every((w, i) => lines[i] === w), JSON.stringify(lines));
}

// 3. Time: a frame's worth of cycles is exactly that, so delay() keeps pace.
{
  avr.loadHex(readFileSync(root + 'assets/templates/blink/blink.ino.hex', 'utf8'));
  let exact = true;
  for (let f = 0; f < 50; f++) {
    const before = avr.getCycles();
    avr.tick(256000);
    const ran = avr.getCycles() - before;
    if (ran < 256000 || ran > 256005) exact = false;
  }
  check('tick counts cycles', exact);
  // The blink template toggles pin 13 every 500 ms: 8 edges in 4 simulated s.
  let edges = 0, last = avr.getPin13State();
  for (let f = 0; f < 250; f++) {
    avr.tick(256000);
    const now = avr.getPin13State();
    if (now !== last) edges++;
    last = now;
  }
  check('blink keeps real time', edges >= 7 && edges <= 9, `${edges} edges in 4 s (delay(500): 8 expected)`);
}

// 4. Speed: the reason this is dart2js and not the app's Wasm.
{
  avr.loadHex(readFileSync(root + 'assets/templates/oled/oled.ino.hex', 'utf8'));
  const t0 = performance.now();
  for (let f = 0; f < 312; f++) avr.tick(256000); // ~5 simulated seconds
  const x = avr.getCycles() / ((performance.now() - t0) / 1000) / CLOCK;
  // The bar is real time itself, not the ~3.5x a laptop gets: a shared CI
  // runner is slower, and what the web needs is only never to fall behind.
  check('faster than real time', x > 1, `x${x.toFixed(2)} real time`);
}

console.log(failures ? `${failures} failed` : 'all passed');
process.exit(failures ? 1 : 0);
