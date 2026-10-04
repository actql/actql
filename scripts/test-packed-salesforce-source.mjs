// The packed Local Host reading an installed Salesforce source, installed
// outside this checkout and run without MoonBit: publish, a restarted Host
// that restores the publication without provider I/O, discovery, a Program's
// acquisition and computation, and the Named Result. The org is a local HTTPS
// mock; the `sf` CLI is a stand-in that returns a test-only token.
import assert from 'node:assert/strict';
import {execFileSync, spawn, spawnSync} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {appendFile, mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {loadTwoSourceFixtures, installTwoSourceFixtures, canonical} from
  './fixtures/two-source-public-query.mjs';
import {compositionExpectations, databaseRows, expectedUpdates, expectedWrites, expectedModelInputs,
  publicFixtureEnvironment, modelConfiguration} from
  './fixtures/composed-infer-effect-input.mjs';
import {canonicalJson} from '../adapters/host-node/local-account-config.mjs';
import {packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';
import {readTwoSourceJournal} from './fixtures/two-source-public-query.mjs';
import {graphCompositionExpectations, graphResultDataPolicy} from './fixtures/graph-infer-effect-input.mjs';
import {optionalEffectCases, optionalEffectFixtureFiles, optionalEffectExpectations} from
  './fixtures/two-source-optional-effect.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
await mkdir(build, {recursive: true});
// Outside the checkout: nothing under it can fill in a missing file.
const externalScratch = join(repository, '..', '.codex-scratch');
await mkdir(externalScratch, {recursive: true});
const root = await mkdtemp(join(externalScratch, 'actql-packed-salesforce-'));
const twoSourceEffect = process.argv.includes('--two-source-effect');
const optionalCases = optionalEffectCases(process.argv);
const compositionCases = process.argv.includes('--optional-effect-only') ? []
  : process.argv.includes('--composed-graph-node') ? ['infer-graph-node']
  : process.argv.includes('--composed-graph-edge') ? ['infer-graph-edge']
  : process.argv.includes('--composed-graph') ? ['infer-graph-node','infer-graph-edge']
  : process.argv.includes('--composed-text') ? ['infer-text']
  : process.argv.includes('--composed-infer') ? ['infer', 'infer-text']
  : twoSourceEffect ? ['two-source'] : ['source', 'infer', 'infer-text', 'infer-graph-node', 'infer-graph-edge'];
const inferEnabled = compositionCases.some(kind => kind.startsWith('infer'));
const composed = compositionCases.some(kind => kind !== 'source') || optionalCases.length > 0;
const orgId = '00D000000000001EAA';
const token = 'packed-test-only-token';

function run(command, args, cwd, env = {...process.env,
  npm_config_cache: packedNpmCache(root)}) {
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
function runChild(script, env, args = [], expectedExit = 0) {
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
      if (code === expectedExit) resolve(stdout);
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
  // The current Name every target read answers; a test changes it to make
  // a Preview stale.
  const target = {name: 'prior-name', loseReply: false};
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
    // Test_Record__c is read and written; Other_Record__c, of the same
    // shape, is the second Resource of an Effect Set.
    const described = ['Test_Record__c', 'Other_Record__c'].find(name =>
      request.url === `${prefix}sobjects/${name}/describe`);
    if (described !== undefined) {
      json({name: described, queryable: true, createable: true,
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
    const record = ['Test_Record__c', 'Other_Record__c'].find(name =>
      request.url?.startsWith(`${prefix}sobjects/${name}/`));
    if (request.method === 'GET' && record !== undefined) {
      const id = decodeURIComponent(request.url.slice(
        `${prefix}sobjects/${record}/`.length));
      json({Id: id, Name: target.name, External_Key__c: id});
      return;
    }
    if (request.method === 'PATCH' && record !== undefined) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        seen.at(-1).body = text;
        const body = JSON.parse(text);
        assert.deepEqual(Object.keys(body), ['Name']);
        if (target.loseReply) {
          target.loseReply = false;
          target.name = body.Name; // The write happened; its response was lost.
          response.destroy();
          return;
        }
        response.writeHead(204).end();
      });
      return;
    }
    response.writeHead(404).end();
  });
  await new Promise(resolve => https.listen(0, '127.0.0.1', resolve));
  return {seen, target, origin: `https://127.0.0.1:${https.address().port}`,
    close: () => new Promise(resolve => https.close(resolve))};
})();

