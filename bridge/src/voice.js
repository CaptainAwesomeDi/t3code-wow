// Text-to-speech and dictation on the desktop side.
//
// Speech: a configured command, else speech-dispatcher (`spd-say`), else espeak-ng,
// else macOS's `say`.
// Dictation: record the mic with pw-record and transcribe with `voxtype transcribe`;
// the bridge sends the text to the addon. Without those, fall back to Omarchy's
// `omarchy-dictation`, which pastes into the focused window.

import { spawn, execFile } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const EXTRA_PATHS = [
  path.join(os.homedir(), '.local/share/omarchy/bin'),
  path.join(os.homedir(), 'omarchy/bin'),
  '/usr/share/omarchy/bin',
  path.join(os.homedir(), '.local/bin'),
];

export function which(bin) {
  for (const dir of [...(process.env.PATH || '').split(path.delimiter), ...EXTRA_PATHS]) {
    if (!dir) continue;
    const p = path.join(dir, bin);
    try {
      fs.accessSync(p, fs.constants.X_OK);
      return p;
    } catch {}
  }
  return null;
}

// A tts.command runs through a shell, which may start other programs (a pipeline into
// a player, say). Stopping the reading must stop all of them, not just the shell. On
// Linux and macOS the shell leads a process group of its own, ended as a whole. That
// group is out of reach of what used to end it with the bridge (systemd's cgroup does,
// launchd and a terminal don't), so groups still running are ended when the bridge
// exits. Windows ends a Node program's children with it already; there `taskkill /T`
// ends the shell's tree.
const GROUPS = process.platform !== 'win32';
const TASKKILL = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'taskkill.exe');
const liveGroups = new Set();
let groupsHooked = false;

function endGroup(pid) {
  try {
    process.kill(-pid, 'SIGTERM');
  } catch {}
}

function keepGroup(child) {
  if (!groupsHooked) {
    groupsHooked = true;
    process.on('exit', () => {
      for (const pid of liveGroups) endGroup(pid);
    });
  }
  liveGroups.add(child.pid);
  child.on('exit', () => liveGroups.delete(child.pid));
}

/** Stops a reading's program and, for a tts.command, everything its shell started. */
function stopReader(child) {
  const running = child.exitCode === null && child.signalCode === null;
  if (child.shellGroup) {
    liveGroups.delete(child.pid);
    if (running) endGroup(child.pid);
  } else if (child.shellTree && running) {
    spawn(TASKKILL, ['/pid', String(child.pid), '/T', '/F'], { stdio: 'ignore', windowsHide: true }).on('error', () => child.kill());
  } else {
    try {
      child.kill('SIGTERM');
    } catch {}
  }
}

export class Voice {
  constructor({ ttsCommand = null, rate = 0, log = () => {}, onSpeaking = () => {} } = {}) {
    this.ttsCommand = ttsCommand; // e.g. "piper-say" or "my-tts --stdin"; text arrives on stdin
    this.rate = rate;
    this.log = log;
    this.onSpeaking = onSpeaking; // called with true or false each time `speaking` changes
    this.current = null;
    this.dictating = false;
  }

  /**
   * Whether something is being read aloud: the program reading it is still running.
   * A tts.command that returns before it has finished speaking counts as done then.
   */
  get speaking() {
    return this.current !== null;
  }

  ttsEngine() {
    if (this.ttsCommand) return { kind: 'custom', cmd: this.ttsCommand };
    const spd = which('spd-say');
    if (spd) return { kind: 'spd', cmd: spd };
    const espeak = which('espeak-ng') || which('espeak');
    if (espeak) return { kind: 'espeak', cmd: espeak };
    const say = process.platform === 'darwin' && which('say');
    if (say) return { kind: 'say', cmd: say };
    return null;
  }

