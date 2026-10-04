// This file runs inside the immutable image only. Mutable sources/build output
// live in an initially empty tmpfs; neither the host checkout nor a cache is
// mounted. Keep the original mutation executor and its assertion requirements.
import assert from 'node:assert/strict';
import {cpSync, readdirSync, readFileSync, mkdirSync, writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {snapshot} from '../bounded-session/evidence.mjs';
import {encode} from '../bounded-session/action-inputs.mjs';
import {observeImageRoot, platformInputs} from './isolated-runtime.mjs';

assert.equal(process.platform, 'linux'); assert.equal(process.arch, 'x64');
assert.equal(process.cwd(), '/workspace');
assert.equal(readdirSync('/workspace').length, 0, 'Isolated scratch must start empty');
assert.equal(process.env.MOON_HOME, '/runtime/moonbit');
assert.equal(process.env.PATH, '/runtime/moonbit/bin:/runtime');
const manifest = JSON.parse(readFileSync('/control/inputs.json', 'utf8'));
const observed = observeImageRoot('/'), platform = platformInputs();
assert.equal(encode(observed), encode(manifest.root), 'Image differs from staged immutable input bytes');
assert.equal(encode(platform), encode(manifest.platformInputs), 'Image runs under different kernel/CPU inputs');
const environment = Object.fromEntries(Object.keys(manifest.environment).map(name => [name, process.env[name]]));
assert.equal(encode(environment), encode(manifest.environment));
assert.deepEqual(Object.keys(process.env).filter(name => !Object.hasOwn(environment, name)).sort(), ['HOSTNAME'], 'Unexpected inherited container environment');
assert.equal(process.env.HOSTNAME, 'actql-session');
// This assertion is an actual write attempt, not a copied isolation label.
assert.throws(() => writeFileSync('/runtime/actql-write-probe', 'must fail', {flag: 'a'}),
  error => error.code === 'EROFS', 'Runtime must be immutable during execution');
cpSync('/source', '/workspace', {recursive: true, preserveTimestamps: true, errorOnExist: true, force: false});
mkdirSync('/tmp/home', {recursive: true});
const before = snapshot('/workspace');
const result = spawnSync('/runtime/node', ['proofs/bounded-session/mutations.mjs'], {
  cwd: '/workspace', env: process.env, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
  timeout: 10 * 60 * 1000,
});
process.stdout.write(result.stdout ?? ''); process.stderr.write(result.stderr ?? '');
assert(!result.error && result.status === 0, 'Original isolated mutation action failed');
assert.equal(snapshot('/workspace').digest, before.digest, 'Isolated mutation bytes were not restored');
const report = JSON.parse(readFileSync('/workspace/.artifacts/bounded-session/mutations.json', 'utf8'));
assert.equal(report.source.digest, before.digest);
assert.equal(encode(observeImageRoot('/')), encode(observed), 'Immutable inputs changed during execution');
const logs = Object.fromEntries(report.results.map(entry => {
  assert(/^[a-z0-9-]+$/u.test(entry.id));
  return [entry.id, readFileSync(`/workspace/.artifacts/bounded-session/mutation-${entry.id}.log`, 'utf8')];
}));
// The host seals the normal receipt and independently checks its required IDs
// and nonzero assertion failures. No CI token/credentials exist in this process.
console.log(`ACTQL_ISOLATED_MUTATIONS ${JSON.stringify({version: 'actql-isolated-mutation-observation/0.1',
  report, logs, restored: true, readOnlyConfirmed: true, root: observed, platformInputs: platform, environment})}`);
