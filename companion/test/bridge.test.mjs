// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Runs the bridge against a pretend NihonSub and a small web server that holds a test tone.
//   node --test companion/test

import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createBridge } from '../nihonsub-bridge.mjs';

const TOKEN = 'test-token-0123456789abcdef';
const SRT = '1\n00:00:00,000 --> 00:00:02,000\nHello there.\n\n2\n00:00:02,500 --> 00:00:04,000\nSecond line.\n';

function listen(server) {
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
}

/** A stand-in for NihonSub: same routes and event shapes, no AI. */
function fakeNihonSub({ failWith } = {}) {
  const seen = { fields: [], bytes: 0 };
  const server = http.createServer((req, res) => {
    if (req.url === '/api/config') {
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ groqConfigured: true }));
    }
    if (req.method === 'POST' && req.url === '/api/process') {
      const chunks = [];
      req.on('data', (c) => chunks.push(c));
      req.on('end', () => {
        const body = Buffer.concat(chunks);
        seen.bytes = body.length;
        const text = body.toString('latin1');
        for (const m of text.matchAll(/name="(targetLang|hindiScript)"\r\n\r\n([^\r]*)/g)) seen.fields.push(`${m[1]}=${m[2]}`);
        seen.hasFile = text.includes('name="video"; filename="audio.mp3"');
        res.writeHead(200, { 'Content-Type': 'application/x-ndjson' });
        res.write(JSON.stringify({ type: 'progress', step: 'transcribe', percent: 40, message: 'Transcribing' }) + '\n');
        if (failWith) {
          res.write(JSON.stringify({ type: 'error', error: failWith }) + '\n');
          return res.end();
        }
        res.write(JSON.stringify({ type: 'progress', step: 'translate', percent: 80, message: 'Translating' }) + '\n');
        const lang = seen.fields.some((f) => f.startsWith('targetLang=hi')) ? 'hi' : 'en';
        res.write(JSON.stringify({ type: 'complete', percent: 100, data: { jobId: 'job1', subtitles: { [lang]: { srtUrl: `/api/subtitles/job1/${lang}/srt` } } } }) + '\n');
        res.end();
      });
      return;
    }
    if (req.url.startsWith('/api/subtitles/job1/')) {
      res.setHeader('Content-Type', 'text/plain');
      return res.end(SRT);
    }
    res.writeHead(404); res.end();
  });
  return { server, seen };
}

