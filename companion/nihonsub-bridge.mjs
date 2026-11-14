#!/usr/bin/env node
// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Bridge between CasaPlay (Apple TV, iPhone, iPad) and NihonSub, which runs on your Mac.
// NihonSub only takes uploaded files, so this does the legwork for the app:
//
//   1. CasaPlay sends the stream's link.
//   2. The bridge pulls just the audio from that link with FFmpeg (a small mono MP3).
//   3. NihonSub transcribes the Japanese speech and translates it.
//   4. CasaPlay downloads the finished SRT subtitles and shows them in the player.
//
// Needs Node 18+ and FFmpeg. No npm packages. Everything stays on your network; the only
// outside calls are the ones NihonSub itself makes (Groq, and OpenRouter if you set it up).
//
// Access is protected by a token (see "Token" below). Anyone on your Wi-Fi who has the token
// can ask this bridge to read a link, so keep it private like a password.
//
// API (all need  Authorization: Bearer <token>):
//   GET    /health          -> { ok, ffmpeg, nihonsub, configured }
//   POST   /jobs            -> { id }   body: { url, language: "en"|"hi"|"hinglish", headers? }
//   GET    /jobs/:id        -> { id, state, percent, message, error? }
//   GET    /jobs/:id/srt    -> the subtitles (once state is "done")
//   DELETE /jobs/:id        -> stops the job

import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const LANGUAGES = new Set(['en', 'hi', 'hinglish']);
const HEADER_NAMES = new Map([
  ['user-agent', 'User-Agent'], ['referer', 'Referer'], ['origin', 'Origin'], ['cookie', 'Cookie'],
]);
const MAX_QUEUED = 8;
const KEEP_FINISHED_MS = 6 * 60 * 60 * 1000;

// MARK: - Token

/**
 * The token comes from BRIDGE_TOKEN, or else a file next to this script. The first run creates
 * the file with a random token and only you can read it.
 */
export function loadToken(file) {
  if (process.env.BRIDGE_TOKEN && process.env.BRIDGE_TOKEN.length >= 16) return process.env.BRIDGE_TOKEN;
  try {
    const saved = fs.readFileSync(file, 'utf8').trim();
    if (saved.length >= 16) return saved;
  } catch {}
  const fresh = randomBytes(24).toString('base64url');
  fs.writeFileSync(file, fresh + '\n', { mode: 0o600 });
  return fresh;
}

