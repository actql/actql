// Owned execution-log capture outside semantic/cleanup boundaries. No exporter.
import assert from 'node:assert/strict';
import {writeFile, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {performance} from 'node:perf_hooks';
import {captureModes, profileDigest} from './local-performance-profile.mjs';

export const captureLimitBytes = 2 * 1024 * 1024;

export async function captureLocalExecution(options) {
  const {mode, directory, maxBytes = captureLimitBytes} = options;
  assert(captureModes.includes(mode));
  assert(Number.isSafeInteger(maxBytes) && maxBytes > 0 && maxBytes <= captureLimitBytes);
  if (mode === 'off') return {status: 'omitted', bytes: 0, elapsedMs: 0, files: []};
  const started = performance.now();
  let bytes = 0;
  const files = [];
  try {
    const {metadata} = options;
    const members = [['capture-metadata.json', JSON.stringify(metadata) + '\n'],
      ...(mode === 'evidence-enabled' ? [['stdout.log', options.stdout], ['stderr.log', options.stderr]] : [])];
    const total = members.reduce((sum, [, contents]) => sum + Buffer.byteLength(contents), 0);
    if (total > maxBytes) return {status: 'missing', reason: 'capture-byte-limit', bytes: 0,
      elapsedMs: performance.now() - started, files: []};
    for (const [path, content] of members) {
      await writeFile(join(directory, path), content, {flag: 'wx', mode: 0o600});
      const original = Buffer.from(content), stored = await readFile(join(directory, path));
      assert(stored.equals(original), 'CaptureReadbackMismatch');
      bytes += stored.length; files.push({path, bytes: stored.length, digest: profileDigest(stored)});
    }
    return {status: 'complete', bytes, files, elapsedMs: performance.now() - started,
      scope: 'synthetic fixture execution metadata; evidence mode additionally preserves actual admitted stdout/stderr; no row payload capture'};
  } catch {
    return {status: 'failed', reason: 'local-sink-failed', bytes, files,
      elapsedMs: performance.now() - started};
  }
}
