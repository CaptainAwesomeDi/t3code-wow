import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { Voice } from '../src/voice.js';

test('a custom speech command gets the text on its standard input, through the shell of the system it runs on', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 't3wow-voice-'));
  const heard = path.join(dir, 'heard.txt');
  const say = path.join(dir, 'say.cjs');
  fs.writeFileSync(say, "let text = ''; process.stdin.on('data', (d) => (text += d)).on('end', () => require('node:fs').writeFileSync(process.argv[2], text));");
  const voice = new Voice({ ttsCommand: `"${process.execPath}" "${say}" "${heard}"` });
  assert.equal(voice.speak('Für Elise, twice'), true);
  await new Promise((resolve) => voice.current.child.once('exit', resolve));
  assert.equal(fs.readFileSync(heard, 'utf8'), 'Für Elise, twice');
});

/** A stand-in voice that takes `ms` to say whatever arrives on its standard input. */
function slowVoice(dir, ms) {
  const say = path.join(dir, 'slow.cjs');
  fs.writeFileSync(say, `process.stdin.resume().on('end', () => setTimeout(() => {}, ${ms}));`);
  return `"${process.execPath}" "${say}"`;
}

test('a reading is speaking until its program exits or a hush stops it, and each change is reported once', async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 't3wow-voice-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const changes = [];
  const voice = new Voice({ ttsCommand: slowVoice(dir, 300), onSpeaking: (on) => changes.push(on) });
  assert.equal(voice.speaking, false);
  voice.speak('One');
  assert.equal(voice.speaking, true);
  await new Promise((resolve) => voice.current.child.once('exit', resolve));
  assert.equal(voice.speaking, false, 'done once the program exits');
  voice.speak('Two');
  voice.speak('Three');
  assert.equal(voice.speaking, true, 'the next reading cuts the last one off and goes on');
  voice.hush();
  assert.equal(voice.speaking, false, 'a hush stops it at once');
  voice.hush();
  assert.deepEqual(changes, [true, false, true, false]);
});

/** A tts.command whose shell starts a program that runs until stopped and writes its pid. */
function pipedVoice(dir) {
  const player = path.join(dir, 'player.cjs');
  fs.writeFileSync(player, "require('node:fs').writeFileSync(process.argv[2], String(process.pid)); setInterval(() => {}, 1000);");
  const sink = path.join(dir, 'sink.cjs');
  fs.writeFileSync(sink, 'process.stdin.resume();');
  const pidFile = path.join(dir, 'player.pid');
  return { cmd: `"${process.execPath}" "${player}" "${pidFile}" | "${process.execPath}" "${sink}"`, pidFile };
}

const alive = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

async function until(check, ms = 3000) {
  for (const end = Date.now() + ms; Date.now() < end; await new Promise((r) => setTimeout(r, 20))) {
    if (check()) return true;
  }
  return check();
}

// Windows ends the shell's tree with taskkill, which this suite hasn't measured there.
const skipWindows = process.platform === 'win32' ? 'process groups are Linux and macOS' : false;

test("a hush stops every program a tts.command's shell started, not just the shell", { skip: skipWindows }, async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 't3wow-voice-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const { cmd, pidFile } = pipedVoice(dir);
  const voice = new Voice({ ttsCommand: cmd });
  voice.speak('Long reply');
  assert.ok(await until(() => fs.existsSync(pidFile) && fs.readFileSync(pidFile, 'utf8')), 'the player started');
  const pid = Number(fs.readFileSync(pidFile, 'utf8'));
  t.after(() => alive(pid) && process.kill(pid, 'SIGKILL'));
  voice.hush();
  assert.ok(await until(() => !alive(pid)), 'the player stopped with the reading');
});

test('a reading still going when the bridge exits ends with it', { skip: skipWindows }, async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 't3wow-voice-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const { cmd, pidFile } = pipedVoice(dir);
  const bridge = path.join(dir, 'bridge.mjs');
  const voiceUrl = new URL('../src/voice.js', import.meta.url).href;
  fs.writeFileSync(bridge, `import { Voice } from ${JSON.stringify(voiceUrl)};
import fs from 'node:fs';
new Voice({ ttsCommand: ${JSON.stringify(cmd)} }).speak('Long reply');
const wait = setInterval(() => { if (fs.existsSync(${JSON.stringify(pidFile)})) { clearInterval(wait); process.exit(0); } }, 20);
`);
  execFileSync(process.execPath, [bridge], { timeout: 5000 });
  const pid = Number(fs.readFileSync(pidFile, 'utf8'));
  t.after(() => alive(pid) && process.kill(pid, 'SIGKILL'));
  assert.ok(await until(() => !alive(pid)), 'the player stopped with the bridge');
});

test("speech-dispatcher's next reading waits for the cancel of the last, which would cut it off too", { skip: skipWindows }, async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 't3wow-voice-'));
  const log = path.join(dir, 'log');
  const savedPath = process.env.PATH;
  t.after(() => {
    process.env.PATH = savedPath;
    fs.rmSync(dir, { recursive: true, force: true });
  });
  // A stand-in spd-say whose cancel takes a moment, as speech-dispatcher's can.
  fs.writeFileSync(path.join(dir, 'spd-say'), `#!/bin/sh\nif [ "$1" = --cancel ]; then sleep 0.2; echo cancelled >> "${log}"; else cat > /dev/null; echo read >> "${log}"; fi\n`, { mode: 0o755 });
  process.env.PATH = `${dir}${path.delimiter}${savedPath}`;
  const voice = new Voice();
  assert.equal(voice.ttsEngine().kind, 'spd');
  voice.speak('Next reply');
  assert.equal(voice.speaking, true, 'speaking from the click, while the cancel goes on');
  assert.ok(await until(() => !voice.speaking), 'the reading went and ended');
  assert.deepEqual(fs.readFileSync(log, 'utf8').trim().split('\n'), ['cancelled', 'read']);
});
