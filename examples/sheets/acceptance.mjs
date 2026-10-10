// Copy into an isolated external installation; never run against an unapproved file.
// Operator-owned acceptance, not a new execution or recovery owner.
// All product imports must resolve from the external release installation.
import assert from 'node:assert/strict';
import {generateKeyPairSync, randomBytes, sign} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import {connect as localConnect} from '@actql/node';
import {connect as remoteConnect} from '@actql/sdk';
import {canonicalJson} from '@actql/sdk/host-port';
import {publishSource, publishEffect} from '@actql/local-node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';

const root = fileURLToPath(new URL('./', import.meta.url));
const [action, transport = 'local', selectedCase = 'normal'] = process.argv.slice(2);
const config = JSON.parse(await readFile(process.env.ACTQL_SHEETS_CAMPAIGN ?? join(root, 'campaign.json'), 'utf8'));
assert.equal(typeof config.spreadsheetId, 'string');
assert(config.spreadsheetId.length > 0 && !config.spreadsheetId.includes('REPLACE'));
assert(Number.isSafeInteger(config.readSheetId) && config.readSheetId >= 0);
assert(Number.isSafeInteger(config.appendSheetId) && config.appendSheetId >= 0);
assert.notEqual(config.readSheetId, config.appendSheetId);
assert.equal(typeof config.campaignMarker, 'string');
assert(config.campaignMarker.length > 0);
function accessToken() {
  const token = process.env.ACTQL_SHEETS_ACCESS_TOKEN;
  assert(typeof token === 'string' && token.length > 0, 'Supply an existing private token reference');
  return token;
}
assert.equal(config.maxAppendRows, 2);
assert(['local', 'https'].includes(transport));
const columns = [
  {name: 'text', type: 'string', nullable: false},
  {name: 'number', type: 'number', nullable: true},
  {name: 'flag', type: 'boolean', nullable: true},
];
// Independent expectations; no successful response supplies expected rows.
const cases = {
  normal: {startRow: 1, endRow: 4, rows: [
    {text: '=literal', number: 0, flag: false},
    {text: 'e\u0301', number: 7, flag: true},
    {text: 'e\u0301', number: 7, flag: true},
  ]},
  nullable: {startRow: 5, endRow: 7, rows: [{text: 'missing', number: null, flag: null}]},
  empty: {startRow: 6, endRow: 7, rows: []},
  formula: {startRow: 1, endRow: 7, refused: 'MissingEffectiveValue'},
  error: {startRow: 7, endRow: 8, refused: 'CellError'},
};
const owner = userInfo().username;
const reviewer = 'sheets-acceptance-reviewer';
const connection = `sheets:sheets.googleapis.com/${config.spreadsheetId}`;
const pem = key => key.export({format: 'pem', type: key.type === 'private' ? 'pkcs8' : 'spki'});
const entry = (entry_id, outcome, resource, operation) => ({entry_id, outcome,
  principal: {any_of: [owner]}, connection: {any_of: [connection]},
  resource: {any_of: [resource]}, operation: {any_of: [operation]}, exclusions: []});
const account = canonicalJson({version: 'actql-execution-account-config/0.1',
  account_id: 'sheets-real-acceptance', entries: [
    entry('append', 'delegate', 'append_rows', 'effect'),
    entry('append-read', 'allow', 'append_rows', 'read'),
    entry('read', 'allow', 'rows', 'read'),
    {entry_id: 'run', outcome: 'allow', principal: {any_of: [owner]},
      connection: {all: true}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []},
  ]});
async function json(path, value) {
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, {flag: 'wx', mode: 0o600});
}
const readJson = async path => JSON.parse(await readFile(path, 'utf8'));
const authorization = keys => ({accountConfiguration: account,
  reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
    principalId: reviewer, publicKey: keys.reviewerPublic}],
  reviewReaders: [reviewer],
  hostKey: {keyId: 'host-key', privateKey: keys.hostPrivate},
  leaseMs: 10_000, resumeAfterAnswer: false});