function tokenMatches(given, expected) {
  const a = Buffer.from(given), b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

// MARK: - Bridge

/**
 * @param {object} o
 * @param {string} o.token        shared secret the app must send
 * @param {string} [o.nihonsubUrl]
 * @param {string} [o.ffmpeg]
 * @param {string} [o.ffprobe]
 * @param {string} [o.tmpDir]
 */
export function createBridge(o) {
  const nihonsubUrl = (o.nihonsubUrl || 'http://127.0.0.1:3000').replace(/\/+$/, '');
  const ffmpeg = o.ffmpeg || 'ffmpeg';
  const ffprobe = o.ffprobe || 'ffprobe';
  const tmpDir = o.tmpDir || fs.mkdtempSync(path.join(os.tmpdir(), 'casaplay-bridge-'));
  const jobs = new Map();
  let chain = Promise.resolve();

  // ---- jobs

  function publicJob(job) {
    const out = { id: job.id, state: job.state, percent: job.percent, message: job.message };
    if (job.error) out.error = job.error;
    return out;
  }

  function update(job, state, percent, message) {
    job.state = state;
    job.percent = Math.max(job.percent, percent);
    job.message = String(message).slice(0, 200);
  }

  async function run(job) {
    if (job.cancelled) return;
    let audioFile;
    try {
      update(job, 'extracting', 3, 'Reading the audio from the video…');
      audioFile = path.join(tmpDir, `${job.id}.mp3`);
      await extractAudio(job, audioFile);
      if (job.cancelled) return;
      update(job, 'transcribing', 25, 'Sending the audio to NihonSub…');
      job.srt = await translateWithNihonSub(job, audioFile);
      update(job, 'done', 100, 'Subtitles ready.');
    } catch (error) {
      if (job.cancelled) return;
      job.state = 'failed';
      job.error = String(error && error.message ? error.message : error).slice(0, 400);
      job.message = 'Failed.';
    } finally {
      job.finishedAt = Date.now();
      if (audioFile) fs.rm(audioFile, { force: true }, () => {});
    }
  }

  // ---- FFmpeg

  function headerArgs(headers) {
    const lines = Object.entries(headers).map(([k, v]) => `${k}: ${v}\r\n`).join('');
    return lines ? ['-headers', lines] : [];
  }

  // Only web links; "file" is left out on purpose so a playlist can't point FFmpeg at local files.
  const inputArgs = (job) => [
    '-protocol_whitelist', 'http,https,tcp,tls,crypto',
    '-rw_timeout', '30000000',
    ...headerArgs(job.headers),
  ];

  function runProcess(job, command, args, { onStdout, onStderr } = {}) {
    return new Promise((resolve, reject) => {
      const child = spawn(command, args, { stdio: ['ignore', 'pipe', 'pipe'] });
      job.child = child;
      let out = '', err = '';
      child.stdout.on('data', (d) => { out += d; if (onStdout) onStdout(String(d)); });
      child.stderr.on('data', (d) => { err = (err + d).slice(-2000); if (onStderr) onStderr(String(d)); });
      child.on('error', (e) => reject(new Error(`Could not start ${path.basename(command)}: ${e.message}`)));
      child.on('close', (code) => {
        job.child = null;
        if (code === 0) resolve(out);
        else reject(new Error(job.cancelled ? 'Cancelled.' : `${path.basename(command)} stopped (code ${code}). ${err.trim().split('\n').slice(-2).join(' ')}`));
      });
    });
  }

  /** Picks the Japanese audio track if there is one, otherwise the first. Also reads the length. */
  async function probe(job) {
    const text = await runProcess(job, ffprobe, [
      '-v', 'error', ...inputArgs(job),
      '-show_entries', 'stream=index,codec_type:stream_tags=language:format=duration',
      '-of', 'json', job.url,
    ]);
    let info;
    try { info = JSON.parse(text); } catch { throw new Error('Could not read that video.'); }
    const audio = (info.streams || []).filter((s) => s.codec_type === 'audio');
    if (audio.length === 0) throw new Error('That video has no audio track.');
    const japanese = audio.find((s) => /^(ja|jpn)$/i.test((s.tags && s.tags.language) || ''));
    return { index: (japanese || audio[0]).index, duration: Number(info.format && info.format.duration) || 0 };
  }

  async function extractAudio(job, outFile) {
    const { index, duration } = await probe(job);
    await runProcess(job, ffmpeg, [
      '-nostdin', '-y', '-v', 'error', '-progress', 'pipe:1', ...inputArgs(job),
      '-i', job.url, '-map', `0:${index}`, '-vn', '-ac', '1', '-ar', '16000',
      '-c:a', 'libmp3lame', '-b:a', '48k', outFile,
    ], {
      onStdout(chunk) {
        const m = chunk.match(/out_time_us=(\d+)/g);
        if (!m || !duration) return;
        const seconds = Number(m[m.length - 1].split('=')[1]) / 1e6;
        update(job, 'extracting', 3 + Math.round(Math.min(1, seconds / duration) * 20), 'Reading the audio from the video…');
      },
    });
  }

  // ---- NihonSub

  /** Plain multipart upload with node:http, which has no body timeout for the long NDJSON reply. */
  function postMultipart(url, fields, file) {
    const boundary = '----casaplay' + randomBytes(12).toString('hex');
    const parts = [];
    for (const [name, value] of Object.entries(fields)) {
      parts.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${value}\r\n`));
    }
    parts.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="video"; filename="${file.name}"\r\nContent-Type: ${file.type}\r\n\r\n`));
    parts.push(file.data);
    parts.push(Buffer.from(`\r\n--${boundary}--\r\n`));
    const body = Buffer.concat(parts);
    return new Promise((resolve, reject) => {
      const req = http.request(url, {
        method: 'POST',
        headers: { 'Content-Type': `multipart/form-data; boundary=${boundary}`, 'Content-Length': body.length },
      }, resolve);
      req.on('error', reject);
      req.end(body);
    });
  }

  async function translateWithNihonSub(job, audioFile) {
    const hindi = job.language !== 'en';
    const fields = { targetLang: hindi ? 'hi' : 'en' };
    if (hindi) fields.hindiScript = job.language === 'hinglish' ? 'hinglish' : 'devanagari';
    let response;
    try {
      response = await postMultipart(`${nihonsubUrl}/api/process`, fields, {
        name: 'audio.mp3', type: 'audio/mpeg', data: await fs.promises.readFile(audioFile),
      });
    } catch (e) {
      throw new Error(`NihonSub isn't answering at ${nihonsubUrl}. Is it running?`);
    }
    job.response = response;
    if (response.statusCode !== 200) throw new Error(`NihonSub answered ${response.statusCode}.`);

    let complete = null, buffer = '';
    const handle = (line) => {
      let event;
      try { event = JSON.parse(line); } catch { return; }
      if (event.type === 'progress') {
        const p = Number(event.percent) || 0;
        update(job, event.step === 'translate' ? 'translating' : 'transcribing',
          25 + Math.round(Math.max(0, p - 15) * 0.7), event.message || 'Working…');
      } else if (event.type === 'error') {
        throw new Error(event.error || 'NihonSub reported an error.');
      } else if (event.type === 'complete') {
        complete = event.data;
      }
    };
    try {
      for await (const chunk of response) {
        buffer += chunk.toString('utf8');
        let newline;
        while ((newline = buffer.indexOf('\n')) >= 0) {
          const line = buffer.slice(0, newline).trim();
          buffer = buffer.slice(newline + 1);
          if (line) handle(line);
        }
      }
      if (buffer.trim()) handle(buffer.trim());
    } finally {
      response.destroy();
    }
    if (job.cancelled) throw new Error('Cancelled.');
    if (!complete) throw new Error('NihonSub stopped before finishing.');

    const entry = complete.subtitles && complete.subtitles[hindi ? 'hi' : 'en'];
    const link = entry && entry.srtUrl;
    if (typeof link !== 'string' || !link.startsWith('/api/subtitles/')) throw new Error('NihonSub sent no subtitles.');
    const file = await fetch(nihonsubUrl + link);
    const text = file.ok ? await file.text() : '';
    if (!text.includes('-->')) throw new Error('The subtitles from NihonSub were empty.');
    return text;
  }

  // ---- HTTP

  function send(res, status, body, type = 'application/json; charset=utf-8') {
    const data = typeof body === 'string' ? body : JSON.stringify(body);
    res.writeHead(status, { 'Content-Type': type, 'Content-Length': Buffer.byteLength(data), 'Cache-Control': 'no-store' });
    res.end(data);
  }

  function readJSON(req, limit = 16 * 1024) {
    return new Promise((resolve, reject) => {
      let size = 0; const chunks = [];
      req.on('data', (c) => {
        size += c.length;
        if (size > limit) { reject(Object.assign(new Error('Request too large.'), { status: 413 })); req.destroy(); return; }
        chunks.push(c);
      });
      req.on('end', () => {
        try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}')); }
        catch { reject(Object.assign(new Error('Send JSON.'), { status: 400 })); }
      });
      req.on('error', reject);
    });
  }

  function cleanHeaders(input) {
    const out = {};
    if (input && typeof input === 'object') {
      for (const [name, value] of Object.entries(input)) {
        const canonical = HEADER_NAMES.get(String(name).toLowerCase());
        if (canonical && typeof value === 'string' && value.length < 2000 && !/[\r\n]/.test(value)) out[canonical] = value;
      }
    }
    return out;
  }

  async function health() {
    const result = { ok: true, ffmpeg: false, nihonsub: false, configured: false };
    result.ffmpeg = await new Promise((resolve) => {
      const child = spawn(ffmpeg, ['-version'], { stdio: 'ignore' });
      child.on('error', () => resolve(false));
      child.on('close', (code) => resolve(code === 0));
    });
    try {
      const r = await fetch(`${nihonsubUrl}/api/config`, { signal: AbortSignal.timeout(3000) });
      if (r.ok) {
        result.nihonsub = true;
        const config = await r.json().catch(() => ({}));
        result.configured = Boolean(config.groqConfigured);
      }
    } catch {}
    return result;
  }

  const server = http.createServer(async (req, res) => {
    try {
      const header = req.headers.authorization || '';
      if (!header.startsWith('Bearer ') || !tokenMatches(header.slice(7), o.token)) {
        return send(res, 401, { error: 'Wrong or missing token.' });
      }
      const url = new URL(req.url, 'http://bridge.local');
      const parts = url.pathname.split('/').filter(Boolean);

      if (req.method === 'GET' && url.pathname === '/health') return send(res, 200, await health());

      if (req.method === 'POST' && url.pathname === '/jobs') {
        const body = await readJSON(req);
        let target;
        try { target = new URL(String(body.url)); } catch { return send(res, 400, { error: 'That link is not valid.' }); }
        if (target.protocol !== 'http:' && target.protocol !== 'https:') return send(res, 400, { error: 'Only http and https links work.' });
        const language = body.language === undefined ? 'en' : body.language;
        if (!LANGUAGES.has(language)) return send(res, 400, { error: 'Language must be en, hi or hinglish.' });
        const waiting = [...jobs.values()].filter((j) => j.state === 'queued').length;
        if (waiting >= MAX_QUEUED) return send(res, 429, { error: 'Too many jobs waiting. Try again later.' });
        const job = {
          id: randomBytes(8).toString('hex'), url: target.href, language, headers: cleanHeaders(body.headers),
          state: 'queued', percent: 0, message: 'Waiting to start…', createdAt: Date.now(),
        };
        jobs.set(job.id, job);
        chain = chain.then(() => run(job));
        return send(res, 202, { id: job.id });
      }

      if (parts[0] === 'jobs' && parts[1]) {
        const job = jobs.get(parts[1]);
        if (!job) return send(res, 404, { error: 'No such job.' });
        if (req.method === 'GET' && parts.length === 2) return send(res, 200, publicJob(job));
        if (req.method === 'GET' && parts[2] === 'srt' && parts.length === 3) {
          if (job.state !== 'done') return send(res, 409, { error: 'Not finished yet.' });
          return send(res, 200, job.srt, 'text/plain; charset=utf-8');
        }
        if (req.method === 'DELETE' && parts.length === 2) {
          job.cancelled = true;
          if (job.child) job.child.kill('SIGTERM');
          if (job.response) job.response.destroy();
          if (job.state !== 'done') { job.state = 'failed'; job.error = 'Cancelled.'; job.message = 'Cancelled.'; }
          return send(res, 200, publicJob(job));
        }
      }
      send(res, 404, { error: 'Not found.' });
    } catch (error) {
      send(res, error.status || 500, { error: error.message || 'Something went wrong.' });
    }
  });

  const sweep = setInterval(() => {
    for (const [id, job] of jobs) {
      if (job.finishedAt && Date.now() - job.finishedAt > KEEP_FINISHED_MS) jobs.delete(id);
    }
  }, 30 * 60 * 1000);
  sweep.unref();
  server.on('close', () => clearInterval(sweep));
  return server;
}

// MARK: - Run

function lanAddresses() {
  return Object.values(os.networkInterfaces()).flat()
    .filter((i) => i && i.family === 'IPv4' && !i.internal).map((i) => i.address);
}

function main() {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const port = Number(process.env.BRIDGE_PORT || 3100);
  const token = loadToken(process.env.BRIDGE_TOKEN_FILE || path.join(here, '.bridge-token'));
  const server = createBridge({
    token,
    nihonsubUrl: process.env.NIHONSUB_URL,
    ffmpeg: process.env.FFMPEG_PATH,
    ffprobe: process.env.FFPROBE_PATH,
  });
  server.listen(port, '0.0.0.0', () => {
    console.log('==================================================');
    console.log('  CasaPlay ↔ NihonSub bridge is running');
    for (const ip of lanAddresses()) console.log(`  Address for CasaPlay:  http://${ip}:${port}`);
    console.log(`  Token for CasaPlay:    ${token}`);
    console.log('  Enter both in CasaPlay › Profile › Online services › NihonSub.');
    console.log('==================================================');
  });
  process.on('SIGINT', () => { server.close(); process.exit(0); });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
