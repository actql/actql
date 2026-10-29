// Async child mechanics from A's warm-plus-saved consumer. The parent must
// keep serving provider TLS. Existing caller guards own the whole-child limit.
// A successful process is never an Account/Client/Run/close acknowledgement.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {stat} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {saveInstalledFamilyObservation as save} from './installed-family-read.fixture.mjs';

const ownText = (error, name, limit) => {
  const field = Object.getOwnPropertyDescriptor(error, name);
  return typeof field?.value === 'string' ? field.value.slice(0, limit) : null;
};

export async function runInstalledFamilyProcess({script, args = [], cwd, env,
  output, maxOutputBytes = 1048576}) {
  for (const path of [script, cwd, output]) assert.equal(typeof path, 'string');
  assert([script, cwd, output].every(isAbsolute));
  assert(Array.isArray(args) && args.every(value => typeof value === 'string'));
  assert(env !== null && typeof env === 'object');
  assert(Object.values(env).every(value => typeof value === 'string'));
  assert(Number.isSafeInteger(maxOutputBytes) && maxOutputBytes > 0 && maxOutputBytes <= 1048576);
  assert((await stat(script)).isFile(), 'Selected child source must exist before any process starts');
  assert((await stat(cwd)).isDirectory());
  const startedAt = new Date().toISOString();
  const result = await new Promise(resolve => {
    const child = spawn(process.execPath, [script, ...args], {cwd, env,
      stdio: ['ignore', 'pipe', 'pipe']});
    let spawnError = null;
    const streams = {stdout: {pieces: [], bytes: 0, retained: 0},
      stderr: {pieces: [], bytes: 0, retained: 0}};
    for (const name of Object.keys(streams)) child[name].on('data', chunk => {
      const stream = streams[name];
      stream.bytes += chunk.byteLength;
      const keep = Math.min(chunk.byteLength, maxOutputBytes - stream.retained);
      if (keep > 0) {stream.pieces.push(Buffer.from(chunk.subarray(0, keep))); stream.retained += keep;}
    });
    child.once('error', error => {spawnError = {name: ownText(error, 'name', 100),
      code: ownText(error, 'code', 200), message: ownText(error, 'message', 2000)};});
    child.once('close', (code, signal) => {
      const data = {};
      for (const [name, stream] of Object.entries(streams)) {
        const bytes = Buffer.concat(stream.pieces, stream.retained);
        data[name] = bytes.toString('utf8');
        data[name + 'Base64'] = bytes.toString('base64');
        data[name + 'Bytes'] = stream.bytes;
        data[name + 'RetainedBytes'] = stream.retained;
      }
      resolve({kind: 'installed-family-process/0.1', pid: child.pid ?? null,
        parentPid: process.pid, code, signal, spawnError, startedAt,
        endedAt: new Date().toISOString(), processClosed: true,
        truncated: Object.values(streams).some(stream => stream.bytes > stream.retained), ...data});
    });
  });
  // Preserve the original process outcome before stopping the caller. The
  // actual public first-close and original Run/Result oracles stay separate.
  await save(output, result);
  if (result.spawnError !== null || result.code !== 0 || result.signal !== null || result.truncated) {
    const error = new Error('InstalledFamilyChildProcessFailed');
    error.processReportPath = output;
    throw error;
  }
  assert(Number.isSafeInteger(result.pid) && result.pid > 0 && result.pid !== process.pid);
  return result;
}