const closes = [];
async function open(directory, effect, mode) {
  const keys = await readJson(join(root, 'host-keys.json'));
  const token = accessToken();
  const installation = {directory: join(directory, 'state'),
    ...(effect ? {effectProfilePath: join(directory, 'effect.json'), resolveEffectSecret: async () => token}
      : {sourceProfilePath: join(directory, 'source.json'), resolveSourceSecret: async () => token}),
    authorization: authorization(keys)};
  if (mode === 'local') {
    const client = await localConnect({mode: 'local', owner: 'local', durability: 'durable', installation});
    closes.push(() => client.close());
    return {client};
  }
  const tlsRoot = config.tlsDirectory ?? join(root, 'tls');
  const tls = {key: await readFile(join(tlsRoot, 'resource.key')),
    cert: await readFile(join(tlsRoot, 'resource.crt')),
    ca: await readFile(join(tlsRoot, 'ca.crt'))};
  setDefaultCACertificates([...getCACertificates('default'), tls.ca.toString('utf8')]);
  const ownerToken = keys.ownerToken, reviewerToken = keys.reviewerToken;
  const host = await openInstalledRemoteHttpHost({...installation,
    authenticate: header => new Map([[ownerToken, owner], [reviewerToken, reviewer]])
      .get(header?.replace(/^Bearer /u, ''))});
  const server = createServer(tls, host.handler);
  await new Promise((resolve, reject) => {
    server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
  });
  closes.push(async () => {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve)); await host.close();
  });
  async function as(selected) {
    const client = await remoteConnect({mode: 'remote',
      endpoint: `https://127.0.0.1:${server.address().port}/`,
      token: selected === 'reviewer' ? reviewerToken : ownerToken, durability: 'durable'});
    closes.push(() => client.close());
    return client;
  }
  return {client: await as('owner'), as};
}
async function settled(execution) {
  const deadline = performance.now() + 60_000;
  while (performance.now() < deadline) {
    const state = await execution.status();
    if (['succeeded', 'failed', 'cancelled', 'waiting_checkpoint', 'needs_reconciliation'].includes(state.status)) return state;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw new Error('OriginalRunBoundaryTimeout');
}
const program = JSON.stringify({version: 'actql/0.1', id: 'sheets-real-read', stages: [{
  id: 'read', inputs: {sheet: {connector: 'sheet-book', resource: 'rows'}},
  steps: [{filter: 'true', as: 'scanned'}, {select: ['text', 'number', 'flag'], as: 'out'}],
  results: {rows: {from: 'out', fields: ['text', 'number', 'flag']}},
}, {id: 'compute', inputs: {captured: {result: {stage: 'read', result: 'rows'}}},
  steps: [{select: ['text', 'number', 'flag'], as: 'out'}],
  results: {rows: {from: 'out', fields: ['text', 'number', 'flag']}},
}], results: {answer: {from: {stage: 'compute', result: 'rows'}}}});

// Read-only observation of the real credential owner. A claim alone is not
// labelled a physical send; saved response/Google readback remain separate facts.
function credentialCounts(directory) {
  const database = new DatabaseSync(join(directory, 'credential-journal/credential-journal.sqlite3'), {readOnly: true});
  try {
    return database.prepare(`SELECT g.grant_json, u.outcome FROM credential_uses u
      JOIN credential_grants g ON u.grant_cid = g.grant_cid`).all()
      .reduce((totals, row) => {
        const grant = JSON.parse(row.grant_json);
        const operation = grant.operation;
        assert(['sheets:cells:append', 'sheets:grid:read'].includes(operation));
        const name = operation === 'sheets:cells:append' ? 'append' : 'read';
        totals[name]++; return totals;
      }, {append: 0, read: 0});
  } finally {database.close();}
}

try {
  if (action === 'setup') {
    for (const name of ['resource.key', 'resource.crt', 'ca.crt']) {
      await readFile(join(config.tlsDirectory ?? join(root, 'tls'), name));
    }
    const reviewerPair = generateKeyPairSync('ed25519'), hostPair = generateKeyPairSync('ed25519');
    const credentialPair = generateKeyPairSync('ed25519');
    await json(join(root, 'host-keys.json'), {reviewerPublic: pem(reviewerPair.publicKey),
      reviewerPrivate: pem(reviewerPair.privateKey), hostPrivate: pem(hostPair.privateKey),
      ownerToken: randomBytes(32).toString('base64url'),
      reviewerToken: randomBytes(32).toString('base64url')});
    await writeFile(join(root, 'credential-signing.key'), pem(credentialPair.privateKey), {flag: 'wx', mode: 0o600});
    // HTTPS uses operator-provided localhost certificates, never a new trust service.
    for (const [name, shape] of [...Object.entries(cases), ['append', cases.normal]]) {
      for (const mode of name === 'append' ? ['https'] : ['local', 'https']) {
        const directory = join(root, `${name}-${mode}`);
        await mkdir(directory, {mode: 0o700});
        const site = {version: 'actql-installed-sheets-site/0.1',
          apiOrigin: 'https://sheets.googleapis.com', spreadsheetId: config.spreadsheetId,
          gridRange: {sheetId: config.readSheetId, startRow: shape.startRow, endRow: shape.endRow,
            startColumn: 0, endColumn: 3}, appendSheetId: config.appendSheetId, columns,
          namespaceId: 'sheets-real-acceptance', environment: 'test', siteKey: `sheets-${name}-${mode}`,
          siteGeneration: 1, credentialAuthorityId: 'sheets-real-authority', credentialKeyId: 'sheets-real-key',
          credentialPrivateKeyPath: join(root, 'credential-signing.key'),
          journalRoot: join(directory, 'credential-journal'), tokenEnvironment: 'ACTQL_SHEETS_ACCESS_TOKEN'};
        await json(join(directory, 'site.json'), site);
        const base = {siteProfilePath: join(directory, 'site.json'),
          publicationPath: join(directory, 'publication.json'), connectorId: 'sheet-book',
          accountConfigurationWire: account};
        await json(join(directory, 'source.json'), {...base, version: 'actql-installed-sheets-source/0.1'});
        await json(join(directory, 'effect.json'), {...base, version: 'actql-installed-sheets-effect/0.1',
          sources: columns.map(column => ({target: column.name, field: column.name, null_behavior: 'reject'}))});
      }
    }
    console.log('SHEETS_REAL_SETUP_READY');
  } else if (action === 'read') {
    const shape = cases[selectedCase]; assert.ok(shape);
    const directory = join(root, `${selectedCase}-${transport}`);
    const token = accessToken();
    await publishSource({sourceProfilePath: join(directory, 'source.json'),
      directory: join(directory, 'state'), resolveSourceSecret: async () => token});
    const {client} = await open(directory, false, transport);
    const submissionRef = client.newSubmission();
    await json(join(directory, 'submission.json'), submissionRef);
    const execution = await client.startSource(program, {format: 'json', submissionRef});
    await json(join(directory, 'run.json'), execution.ref);
    const state = await settled(execution);
    if (shape.refused) {
      assert.equal(state.status, 'failed'); assert.equal(state.result_available, false);
    } else {
      assert.equal(state.status, 'succeeded');
      assert.deepEqual(await execution.result('answer').all(), shape.rows);
      const before = credentialCounts(directory);
      assert.deepEqual(await execution.result('answer').all(), shape.rows);
      const repeated = await client.startSource(program, {format: 'json', submissionRef});
      assert.deepEqual(await repeated.result('answer').all(), shape.rows);
      assert.deepEqual(credentialCounts(directory), before);
    }
    await json(join(directory, 'receipt.json'), {action, transport, selectedCase,
      status: state.status, resultAvailable: state.result_available,
      independentlyExpectedRefusal: shape.refused, credentialCounts: credentialCounts(directory)});
    console.log('SHEETS_REAL_READ_VERIFIED', transport, selectedCase, state.status);
  } else if (['append-start', 'approve', 'resume', 'replay'].includes(action)) {
    assert.equal(transport, 'https');
    const directory = join(root, 'append-https');
    const rows = [{text: config.campaignMarker, number: 0, flag: false},
      {text: config.campaignMarker, number: 0, flag: false}];
    const keys = await readJson(join(root, 'host-keys.json'));
    if (action === 'append-start') {
      assert.equal(config.appendPermissionConfirmed, true, 'Explicit resource-owner append permission required');
      // EXCL custody record below prevents repeating the original submission.
      const token = accessToken();
      const {mappings: [mapping]} = await publishEffect({effectProfilePath: join(directory, 'effect.json'),
        directory: join(directory, 'state'), resolveEffectSecret: async () => token});
      const {client} = await open(directory, true, transport);
      const submissionRef = client.newSubmission();
      await json(join(directory, 'submission.json'), submissionRef);
      const document = JSON.stringify({version: 'actql/0.1', id: 'sheets-real-append', stages: [{
        id: 'write', inputs: {}, steps: [{values: {schema: Object.fromEntries(columns.map(({name, ...type}) => [name, type])), rows}, as: 'out'}],
        results: {rows: {from: 'out', fields: ['text', 'number', 'flag']}},
        effects: {append: {create: {target: mapping.target, mapping: mapping.mappingRef, from: {result: 'rows'}}}},
      }], results: {answer: {from: {stage: 'write', result: 'rows'}}}});
      const execution = await client.startSource(document, {format: 'json', submissionRef});
      await json(join(directory, 'run.json'), execution.ref);
      assert.equal((await settled(execution)).status, 'waiting_checkpoint');
      assert.equal(credentialCounts(directory).append, 0);
    } else {
      const ref = await readJson(join(directory, 'run.json'));
      const beforeOpening = credentialCounts(directory);
      const host = await open(directory, true, transport);
      if (action === 'approve') {
        const client = await host.as('reviewer');
        const {items} = await client.checkpoints();
        assert.equal(items.length, 1); assert.equal(items[0].kind, 'effect_set');
        const answer = await client.resolveCheckpoints([{checkpoint: items[0], decision: 'approved'}], {
          signer: {keyId: 'reviewer-key', reviewerId: 'reviewer', authorityScopeCid: ref.authorityScopeCid,
            sign: bytes => sign(null, bytes, keys.reviewerPrivate)}});
        assert.deepEqual(answer.results.map(result => result.status), ['committed']);
        assert.equal(credentialCounts(directory).append, 0);
      } else {
        const execution = await host.client.attach(ref);
        const state = await settled(execution);
        if (state.status === 'needs_reconciliation') throw new Error('UnknownAppendPreserved:STOP_REAL_WRITES');
        assert.equal(state.status, 'succeeded');
        assert.deepEqual(await execution.result('answer').all(), rows);
        const after = credentialCounts(directory);
        assert.equal(after.append, 2);
        if (action === 'replay') assert.deepEqual(after, beforeOpening);
      }
    }
    await json(join(directory, `${action}-${process.pid}.receipt.json`), {action, credentialCounts: credentialCounts(directory)});
    console.log('SHEETS_REAL_APPEND_BOUNDARY_VERIFIED', action);
  } else throw new Error('UnknownAcceptanceAction');
} finally {
  for (const close of closes.reverse()) await close();
}
