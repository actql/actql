import assert from 'node:assert/strict';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

// Package versions are independent of language/protocol/ABI/CID versions.
// No relative bump, whitespace normalization or implicit next version exists.
export function releaseVersion(value) {
  assert.equal(typeof value, 'string', 'A complete explicit release version is required');
  const match = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(alpha|beta|rc)\.(0|[1-9][0-9]*))?$/u.exec(value);
  assert(match && match[0] === value, 'Use X.Y.Z or X.Y.Z-alpha.N, -beta.N, -rc.N without build metadata');
  const [, major, minor, patch, stage, serial] = match;
  const base = `${major}.${minor}.${patch}`;
  const suffix = stage ? {alpha: 'a', beta: 'b', rc: 'rc'}[stage] + serial : '';
  return Object.freeze({version: value, pythonVersion: base + suffix,
    line: `${major}.${minor}`, gitTag: `v${value}`, prerelease: stage !== undefined});
}

// Build-time Python tooling consumes this same projection; installed consumers
// do not need Node and do not execute this source-repository command.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 3, 'Supply one complete explicit release version');
  console.log(JSON.stringify(releaseVersion(process.argv[2])));
}
