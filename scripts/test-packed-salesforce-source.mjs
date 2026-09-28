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
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {canonicalJson} from '../adapters/host-node/local-account-config.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
await mkdir(build, {recursive: true});
// Outside the checkout: nothing under it can fill in a missing file.
const root = await mkdtemp(join(tmpdir(), 'actql-packed-salesforce-'));
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
function runChild(script, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script], {cwd: root, env});
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
    seen.push(decodeURIComponent(request.url ?? '').split('?')[0]);
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
    response.writeHead(404).end();
  });
  await new Promise(resolve => https.listen(0, '127.0.0.1', resolve));
  return {seen, origin: `https://127.0.0.1:${https.address().port}`,
    close: () => new Promise(resolve => https.close(resolve))};
})();

try {
  const artifacts = [];
  for (const name of ['client-wire', 'sdk', 'local-node']) {
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
import {connect} from '@actql/local-node';
const client = await connect({mode: 'local', owner: 'local',
  durability: 'durable'});
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
    requestId: 'packed-read-1'});
  assert.equal((await execution.wait()).status, 'succeeded');
  const rows = await execution.result('records').all();
  process.stdout.write(JSON.stringify(rows.map(row =>
    [row.External_Key__c, row.Name]).sort()) + '\\n');
} finally { await client.close(); }
`);
  const catalogCid = (await runChild('publish.mjs', childEnvironment)).trim();
  assert.match(catalogCid, /^sha256:[0-9a-f]{64}$/u);
  assert.deepEqual(server.seen, [
    '/services/data/v62.0/sobjects/Test_Record__c/describe']);
  // A new process: the Host restores the publication without provider I/O
  // and discovery answers from it; only the Program's acquisition reads.
  const output = (await runChild('read.mjs', childEnvironment))
    .trim().split('\n');
  assert.equal(output[0], 'discovered');
  assert.deepEqual(JSON.parse(output[1]),
    [['key-1', 'record-1'], ['key-3', 'record-3']]);
  assert.deepEqual(server.seen.slice(1), [
    '/services/data/v62.0/sobjects/Test_Record__c/describe',
    '/services/data/v62.0/sobjects/Test_Record__c/describe',
    '/services/data/v62.0/query']);
  console.log('packed Local Host Salesforce publish, restart, discovery and ' +
    'Named Result passed');

  // The installed Effect's explicit publication: one generation of its
  // declaration, execution Mapping and Check Environment, from the package.
  await writeFile(join(root, 'effect.json'), JSON.stringify({
    version: 'actql-installed-salesforce-effect/0.1',
    siteProfilePath: join(root, 'site.json'),
    publicationPath: join(root, 'effect-publication.json'),
    connectorId: 'salesforce',
    writes: [{resource: 'Test_Record__c', kind: 'update', fields: ['Name']}],
    accountConfigurationWire: canonicalJson({
      version: 'actql-execution-account-config/0.1',
      account_id: 'packed-account', entries: [{entry_id: 'records-read',
        outcome: 'allow', exclusions: [], principal: {all: true},
        connection: {any_of: [`salesforce:${orgId}`]},
        resource: {any_of: ['Test_Record__c']},
        operation: {any_of: ['read']}}]})}));
  await writeFile(join(root, 'publish-effect.mjs'), `
import {publishEffect} from '@actql/local-node';
const published = await publishEffect();
console.log(JSON.stringify(published.mappings.map(mapping =>
  [mapping.resource, mapping.kind])));
`);
  const effect = JSON.parse((await runChild('publish-effect.mjs', {
    ...childEnvironment, ACTQL_LOCAL_EFFECT_PROFILE: join(root, 'effect.json'),
  })).trim());
  assert.deepEqual(effect, [['Test_Record__c', 'update']]);
  const generation = JSON.parse(await readFile(join(root,
    'effect-publication.json'), 'utf8'));
  assert.deepEqual(Object.keys(generation),
    ['environment_cid', 'mappings', 'source', 'version']);
  assert.deepEqual(server.seen.slice(4), [
    '/services/data/v62.0/sobjects/Test_Record__c/describe']);
  console.log('packed Local Host Salesforce Effect publication passed');
} finally {
  await server.close();
  await rm(root, {recursive: true, force: true});
}