/** Serves one short MP3 tone with a Japanese-tagged audio track. */
function toneServer(dir) {
  const file = path.join(dir, 'tone.mp3');
  execFileSync('ffmpeg', ['-y', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3', '-metadata:s:a:0', 'language=jpn', file]);
  const server = http.createServer((req, res) => {
    if (req.url !== '/tone.mp3') { res.writeHead(404); return res.end(); }
    const data = fs.readFileSync(file);
    res.writeHead(200, { 'Content-Type': 'audio/mpeg', 'Content-Length': data.length });
    res.end(data);
  });
  return server;
}

async function api(port, method, route, body, token = TOKEN) {
  const res = await fetch(`http://127.0.0.1:${port}${route}`, {
    method,
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch {}
  return { status: res.status, json, text };
}

async function waitFor(port, id, states) {
  for (let i = 0; i < 100; i++) {
    const { json } = await api(port, 'GET', `/jobs/${id}`);
    if (states.includes(json.state)) return json;
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error('timed out waiting for ' + states.join('/'));
}

async function setup(options) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bridge-test-'));
  const fake = fakeNihonSub(options);
  const tone = toneServer(dir);
  const [fakePort, tonePort] = [await listen(fake.server), await listen(tone)];
  const bridge = createBridge({ token: TOKEN, nihonsubUrl: `http://127.0.0.1:${fakePort}`, tmpDir: dir });
  const bridgePort = await listen(bridge);
  const close = () => { for (const s of [bridge, fake.server, tone]) s.close(); fs.rmSync(dir, { recursive: true, force: true }); };
  return { bridgePort, tonePort, fake, close };
}

test('turns a link into subtitles', async () => {
  const t = await setup();
  try {
    const started = await api(t.bridgePort, 'POST', '/jobs', { url: `http://127.0.0.1:${t.tonePort}/tone.mp3`, language: 'en' });
    assert.equal(started.status, 202);
    const done = await waitFor(t.bridgePort, started.json.id, ['done', 'failed']);
    assert.equal(done.state, 'done', done.error);
    assert.equal(done.percent, 100);
    const srt = await api(t.bridgePort, 'GET', `/jobs/${started.json.id}/srt`);
    assert.equal(srt.status, 200);
    assert.equal(srt.text, SRT);
    assert.deepEqual(t.fake.seen.fields, ['targetLang=en']);
    assert.ok(t.fake.seen.hasFile, 'audio was uploaded as the video field');
    assert.ok(t.fake.seen.bytes > 1000, 'a real audio file was sent');
  } finally { t.close(); }
});

test('Hinglish asks NihonSub for Roman-script Hindi', async () => {
  const t = await setup();
  try {
    const started = await api(t.bridgePort, 'POST', '/jobs', { url: `http://127.0.0.1:${t.tonePort}/tone.mp3`, language: 'hinglish' });
    const done = await waitFor(t.bridgePort, started.json.id, ['done', 'failed']);
    assert.equal(done.state, 'done', done.error);
    assert.deepEqual(t.fake.seen.fields.sort(), ['hindiScript=hinglish', 'targetLang=hi']);
  } finally { t.close(); }
});

test('an error from NihonSub fails the job with its message', async () => {
  const t = await setup({ failWith: 'Transcription API key is missing.' });
  try {
    const started = await api(t.bridgePort, 'POST', '/jobs', { url: `http://127.0.0.1:${t.tonePort}/tone.mp3` });
    const done = await waitFor(t.bridgePort, started.json.id, ['done', 'failed']);
    assert.equal(done.state, 'failed');
    assert.match(done.error, /key is missing/);
    assert.equal((await api(t.bridgePort, 'GET', `/jobs/${started.json.id}/srt`)).status, 409);
  } finally { t.close(); }
});

test('a link that does not work fails cleanly', async () => {
  const t = await setup();
  try {
    const started = await api(t.bridgePort, 'POST', '/jobs', { url: `http://127.0.0.1:${t.tonePort}/missing.mp3` });
    const done = await waitFor(t.bridgePort, started.json.id, ['done', 'failed']);
    assert.equal(done.state, 'failed');
    assert.ok(done.error.length > 0);
  } finally { t.close(); }
});

test('needs the token, a web link and a known language', async () => {
  const t = await setup();
  try {
    assert.equal((await api(t.bridgePort, 'GET', '/health', null, 'wrong')).status, 401);
    assert.equal((await api(t.bridgePort, 'GET', '/health', null, '')).status, 401);
    assert.equal((await api(t.bridgePort, 'POST', '/jobs', { url: 'file:///etc/passwd' })).status, 400);
    assert.equal((await api(t.bridgePort, 'POST', '/jobs', { url: 'not a url' })).status, 400);
    assert.equal((await api(t.bridgePort, 'POST', '/jobs', { url: 'https://example.com/a.mkv', language: 'fr' })).status, 400);
    assert.equal((await api(t.bridgePort, 'GET', '/jobs/nope')).status, 404);
  } finally { t.close(); }
});

test('health reports FFmpeg and NihonSub', async () => {
  const t = await setup();
  try {
    const { status, json } = await api(t.bridgePort, 'GET', '/health');
    assert.equal(status, 200);
    assert.deepEqual(json, { ok: true, ffmpeg: true, nihonsub: true, configured: true });
  } finally { t.close(); }
});

test('health says when NihonSub is not running', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bridge-test-'));
  const bridge = createBridge({ token: TOKEN, nihonsubUrl: 'http://127.0.0.1:1', tmpDir: dir });
  const port = await listen(bridge);
  try {
    const { json } = await api(port, 'GET', '/health');
    assert.equal(json.nihonsub, false);
    assert.equal(json.configured, false);
  } finally { bridge.close(); fs.rmSync(dir, { recursive: true, force: true }); }
});
