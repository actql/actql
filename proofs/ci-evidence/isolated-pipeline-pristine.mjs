// The registered pipeline phase uses the shared immutable scratch protocol.
// This is local physical evidence, not an Actions original or a reuse permit.
import assert from 'node:assert/strict';
import {cpSync, readdirSync, readFileSync, mkdirSync, writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {snapshot} from '../relation-pipeline/inventory.mjs';
import {validatePristineReport, readPristineFiles} from '../relation-pipeline/pristine-replay.mjs';
import {encode} from '../bounded-session/action-inputs.mjs';
import {observeImageRoot, platformInputs} from './isolated-runtime.mjs';

assert.equal(process.platform, 'linux'); assert.equal(process.arch, 'x64');
assert.equal(process.cwd(), '/workspace');
assert.equal(readdirSync('/workspace').length, 0, 'Isolated scratch must start empty');
const manifest = JSON.parse(readFileSync('/control/inputs.json'));
assert.equal(manifest.version, 'actql-isolated-pipeline-pristine-inputs/0.1');
assert.equal(manifest.localDiagnostic, true);
const observed = observeImageRoot('/'), platform = platformInputs();
assert.equal(encode(observed), encode(manifest.root));
assert.equal(encode(platform), encode(manifest.platformInputs));
const environment = Object.fromEntries(Object.keys(manifest.environment).map(name => [name, process.env[name]]));
assert.equal(encode(environment), encode(manifest.environment));
assert.deepEqual(Object.keys(process.env).filter(name => !Object.hasOwn(environment, name)).sort(), ['HOSTNAME']);
assert.equal(process.env.HOSTNAME, 'actql-session');
assert.throws(() => writeFileSync('/runtime/actql-write-probe', 'must fail', {flag: 'a'}), error => error.code === 'EROFS');
const shell = spawnSync('/bin/sh', ['-c', ':'], {env: process.env, encoding: 'utf8', timeout: 1000});
assert(!shell.error && shell.status === 0);
cpSync('/source', '/workspace', {recursive: true, preserveTimestamps: true, errorOnExist: true, force: false});
mkdirSync('/tmp/home', {recursive: true});
const before = snapshot('/workspace');
const result = spawnSync('/runtime/node', ['proofs/relation-pipeline/pristine-replay.mjs'], {
  cwd: '/workspace', env: process.env, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, timeout: 10 * 60 * 1000,
});
process.stdout.write(result.stdout ?? ''); process.stderr.write(result.stderr ?? '');
assert(!result.error && result.status === 0, 'Original pipeline pristine phase failed');
const prefix = 'ACTQL_PIPELINE_PRISTINE ';
const records = result.stdout.split('\n').filter(line => line.startsWith(prefix)); assert.equal(records.length, 1);
const summary = JSON.parse(records[0].slice(prefix.length));
assert(/^\/workspace\/\.artifacts\/pipeline-pristine\/replay-[a-f0-9-]+\.json$/u.test(summary.path));
const report = JSON.parse(readFileSync(summary.path));
const files = readPristineFiles('/workspace', report);
validatePristineReport(report, before, files);
assert.deepEqual(snapshot('/workspace'), before);
assert.equal(encode(observeImageRoot('/')), encode(observed));
console.log(`ACTQL_ISOLATED_PIPELINE_PRISTINE ${JSON.stringify({version: 'actql-isolated-pipeline-pristine-observation/0.1',
  report, files, sourcePreserved: true, readOnlyConfirmed: true, shellStartupConfirmed: true,
  root: observed, platformInputs: platform, environment, reuseAuthorized: false})}`);