  describe() {
    const e = this.ttsEngine();
    const dictation = this.canOmarchyDictate()
      ? `omarchy-dictation (${this.backendName() || 'no backend set'})`
      : this.canTranscribe() ? 'voxtype' : null;
    return {
      tts: e ? (e.kind === 'custom' ? 'custom' : path.basename(e.cmd)) : null,
      dictation,
      // What to tell the player when there is nothing to dictate with; Omarchy's
      // dictation setup only exists on Linux.
      hint: dictation ? null : this.dictationHint(),
    };
  }

  dictationHint(platform = process.platform) {
    if (platform === 'darwin') return "Dictation isn't available on macOS yet.";
    if (platform === 'win32') return "Dictation isn't available on Windows yet.";
    return 'No dictation backend found; pick one in Omarchy > Setup > Defaults > Dictation.';
  }

  hush() {
    const was = this.speaking;
    this.silence();
    if (was) this.onSpeaking(false);
  }

  // Stops whatever is being read without reporting it: speak() reports once, after
  // the next reading has started. Returns a promise that settles once speech-dispatcher
  // has cancelled what it holds (or after 2 s), or null without speech-dispatcher.
  silence() {
    if (this.current) {
      if (this.current.child) stopReader(this.current.child);
      this.current = null;
    }
    const spd = which('spd-say');
    if (!spd) return null;
    return new Promise((resolve) => {
      const timer = setTimeout(resolve, 2000);
      timer.unref();
      const done = () => {
        clearTimeout(timer);
        resolve();
      };
      spawn(spd, ['--cancel'], { stdio: 'ignore' }).on('error', done).on('exit', done);
    });
  }

  /**
   * Reads `text` aloud. `current` is the reading ({ child }) from here until its program
   * exits or a hush stops it; its child may start a moment later (see below).
   */
  speak(text) {
    text = String(text || '').trim();
    if (!text) return false;
    const engine = this.ttsEngine();
    if (!engine) {
      this.log('speak: no text-to-speech engine found (install speech-dispatcher or espeak-ng, or set tts.command)');
      return false;
    }
    const was = this.speaking;
    const cancelled = this.silence();
    const reading = { child: null };
    this.current = reading;
    const start = () => {
      if (this.current !== reading) return; // stopped, or another reading took over
      const child = (reading.child = this.startReader(engine, text));
      const done = () => {
        if (this.current !== reading) return;
        this.current = null;
        this.onSpeaking(false);
      };
      child.on('error', (err) => {
        this.log(`speak: ${err.message}`);
        done();
      });
      child.on('exit', done);
    };
    // `spd-say --cancel` cancels everything speech-dispatcher holds, the new text too
    // if it lands after it, so speech-dispatcher's next reading waits for the cancel.
    if (engine.kind === 'spd' && cancelled) cancelled.then(start);
    else start();
    if (!was) this.onSpeaking(true);
    return true;
  }

  startReader(engine, text) {
    let child;
    if (engine.kind === 'custom') {
      child = spawn(engine.cmd, { shell: true, detached: GROUPS, stdio: ['pipe', 'ignore', 'ignore'] });
      // No pid: it didn't start, and its 'error' says why.
      if (child.pid && GROUPS) {
        child.shellGroup = true;
        keepGroup(child);
      } else if (child.pid) {
        child.shellTree = true;
      }
    } else if (engine.kind === 'spd') {
      const args = ['--wait', '-e'];
      if (this.rate) args.push('-r', String(this.rate));
      child = spawn(engine.cmd, args, { stdio: ['pipe', 'ignore', 'ignore'] });
    } else if (engine.kind === 'say') {
      // Reads the text from stdin; -r is words per minute (the system default is ~175).
      const args = ['-f', '-'];
      if (this.rate) args.push('-r', String(175 + this.rate));
      child = spawn(engine.cmd, args, { stdio: ['pipe', 'ignore', 'ignore'] });
    } else {
      const args = ['--stdin'];
      if (this.rate) args.push('-s', String(175 + this.rate));
      child = spawn(engine.cmd, args, { stdio: ['pipe', 'ignore', 'ignore'] });
    }
    child.stdin.end(text);
    return child;
  }

