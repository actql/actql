// The packed Local Host reading an installed Salesforce source, installed
// outside this checkout and run without MoonBit: publish, a restarted Host
// that restores the publication without provider I/O, discovery, a Program's
// acquisition and computation, and the Named Result. The org is a local HTTPS
// mock; the `sf` CLI is a stand-in that returns a test-only token.
import assert from 'node:assert/strict';
import {execFileSync, spawn, spawnSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {canonicalJson} from '../adapters/host-node/local-account-config.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
await mkdir(build, {recursive: true});
// Outside the checkout: nothing under it can fill in a missing file.
const externalScratch = join(repository, '..', '.codex-scratch');
await mkdir(externalScratch, {recursive: true});
const root = await mkdtemp(join(externalScratch, 'actql-packed-salesforce-'));
const orgId = '00D000000000001EAA';
const token = 'packed-test-only-token';

function run(command, args, cwd, env = {...process.env,
  npm_config_cache: join(build, 'npm-cache')}) {
  const result = spawnSync(command, args, {cwd, env, encoding: 'utf8',
    timeout: command === 'npm' && args[0] === 'pack' ? 600000 : 120000});
  if (result.error || result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed:\n` +
      `${result.stdout}\n${result.stderr}`, {cause: result.error});
  }
  return result.stdout;
}

// A child that talks to the mock org served by this process: it must not
// block this process's event loop.
function runChild(script, env, args = []) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script, ...args], {cwd: root, env});
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    const timer = setTimeout(() => child.kill('SIGKILL'), 120000);
    child.on('error', reject);
    child.on('close', code => {
      clearTimeout(timer);
      if (code === 0) resolve(stdout);
      else reject(new Error(`${script} failed:\n${stdout}\n${stderr}`));
    });
  });
}

const server = await (async () => {
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'org.key', '-out', 'org.crt', '-days', '1',
    '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
  {cwd: root, stdio: 'ignore'});
  const seen = [];
  const prefix = '/services/data/v62.0/';
  const records = [1, 2, 3].map(index => ({Id: `a0000000000000${index}`,
    Name: `record-${index}`, External_Key__c: `key-${index}`}));
  const https = createServer({key: await readFile(join(root, 'org.key')),
    cert: await readFile(join(root, 'org.crt'))}, (request, response) => {
    seen.push({method: request.method,
      path: decodeURIComponent(request.url ?? '').split('?')[0]});
    if (request.headers.authorization !== `Bearer ${token}`) {
      response.writeHead(401).end();
      return;
    }
    const json = value => {
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify(value));
    };
    if (request.url === `${prefix}sobjects/Test_Record__c/describe`) {
      json({name: 'Test_Record__c', queryable: true, createable: true,
        updateable: true, fields: [
          {name: 'Id', type: 'id', nillable: false, sortable: false},
          {name: 'Name', type: 'string', nillable: false,
            defaultedOnCreate: false, createable: true, updateable: true},
          {name: 'External_Key__c', type: 'string', externalId: true,
            unique: true, caseSensitive: true, nillable: false,
            defaultedOnCreate: false, createable: true, updateable: true},
        ]});
      return;
    }
    const query = /^SELECT ([A-Za-z_,]+) FROM Test_Record__c$/u.exec(
      decodeURIComponent((request.url ?? '').slice(`${prefix}query?q=`
        .length)));
    if (request.url?.startsWith(`${prefix}query?q=`) && query) {
      json({totalSize: records.length, done: true, records: records.map(
        record => Object.fromEntries([['attributes',
          {type: 'Test_Record__c'}], ...query[1].split(',').map(name =>
          [name, record[name]])]))});
      return;
    }
    if (request.method === 'GET' && request.url?.startsWith(
      `${prefix}sobjects/Test_Record__c/`)) {
      const id = decodeURIComponent(request.url.slice(
        `${prefix}sobjects/Test_Record__c/`.length));
      json({Id: id, Name: 'prior-name', External_Key__c: id});
      return;
    }
    if (request.method === 'PATCH' && request.url?.startsWith(
      `${prefix}sobjects/Test_Record__c/`)) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.on('end', () => {
        const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        assert.deepEqual(Object.keys(body), ['Name']);
        response.writeHead(204).end();
      });
      return;
    }
    response.writeHead(404).end();
  });
  await new Promise(resolve => https.listen(0, '127.0.0.1', resolve));
  return {seen, origin: `https://127.0.0.1:${https.address().port}`,
    close: () => new Promise(resolve => https.close(resolve))};
})();

