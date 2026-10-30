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

export function compareReleaseVersions(left, right) {
  releaseVersion(left); releaseVersion(right);
  const a = left.split(/[.-]/u), b = right.split(/[.-]/u);
  const order = (x, y) => x < y ? -1 : x > y ? 1 : 0;
  for (let index = 0; index < 3; index++) {
    const result = order(BigInt(a[index]), BigInt(b[index]));
    if (result) return result;
  }
  if (a.length === 3 || b.length === 3) return order(a.length === 3 ? 1 : 0, b.length === 3 ? 1 : 0);
  const stages = ['alpha', 'beta', 'rc'];
  return order(stages.indexOf(a[3]), stages.indexOf(b[3])) || order(BigInt(a[4]), BigInt(b[4]));
}

// Build-time Python tooling consumes this same projection; installed consumers
// do not need Node and do not execute this source-repository command.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 3, 'Supply one complete explicit release version');
  console.log(JSON.stringify(releaseVersion(process.argv[2])));
}