  // ---- Omarchy dictation with clipboard capture ----------------------------------
  // `omarchy-dictation start|stop` drives whichever backend the user picked
  // (Voxtype, Superwhisper, Hex...), whose model stays loaded, so it's fast. Every
  // backend delivers the transcript through the clipboard and then sends a paste
  // keystroke; that keystroke doesn't reliably reach the game under Wine, so we
  // watch the clipboard and hand the text to the addon ourselves.
  //
  // Voxtype's usual mode types each letter into the focused window. In the game
  // those letters are ability keys, so the addon window closes and a skill fires.
  // This one recording is asked for the clipboard only, with no typed keys and
  // no Enter afterwards.

  // The commands for one dictation. Voxtype is driven directly so the recording
  // can be told not to type; every other backend stays on omarchy-dictation.
  dictationCommands({ voxtype = which('voxtype'), omarchy = which('omarchy-dictation') } = {}) {
    if (this.backendName() === 'voxtype' && voxtype) {
      return {
        start: [voxtype, ['record', 'start', '--clipboard', '--no-auto-submit']],
        stop: [voxtype, ['record', 'stop']],
        cancel: [voxtype, ['record', 'cancel']],
      };
    }
    return { start: [omarchy, ['start']], stop: [omarchy, ['stop']], cancel: null };
  }

  canOmarchyDictate() {
    return !!(which('omarchy-dictation') && which('wl-paste'));
  }

