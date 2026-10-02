// Keep the corrected delayed-stop regression separate from capacity evidence.
// The historical counterexample was parent=3, child=4; no claim is broadened.
import { existsSync, mkdirSync, readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { snapshot } from './evidence.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const pin = JSON.parse(readFileSync(join(root, 'toolchain.json')));
const home = process.env.MOON_HOME ?? join(root, '.toolchains', `moonbit-${pin.version}`);
const directory = join(root, '.artifacts/relation-capacity'); mkdirSync(directory, { recursive: true });
const fixture = 'proofs/relation-capacity/fixtures/delayed-stop.mbt';
const path = 'src/query_integration/relation_capacity_delayed_stop_repro_wbtest.mbt';
const file = join(root, path), body = readFileSync(join(root, fixture));
if (existsSync(file)) throw new Error('Do not overwrite an existing reproduction');
const before = snapshot(root);
let result;
try {
  writeFileSync(file, body, { flag: 'wx' });
  result = spawnSync(join(home, 'bin/moon'), ['test', path, '--target', 'js', '--deny-warn'], {
    cwd: root, env: { ...process.env, MOON_HOME: home, PATH: `${home}/bin:${process.env.PATH}` },
    encoding: 'utf8', maxBuffer: 8 * 1024 * 1024,
  });
} finally {
  // Remove only this runner's newly created test copy; the fixed repro source
  // and all logs are retained. No old worktree/artifact is cleaned up.
  if (existsSync(file)) unlinkSync(file);
}
const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
writeFileSync(join(directory, 'delayed-stop-repro.log'), output);
const match = output.match(/DELAYED_STOP_RECEIPT parent=(\d+) child=(\d+) stop_polls=(\d+)/);
if (result.error || result.status !== 0 || !match || !/Total tests: 1, passed: 1, failed: 0/.test(output) ||
    /Error: \[\d+\]/.test(output) || match[1] !== '4' || match[2] !== '4' || match[3] !== '3') {
  throw result.error ?? new Error(`Delayed-stop accounting regression failed\n${output}`);
}
if (snapshot(root).digest !== before.digest) throw new Error('Reproduction did not restore source tree');
writeFileSync(join(directory, 'delayed-stop-repro.json'), `${JSON.stringify({
  kind: 'runtime-regression', capacityEvidence: false, source: before, fixture,
  fixtureDigest: createHash('sha256').update(body).digest('hex'), executionPath: path,
  target: 'js', expectedFailure: false, parentWork: 4, childWork: 4, configuredComputeBudget: 1,
  stopPolls: 3, computeCalls: 1,
  historicalCounterexample: {parentWork: 3, childWork: 4},
  contract: 'max_work admits Compute/handoff; mandatory stop deltas remain accounted without reopening admission',
  unresolved: 'arbitrary delayed-stop provider liveness and allocation bounds are not certified by this regression',
}, null, 2)}\n`);
console.log('Registered delayed-stop regression passed: parent=4, child=4, Compute=1; excluded from capacity proof');
