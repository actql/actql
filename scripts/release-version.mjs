import assert from 'node:assert/strict';

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