  backendName() {
    try {
      const file = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'omarchy/defaults/dictation');
      return fs.readFileSync(file, 'utf8').trim() || null;
    } catch {
      return null;
    }
  }

  startOmarchy() {
    this.cancelOmarchy();
    // Each clipboard change arrives on stdout followed by a NUL.
    const watcher = spawn(which('wl-paste'), ['--type', 'text', '--watch', 'sh', '-c', 'cat; printf "\\0"'], {
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    const session = { watcher, events: [], waiters: [], stoppedAt: null, startedAt: Date.now() };
    let buf = '';
    watcher.stdout.setEncoding('utf8');
    watcher.stdout.on('data', (chunk) => {
      buf += chunk;
      let i;
      while ((i = buf.indexOf('\0')) >= 0) {
        const text = buf.slice(0, i);
        buf = buf.slice(i + 1);
        const ev = { text, at: Date.now() };
        session.events.push(ev);
        for (const w of session.waiters.splice(0)) w(ev);
      }
    });
    watcher.on('error', (err) => this.log(`clipboard watch: ${err.message}`));
    session.commands = this.dictationCommands();
    this.omarchy = session;
    this.dictating = true;
    const [cmd, args] = session.commands.start;
    spawn(cmd, args, { stdio: 'ignore' }).on('error', (err) => this.log(`dictate: ${err.message}`));
    return true;
  }

  cancelOmarchy() {
    const s = this.omarchy;
    this.omarchy = null;
    this.dictating = false;
    if (!s) return;
    try {
      s.watcher.kill();
    } catch {}
    // Drop the recording without output, so a closed window can't still type
    // the transcript into the game a moment later.
    if (s.commands?.cancel) {
      const [cmd, args] = s.commands.cancel;
      spawn(cmd, args, { stdio: 'ignore' }).on('error', () => {});
    }
  }

  // Stop the backend and resolve with the first clipboard text that appears after
  // stopping ('' if nothing was heard within the timeout).
  stopOmarchy({ timeoutMs = 15000 } = {}) {
    const s = this.omarchy;
    if (!s) return Promise.reject(new Error('not dictating'));
    this.dictating = false;
    s.stoppedAt = Date.now();
    return new Promise((resolve) => {
      let done = false;
      const finish = (text) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        if (this.omarchy === s) this.omarchy = null;
        try {
          s.watcher.kill();
        } catch {}
        resolve((text || '').trim());
      };
      const timer = setTimeout(() => finish(''), timeoutMs);
      // wl-paste also reports the clipboard as it already was when the watch starts;
      // only a change after the release is the transcript.
      const fresh = (ev) => ev.at >= s.stoppedAt && ev.text.trim();
      s.waiters.push(function wait(ev) {
        if (fresh(ev)) finish(ev.text);
        else s.waiters.push(wait);
      });
      const [cmd, args] = s.commands.stop;
      const stopper = spawn(cmd, args, { stdio: ['ignore', 'ignore', 'pipe'] });
      let err = '';
      stopper.stderr.on('data', (d) => (err += d));
      stopper.on('exit', (code) => {
        if (code && !done) {
          this.log(`${path.basename(cmd)} ${args.join(' ')} failed: ${err.trim()}`);
          finish('');
        }
      });
    });
  }

  // ---- Direct dictation (fallback when Omarchy's dictation isn't available) -----
  // Record the default microphone ourselves and transcribe the file with Voxtype,
  // so the text comes back to the bridge instead of being pasted into whatever
  // window has focus (pasting into the game under Wine doesn't arrive).

  recorder() {
    const pw = which('pw-record');
    if (pw) return (file) => [pw, ['--rate', '16000', '--channels', '1', '--format', 's16', file]];
    const pa = which('parecord');
    if (pa) return (file) => [pa, ['--rate=16000', '--channels=1', '--format=s16le', '--file-format=wav', file]];
    const al = which('arecord');
    if (al) return (file) => [al, ['-q', '-f', 'S16_LE', '-r', '16000', '-c', '1', file]];
    return null;
  }

  transcriber() {
    return which('voxtype');
  }

  canTranscribe() {
    return !!(this.recorder() && this.transcriber());
  }

  startRecording() {
    this.cancelRecording();
    const file = path.join(os.tmpdir(), `t3wow-dictation-${process.pid}-${Date.now()}.wav`);
    const [cmd, args] = this.recorder()(file);
    const child = spawn(cmd, args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let stderr = '';
    child.stderr.on('data', (d) => (stderr += d));
    child.on('error', (err) => this.log(`record: ${err.message}`));
    this.recording = { child, file, startedAt: Date.now(), stderr: () => stderr };
    this.dictating = true;
    return true;
  }

  cancelRecording() {
    const r = this.recording;
    this.recording = null;
    this.dictating = false;
    if (!r) return;
    try {
      r.child.kill('SIGINT');
    } catch {}
    setTimeout(() => fs.rm(r.file, { force: true }, () => {}), 2000);
  }

  // Stop recording and resolve with the transcript ('' when nothing was said).
  async stopAndTranscribe() {
    const r = this.recording;
    this.recording = null;
    this.dictating = false;
    if (!r) throw new Error('not recording');
    await new Promise((res) => {
      if (r.child.exitCode !== null) return res();
      r.child.once('exit', res);
      try {
        r.child.kill('SIGINT');
      } catch {
        res();
      }
      setTimeout(res, 3000);
    });
    try {
      const size = fs.existsSync(r.file) ? fs.statSync(r.file).size : 0;
      if (size < 3200) throw new Error(`no audio recorded${r.stderr() ? `: ${r.stderr().trim().split('\n').pop()}` : ''}`);
      const text = await new Promise((resolve, reject) => {
        execFile(this.transcriber(), ['transcribe', r.file], { timeout: 60000, maxBuffer: 4 * 1024 * 1024 }, (err, stdout, stderr) => {
          if (err) return reject(new Error(`transcription failed: ${(stderr || err.message).trim().split('\n').pop()}`));
          const lines = stdout.split('\n').map((l) => l.trim()).filter(Boolean);
          // `voxtype transcribe` prints progress lines first and the text last.
          const last = lines.filter((l) => !/^(Loading audio file|Audio format|Processing \d+ samples)/.test(l)).pop() || '';
          resolve(last);
        });
      });
      return text;
    } finally {
      fs.rm(r.file, { force: true }, () => {});
    }
  }
}