let passed = false;
try {
  const sourceRevision = run('git', ['rev-parse', 'HEAD'], repository).trim();
  assert.match(sourceRevision, /^[0-9a-f]{40}$/u);
  console.log('packed source revision ' + sourceRevision);
  const artifacts = [];
  for (const name of ['client-wire', 'sdk', 'local-node', 'node']) {
    await packedClientPackage({repository, name, destination: root,
      pack: packageName => run('npm', ['pack', '--pack-destination', root,
        '--json'], join(repository, 'packages', packageName))});
    artifacts.push(join(root, `actql-${name}-0.0.0-development.tgz`));
  }
  console.log('packed package digests ' + JSON.stringify(
    await Promise.all(artifacts.map(async path => ({
      package: path.split('/').at(-1),
      sha256: createHash('sha256').update(await readFile(path)).digest('hex'),
    })))));
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
    siteKey: 'packed-site', namespaceId: 'packed-namespace',
    caPath: join(root, 'org.crt')}));
  await writeFile(join(root, 'source.json'), JSON.stringify({
    version: 'actql-installed-salesforce-source/0.1',
    siteProfilePath: join(root, 'site.json'),
    publicationPath: join(root, 'publication.json'),
    connectorId: 'crm-main',
    resources: ['Test_Record__c', 'Other_Record__c'],
    accountConfigurationWire: canonicalJson({
      version: 'actql-execution-account-config/0.1',
      account_id: 'packed-account', entries: [{entry_id: 'records-read',
        outcome: 'allow', exclusions: [], principal: {all: true},
        connection: {any_of: [`salesforce:${orgId}`]},
        resource: {any_of: ['Other_Record__c', 'Test_Record__c']},
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
    [{name: 'Test_Record__c', outcome: 'described'},
      {name: 'Other_Record__c', outcome: 'described'}]);
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
    '/services/data/v62.0/sobjects/Test_Record__c/describe',
    '/services/data/v62.0/sobjects/Other_Record__c/describe']);
  // A new process: the Host restores the publication without provider I/O
  // and discovery answers from it; only the Program's acquisition reads.
  const output = (await runChild('read.mjs', childEnvironment))
    .trim().split('\n');
  assert.equal(output[0], 'discovered');
  assert.deepEqual(JSON.parse(output[1]),
    [['key-1', 'record-1'], ['key-3', 'record-3']]);
  assert.deepEqual(server.seen.slice(2).map(item => item.path), [
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
  const composedModel = composed ? await modelConfiguration(JSON.parse(
    await readFile(join(repository, 'spec/local-check-environment.json'),
      'utf8'))) : undefined;
  const effectAccount = canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'packed-effect-account', entries: [
      ...(composed ? [{entry_id: 'a-fixture-model', outcome: 'allow',
        exclusions: [], principal: {all: true},
        connection: {any_of: ['models/composition']},
        resource: {any_of: [composedModel.taskCid]},
        operation: {any_of: ['infer']}}] : []),
      {entry_id: 'effect-commit', outcome: 'delegate', exclusions: [],
        principal: {all: true},
        connection: {any_of: [`salesforce:${orgId}`]},
        resource: {any_of: ['Other_Record__c', 'Test_Record__c']},
        operation: {any_of: ['effect']}},
      {entry_id: 'host-run', outcome: 'allow', exclusions: [],
        principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['write']}},
      {entry_id: 'target-read', outcome: 'allow', exclusions: [],
        principal: {all: true},
        connection: {any_of: [`salesforce:${orgId}`]},
        resource: {any_of: ['Other_Record__c', 'Test_Record__c']},
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
    writes: ['Test_Record__c', 'Other_Record__c'].map(resource =>
      ({resource, kind: 'update', fields: ['Name']})),
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
  assert.deepEqual(effect, [['Test_Record__c', 'update'],
    ['Other_Record__c', 'update']]);
  const generation = JSON.parse(await readFile(join(root,
    'effect-publication.json'), 'utf8'));
  assert.deepEqual(Object.keys(generation),
    ['environment_cid', 'mappings', 'source', 'version']);
  assert.deepEqual(server.seen.slice(5).map(item => item.path), [
    '/services/data/v62.0/sobjects/Test_Record__c/describe',
    '/services/data/v62.0/sobjects/Other_Record__c/describe']);
  console.log('packed Local Host Salesforce Effect publication passed');

  const coinstalledRead = (await runChild('read.mjs', effectEnvironment))
    .trim().split('\n');
  assert.equal(coinstalledRead[0], 'discovered');
  assert.deepEqual(JSON.parse(coinstalledRead[1]),
    [['key-1', 'record-1'], ['key-3', 'record-3']]);
  console.log('packed Local Host coinstalled Source and Effect read passed');

  for (const name of ['composed-infer-effect-input.mjs',
    'composed-infer-effect.program.template.json', 'composed-infer-effect.expected.json',
    'composed-infer-effect.aql.template',
    'composed-infer-effect-null-assert.aql.template',
    'graph-infer-effect-input.mjs',
    'graph-node-infer-effect.program.template.json',
    'graph-edge-infer-effect.program.template.json',
    'graph-node-infer-effect-duplicate-key.program.template.json',
    'graph-node-infer-effect-null-property.program.template.json',
    'installed-infer-fixture.mjs', 'two-source-public-query.mjs',
    'public-query-input.mjs', ...optionalEffectFixtureFiles]) {
    await writeFile(join(root, name), await readFile(join(repository,
      'scripts/fixtures', name)));
  }
  await writeFile(join(root, 'base-environment.json'), await readFile(
    join(repository, 'spec/local-check-environment.json')));
  if (composed) {
    const fixture = await loadTwoSourceFixtures(join(repository,
      'adapters/host-node/fixtures/two-source'));
    fixture.rows = {...databaseRows, equal_content: databaseRows.left};
    for (const name of ['left', 'right']) {
      fixture.environments[name] = await publicFixtureEnvironment(
        fixture.environments[name]);
    }
    const duckdb = createRequire(join(root,
      'node_modules/@actql/local-node/package.json'))('@duckdb/node-api');
    const installed = await installTwoSourceFixtures({root: join(root,
      'composition-sources'), fixture, duckdb});
    // Publish aliases through the same installed Source profiles used by the
    // JSON control. Text lowering must resolve the exact installed identities.
    for (const name of ['left', 'right']) {
      const profile = JSON.parse(await readFile(installed.profiles[name], 'utf8'));
      const view = fixture.environments[name].source_views[0];
      profile.queryAliases = [{name: name + '_records', sourceRef: profile.sourceRef,
        sourceViewContractCid: view.contract_cid,
        schemaContractCid: view.output.schema.cid}];
      await writeFile(installed.profiles[name], canonical(profile));
    }
    await writeFile(join(root, 'composition-profiles.json'), JSON.stringify([
      installed.profiles.left, installed.profiles.right]));
    await writeFile(join(root, 'model-calls.jsonl'), '');
    await writeFile(join(root, 'source-calls.jsonl'), '');
    await writeFile(join(root, 'composition-custody.jsonl'), '');
    await writeFile(join(root, 'composition-databases.json'),
      JSON.stringify(installed.databases));
    if (optionalCases.length > 0) {
      // Retain the pure JOIN's independently authored NULL, duplicate and
      // negative rows. Both members of each pair use these same databases.
      const paired = await loadTwoSourceFixtures(join(repository,
        'adapters/host-node/fixtures/two-source'));
      for (const name of ['left', 'right']) {
        paired.environments[name] = await publicFixtureEnvironment(paired.environments[name]);
      }
      const sources = await installTwoSourceFixtures({root: join(root,
        'optional-effect-sources'), fixture: paired, duckdb});
      await writeFile(join(root, 'optional-effect-databases.json'), JSON.stringify(sources.databases));
      await writeFile(join(root, 'optional-effect-selections.jsonl'), '');
      for (const [kind, suffix] of [['native-json', ''], ['broad-text', '_broad']]) {
        await writeFile(join(root, 'optional-effect-' + kind + '-profiles.json'), JSON.stringify([
          sources.profiles['left' + suffix], sources.profiles['right' + suffix]]));
      }
    }
    // Independent bad rows in separate databases: never alter the positive
    // capture or infer that a NULL id rejected by JOIN tests assertion custody.
    if (compositionCases.includes('infer-text')) {
      for (const [variant, rows] of Object.entries({
        duplicate: {left: [{id: 1, amount: 10}, {id: 1, amount: 10},
          {id: 2, amount: 20}], right: databaseRows.right},
        null: {left: databaseRows.left, right: [{id: 1, amount: null},
          {id: 2, amount: 200}, {id: 3, amount: 300}]},
      })) {
        const bad = await installTwoSourceFixtures({root: join(root,
          'composition-' + variant), fixture: {...fixture,
          rows: {...rows, equal_content: rows.left}}, duckdb});
        for (const name of ['left', 'right']) {
          const profile = JSON.parse(await readFile(bad.profiles[name], 'utf8'));
          const view = fixture.environments[name].source_views[0];
          profile.queryAliases = [{name: name + '_records', sourceRef: profile.sourceRef,
            sourceViewContractCid: view.contract_cid, schemaContractCid: view.output.schema.cid}];
          await writeFile(bad.profiles[name], canonical(profile));
        }
        await writeFile(join(root, 'composition-' + variant + '-profiles.json'),
          JSON.stringify([bad.profiles.left, bad.profiles.right]));
        await writeFile(join(root, 'composition-' + variant + '-databases.json'),
          JSON.stringify(bad.databases));
      }
    }
  }

  // Every step runs in a fresh process with only the installed tarballs.
  // The same public @actql/node connect() path handles submission, review,
  // recovery and the Named Result without a MoonBit toolchain.
  await writeFile(join(root, 'effect-run.mjs'), `
import assert from 'node:assert/strict';
import {createHash, createPrivateKey, sign} from 'node:crypto';
import {appendFileSync, readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {observeTwoSourceProvider} from './two-source-public-query.mjs';
import {userInfo} from 'node:os';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {connect} from '@actql/node';
import {compositionProgram, compositionText, twoSourceEffectProgram, modelConfiguration, registerCompositionModel,
  compositionExpectations} from
  './composed-infer-effect-input.mjs';
import {graphCompositionProgram, graphCompositionExpectations,
  graphCompositionRefusalProgram, graphResultDataPolicy} from './graph-infer-effect-input.mjs';
const composed = process.env.PACKED_COMPOSED_INFER === '1';
const twoSourceEffect = process.env.PACKED_TWO_SOURCE_EFFECT === '1';
const composedText = process.env.PACKED_COMPOSED_TEXT === '1';
const graphFamily = process.env.PACKED_GRAPH_ROWS || undefined;
const {classified:expectedClassified,classifiedColumns,updates:expectedUpdates,
  updateColumns} = graphFamily ? graphCompositionExpectations(graphFamily) : compositionExpectations;
import {optionalEffectSubmission, optionalEffectExpectations} from './two-source-optional-effect.mjs';
const optionalKind = process.env.PACKED_OPTIONAL_EFFECT_KIND;
const optionalEnabled = process.env.PACKED_OPTIONAL_EFFECT_ENABLED === '1';
const authorization = JSON.parse(readFileSync('authorization.json', 'utf8'));
if (process.env.PACKED_CHECKPOINT_TTL_MS !== undefined) {
  authorization.checkpointTtlMs = Number(process.env.PACKED_CHECKPOINT_TTL_MS);
}
if (process.env.PACKED_DENY_EFFECT === '1') {
  const account = JSON.parse(authorization.accountConfiguration);
  account.entries = account.entries.map(entry => entry.entry_id === 'effect-commit'
    ? {...entry, outcome: 'deny'} : entry);
  authorization.accountConfiguration = JSON.stringify(account);
}
const pendingScratch = process.argv[2] === 'rce-submit-pending';
let scratchReleased = !pendingScratch;
let temporaryReleaseConfirmed = false;
authorization.observe = (name, detail) => {
  if (name === 'effect_start_failed' || name === 'effect_settlement_failed') {
    appendFileSync('composition-custody.jsonl', JSON.stringify({name, ...detail,
      pendingScratch}) + '\\n');
  }
  if (optionalKind && name === 'acquisition_completed') {
    appendFileSync('optional-effect-selections.jsonl', JSON.stringify({ref: detail.ref,
      selection: detail.acquisition?.selection}) + '\\n');
  }
  if (name.startsWith('effect_computation_')) {
    appendFileSync('composition-custody.jsonl', JSON.stringify({name, ...detail,
      pendingScratch}) + '\\n');
    if (name === 'effect_computation_cleanup_completed') temporaryReleaseConfirmed = true;
    if (pendingScratch && name === 'effect_computation_cleanup_pending') {
      assert.ok(BigInt(detail.resourceUsage.reservedExecutionBytes) > 0n,
        'false physical cleanup must retain the original execution reservation');
      scratchReleased = true;
    }
  }
};
authorization.resumeAfterAnswer = process.argv[2] === 'resume';
const installation = {
  directory: process.env.ACTQL_LOCAL_STATE_DIR,
  sourceProfilePath: process.env.ACTQL_LOCAL_SOURCE_PROFILE,
  effectProfilePath: process.env.ACTQL_LOCAL_EFFECT_PROFILE,
  authorization,
};
let sourceObservation;
if (composed) {
  sourceObservation = observeTwoSourceProvider(createRequire(
    new URL('./node_modules/@actql/local-node/package.json', import.meta.url))(
      '@duckdb/node-api'), JSON.parse(readFileSync(
        process.env.PACKED_COMPOSITION_DATABASES ?? 'composition-databases.json', 'utf8')));
  delete installation.sourceProfilePath;
  if (graphFamily) {
    // This acceptance must work without any installed Source whose Policy
    // could accidentally substitute for the explicitly bound Result Policy.
    assert.equal(process.env.ACTQL_LOCAL_SOURCE_PROFILE, undefined);
    if (process.env.PACKED_GRAPH_POLICY !== 'absent') {
      installation.resultDataPolicy = graphResultDataPolicy;
    }
  } else {
    installation.sourceProfilePaths = JSON.parse(readFileSync(
      process.env.PACKED_COMPOSITION_PROFILES ?? 'composition-profiles.json', 'utf8'));
  }
  const model = await modelConfiguration(JSON.parse(readFileSync(
    'base-environment.json', 'utf8')));
  installation.modelInstallation = model.installation;
  installation.registerModelProviders = moon => registerCompositionModel(
    moon, model.taskCid, score => appendFileSync('model-calls.jsonl',
      JSON.stringify({score}) + '\\n'), {cleanup: () => scratchReleased});
}
let remoteHost;
let remoteServer;
let connection = {mode: 'local', owner: 'local',
  durability: 'durable', installation};
if (process.env.PACKED_RCE_TRANSPORT === 'https') {
  remoteHost = await openInstalledRemoteHttpHost({...installation,
    authenticate: header => header === 'Bearer fixture-token'
      ? userInfo().username : undefined});
  remoteServer = createServer({key: readFileSync('org.key'),
    cert: readFileSync('org.crt')}, remoteHost.handler);
  await new Promise(resolve => remoteServer.listen(0, '127.0.0.1', resolve));
  connection = {mode: 'remote', durability: 'durable',
    endpoint: 'https://127.0.0.1:' + remoteServer.address().port + '/',
    token: 'fixture-token'};
}
const client = await connect(connection);
async function terminate(boundary, ref) {
  if (graphFamily && boundary === 'capture-waiting') {
    await waitFor(() => temporaryReleaseConfirmed);
  }
  appendFileSync('restart-boundaries.jsonl', JSON.stringify({boundary, ref,
    transport: process.env.PACKED_RCE_TRANSPORT}) + '\\n');
  // Stop the dedicated Host and its execution process without finally or
  // graceful close. The following process must use only durable custody.
  if (sourceObservation) appendFileSync('source-calls.jsonl', JSON.stringify(
    sourceObservation.snapshot()) + '\\n');
  process.stdout.write(boundary === 'approval-committed' ? 'approved\\n' : 'held\\n',
    () => process.exit(77));
  return new Promise(() => {});
}
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
    // One member per installed Resource: an Effect Set over two Resources.
    const effects = Object.fromEntries(generation.mappings.map(
      (entry, index) => ['save_' + index, {update: {
        target: 'connector://crm-main/' + entry.write.resource,
        mapping: entry.mapping_ref, from: {result: 'rows'}, id: 'id',
        set: {Name: {field: 'id'}}}}]));
    const program = {version: 'actql/0.1', id: 'packed-effect', stages: [{
      id: 'source', inputs: {},
      steps: [{values: {schema: {id: {type: 'string', nullable: false}},
        rows: [{id: 'a00000000000001'}, {id: 'a00000000000002'}]},
        as: 'selected'}],
      results: {rows: {from: 'selected', fields: ['id']}},
      effects,
    }], results: {answer: {from: {stage: 'source', result: 'rows'}}}};
    const execution = await client.aql(JSON.stringify(program), {
      format: 'json', requestId: 'packed-effect-1'});
    await waitFor(async () => {
      const status = await execution.status();
      if (status.status === 'failed') throw new Error('PackedEffectFailed: ' + JSON.stringify(status));
      return status.status === 'waiting_checkpoint';
    });
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
    if (composed) await terminate('approval-committed', ref);
    console.log('approved');
  } else if (step === 'rce-empty') {
    assert.deepEqual(await client.lookupRequest('unsupported-rce'),
      {kind: 'not_found'});
    console.log('empty');
  } else if (step === 'rce-unsupported') {
    const submission = JSON.parse(readFileSync('rce-submission.json', 'utf8'));
    assert.equal(createHash('sha256').update(submission.document).digest('hex'),
      process.argv[3], 'the exact positively executed Program is reused');
    await assert.rejects(client.aql(submission.document, {format: submission.format,
      requestId: 'unsupported-rce'}), {code: 'ClientProgramUnsupported'});
    const lookup = await client.lookupRequest('unsupported-rce');
    assert.deepEqual(lookup, {kind: 'not_found'});
    console.log(JSON.stringify({code: 'ClientProgramUnsupported', lookup,
      programSha256: process.argv[3]}));
  } else if (step === 'policy-refusal') {
    assert.ok(graphFamily);
    assert.equal(installation.resultDataPolicy, undefined);
    const generation = JSON.parse(readFileSync('effect-publication.json', 'utf8'));
    const mapping = generation.mappings.find(entry => entry.write.resource === 'Test_Record__c');
    const document = JSON.stringify(graphCompositionProgram(mapping.mapping_ref, graphFamily));
    const requestId = 'missing-graph-result-policy';
    await assert.rejects(client.aql(document, {format: 'json', requestId}),
      {code: 'ClientHostFailure'});
    const lookup = await client.lookupRequest(requestId);
    assert.deepEqual(lookup, {kind: 'not_found'});
    assert.deepEqual((await client.checkpoints()).items, []);
    console.log(JSON.stringify({code: 'ClientHostFailure', requestId, lookup,
      programSha256: createHash('sha256').update(document).digest('hex')}));
  } else if (step === 'assertion-refusal') {
    const variant = process.argv[3];
    const generation = JSON.parse(readFileSync('effect-publication.json', 'utf8'));
    const mapping = generation.mappings.find(entry => entry.write.resource === 'Test_Record__c');
    const document = graphFamily
      ? JSON.stringify(graphCompositionRefusalProgram(mapping.mapping_ref, variant))
      : compositionText(mapping.mapping_ref, variant);
    const format = graphFamily ? 'json' : 'aql-text';
    const execution = await client.aql(document, {format,
      requestId: 'assertion-' + variant});
    const state = await execution.wait();
    assert.equal(state.status, 'failed', 'assertion failure precedes INFER and Effect');
    assert.deepEqual((await client.checkpoints()).items, []);
    console.log(JSON.stringify({variant, state, ref: execution.ref, submittedFormat: format,
      submittedProgramSha256: createHash('sha256').update(document).digest('hex')}));
  } else if (step === 'rce-submit' || step === 'rce-submit-pending') {
    // Read→Compute→Effect: acquire Test_Record__c, keep every record but
    // record-2, derive the new Name locally, and update the same records.
    const generation = JSON.parse(readFileSync('effect-publication.json',
      'utf8'));
    const mapping = generation.mappings.find(entry =>
      entry.write.resource === 'Test_Record__c');
    const program = optionalKind ? undefined : composed ? graphFamily
      ? graphCompositionProgram(mapping.mapping_ref,graphFamily)
      : (twoSourceEffect ? twoSourceEffectProgram : compositionProgram)(mapping.mapping_ref)
      : {version: 'actql/0.1', id: 'packed-rce', stages: [
      {id: 'acquire',
        inputs: {remote: {connector: 'crm-main', resource: 'Test_Record__c'}},
        steps: [{filter: "Name <> 'record-2'", as: 'filtered'},
          {select: ['Id', 'External_Key__c'], as: 'captured'}],
        results: {r: {from: 'captured', fields: ['Id', 'External_Key__c']}}},
      {id: 'compute',
        inputs: {x: {result: {stage: 'acquire', result: 'r'}}},
        steps: [
          {derive: {next_name: "concat(External_Key__c, '-processed')"},
            as: 'derived'},
          {select: ['Id', 'next_name'], as: 'out'}],
        results: {updates: {from: 'out', fields: ['Id', 'next_name']}},
        effects: {save: {update: {target: 'connector://crm-main/Test_Record__c',
          mapping: mapping.mapping_ref, from: {result: 'updates'}, id: 'Id',
          set: {Name: {field: 'next_name'}}}}}},
    ], results: {updates: {from: {stage: 'compute', result: 'updates'}}}};
    const submission = {...(optionalKind
      ? optionalEffectSubmission(optionalKind, optionalEnabled, mapping.mapping_ref)
      : {document: composedText ? compositionText(mapping.mapping_ref)
      : JSON.stringify(program), format: composedText ? 'aql-text' : 'json',
      }),
      requestId: 'packed-rce-' + process.argv[3],
      installedSourceProfiles: installation.sourceProfilePaths?.length ??
        (installation.sourceProfilePath === undefined ? 0 : 1)};
    let execution;
    try {
      execution = await client.aql(submission.document, {
        format: submission.format, requestId: submission.requestId});
    } catch (error) {
      if (error?.code === 'ClientProgramUnsupported') {
        console.log('not-connected');
        process.exit(0);
      }
      throw error;
    }
    if (pendingScratch) {
      await waitFor(async () => (await execution.status()).status === 'waiting_checkpoint');
    } else {
      assert.equal((await execution.wait()).status,
        optionalKind && !optionalEnabled ? 'succeeded' : 'waiting_checkpoint');
    }
    writeFileSync('effect-ref.json', JSON.stringify(execution.ref));
    writeFileSync('rce-submission.json', JSON.stringify(submission));
    if (process.argv[3] === 'success' || optionalKind) {
      const repeated = await client.aql(submission.document, {
        format: submission.format, requestId: submission.requestId});
      assert.deepEqual(repeated.ref, execution.ref,
        'resubmitting the same request must retain the original Run');
    }
    if (process.env.PACKED_CHECKPOINT_TTL_MS !== undefined) {
      const [checkpoint] = (await client.checkpoints()).items;
      assert.equal(checkpoint.kind, 'effect_set');
      writeFileSync('effect-deadline.json', JSON.stringify({ref: execution.ref,
        expiresAt: checkpoint.expiresAt}));
    }
    if (optionalKind && !optionalEnabled) {
      assert.deepEqual((await client.checkpoints()).items, []);
      assert.deepEqual(await execution.result('updates').all(), optionalEffectExpectations.rows);
      assert.deepEqual((await execution.result('updates').describe()).columns, optionalEffectExpectations.columns);
      await terminate('completed', execution.ref);
    }
    if (composed && !pendingScratch) await terminate('capture-waiting', execution.ref);
    console.log('held');
  } else if (step === 'rce-resume') {
    const ref = JSON.parse(readFileSync('effect-ref.json', 'utf8'));
    const submission = JSON.parse(readFileSync('rce-submission.json', 'utf8'));
    const lookup = await client.lookupRequest(submission.requestId);
    assert.equal(lookup.kind, 'found');
    assert.deepEqual(lookup.ref, ref);
    assert.deepEqual((await client.checkpoints()).items, []);
    if (process.argv[3] === 'resubmit') {
      const repeated = await client.aql(submission.document, {
        format: submission.format, requestId: submission.requestId});
      assert.deepEqual(repeated.ref, ref,
        'resubmission after process termination must recover the same Run');
    }
    const execution = await client.attach(lookup.ref);
    const state = await waitFor(async () => {
      const current = await execution.status();
      return ['succeeded', 'failed', 'needs_reconciliation', 'cancelled']
        .includes(current.status) ? current : undefined;
    });
    let retainedNamedResults;
    if (state.status === 'succeeded' && optionalKind) {
      assert.deepEqual(await execution.result('updates').all(), optionalEffectExpectations.rows);
      assert.deepEqual((await execution.result('updates').describe()).columns, optionalEffectExpectations.columns);
    } else if (state.status === 'succeeded' && composed) {
      if (!twoSourceEffect) {
      assert.deepEqual(await execution.result('classified').all(), expectedClassified);
      assert.deepEqual((await execution.result('classified').describe()).columns,
        classifiedColumns);
      assert.deepEqual((await execution.result('updates').describe()).columns,
        updateColumns);
      retainedNamedResults = await Promise.all(['classified', 'updates'].map(async name => ({
        name, artifactCid: (await execution.result(name).describe()).resultArtifactCid,
        rows: (await execution.result(name).all()).length,
      })));
      }
      assert.deepEqual(await execution.result('updates').all(), expectedUpdates);
    } else if (state.status === 'succeeded') {
      assert.deepEqual((await execution.result('updates').describe()).columns, [
        {name: 'Id', contract: {type: 'string', nullable: false}},
        {name: 'next_name', contract: {type: 'string', nullable: false}},
      ]);
    }
    console.log(JSON.stringify({status: state.status,
      retainedNamedResults,
      ...(optionalKind && state.status === 'succeeded'
        ? {columns: (await execution.result('updates').describe()).columns} : {}),
      rows: state.status === 'succeeded'
        ? await execution.result('updates').all() : undefined}));
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
  if (remoteServer) {
    remoteServer.closeAllConnections();
    await new Promise(resolve => remoteServer.close(resolve));
    await remoteHost.close();
  }
  if (sourceObservation) {
    appendFileSync('source-calls.jsonl', JSON.stringify(
      sourceObservation.snapshot()) + '\\n');
    sourceObservation.restore();
  }
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
  // Each row of each Resource once.
  assert.deepEqual(server.seen.filter(item => item.method === 'PATCH')
    .map(item => item.path.split('/').slice(-2).join('/')).sort(),
  ['Other_Record__c', 'Test_Record__c'].flatMap(resource =>
    ['a00000000000001', 'a00000000000002'].map(id => `${resource}/${id}`)));
  assert.equal((await runChild('effect-run.mjs', effectEnvironment,
    ['recheck'])).trim(), 'published');
  assert.equal(server.seen.filter(item => item.method === 'PATCH').length, 4);
  console.log('packed public Client Effect approval, restart, write and ' +
    'Named Result passed');

  // Read→Compute→Effect from the installed tarballs: acquire, compute and
  // hold; approve; resume in a new process; write once; nothing more on a
  // further restart. Then a target changed after the Preview writes nothing.
  // Until the common Host runs an Effect from an acquisition, this ends as
  // not connected, never as passed.
  const queries = () => server.seen.filter(item =>
    item.method === 'GET' && item.path === '/services/data/v62.0/query').length;
  // Each invocation owns both its Host and its execution context. Exiting
  // before the next invocation stops both, also for the public HTTPS path.
  for (const compositionKind of compositionCases) {
  const composed = compositionKind !== 'source';
  const inferEnabled = compositionKind.startsWith('infer');
  const twoSourceEffect = compositionKind === 'two-source';
  const graphFamily = compositionKind.startsWith('infer-graph-')
    ? compositionKind.slice('infer-graph-'.length) : undefined;
  const expectations = graphFamily ? graphCompositionExpectations(graphFamily) : compositionExpectations;
  const {updates:expectedUpdates,writes:expectedWrites,modelInputs:expectedModelInputs} = expectations;
  for (const transport of ['local', 'https']) {
    server.target.name = 'prior-name';
    const rceEnvironment = {...effectEnvironment,
      PACKED_RCE_TRANSPORT: transport,
      PACKED_COMPOSED_INFER: composed ? '1' : '0',
      PACKED_TWO_SOURCE_EFFECT: twoSourceEffect ? '1' : '0',
      PACKED_COMPOSED_TEXT: compositionKind === 'infer-text' ? '1' : '0',
      ...(graphFamily === undefined ? {} : {PACKED_GRAPH_ROWS:graphFamily}),
      NODE_EXTRA_CA_CERTS: join(root, 'org.crt'),
      ACTQL_LOCAL_STATE_DIR: join(root, 'rce-' + compositionKind + '-' + transport)};
    if (composed) delete rceEnvironment.ACTQL_LOCAL_SOURCE_PROFILE;
    const rce = async (steps, id, environment = rceEnvironment) => {
      const readsBefore = queries();
      const held = (await runChild('effect-run.mjs', environment,
        ['rce-submit', id], composed ? 77 : 0)).trim();
      if (held === 'not-connected') {
        throw Object.assign(new Error('ReadComputeEffectNotConnected: the ' +
          'packed Host refuses the Program (ClientProgramUnsupported).'),
        {code: 'ReadComputeEffectNotConnected'});
      }
      assert.equal(held, 'held');
      if (!composed) assert.equal(queries(), readsBefore + 1);
      await steps();
      if (!composed) assert.equal(queries(), readsBefore + 1,
        'recovery must use captured Source rows without another query');
    };
    const writesBefore = server.seen.filter(item => item.method === 'PATCH')
      .length;
    const patches = () => server.seen.filter(item => item.method === 'PATCH')
      .slice(writesBefore);
    const sourceCallsBefore = composed ? (await readFile(join(root,
      'source-calls.jsonl'), 'utf8')).trim().split('\n').filter(Boolean).length : 0;
    const modelCallsBefore = composed ? (await readFile(join(root,
      'model-calls.jsonl'), 'utf8')).trim().split('\n').filter(Boolean).length : 0;
    const effectWriteCounts = [];
    const custodyBefore = inferEnabled ? (await readFile(join(root,
      'composition-custody.jsonl'), 'utf8')).trim().split('\n').filter(Boolean).length : 0;
    let normalResult;
    await rce(async () => {
      const recoveryEnvironment = graphFamily ? {...rceEnvironment,
        PACKED_GRAPH_POLICY: 'absent'} : rceEnvironment;
      effectWriteCounts.push(patches().length);
      assert.equal(patches().length, 0);
      assert.equal((await runChild('effect-run.mjs', recoveryEnvironment,
        ['answer'], composed ? 77 : 0)).trim(), 'approved');
      effectWriteCounts.push(patches().length);
      assert.equal(patches().length, 0);
      const done = JSON.parse((await runChild('effect-run.mjs',
        recoveryEnvironment, ['rce-resume', 'resubmit'])).trim());
      normalResult = done;
      effectWriteCounts.push(patches().length);
      assert.equal(done.status, 'succeeded');
      if (composed) {
        assert.deepEqual(done.rows, expectedUpdates);
        assert.deepEqual(patches().map(item => ({id: item.path.split('/').at(-1),
          body: JSON.parse(item.body)})), expectedWrites);
      } else {
      assert.deepEqual([...done.rows].sort((a, b) => a.Id < b.Id ? -1 : 1), [
        {Id: 'a00000000000001', next_name: 'key-1-processed'},
        {Id: 'a00000000000003', next_name: 'key-3-processed'}]);
      assert.deepEqual(patches().map(item => [item.path.split('/').at(-1),
        item.body]).sort(), [
        ['a00000000000001', '{"Name":"key-1-processed"}'],
        ['a00000000000003', '{"Name":"key-3-processed"}']]);
      }
      assert.equal(JSON.parse((await runChild('effect-run.mjs',
        recoveryEnvironment, ['rce-resume', 'resubmit'])).trim()).status, 'succeeded');
      effectWriteCounts.push(patches().length);
      assert.equal(patches().length, composed ? 1 : 2);
    }, 'success');
    if (composed) {
      const calls = (await readFile(join(root, 'model-calls.jsonl'), 'utf8'))
        .trim().split('\n').filter(Boolean).map(line => JSON.parse(line).score);
      const sourceCalls = (await readFile(join(root, 'source-calls.jsonl'), 'utf8'))
        .trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
      const sourceReadSessions = sourceCalls.slice(sourceCallsBefore).map(item =>
        item.sourceReadSessions);
      const modelInputs = calls.slice(modelCallsBefore).sort((a, b) => a - b);
      assert.deepEqual(sourceReadSessions, expectations.sourceReadSessions,
      'only submission acquires the two Sources; recovery uses captured inputs');
      assert.deepEqual(modelInputs,
        inferEnabled ? expectedModelInputs : [],
        'saved Model results must not be replayed physically');
      assert.deepEqual(effectWriteCounts, expectations.effectWriteCounts);
      const ref = JSON.parse(await readFile(join(root, 'effect-ref.json'), 'utf8'));
      const boundaries = (await readFile(join(root, 'restart-boundaries.jsonl'), 'utf8'))
        .trim().split('\n').filter(Boolean).map(line => JSON.parse(line))
        .filter(item => item.transport === transport &&
          item.ref.runDefinitionCid === ref.runDefinitionCid &&
          item.ref.authorityScopeCid === ref.authorityScopeCid);
      assert.deepEqual(boundaries.map(item => item.boundary),
        expectations.restartBoundaries);
      for (const boundary of boundaries) assert.deepEqual(boundary.ref, ref);
      const submission = JSON.parse(await readFile(join(root,
        'rce-submission.json'), 'utf8'));
      const observation = {sourceRevision, transport, case: compositionKind,
        requestId: submission.requestId, ref, submittedFormat: submission.format,
        submittedProgramSha256: createHash('sha256').update(
          submission.document).digest('hex'),
        sourceReadSessions, modelInputs, effectWriteCounts,
        writes: patches().map(item => ({id: item.path.split('/').at(-1),
          body: JSON.parse(item.body)})), rows: normalResult.rows,
        restartBoundaries: boundaries};
      if (graphFamily) {
        assert.equal(submission.installedSourceProfiles, 0,
          'source-free Graph acceptance must not borrow an unused Source Policy');
        const custody = (await readFile(join(root, 'composition-custody.jsonl'), 'utf8'))
          .trim().split('\n').filter(Boolean).slice(custodyBefore).map(line => JSON.parse(line));
        const released = custody.find(item => item.name === 'effect_computation_cleanup_completed');
        assert.ok(released, 'the original owner confirms cleanup before the capture-waiting crash');
        for (const field of ['heldBytes', 'reservedTransferBytes',
          'reservedRetentionBytes', 'reservedExecutionBytes']) assert.equal(released.resourceUsage[field], '0');
        assert.deepEqual(normalResult.retainedNamedResults.map(({name, rows}) => ({name, rows})),
          [{name:'classified', rows:2}, {name:'updates', rows:1}]);
        observation.temporaryRetention = {cleanupConfirmed:true, resourceUsage:released.resourceUsage};
        observation.namedResultRetention = normalResult.retainedNamedResults;
        observation.installedSourceProfiles = submission.installedSourceProfiles;
        const retained = readTwoSourceJournal(rceEnvironment.ACTQL_LOCAL_STATE_DIR)
          .find(row => row.run_definition_cid === ref.runDefinitionCid);
        assert.ok(retained, 'the same Run retains its accepted Policy dependency');
        const evidence = JSON.parse(retained.run_admission_evidence_json);
        assert.deepEqual(evidence.resultPolicyOriginal, graphResultDataPolicy,
          'restart uses the exact accepted Policy original, without a current Host binding');
        observation.resultPolicyOriginal = evidence.resultPolicyOriginal;
        observation.recoveryHostPolicy = 'absent';
      }
      await appendFile(join(root, 'composition-acceptance.jsonl'),
        JSON.stringify(observation) + '\n');
      console.log('packed composition acceptance ' + JSON.stringify(observation));
    }
    if (graphFamily === 'node') {
      const environment = {...rceEnvironment, PACKED_GRAPH_POLICY: 'absent',
        ACTQL_LOCAL_STATE_DIR: join(root, 'missing-graph-policy-' + transport)};
      const modelsBefore = await readFile(join(root, 'model-calls.jsonl'), 'utf8');
      const sourcesBefore = (await readFile(join(root, 'source-calls.jsonl'), 'utf8'))
        .trim().split('\n').filter(Boolean).length;
      const writesBefore = server.seen.filter(item => item.method === 'PATCH').length;
      const refusal = JSON.parse((await runChild('effect-run.mjs', environment,
        ['policy-refusal'])).trim());
      assert.equal(await readFile(join(root, 'model-calls.jsonl'), 'utf8'), modelsBefore);
      assert.equal(server.seen.filter(item => item.method === 'PATCH').length, writesBefore);
      assert.deepEqual(readTwoSourceJournal(environment.ACTQL_LOCAL_STATE_DIR), [],
        'missing Host Policy refuses preparation before accepted Run/dispatch custody');
      const sources = (await readFile(join(root, 'source-calls.jsonl'), 'utf8'))
        .trim().split('\n').filter(Boolean).slice(sourcesBefore).map(line => JSON.parse(line));
      assert.deepEqual(sources.map(item => item.sourceReadSessions), [0]);
      console.log('packed Graph policy refusal ' + JSON.stringify({sourceRevision,
        transport, ...refusal, modelCalls: 0, sourceReadSessions: 0, writes: 0}));
    }
    if (compositionKind === 'infer-text' || graphFamily === 'node') {
      // Positive execution above must pass first: a missing Result Policy is
      // not evidence that a row assertion refused the independent bad input.
      const variants = graphFamily ? ['duplicate-key', 'null-property'] : ['duplicate', 'null'];
      for (const variant of variants) {
        const modelBefore = await readFile(join(root, 'model-calls.jsonl'), 'utf8');
        const sourceBefore = graphFamily ? await readFile(join(root, 'source-calls.jsonl'), 'utf8') : undefined;
        const writeBefore = server.seen.filter(item => item.method === 'PATCH').length;
        const refusal = JSON.parse((await runChild('effect-run.mjs', {
          ...rceEnvironment,
          ACTQL_LOCAL_STATE_DIR: join(root, 'assertion-' + variant + '-' + transport),
          ...(graphFamily ? {} : {
            PACKED_COMPOSITION_PROFILES: 'composition-' + variant + '-profiles.json',
            PACKED_COMPOSITION_DATABASES: 'composition-' + variant + '-databases.json',
          }),
        }, ['assertion-refusal', variant])).trim());
        assert.equal(refusal.state.status, 'failed');
        assert.equal(await readFile(join(root, 'model-calls.jsonl'), 'utf8'), modelBefore,
          'bad assertion rows must be rejected before any Model call');
        assert.equal(server.seen.filter(item => item.method === 'PATCH').length, writeBefore);
        if (graphFamily) assert.equal(await readFile(join(root, 'source-calls.jsonl'), 'utf8'),
          sourceBefore, 'source-free assertion failure must not acquire an installed Source');
        const observation = {sourceRevision, transport, ...refusal,
          modelCalls: 0, writes: 0, checkpoints: 0,
          ...(graphFamily ? {sourceReadSessions: 0, case: compositionKind} : {})};
        await appendFile(join(root, 'composition-assertion-refusals.jsonl'),
          JSON.stringify(observation) + '\n');
        console.log('packed composition assertion refusal ' + JSON.stringify(observation));
      }
    }
    if (!composed) {
      // The preceding public execution and independent rows establish semantic
      // validity. Reuse its exact bytes in a fresh source-only installation;
      // the unsupported refusal alone must never be treated as a validity check.
      const submission = JSON.parse(await readFile(join(root,
        'rce-submission.json'), 'utf8'));
      const programSha256 = createHash('sha256').update(
        submission.document).digest('hex');
      const unsupportedEnvironment = {...rceEnvironment,
        ACTQL_LOCAL_STATE_DIR: join(root, 'unsupported-rce-' + transport)};
      delete unsupportedEnvironment.ACTQL_LOCAL_EFFECT_PROFILE;
      const providerBefore = server.seen.slice();
      assert.equal((await runChild('effect-run.mjs', unsupportedEnvironment,
        ['rce-empty'])).trim(), 'empty');
      const journalBefore = readTwoSourceJournal(
        unsupportedEnvironment.ACTQL_LOCAL_STATE_DIR);
      assert.deepEqual(journalBefore, [], 'fresh installation has no accepted Run');
      assert.deepEqual(server.seen, providerBefore, 'opening restores without provider I/O');
      const refusal = JSON.parse((await runChild('effect-run.mjs',
        unsupportedEnvironment, ['rce-unsupported', programSha256])).trim());
      assert.equal(refusal.code, 'ClientProgramUnsupported');
      assert.deepEqual(refusal.lookup, {kind: 'not_found'});
      assert.equal(refusal.programSha256, programSha256);
      const journalAfter = readTwoSourceJournal(
        unsupportedEnvironment.ACTQL_LOCAL_STATE_DIR);
      assert.deepEqual(journalAfter, journalBefore,
        'unsupported input creates no Run, dispatch or physical-start reservation');
      assert.deepEqual(server.seen, providerBefore,
        'unsupported input performs no provider HTTP request, including source reads or Effect writes');
      console.log('packed unsupported admission ' + JSON.stringify({
        transport, sourceRevision, programSha256,
        profile: 'installed Salesforce Source; no Effect execution profile',
        positive: 'same bytes completed Read→Compute→Effect with independent rows',
        ...refusal, providerRequests: 0, journalBefore, journalAfter}));
    }
    await rce(async () => {
      server.target.name = 'changed-after-preview';
      assert.equal((await runChild('effect-run.mjs', rceEnvironment,
        ['answer'], composed ? 77 : 0)).trim(), 'approved');
      const done = JSON.parse((await runChild('effect-run.mjs',
        rceEnvironment, ['rce-resume'])).trim());
      assert.equal(done.status, 'failed');
      assert.equal(patches().length, composed ? 1 : 2);
    }, 'stale');
    if (inferEnabled && graphFamily !== 'edge') {
      server.target.name = 'prior-name';
      const writesBeforePending = patches().length;
      const modelsBeforePending = (await readFile(join(root, 'model-calls.jsonl'),
        'utf8')).trim().split('\n').filter(Boolean).length;
      const sourceCallsBeforePending = (await readFile(join(root, 'source-calls.jsonl'),
        'utf8')).trim().split('\n').filter(Boolean).length;
      assert.equal((await runChild('effect-run.mjs', rceEnvironment,
        ['rce-submit-pending', 'pending'])).trim(), 'held');
      assert.equal(patches().length, writesBeforePending,
        'cleanup retry cannot send an unapproved Effect');
      const custody = (await readFile(join(root, 'composition-custody.jsonl'), 'utf8'))
        .trim().split('\n').map(line => JSON.parse(line)).filter(item => item.pendingScratch);
      const completed = custody.find(item => item.name === 'effect_computation_completed');
      const pending = custody.find(item => item.name === 'effect_computation_cleanup_pending');
      const released = custody.filter(item => item.name === 'effect_computation_cleanup_completed').at(-1);
      assert.ok(completed && pending && released,
        'the original completed computation must report pending and then actual release');
      assert.ok(BigInt(pending.resourceUsage.reservedExecutionBytes) > 0n);
      assert.equal(released.resourceUsage.reservedExecutionBytes, '0');
      assert.equal(released.resourceUsage.reservedTransferBytes, '0');
      assert.equal(released.resourceUsage.reservedRetentionBytes, '0');
      assert.equal(released.resourceUsage.heldBytes, '0');
      assert.equal(released.resourceUsage.transferredBytes, completed.resourceUsage.transferredBytes);
      assert.equal(released.resourceUsage.planningWork, completed.resourceUsage.planningWork);
      assert.equal((await runChild('effect-run.mjs', rceEnvironment,
        ['answer'], 77)).trim(), 'approved');
      for (let restart = 0; restart < 2; restart++) {
        assert.equal(JSON.parse((await runChild('effect-run.mjs', rceEnvironment,
          ['rce-resume'])).trim()).status, 'succeeded');
        assert.deepEqual(patches().slice(writesBeforePending).map(item => ({
          id: item.path.split('/').at(-1), body: JSON.parse(item.body)})), expectedWrites);
      }
      const modelCalls = (await readFile(join(root, 'model-calls.jsonl'), 'utf8'))
        .trim().split('\n').filter(Boolean).map(line => JSON.parse(line).score);
      assert.deepEqual(modelCalls.slice(modelsBeforePending).sort((a, b) => a - b), expectedModelInputs);
      const sourceCalls = (await readFile(join(root, 'source-calls.jsonl'), 'utf8'))
        .trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
      assert.deepEqual(sourceCalls.slice(sourceCallsBeforePending).map(item =>
        item.sourceReadSessions), expectations.sourceReadSessions);
      console.log('packed ' + transport + ' composed cleanup false → retained reservation → release passed');
      server.target.name = 'prior-name';
      const writesBeforeLost = patches().length;
      const modelsBeforeLost = (await readFile(join(root, 'model-calls.jsonl'),
        'utf8')).trim().split('\n').filter(Boolean).length;
      const sourcesBeforeLost = (await readFile(join(root, 'source-calls.jsonl'),
        'utf8')).trim().split('\n').filter(Boolean).length;
      await rce(async () => {
        assert.equal(patches().length, writesBeforeLost);
        assert.equal((await runChild('effect-run.mjs', rceEnvironment,
          ['answer'], 77)).trim(), 'approved');
        assert.equal(patches().length, writesBeforeLost);
        server.target.loseReply = true;
        for (let restart = 0; restart < 2; restart++) {
          const done = JSON.parse((await runChild('effect-run.mjs', rceEnvironment,
            ['rce-resume'])).trim());
          assert.equal(done.status, 'needs_reconciliation',
            'a lost Effect response cannot become success or an unconditional resend');
          assert.deepEqual(patches().slice(writesBeforeLost).map(item => ({
            id: item.path.split('/').at(-1), body: JSON.parse(item.body)})), expectedWrites);
        }
      }, 'lost-reply');
      assert.deepEqual((await readFile(join(root, 'model-calls.jsonl'), 'utf8'))
        .trim().split('\n').filter(Boolean).slice(modelsBeforeLost)
        .map(line => JSON.parse(line).score).sort((a, b) => a - b), expectedModelInputs);
      assert.deepEqual((await readFile(join(root, 'source-calls.jsonl'), 'utf8'))
        .trim().split('\n').filter(Boolean).slice(sourcesBeforeLost)
        .map(line => JSON.parse(line).sourceReadSessions), expectations.sourceReadSessions);
      console.log('packed ' + transport + ' composed lost Effect response → reconciliation without resend passed');
      for (const boundary of ['expired-checkpoint', 'current-denial',
        'valid-approval-after-answer-deadline']) {
        server.target.name = 'prior-name';
        const environment = {...rceEnvironment,
          ACTQL_LOCAL_STATE_DIR: join(root, 'rce-' + compositionKind + '-' + transport + '-' + boundary),
          ...(boundary !== 'current-denial'
            ? {PACKED_CHECKPOINT_TTL_MS: '30000'} : {})};
        const writesBefore = patches().length;
        const modelsBefore = (await readFile(join(root, 'model-calls.jsonl'), 'utf8'))
          .trim().split('\n').filter(Boolean).length;
        const sourcesBefore = (await readFile(join(root, 'source-calls.jsonl'), 'utf8'))
          .trim().split('\n').filter(Boolean).length;
        await rce(async () => {
          assert.equal(patches().length, writesBefore);
          if (boundary !== 'expired-checkpoint') {
            assert.equal((await runChild('effect-run.mjs', environment,
              ['answer'], 77)).trim(), 'approved');
          }
          assert.equal(patches().length, writesBefore,
            'committing approval cannot itself send the Effect');
          if (boundary !== 'current-denial') {
            const checkpoint = JSON.parse(await readFile(join(root, 'effect-deadline.json'), 'utf8'));
            const until = Date.parse(checkpoint.expiresAt);
            assert.ok(Number.isFinite(until), 'wait for the actual public Checkpoint deadline');
            await new Promise(resolve => setTimeout(resolve, Math.max(0, until - Date.now() + 100)));
          } else {
            environment.PACKED_DENY_EFFECT = '1';
          }
          for (let restart = 0; restart < 2; restart++) {
            const done = JSON.parse((await runChild('effect-run.mjs', environment,
              ['rce-resume'])).trim());
            const approved = boundary === 'valid-approval-after-answer-deadline';
            // The common waiting-exit contract cancels an unanswered expired
            // Checkpoint; resumed current-authority refusal fails before send.
            const expectedStatus = approved ? 'succeeded'
              : boundary === 'expired-checkpoint' ? 'cancelled' : 'failed';
            assert.equal(done.status, expectedStatus,
              'the same Run must respect the Checkpoint closure and current account');
            assert.deepEqual(patches().slice(writesBefore).map(item => ({
              id: item.path.split('/').at(-1), body: JSON.parse(item.body)})),
            approved ? expectedWrites : [],
            'a closed unanswered Checkpoint or current denial cannot authorize a send');
          }
        }, boundary, environment);
        assert.deepEqual((await readFile(join(root, 'model-calls.jsonl'), 'utf8'))
          .trim().split('\n').filter(Boolean).slice(modelsBefore)
          .map(line => JSON.parse(line).score).sort((a, b) => a - b), expectedModelInputs);
        assert.deepEqual((await readFile(join(root, 'source-calls.jsonl'), 'utf8'))
          .trim().split('\n').filter(Boolean).slice(sourcesBefore)
          .map(line => JSON.parse(line).sourceReadSessions),
        boundary === 'expired-checkpoint' ? expectations.sourceReadSessions.slice(0,3)
          : expectations.sourceReadSessions);
        console.log('packed ' + transport + ' composed ' + boundary + ' → same Run with current authorization and no replay passed');
      }
    }
    console.log('packed ' + transport +
      ' ' + compositionKind + ' Read→Compute→Effect recovery passed');
  }
  }
  // Same acquisition and JOIN semantics, with only a terminal Effect added.
  // Reuse the dedicated Host, signed approval and durable restart driver.
  for (const kind of optionalCases) for (const transport of ['local', 'https']) {
    const pair = [];
    for (const enabled of [false, true]) {
      server.target.name = 'prior-name';
      const environment = {...effectEnvironment,
        PACKED_RCE_TRANSPORT: transport, PACKED_COMPOSED_INFER: '1',
        PACKED_OPTIONAL_EFFECT_KIND: kind, PACKED_OPTIONAL_EFFECT_ENABLED: enabled ? '1' : '0',
        PACKED_COMPOSITION_PROFILES: 'optional-effect-' + kind + '-profiles.json',
        PACKED_COMPOSITION_DATABASES: 'optional-effect-databases.json',
        NODE_EXTRA_CA_CERTS: join(root, 'org.crt'),
        ACTQL_LOCAL_STATE_DIR: join(root, 'optional-effect-' + kind + '-' + transport + '-' + enabled)};
      delete environment.ACTQL_LOCAL_SOURCE_PROFILE;
      const lines = async name => (await readFile(join(root, name), 'utf8'))
        .trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
      const sourceBefore = (await lines('source-calls.jsonl')).length;
      const selectionBefore = (await lines('optional-effect-selections.jsonl')).length;
      const modelBefore = await readFile(join(root, 'model-calls.jsonl'), 'utf8');
      const writesBefore = server.seen.filter(item => item.method === 'PATCH').length;
      const patches = () => server.seen.filter(item => item.method === 'PATCH').slice(writesBefore);
      assert.equal((await runChild('effect-run.mjs', environment,
        ['rce-submit', 'optional-' + kind + '-' + enabled], 77)).trim(), 'held');
      const writeCounts = [patches().length];
      assert.equal(patches().length, 0, 'no write before approval, including the pure member');
      if (enabled) {
        assert.equal((await runChild('effect-run.mjs', environment, ['answer'], 77)).trim(), 'approved');
        writeCounts.push(patches().length);
        assert.equal(patches().length, 0, 'persisting approval does not dispatch the Effect');
      }
      let result;
      for (let restart = 0; restart < 2; restart++) {
        result = JSON.parse((await runChild('effect-run.mjs', environment,
          ['rce-resume', 'resubmit'])).trim());
        assert.equal(result.status, 'succeeded');
        assert.deepEqual(result.rows, optionalEffectExpectations.rows);
        assert.deepEqual(result.columns, optionalEffectExpectations.columns);
        writeCounts.push(patches().length);
      }
      const expected = optionalEffectExpectations[enabled ? 'withEffect' : 'withoutEffect'];
      const sourceCalls = (await lines('source-calls.jsonl')).slice(sourceBefore);
      assert.deepEqual(sourceCalls.map(item => item.sourceReadSessions), expected.sourceReadSessions);
      const databases = JSON.parse(await readFile(join(root, 'optional-effect-databases.json'), 'utf8'));
      const expectedDatabases = [databases.left, databases.right].sort();
      assert.deepEqual([...new Set(sourceCalls[0].sourceReadCommands.map(item => item.database))].sort(),
        expectedDatabases, 'both exact used Sources are read, once each');
      for (const database of expectedDatabases) {
        assert.equal(new Set(sourceCalls[0].sourceReadCommands.filter(item => item.database === database)
          .map(item => item.session)).size, 1);
      }
      for (const recovered of sourceCalls.slice(1)) {
        assert.deepEqual(recovered.sourceProviderOpens, []);
        assert.equal(recovered.sourceIo, 0, 'recovery must not execute any provider SQL');
      }
      assert.equal(await readFile(join(root, 'model-calls.jsonl'), 'utf8'), modelBefore,
        'no Model is present in either submitted Program');
      const selections = (await lines('optional-effect-selections.jsonl')).slice(selectionBefore)
        .map(item => item.selection);
      assert.equal(selections.length, 2, 'observe actual selection for both acquisitions');
      for (const selection of selections) {
        assert.equal(selection.status, 'selected');
        assert.equal(selection.selectedCandidate, kind === 'broad-text' ? 'broadQuery' : 'nativeQuery');
        assert.equal(selection.selectionBasis, 'explicitPriority');
        assert.ok(selection.nativeSupported && selection.broadSupported,
          'Effect presence must preserve both provider eligibility judgments');
      }
      assert.deepEqual(writeCounts, expected.writeCounts);
      const writes = patches().map(item => ({id: item.path.split('/').at(-1), body: JSON.parse(item.body)}));
      assert.deepEqual(writes, enabled ? optionalEffectExpectations.writes : []);
      const ref = JSON.parse(await readFile(join(root, 'effect-ref.json'), 'utf8'));
      const boundaries = (await lines('restart-boundaries.jsonl')).filter(item => item.transport === transport &&
        item.ref.runDefinitionCid === ref.runDefinitionCid && item.ref.authorityScopeCid === ref.authorityScopeCid);
      assert.deepEqual(boundaries.map(item => item.boundary), expected.restartBoundaries);
      for (const boundary of boundaries) assert.deepEqual(boundary.ref, ref);
      const submission = JSON.parse(await readFile(join(root, 'rce-submission.json'), 'utf8'));
      const observation = {sourceRevision, kind, transport, effectEnabled: enabled,
        requestId: submission.requestId, ref, submittedFormat: submission.format,
        submittedProgramSha256: createHash('sha256').update(submission.document).digest('hex'),
        sourceReadSessions: sourceCalls.map(item => item.sourceReadSessions),
        modelCalls: 0, writeCounts, writes, selections,
        rows: result.rows, columns: result.columns, restartBoundaries: boundaries};
      await appendFile(join(root, 'optional-effect-acceptance.jsonl'), JSON.stringify(observation) + '\n');
      console.log('packed optional Effect acceptance ' + JSON.stringify(observation));
      pair.push(observation);
    }
    assert.deepEqual(pair[0].rows, pair[1].rows);
    assert.deepEqual(pair[0].columns, pair[1].columns);
    const eligibility = selection => ({status: selection.status, selectionBasis: selection.selectionBasis,
      selectedCandidate: selection.selectedCandidate,
      nativeSupported: selection.nativeSupported, broadSupported: selection.broadSupported});
    assert.deepEqual(pair[0].selections.map(eligibility), pair[1].selections.map(eligibility),
      'the same priority and input requirements remain eligible with or without the Effect');
  }
  if (composed) {
    const boundaries = (await readFile(join(root, 'restart-boundaries.jsonl'), 'utf8'))
      .trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
    for (const transport of ['local', 'https']) {
      assert.ok(boundaries.some(item => item.transport === transport &&
        item.boundary === 'capture-waiting'));
      assert.ok(boundaries.some(item => item.transport === transport &&
        item.boundary === 'approval-committed'));
    }
    console.log('packed composed Host + execution process termination at durable capture and approval passed');
  }
  console.log('packed public Client Read→Compute→Effect passed');
  passed = true;
} finally {
  await server.close();
  if (passed && !process.argv.includes('--keep-artifacts')) await rm(root, {recursive: true, force: true});
  else if (passed) console.log('Preserved packed composition evidence at ' + root);
  else console.error('Preserved failed packed composition at ' + root);
}
