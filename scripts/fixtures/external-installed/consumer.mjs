import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {generateKeyPairSync, sign} from 'node:crypto';
import {Readable, Writable} from 'node:stream';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import http from 'node:http';
import https from 'node:https';
import {syncBuiltinESMExports} from 'node:module';
import net from 'node:net';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import tls from 'node:tls';
import {promisify} from 'node:util';
import {connect, publishEffect} from '@actql/local-node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {createHostObservationConnection} from '@actql/local-node/observation';
import {canonicalJson} from '@actql/sdk/host-port';

const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki',
  format: 'pem'});
const principalId = userInfo().username;
const terminal = ['succeeded', 'failed', 'cancelled', 'needs_reconciliation'];
const execute = promisify(execFile);
const privateFile = {mode: 0o600, flag: 'wx'};

async function until(check) {
  const deadline = Date.now() + 20_000;
  while (Date.now() < deadline) {
    const result = await check();
    if (result) return result;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  throw new Error('ExternalInstalledFixtureTimeout');
}

const stateOf = execution => until(async () => {
  const state = await execution.status();
  return terminal.includes(state.status) || state.status === 'waiting_checkpoint'
    ? state : undefined;
});

// Capture only the physical HTTPS request. The unchanged common credential
// owner still signs, claims, authorizes, resolves the synthetic credential and
// finishes its journal. No socket, real credential or external service is used.
// Actual Node streams supply readable/body and close events; the explicit
// transport port does not stand in for a real socket's physical cleanup ACK.
export function captureFixtureTransport() {
  const originals = {fetch: globalThis.fetch, request: https.request,
    httpsGet: https.get, httpRequest: http.request, httpGet: http.get,
    connect: net.connect, createConnection: net.createConnection, tlsConnect: tls.connect};
  const state = {requests: [], events: [], readMode: 'ok', effectMode: 'ok',
    records: {selected: {id: 'selected', note: 'before'}, cleared: {id: 'cleared', note: 'original note'},
      refused: {id: 'refused', note: 'before refusal'},
      lost: {id: 'lost', note: 'before lost response'}, conflict: {id: 'conflict', note: 'original before'},
      control: {id: 'control', note: 'unchanged'}},
    updateWrites: 0, secretCalls: 0, forbiddenNetworkCalls: 0};
  const forbidden = () => {
    state.forbiddenNetworkCalls++;
    throw new Error('ExternalInstalledFixtureNetworkForbidden');
  };
  globalThis.fetch = forbidden;
  http.request = forbidden; http.get = forbidden; https.get = forbidden;
  net.connect = forbidden; net.createConnection = forbidden; tls.connect = forbidden;
  https.request = (options, onResponse) => {
    const read = options.hostname === 'external-read.fixture.invalid';
    const effect = options.hostname === 'external-effect.fixture.invalid';
    if ((!read && !effect) || options.protocol !== 'https:') return forbidden();
    let response, originalBody, finishRequest;
    let ended = false;
    const detach = () => options.signal?.removeEventListener('abort', abort);
    const request = new Writable({
      write(_chunk, _encoding, done) {done();},
      final(done) {
        finishRequest = done;
        queueMicrotask(() => {
          if (request.destroyed) return;
          if (options.signal?.aborted) return abort();
          assert.equal(options.headers.authorization, 'Bearer fixture-only-token');
          const body = originalBody;
          state.requests.push({hostname: options.hostname, path: options.path,
            method: options.method, ...(body === undefined ? {} : {body})});
          if (read && state.readMode === 'hold') return;
          let statusCode;
          let value;
          if (read) {
            assert.equal(options.method, 'GET');
            assert.ok(['/records?page=0', '/records?page=1'].includes(options.path));
            statusCode = state.readMode === 'provider-error' ? 503 : 200;
            value = state.readMode === 'provider-error' ? {error: 'unavailable'}
              : state.readMode === 'invalid-page' ? {items: [{key: 'bad'}], next: null}
              : options.path.endsWith('=0')
                ? {items: [{key: 'alpha', amount: 7}, {key: 'beta', amount: 2}], next: 1}
                : {items: [{key: 'gamma', amount: 11}], next: null};
          } else if (['/events/selected', '/events/cleared', '/events/refused', '/events/lost', '/events/conflict'].includes(options.path)) {
            const id = options.path.slice('/events/'.length);
            assert.ok(['GET', 'PUT'].includes(options.method));
            if (options.method === 'PUT') {
              const change = JSON.parse(body);
              assert.deepEqual(Object.keys(change), ['note']);
              assert.ok(change.note === null || typeof change.note === 'string');
              state.records[id] = {...state.records[id], note: change.note};
              state.updateWrites++;
              if (id === 'lost') {
                return request.destroy(Object.assign(new Error('FixtureUpdateReplyLost'), {code: 'ECONNRESET'}));
              }
            } else {
              assert.equal(body, undefined);
            }
            statusCode = 200;
            value = state.records[id];
          } else {
            assert.equal(options.method, 'POST');
            assert.equal(options.path, '/events');
            const event = JSON.parse(body);
            state.events.push(event);
            if (state.effectMode === 'lost-response') {
              return request.destroy(Object.assign(new Error('FixtureReplyLost'), {code: 'ECONNRESET'}));
            }
            statusCode = state.effectMode === 'typed-failure' ? 400 : 201;
            value = state.effectMode === 'typed-failure' ? {error: 'invalid_note'}
              : {id: `event-${state.events.length}`, key: event.key};
          }
          response = new Readable({read() {}});
          response.statusCode = statusCode;
          response.headers = {};
          response.rawHeaders = [];
          response.once('close', () => {
            const finish = finishRequest;
            finishRequest = undefined;
            finish?.();
          });
          onResponse(response);
          response.push(Buffer.from(JSON.stringify(value)));
          response.push(null);
        });
      },
      destroy(cause, done) {
        detach();
        finishRequest = undefined;
        response?.destroy(cause);
        done(cause);
      },
    });
    const abort = () => request.destroy(Object.assign(new Error('The operation was aborted'),
      {name: 'AbortError', code: 'ABORT_ERR'}));
    options.signal?.addEventListener('abort', abort, {once: true});
    request.once('close', detach);
    const end = request.end;
    request.end = function (body, ...args) {
      assert.equal(this, request);
      assert.equal(ended, false);
      ended = true;
      originalBody = body;
      return Reflect.apply(end, request, [body, ...args]);
    };
    return request;
  };
  syncBuiltinESMExports();
  return {state,
    resolveSecret: async () => { state.secretCalls++; return 'fixture-only-token'; },
    restore() {
      globalThis.fetch = originals.fetch;
      https.request = originals.request; https.get = originals.httpsGet;
      http.request = originals.httpRequest; http.get = originals.httpGet;
      net.connect = originals.connect; net.createConnection = originals.createConnection;
      tls.connect = originals.tlsConnect;
      syncBuiltinESMExports();
    }};
}

export function readProgram({resource = 'records', id = 'external-read'} = {}) {
  return JSON.stringify({version: 'actql/0.1', id,
    stages: [{id: 'read', inputs: {external: {connector: 'external-reader', resource}},
      steps: [{filter: 'amount >= 0', as: 'positive'},
        {select: ['id', 'amount'], as: 'captured'}],
      results: {rows: {from: 'captured', fields: ['id', 'amount']}}},
    {id: 'compute', inputs: {captured: {result: {stage: 'read', result: 'rows'}}},
      steps: [{select: ['id', 'amount'], as: 'out'}],
      results: {rows: {from: 'out', fields: ['id', 'amount']}}}],
    results: {rows: {from: {stage: 'compute', result: 'rows'}}}});
}

export function effectProgram(mapping, {key = 'alpha', note = 'hello',
  id = 'external-effect'} = {}) {
  return JSON.stringify({version: 'actql/0.1', id,
    stages: [{id: 'create', inputs: {}, steps: [
      {values: {schema: {key: {type: 'string', nullable: false},
        note: {type: 'string', nullable: false}}, rows: [{key, note}]}, as: 'input'}],
    results: {rows: {from: 'input', fields: ['key', 'note']}},
    effects: {create_event: {create: {target: mapping.target,
      mapping: mapping.mappingRef, from: {result: 'rows'}}}}}],
    results: {rows: {from: {stage: 'create', result: 'rows'}}}});
}

function updateProgram(mapping, {id, note}) {
  return JSON.stringify({version: 'actql/0.1', id: 'external-update',
    stages: [{id: 'update', inputs: {}, steps: [
      {values: {schema: {id: {type: 'string', nullable: false},
        note: {type: 'string', nullable: true}}, rows: [{id, note}]}, as: 'input'}],
    results: {rows: {from: 'input', fields: ['id', 'note']}, verification: {from: 'input', fields: ['id']}},
    effects: {update_event: {update: {target: mapping.target, id: 'id',
      set: {note: {field: 'note'}}, mapping: mapping.mappingRef, from: {result: 'rows'}}}}}],
    results: {rows: {from: {stage: 'update', result: 'rows'}},
      verification: {from: {stage: 'update', result: 'verification'}}}});
}

export async function createFixtureProfiles(directory, {read = 'allow',
  effect = 'delegate', observe} = {}) {
  await mkdir(directory, {recursive: true});
  const authority = generateKeyPairSync('ed25519');
  const credentialPrivateKeyPath = join(directory, 'fixture.key');
  await writeFile(credentialPrivateKeyPath, pem(authority.privateKey), {mode: 0o600});
  const accountConfigurationWire = canonicalJson({
    version: 'actql-execution-account-config/0.1', account_id: 'external-fixture',
    entries: [
      {entry_id: 'effect', outcome: effect, exclusions: [], principal: {all: true},
        connection: {all: true}, resource: {all: true}, operation: {any_of: ['effect']}},
      {entry_id: 'host', outcome: 'allow', exclusions: [], principal: {all: true},
        connection: {all: true}, resource: {all: true}, operation: {any_of: ['write']}},
      {entry_id: 'read', outcome: read, exclusions: [], principal: {all: true},
        connection: {all: true}, resource: {all: true}, operation: {any_of: ['read']}},
    ]});
  const paths = {};
  for (const [role, registration, host, version, connectorId] of [
    ['source', 'external_read', 'external-read',
      'actql-installed-external-read-source/0.1', 'external-reader'],
    ['effect', 'external_effect', 'external-effect',
      'actql-installed-external-effect/0.1', 'external-writer'],
  ]) {
    const siteProfilePath = join(directory, `${role}-site.json`);
    await writeFile(siteProfilePath, JSON.stringify({
      resourceOrigin: `https://${host}.fixture.invalid`, namespaceId: 'fixture',
      environment: 'test', siteKey: registration, siteGeneration: 1,
      credentialAuthorityId: 'fixture-authority', credentialKeyId: 'fixture-key',
      credentialPrivateKeyPath, journalRoot: join(directory, `${role}-credentials`)}));
    paths[`${role}ProfilePath`] = join(directory, `${role}.json`);
    await writeFile(paths[`${role}ProfilePath`], JSON.stringify({version,
      connectorId, siteProfilePath, accountConfigurationWire}));
  }
  const reviewer = generateKeyPairSync('ed25519');
  const hostKey = generateKeyPairSync('ed25519');
  return {...paths,
    authorization: {accountConfiguration: accountConfigurationWire,
      reviewers: [{keyId: 'fixture-reviewer-key', reviewerId: 'fixture-reviewer',
        principalId, publicKey: pem(reviewer.publicKey)}], reviewReaders: [principalId],
      hostKey: {keyId: 'fixture-host-key', privateKey: pem(hostKey.privateKey)},
      resumeAfterAnswer: true, leaseMs: 10_000, observe},
    signer: {keyId: 'fixture-reviewer-key', reviewerId: 'fixture-reviewer',
      sign: bytes => sign(null, bytes, reviewer.privateKey)}};
}

const stopped = (execution, expected) => until(async () => {
  const state = await execution.status();
  if (state.status !== expected || state.control?.physical_stop !== 'confirmed') return;
  return state;
});

// The child receives the original Host inputs and reference, with no signer.
// Its transport refuses ambient network and measures recovery traffic itself.
export async function observeExternalUpdateSaved(inputPath, outcomePath) {
  const {directory, effectProfilePath, authorizationPath, reference, runId, status, results} =
    JSON.parse(await readFile(inputPath, 'utf8'));
  const authorization = JSON.parse(await readFile(authorizationPath, 'utf8'));
  const transport = captureFixtureTransport();
  let client, primary;
  const observedResults = {};
  try {
    client = await connect({mode: 'local', owner: 'local', durability: 'durable',
      installation: {directory, retainedRelationOutput: true, effectProfilePath,
        resolveEffectSecret: transport.resolveSecret, authorization}});
    const restored = await client.attach(reference);
    assert.deepEqual(restored.ref, reference);
    if (results !== undefined) {
      for (const [name, expected] of Object.entries(results)) {
        const observed = await restored.result(name).all();
        assert.deepEqual(observed, expected);
        observedResults[name] = observed;
      }
    }
    const observed = await stateOf(restored);
    assert.equal(observed.run_id, runId);
    assert.equal(observed.status, status);
  } catch (cause) {
    primary = {cause};
    throw cause;
  } finally {
    try { await client?.close(); }
    catch (cleanup) {
      if (primary === undefined) throw cleanup;
      throw new AggregateError([primary.cause, cleanup], 'ExternalSavedReadAndCloseFailed', {cause: primary.cause});
    } finally { transport.restore(); }
  }
  const {requests, updateWrites, secretCalls, forbiddenNetworkCalls} = transport.state;
  assert.equal(requests.length + updateWrites + secretCalls + forbiddenNetworkCalls, 0);
  await writeFile(outcomePath, JSON.stringify({pid: process.pid, reference, runId, status, firstClose: true,
    resultNames: Object.keys(observedResults), results: observedResults,
    requests: requests.length, updateWrites, secretCalls, forbiddenNetworkCalls}), privateFile);
}

async function externalUpdateCold(settings, receiptRoot) {
  const input = join(receiptRoot, 'cold-input.json'), output = join(receiptRoot, 'cold-outcome.json');
  await mkdir(receiptRoot, {mode: 0o700});
  await writeFile(input, JSON.stringify(settings), privateFile);
  const command = `import {observeExternalUpdateSaved} from ${JSON.stringify(import.meta.url)};\n` +
    'await observeExternalUpdateSaved(...process.argv.slice(1));';
  const child = execute(process.execPath, ['--input-type=module', '-e', command, input, output],
    {timeout: 30000, maxBuffer: 8 * 1024 ** 2});
  const pid = child.child.pid;
  await child;
  const outcome = JSON.parse(await readFile(output, 'utf8'));
  assert.equal(outcome.pid, pid);
  assert.notEqual(outcome.pid, process.pid);
  assert.deepEqual(outcome.reference, settings.reference);
  assert.equal(outcome.runId, settings.runId);
  assert.equal(outcome.status, settings.status);
  assert.equal(outcome.firstClose, true);
  assert.deepEqual(outcome.results, settings.results ?? {});
  return outcome;
}

// The harness passes the normal generated installation table and resolver.
// Runtime modules are loaded from that resolver, not a fixture-specific path.
export async function verifyExternalInstalledFixture({directory,
  installedConnectors, providerBundleUrl}) {
  const entries = ['external_read', 'external_effect'].map(name =>
    installedConnectors.find(entry => entry.registration === name));
  assert.ok(entries.every(Boolean));
  assert.ok(entries[0].source); assert.equal(entries[0].effect, undefined);
  assert.ok(entries[1].effect); assert.equal(entries[1].source, undefined);
  for (const entry of entries) {
    assert.equal(entry.compute, undefined);
    const provider = await import(providerBundleUrl(entry).href);
    const role = entry.source ?? entry.effect;
    const adapter = await role.load();
    assert.equal(typeof adapter.load, 'function');
    if (entry.source) {
      assert.deepEqual(JSON.parse(provider.externalReadPageJson(Buffer.from(
        '{"items":[{"key":"independent","amount":17}],"next":null}'), 0)),
      {rows: [{id: 'independent', amount: 17}], next: null});
      assert.ok(JSON.parse(provider.externalReadPageJson(Buffer.alloc(4097), 0)).refused);
    } else {
      assert.deepEqual(JSON.parse(provider.externalEffectObservationJson(201,
        Buffer.from('{"id":"created-17","key":"independent"}'), 'independent')),
      {kind: 'typed-success-response', outcome: {state: 'applied', result: {id: 'created-17'}}});
      assert.equal(JSON.parse(provider.externalEffectObservationJson(201,
        Buffer.from('{"id":"created-17","key":"foreign"}'), 'independent')).kind,
      'unclassified-response');
    }
  }
  const observations = [];
  const clients = new Set();
  const profiles = await createFixtureProfiles(join(directory, 'profiles'), {
    observe: (name, details) => observations.push([name, details])});
  const transport = captureFixtureTransport();
  const open = async (role, profilesForRun = profiles, name = role, observation) => {
    const client = await connect({mode: 'local', owner: 'local', durability: 'durable',
      installation: {directory: join(directory, name), retainedRelationOutput: true,
        ...(observation === undefined ? {} : {observation}),
        [`${role}ProfilePath`]: profilesForRun[`${role}ProfilePath`],
        [`resolve${role === 'source' ? 'Source' : 'Effect'}Secret`]: transport.resolveSecret,
        authorization: profilesForRun.authorization}});
    clients.add(client);
    return client;
  };
  const close = async client => { await client.close(); clients.delete(client); };
  const resolveCheckpoint = async (client, execution, {decision = 'approved', original} = {}) => {
    const checkpoint = original ?? (await client.checkpoints()).items.find(item => item.kind === 'effect_set');
    assert.ok(checkpoint);
    const result = await client.resolveCheckpoints([{checkpoint, decision}],
      {signer: {...profiles.signer, authorityScopeCid: execution.ref.authorityScopeCid}});
    assert.deepEqual(result.results.map(item => item.status), ['committed']);
    return {checkpoint, result};
  };
  let primaryFailure;
  try {
    const reader = await open('source');
    assert.equal(transport.state.requests.length, 0);
    assert.equal(transport.state.secretCalls, 0);
    const captured = await reader.startSource(readProgram(), {format: 'json',
      submissionRef: reader.newSubmission({nonce: 'read-ok'})});
    const capturedState = await stateOf(captured);
    assert.equal(capturedState.status, 'succeeded', JSON.stringify({state: capturedState,
      observations, requests: transport.state.requests}, (_key, value) =>
      typeof value === 'bigint' ? value.toString() : value));
    assert.deepEqual(await captured.result('rows').all(), [
      {id: 'alpha', amount: 7}, {id: 'beta', amount: 2}, {id: 'gamma', amount: 11}]);
    assert.equal(transport.state.requests.length, 2);
    await stopped(captured, 'succeeded');
    const readRuns = [[captured.ref, 'succeeded']];

    for (const mode of ['provider-error', 'invalid-page']) {
      transport.state.readMode = mode;
      const failed = await reader.startSource(readProgram({id: mode}), {
        format: 'json', submissionRef: reader.newSubmission({nonce: mode})});
      assert.equal((await stateOf(failed)).status, 'failed');
      await stopped(failed, 'failed');
      readRuns.push([failed.ref, 'failed']);
    }
    transport.state.readMode = 'hold';
    const count = transport.state.requests.length;
    const cancelled = await reader.startSource(readProgram({id: 'cancel'}), {
      format: 'json', submissionRef: reader.newSubmission({nonce: 'cancel'})});
    await until(() => transport.state.requests.length > count);
    await cancelled.cancel({cancelId: 'external-read-cancel'});
    assert.equal((await stateOf(cancelled)).status, 'cancelled');
    await stopped(cancelled, 'cancelled');
    readRuns.push([cancelled.ref, 'cancelled']);
    await close(reader);
    transport.state.readMode = 'ok';
    const beforeReopen = [transport.state.requests.length, transport.state.secretCalls];
    const reopened = await open('source');
    for (const [ref, expected] of readRuns) await stopped(await reopened.attach(ref), expected);
    await close(reopened);
    assert.deepEqual([transport.state.requests.length, transport.state.secretCalls], beforeReopen);

    const deniedProfiles = await createFixtureProfiles(join(directory, 'denied-profiles'), {read: 'deny'});
    const denied = await open('source', deniedProfiles, 'denied');
    const beforeDenial = [transport.state.requests.length, transport.state.secretCalls];
    await assert.rejects(denied.startSource(readProgram({id: 'denied'}), {
      format: 'json', submissionRef: denied.newSubmission({nonce: 'denied'})}),
    error => error.code === 'SubmissionPreparationFailed' &&
      error.outcome?.problem?.code === 'ACTQL_E_ACCOUNT_DENIED');
    assert.deepEqual([transport.state.requests.length, transport.state.secretCalls], beforeDenial);
    await close(denied);

    const beforeEffect = [transport.state.requests.length, transport.state.secretCalls];
    const publication = await publishEffect({directory: join(directory, 'effect'),
      effectProfilePath: profiles.effectProfilePath, resolveEffectSecret: transport.resolveSecret});
    const [mapping] = publication.mappings;
    let writer = await open('effect');
    assert.deepEqual([transport.state.requests.length, transport.state.secretCalls], beforeEffect);
    for (const [mode, expected] of [['ok', 'succeeded'], ['lost-response', 'needs_reconciliation']]) {
      transport.state.effectMode = mode;
      const before = transport.state.events.length;
      const run = await writer.startSource(effectProgram(mapping, {key: mode, note: 'literal note', id: mode}),
        {format: 'json', submissionRef: writer.newSubmission({nonce: `effect-${mode}`})});
      assert.equal((await stateOf(run)).status, 'waiting_checkpoint');
      assert.equal(transport.state.events.length, before);
      await resolveCheckpoint(writer, run);
      const settled = await until(async () => {
        const state = await run.status();
        return terminal.includes(state.status) ? state : undefined;
      });
      assert.equal(settled.status, expected, JSON.stringify(settled));
      assert.deepEqual(transport.state.events[before], {key: mode, note: 'literal note'});
      assert.equal(transport.state.events.length, before + 1);
      await close(writer);
      writer = await open('effect');
      const recovered = await writer.attach(run.ref);
      assert.equal((await stateOf(recovered)).status, expected);
      assert.equal(transport.state.events.length, before + 1, 'recovery must not resend');
    }
    await close(writer);

    // Install the author's independent UPDATE Mapping through the same
    // generated package and public preparation. Exercise the original
    // signed approval, physical read/write and Saved with fresh Host custody.
    const {effectProfilePath} = profiles;
    const updateProfilePath = join(directory, 'profiles', 'update.json');
    await writeFile(updateProfilePath, JSON.stringify({
      ...JSON.parse(await readFile(effectProfilePath, 'utf8')), write: 'update'}));
    const updateProfiles = {...profiles, effectProfilePath: updateProfilePath};
    const [updateMapping] = (await publishEffect({directory: join(directory, 'update'),
      effectProfilePath: updateProfilePath, resolveEffectSecret: transport.resolveSecret})).mappings;
    assert.equal(updateMapping.kind, 'update');
    assert.notEqual(updateMapping.mappingCid, mapping.mappingCid);
    const updateCases = [
      {id: 'selected', note: 'approved update', decision: 'approved', status: 'succeeded', writes: 1},
      {id: 'cleared', note: null, decision: 'approved', status: 'succeeded', writes: 1},
      {id: 'refused', note: 'never written', decision: 'rejected', status: 'cancelled', writes: 0},
      {id: 'lost', note: 'applied without response', decision: 'approved', status: 'needs_reconciliation', writes: 1},
      {id: 'conflict', note: 'never applied', decision: 'approved', status: 'failed', writes: 0,
        competingNote: 'different current value'},
    ];
    const authorizationPath = join(directory, 'profiles', 'update-cold-authorization.json');
    await writeFile(authorizationPath, JSON.stringify(profiles.authorization), privateFile);
    const updateObservations = [];
    for (const selected of updateCases) {
      const {id, note, status, decision, writes, competingNote} = selected;
      const runName = id === 'selected' ? 'update' : `update-${id}`;
      if (id !== 'selected') {
        const repeated = await publishEffect({directory: join(directory, runName),
          effectProfilePath: updateProfilePath, resolveEffectSecret: transport.resolveSecret});
        assert.deepEqual(repeated.mappings, [updateMapping]);
      }
      const preflightFailures = [];
      const observation = competingNote === undefined ? undefined : createHostObservationConnection({
        include: ['effect'], correlation: {include: ['run']}, measurements: {include: []},
        events: {level: 'diagnostic'}, deliver(record) {
          if (record.operation !== 'effect' || record.event !== 'dispatch_failed') return;
          const fields = record.attributes;
          preflightFailures.push({runDefinitionCid: fields?.['actql.run.definition_cid'],
            code: fields?.['error.type'], kind: fields?.['actql.failure.kind'], phase: fields?.['actql.failure.phase']});
        },
      });
      const updater = await open('effect', updateProfiles, runName, observation);
      const recordsBefore = structuredClone(transport.state.records);
      const writesBefore = transport.state.updateWrites;
      const expectedRow = {id, note}, path = `/events/${id}`;
      const start = transport.state.requests.length;
      const update = await updater.startSource(updateProgram(updateMapping, expectedRow), {format: 'json',
        submissionRef: updater.newSubmission({nonce: `external-update-${id}`})});
      const waiting = await stateOf(update);
      assert.equal(waiting.status, 'waiting_checkpoint', JSON.stringify(waiting));
      assert.equal(transport.state.updateWrites, writesBefore);
      assert.deepEqual(transport.state.records, recordsBefore);
      assert.deepEqual(transport.state.requests.slice(start).map(({method, path}) => [method, path]),
        [['GET', path], ['GET', path]], 'Capture and current preflight precede approval');
      const page = await updater.checkpoints({checkpointId: waiting.checkpoint.id});
      assert.equal(page.items.length, 1);
      const [summary] = page.items;
      assert.equal(summary.kind, 'effect_set');
      assert.equal(summary.checkpointCid, waiting.checkpoint.checkpoint_cid);
      const review = await updater.reviewCheckpoint(summary);
      const view = JSON.parse(Buffer.from(review.bytes).toString('utf8'));
      assert.equal(view.review_projection_cid, summary.reviewProjectionCid);
      assert.equal(view.effect_preview_cid, summary.requiredArtifact.cid);
      assert.equal(view.authority_scope_cid, update.ref.authorityScopeCid);
      assert.deepEqual(view.approval_claims, summary.requirements);
      assert.equal(view.displayed_rows.length, 1);
      const [row] = view.displayed_rows;
      assert.equal(row.target_row_identity, id);
      assert.equal(row.before.state, 'present');
      assert.equal(row.before.value.note, recordsBefore[id].note);
      assert.deepEqual(row.intended_changes, {state: 'present', value: {note}});
      if (competingNote !== undefined) {
        assert.deepEqual(transport.state.records, recordsBefore);
        transport.state.records[id] = {id, note: competingNote};
      }
      const {checkpoint, result: resolution} = await resolveCheckpoint(updater, update, {decision, original: summary});
      assert.deepEqual(checkpoint, summary);
      assert.equal(resolution.signed.length, 1);
      const signed = JSON.parse(resolution.signed[0].resolutionWire);
      assert.equal(signed.decision, decision);
      assert.equal(signed.run_id, waiting.run_id);
      assert.equal(signed.run_definition_cid, update.ref.runDefinitionCid);
      assert.equal(signed.checkpoint_id, waiting.checkpoint.id);
      assert.equal(signed.checkpoint_cid, summary.checkpointCid);
      const final = await until(async () => {
        const state = await update.status();
        return terminal.includes(state.status) ? state : undefined;
      });
      assert.equal(final.status, status, JSON.stringify(final));
      assert.equal(final.run_id, waiting.run_id);
      const results = status === 'succeeded' ? {rows: [expectedRow], verification: [{id}]} : undefined;
      const warmResults = {};
      if (results !== undefined) {
        for (const [name, expected] of Object.entries(results)) {
          const observed = await update.result(name).all();
          assert.deepEqual(observed, expected);
          warmResults[name] = observed;
        }
      }
      assert.equal(transport.state.updateWrites, writesBefore + writes);
      const expectedAfter = {...recordsBefore};
      if (writes === 1) expectedAfter[id] = expectedRow;
      if (competingNote !== undefined) expectedAfter[id] = {id, note: competingNote};
      assert.deepEqual(transport.state.records, expectedAfter);
      const providerRequests = transport.state.requests.slice(start).map(({method, path}) => [method, path]);
      assert.deepEqual(providerRequests, [['GET', path], ['GET', path],
        ...(decision === 'approved' ? [['GET', path]] : []),
        ...(writes === 1 ? [['PUT', path]] : [])]);
      if (status === 'succeeded') await stopped(update, status);
      await close(updater);
      if (observation !== undefined) {
        const report = observation.status();
        assert.equal(report.closed, true);
        assert.equal(report.cleanupPending, false);
        assert(Object.values(report.loss).every(value => value === 0));
        assert.deepEqual(preflightFailures, [{runDefinitionCid: update.ref.runDefinitionCid,
          code: 'EffectTargetVersionMismatch', kind: 'target_version_mismatch', phase: 'effect_apply_preflight'}]);
      }
      const authority = {directory: join(directory, runName), effectProfilePath: updateProfilePath,
        authorizationPath, reference: update.ref, runId: waiting.run_id, status, results};
      const cold = await externalUpdateCold(authority, join(directory, `${runName}-receipt`));
      assert.deepEqual(cold.resultNames, Object.keys(results ?? {}));
      assert.equal(cold.requests + cold.updateWrites + cold.secretCalls + cold.forbiddenNetworkCalls, 0);
      updateObservations.push({id, decision, status, writes, warmPid: process.pid, warmFirstClose: true,
        checkpointCid: summary.checkpointCid, providerRequests, warmResults, cold,
        ...(competingNote === undefined ? {} : {competingNote, preflightFailure: preflightFailures[0]})});
    }
    assert.equal(new Set(updateObservations.map(({cold}) => cold.pid)).size, updateObservations.length);
    assert.equal(transport.state.updateWrites, 3);

    // Fail one real credential-journal close. The ordinary installed Host
    // keeps that same owner and exposes its existing retry handle.
    const host = await openInstalledRemoteHttpHost({directory: join(directory, 'close-retry'),
      authenticate: () => principalId, sourceProfilePath: profiles.sourceProfilePath,
      resolveSourceSecret: transport.resolveSecret});
    const original = DatabaseSync.prototype.close;
    let blocked = true, attempts = 0, completed = 0;
    DatabaseSync.prototype.close = function () {
      if (!new Error().stack.includes('sqlite-credential-journal.mjs')) return original.call(this);
      attempts++;
      if (blocked) throw new Error('FixtureCredentialCloseFailed');
      const result = original.call(this); completed++; return result;
    };
    const beforeClose = [transport.state.requests.length, transport.state.secretCalls];
    try {
      let failure;
      await assert.rejects(host.close(), error => { failure = error; return true; });
      assert.equal(failure.cleanupPending, true);
      assert.equal(typeof failure.cleanupHandle.retry, 'function');
      assert.equal(attempts, 1); assert.equal(completed, 0);
      blocked = false;
      await Promise.all([failure.cleanupHandle.retry(), failure.cleanupHandle.retry()]);
      assert.equal(attempts, 2); assert.equal(completed, 1);
      assert.deepEqual(failure.cleanupHandle.status().pending, []);
      await host.close();
      assert.equal(attempts, 2); assert.equal(completed, 1);
      assert.deepEqual([transport.state.requests.length, transport.state.secretCalls], beforeClose);
    } finally {
      blocked = false;
      DatabaseSync.prototype.close = original;
      await host.close();
    }
    assert.equal(transport.state.forbiddenNetworkCalls, 0);
    return {externalRead: true, externalEffect: true, startupProviderCalls: 0,
      startupSecretCalls: 0, refusedProviderCalls: 0, refusedSecretCalls: 0,
      capturedRows: 3, providerErrorCleanup: true, cancellationCleanup: true,
      effectSends: transport.state.events.length, unknownRecoveryResends: 0,
      declaredUpdateWrites: updateObservations[0].writes, declaredUpdateSavedResends: 0, updateObservations,
      failedCloseAttempts: attempts, successfulCloses: completed,
      networkCalls: transport.state.forbiddenNetworkCalls};
  } catch (error) {
    primaryFailure = error;
    throw error;
  } finally {
    try {
      const settled = await Promise.allSettled([...clients].map(client => client.close()));
      const failures = settled.filter(result => result.status === 'rejected').map(result => result.reason);
      if (failures.length) throw new AggregateError(
        [...(primaryFailure === undefined ? [] : [primaryFailure]), ...failures],
        'ExternalInstalledFixtureCleanupFailed', {cause: primaryFailure});
    } finally { transport.restore(); }
  }
}