try {
  const artifacts = [];
  for (const name of ['client-wire', 'sdk', 'local-node', 'node']) {
    const packed = JSON.parse(run('npm', ['pack', '--pack-destination', root,
      '--json'], join(repository, 'packages', name)));
    artifacts.push(join(root, packed[0]?.filename ??
      packed[`@actql/${name}`]?.filename));
  }
  await writeFile(join(root, 'package.json'),
    '{"private":true,"type":"module"}\n');
  run('npm', ['install', '--ignore-scripts', '--no-save', ...artifacts],
    root);
  assert((await readFile(join(root, 'node_modules/@actql/local-node',
    '_build/js/release/build/connectors/salesforce/host_node/host_node.js')))
    .byteLength > 0);

  // The installed Site (secret references only) and the Host source profile.
  const authority = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential.key'), authority.privateKey.export({
    type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  await writeFile(join(root, 'site.json'), JSON.stringify({
    version: 'actql-installed-salesforce-site/0.1', apiVersion: 'v62.0',
    cliAlias: 'actql-packed', cliUsername: 'packed@example.test',
    connectionRevision: 'packed-connection-a',
    credentialAuthorityId: 'packed-authority', credentialKeyId: 'packed-key',
    credentialPrivateKeyPath: join(root, 'credential.key'),
    environment: 'packed', instanceOrigin: server.origin,
    journalRoot: join(root, 'credential-journal'), orgId, siteGeneration: 1,
    siteKey: 'packed-site', tenant: 'packed-tenant',
    caPath: join(root, 'org.crt')}));
  await writeFile(join(root, 'source.json'), JSON.stringify({
    version: 'actql-installed-salesforce-source/0.1',
    siteProfilePath: join(root, 'site.json'),
    publicationPath: join(root, 'publication.json'),
    connectorId: 'crm-main', resources: ['Test_Record__c'],
    accountConfigurationWire: canonicalJson({
      version: 'actql-execution-account-config/0.1',
      account_id: 'packed-account', entries: [{entry_id: 'records-read',
        outcome: 'allow', exclusions: [], principal: {all: true},
        connection: {any_of: [`salesforce:${orgId}`]},
        resource: {any_of: ['Test_Record__c']},
        operation: {any_of: ['read']}}]})}));
  // A stand-in `sf` CLI: the org binding and a test-only token.
  await mkdir(join(root, 'bin'));
  await writeFile(join(root, 'bin', 'sf'), `#!/bin/sh
case "$2" in
  display) printf '%s' '{"status":0,"result":{"alias":"actql-packed","id":"${orgId}","username":"packed@example.test","instanceUrl":"${server.origin}","connectedStatus":"Connected"}}' ;;
  auth) printf '%s' '{"status":0,"result":{"accessToken":"${token}"}}' ;;
  *) exit 1 ;;
esac
`, {mode: 0o755});
  // No MoonBit on PATH and no checkout paths: only the installed packages.
  const childEnvironment = {HOME: process.env.HOME,
    PATH: [join(root, 'bin'), dirname(process.execPath), '/usr/bin', '/bin']
      .join(':'),
    ACTQL_LOCAL_STATE_DIR: join(root, 'state'),
    ACTQL_LOCAL_SOURCE_PROFILE: join(root, 'source.json')};
  await writeFile(join(root, 'publish.mjs'), `
import {publishSource} from '@actql/local-node';
const published = await publishSource();
console.log(published.declared.catalog_cid);
`);
  await writeFile(join(root, 'read.mjs'), `
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {connect} from '@actql/local-node';
const client = await connect({mode: 'local', owner: 'local',
  durability: 'durable',
  ...(process.env.ACTQL_LOCAL_EFFECT_PROFILE === undefined ? {} : {
    installation: {
      directory: process.env.ACTQL_LOCAL_STATE_DIR,
      sourceProfilePath: process.env.ACTQL_LOCAL_SOURCE_PROFILE,
      effectProfilePath: process.env.ACTQL_LOCAL_EFFECT_PROFILE,
      authorization: JSON.parse(readFileSync('authorization.json', 'utf8')),
    }}),
});
try {
  const listing = await client.resources('salesforce:${orgId}');
  assert.deepEqual(listing.resources,
    [{name: 'Test_Record__c', outcome: 'described'}]);
  process.stdout.write('discovered\\n');
  const program = JSON.stringify({version: 'actql/0.1', id: 'packed-read',
    stages: [
      {id: 'acquire',
        inputs: {remote: {connector: 'crm-main', resource: 'Test_Record__c'}},
        steps: [{filter: "Name <> 'record-2'", as: 'filtered'},
          {select: ['Id', 'Name', 'External_Key__c'], as: 'captured'}],
        results: {r: {from: 'captured',
          fields: ['Id', 'Name', 'External_Key__c']}}},
      {id: 'compute', inputs: {x: {result: {stage: 'acquire', result: 'r'}}},
        steps: [{select: ['External_Key__c', 'Name'], as: 'out'}],
        results: {r: {from: 'out', fields: ['External_Key__c', 'Name']}}}],
    results: {records: {from: {stage: 'compute', result: 'r'}}}});
  const execution = await client.aql(program, {format: 'json',
    requestId: process.env.ACTQL_LOCAL_EFFECT_PROFILE === undefined
      ? 'packed-read-1' : 'packed-coinstalled-read'});
  assert.equal((await execution.wait()).status, 'succeeded');
  const rows = await execution.result('records').all();
  process.stdout.write(JSON.stringify(rows.map(row =>
    [row.External_Key__c, row.Name]).sort()) + '\\n');
} finally { await client.close(); }
`);
  const catalogCid = (await runChild('publish.mjs', childEnvironment)).trim();
  assert.match(catalogCid, /^sha256:[0-9a-f]{64}$/u);
  assert.deepEqual(server.seen.map(item => item.path), [
    '/services/data/v62.0/sobjects/Test_Record__c/describe']);
  // A new process: the Host restores the publication without provider I/O
  // and discovery answers from it; only the Program's acquisition reads.
  const output = (await runChild('read.mjs', childEnvironment))
    .trim().split('\n');
  assert.equal(output[0], 'discovered');
  assert.deepEqual(JSON.parse(output[1]),
    [['key-1', 'record-1'], ['key-3', 'record-3']]);
  assert.deepEqual(server.seen.slice(1).map(item => item.path), [
    '/services/data/v62.0/sobjects/Test_Record__c/describe',
    '/services/data/v62.0/sobjects/Test_Record__c/describe',
    '/services/data/v62.0/query']);
  console.log('packed Local Host Salesforce publish, restart, discovery and ' +
    'Named Result passed');

  // The installed Effect's explicit publication: one generation of its
  // declaration, execution Mapping and Check Environment, from the package.
  const reviewer = generateKeyPairSync('ed25519');
  const host = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'reviewer.key'), reviewer.privateKey.export({
    type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  const effectAccount = canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'packed-effect-account', entries: [
      {entry_id: 'effect-commit', outcome: 'delegate', exclusions: [],
        principal: {all: true},
        connection: {any_of: [`salesforce:${orgId}`]},
        resource: {any_of: ['Test_Record__c']},
        operation: {any_of: ['effect']}},
      {entry_id: 'host-run', outcome: 'allow', exclusions: [],
        principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['write']}},
      {entry_id: 'target-read', outcome: 'allow', exclusions: [],
        principal: {all: true},
        connection: {any_of: [`salesforce:${orgId}`]},
        resource: {any_of: ['Test_Record__c']},
        operation: {any_of: ['read']}},
    ]});
  await writeFile(join(root, 'authorization.json'), JSON.stringify({
    accountConfiguration: effectAccount,
    reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
      principalId: userInfo().username,
      publicKey: reviewer.publicKey.export({type: 'spki', format: 'pem'})}],
    reviewReaders: [userInfo().username],
    hostKey: {keyId: 'host-key', privateKey: host.privateKey.export({
      type: 'pkcs8', format: 'pem'})},
    leaseMs: 10000,
    resumeAfterAnswer: false,
  }));
  await writeFile(join(root, 'effect.json'), JSON.stringify({
    version: 'actql-installed-salesforce-effect/0.1',
    siteProfilePath: join(root, 'site.json'),
    publicationPath: join(root, 'effect-publication.json'),
    connectorId: 'crm-main',
    writes: [{resource: 'Test_Record__c', kind: 'update', fields: ['Name']}],
    accountConfigurationWire: effectAccount}));
  const alternateSource = JSON.parse(await readFile(join(root,
    'source.json'), 'utf8'));
  alternateSource.accountConfigurationWire = canonicalJson({
    ...JSON.parse(alternateSource.accountConfigurationWire),
    account_id: 'changed-source-account',
  });
  await writeFile(join(root, 'source-foreign.json'),
    JSON.stringify(alternateSource));
  const alternateEffect = JSON.parse(await readFile(join(root,
    'effect.json'), 'utf8'));
  alternateEffect.accountConfigurationWire = canonicalJson({
    ...JSON.parse(alternateEffect.accountConfigurationWire),
    account_id: 'changed-effect-account',
  });
  await writeFile(join(root, 'effect-foreign.json'),
    JSON.stringify(alternateEffect));
  await writeFile(join(root, 'publish-effect.mjs'), `
import {publishEffect} from '@actql/local-node';
const published = await publishEffect();
console.log(JSON.stringify(published.mappings.map(mapping =>
  [mapping.resource, mapping.kind])));
`);
  const effectEnvironment = {...childEnvironment};
  effectEnvironment.ACTQL_LOCAL_EFFECT_PROFILE = join(root, 'effect.json');
  const effect = JSON.parse((await runChild('publish-effect.mjs',
    effectEnvironment)).trim());
  assert.deepEqual(effect, [['Test_Record__c', 'update']]);
  const generation = JSON.parse(await readFile(join(root,
    'effect-publication.json'), 'utf8'));
  assert.deepEqual(Object.keys(generation),
    ['environment_cid', 'mappings', 'source', 'version']);
  assert.deepEqual(server.seen.slice(4).map(item => item.path), [
    '/services/data/v62.0/sobjects/Test_Record__c/describe']);
  console.log('packed Local Host Salesforce Effect publication passed');

  const coinstalledRead = (await runChild('read.mjs', effectEnvironment))
    .trim().split('\n');
  assert.equal(coinstalledRead[0], 'discovered');
  assert.deepEqual(JSON.parse(coinstalledRead[1]),
    [['key-1', 'record-1'], ['key-3', 'record-3']]);
  console.log('packed Local Host coinstalled Source and Effect read passed');

  // Every step runs in a fresh process with only the installed tarballs.
  // The same public @actql/node connect() path handles submission, review,
  // recovery and the Named Result without a MoonBit toolchain.
  await writeFile(join(root, 'effect-run.mjs'), `
import assert from 'node:assert/strict';
import {createPrivateKey, sign} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {connect} from '@actql/node';
const authorization = JSON.parse(readFileSync('authorization.json', 'utf8'));
authorization.resumeAfterAnswer = process.argv[2] === 'resume';
const client = await connect({mode: 'local', owner: 'local',
  durability: 'durable', installation: {
    directory: process.env.ACTQL_LOCAL_STATE_DIR,
    sourceProfilePath: process.env.ACTQL_LOCAL_SOURCE_PROFILE,
    effectProfilePath: process.env.ACTQL_LOCAL_EFFECT_PROFILE,
    authorization,
  }});
const pause = () => new Promise(resolve => setTimeout(resolve, 50));
async function waitFor(check) {
  for (let attempt = 0; attempt < 400; attempt++) {
    const value = await check();
    if (value) return value;
    await pause();
  }
  throw new Error('PackedEffectTimeout');
}
try {
  const step = process.argv[2];
  if (step === 'identity') {
    const installation = {
      directory: process.env.ACTQL_LOCAL_STATE_DIR,
      sourceProfilePath: process.env.ACTQL_LOCAL_SOURCE_PROFILE,
      effectProfilePath: process.env.ACTQL_LOCAL_EFFECT_PROFILE,
      authorization,
    };
    const same = await connect({mode: 'local', owner: 'local',
      durability: 'durable', installation: {...installation}});
    await same.close();
    for (const changed of [{sourceProfilePath: resolve(
      'source-foreign.json')}, {effectProfilePath: resolve(
      'effect-foreign.json')}]) {
      await assert.rejects(connect({mode: 'local', owner: 'local',
        durability: 'durable', installation: {...installation,
          ...changed}}),
      {name: 'TypeError', message: 'InstalledHostConfigurationMismatch'});
    }
    console.log('identity-refused');
  } else if (step === 'submit') {
    const generation = JSON.parse(readFileSync('effect-publication.json',
      'utf8'));
    const mapping = generation.mappings[0].mapping_ref;
    const program = {version: 'actql/0.1', id: 'packed-effect', stages: [{
      id: 'source', inputs: {},
      steps: [{values: {schema: {id: {type: 'string', nullable: false}},
        rows: [{id: 'a00000000000001'}, {id: 'a00000000000002'}]},
        as: 'selected'}],
      results: {rows: {from: 'selected', fields: ['id']}},
      effects: {save: {update: {
        target: 'connector://crm-main/Test_Record__c', mapping,
        from: {result: 'rows'}, id: 'id', set: {Name: {field: 'id'}}}}},
    }], results: {answer: {from: {stage: 'source', result: 'rows'}}}};
    const execution = await client.aql(JSON.stringify(program), {
      format: 'json', requestId: 'packed-effect-1'});
    await waitFor(async () => (await execution.status()).status ===
      'waiting_checkpoint');
    writeFileSync('effect-ref.json', JSON.stringify(execution.ref));
    console.log('held');
  } else if (step === 'answer') {
    const ref = JSON.parse(readFileSync('effect-ref.json', 'utf8'));
    const [checkpoint] = (await client.checkpoints()).items;
    assert.equal(checkpoint.kind, 'effect_set');
    const key = createPrivateKey(readFileSync('reviewer.key', 'utf8'));
    const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
      authorityScopeCid: ref.authorityScopeCid,
      sign: bytes => sign(null, bytes, key)};
    const answer = await client.resolveCheckpoints([
      {checkpoint, decision: 'approved'}], {signer});
    assert.deepEqual(answer.results.map(item => item.status), ['committed']);
    console.log('approved');
  } else if (step === 'resume' || step === 'recheck') {
    const ref = JSON.parse(readFileSync('effect-ref.json', 'utf8'));
    const execution = await client.attach(ref);
    const state = await waitFor(async () => {
      const current = await execution.status();
      return current.status === 'succeeded' ? current : undefined;
    });
    assert.equal(state.status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(),
      [{id: 'a00000000000001'}, {id: 'a00000000000002'}]);
    console.log('published');
  } else {
    throw new Error('InvalidPackedEffectStep');
  }
} finally {
  await client.close();
}
`);
  const beforeIdentity = server.seen.length;
  assert.equal((await runChild('effect-run.mjs', effectEnvironment,
    ['identity'])).trim(), 'identity-refused');
  assert.equal(server.seen.length, beforeIdentity);
  assert.equal((await runChild('effect-run.mjs', effectEnvironment,
    ['submit'])).trim(), 'held');
  assert.equal(server.seen.filter(item => item.method === 'PATCH').length, 0);
  assert.equal((await runChild('effect-run.mjs', effectEnvironment,
    ['answer'])).trim(), 'approved');
  assert.equal(server.seen.filter(item => item.method === 'PATCH').length, 0);
  assert.equal((await runChild('effect-run.mjs', effectEnvironment,
    ['resume'])).trim(), 'published');
  assert.equal(server.seen.filter(item => item.method === 'PATCH').length, 2);
  assert.equal((await runChild('effect-run.mjs', effectEnvironment,
    ['recheck'])).trim(), 'published');
  assert.equal(server.seen.filter(item => item.method === 'PATCH').length, 2);
  console.log('packed public Client Effect approval, restart, write and ' +
    'Named Result passed');
} finally {
  await server.close();
  await rm(root, {recursive: true, force: true});
}
