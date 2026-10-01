// The same source-free Values document as the packed Remote HTTP acceptance,
// exercised through a repository-external, MoonBit-free Embedded Local install.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {readdirSync} from 'node:fs';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {userInfo} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {canonicalText} from './check-canonical-json.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {packedClientPackage} from './packed-client-packages.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const externalScratch = join(repository, '..', '.codex-scratch');
await mkdir(externalScratch, {recursive: true});
// The installation, states and logs of this run; removed after it passed.
const scratch = await createOwnedScratch({parent: externalScratch,
  prefix: 'embedded-checkpoint-package-',
  label: 'packed Embedded Local Checkpoint',
  digests: () => readdirSync(root).filter(name => name.endsWith('.tgz'))
    .sort()});
const root = scratch.path;
const environment = {...process.env,
  npm_config_cache: join(externalScratch, 'npm-cache')};

function run(command, args, cwd = root, env = environment) {
  const result = spawnSync(command, args, {cwd, env, encoding: 'utf8',
    timeout: command === 'npm' && args[0] === 'pack' ? 600000 : 120000});
  if (result.error || result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed:\n` +
      `${result.stdout}\n${result.stderr}`, {cause: result.error});
  }
  return result.stdout;
}

for (const name of ['client-wire', 'sdk', 'run-host-core', 'local-node',
  'node']) {
  await packedClientPackage({repository, name, destination: root,
    pack: () => run('npm', ['pack', '--pack-destination', root, '--json'],
      join(repository, 'packages', name))});
}
await writeFile(join(root, 'package.json'),
  '{"private":true,"type":"module"}\n');
run('npm', ['install', '--ignore-scripts', '--no-save', ...[
  'client-wire', 'sdk', 'run-host-core', 'local-node', 'node'].map(name =>
  join(root, `actql-${name}-0.0.0-development.tgz`))]);

const document = await readFile(join(repository,
  'packages/sdk/fixtures/values.json'), 'utf8');
await writeFile(join(root, 'values.json'), document);
await writeFile(join(root, 'expected.json'), JSON.stringify(
  JSON.parse(document).stages[0].steps[0].values.rows));
await writeFile(join(root, 'embedded-client.mjs'), await readFile(join(
  repository, 'scripts/fixtures/packed-embedded-checkpoint.mjs')));

const reviewer = generateKeyPairSync('ed25519');
const host = generateKeyPairSync('ed25519');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});
await writeFile(join(root, 'reviewer.key'), pem(reviewer.privateKey),
  {mode: 0o600});
await writeFile(join(root, 'authorization.json'), JSON.stringify({
  accountConfiguration: canonicalText({
    version: 'actql-execution-account-config/0.1',
    account_id: 'packed-embedded-account', entries: [{
      entry_id: 'run-acceptance', exclusions: [],
      connection: {any_of: ['actql-remote-host']},
      operation: {any_of: ['write']}, outcome: 'delegate',
      principal: {all: true},
      resource: {any_of: ['source-free-values']},
    }],
  }),
  reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
    principalId: userInfo().username, publicKey: pem(reviewer.publicKey)}],
  reviewReaders: [userInfo().username],
  hostKey: {keyId: 'host-key', privateKey: pem(host.privateKey)},
  leaseMs: 10000,
}));

// Deliberately remove MoonBit and the checkout from the child's lookup path.
const childEnvironment = {...environment,
  PATH: [dirname(process.execPath), '/usr/bin', '/bin'].join(':')};
for (const [step, expected] of [['hold', 'held'],
  ['approve', 'approved'], ['resume', 'published'],
  ['recheck', 'published']]) {
  assert.equal(run(process.execPath, ['embedded-client.mjs', step], root,
    childEnvironment).trim(), expected);
}
const events = (await readFile(join(root, 'embedded-events.log'), 'utf8'))
  .split('\n').filter(Boolean);
assert.equal(events.filter(event => event === 'computed').length, 1);
assert.equal(events.filter(event => event === 'physical_start_reserved').length,
  1);
console.log('packed Embedded Local Checkpoint approval, restart and ' +
  'Named Result passed');
// Every child ran to completion through spawnSync.
scratch.passed();
