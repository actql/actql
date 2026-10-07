// Actual preparation, checked Run issuance and SQLite acceptance, without
// physical dispatch. Reply loss never supplies evidence of nonacceptance.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import test, {after} from 'node:test';
import * as sdk from '../../packages/sdk/index.mjs';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
import {sourceFreeValuesPlan} from './local-values-plan.mjs';

const scratch = new URL('../../_build/client-submission-input-tests/', import.meta.url).pathname;
await mkdir(scratch, {recursive: true});
const tlsRoot = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
{cwd: tlsRoot, stdio: 'ignore'});
const tlsKey = await readFile(join(tlsRoot, 'remote.key'));
const tlsCertificate = await readFile(join(tlsRoot, 'remote.crt'));
setDefaultCACertificates([...getCACertificates('default'), tlsCertificate.toString('utf8')]);
after(() => rm(tlsRoot, {recursive: true, force: true}));
const document = await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8');
const environmentWire = await readFile(new URL('../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8');
const environment = moon.clientProgramCheckEnvironment(environmentWire.trimEnd(),
  'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904',
  false, false, true, false, false, false, false);
assert.ok(environment);
const control = runtimeCore(moon).publicationControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const scope = {namespaceId: 'namespace-a', authorityScopeCid: cid('a')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'principal-a', capabilities: ['aql-document'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};

async function fixture(t, entrance, loss) {
  const directory = await mkdtemp(join(scratch, 'request-'));
  const journal = openClientRequestJournal(directory);
  const observer = new DatabaseSync(join(directory, 'client-requests.sqlite3'), {readOnly: true});
  let client, server, authorized = true, submits = 0, issues = 0;
  let endpoint = 'actql:embedded';
  const operations = [], received = [];
  let credentials = 0, authentications = 0, preparations = 0, pause;
  const beforeBoundary = async () => {
    const pending = pause; pause = undefined;
    if (pending) await pending;
  };
  const prepare = installNodeClientProgramPreparation({moon, environment});
  const check = installNodeClientCheck({moon, environment});
  t.after(async () => {
    client?.close();
    if (server) {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
    observer.close();
    journal.close();
    await rm(directory, {recursive: true, force: true});
  });
  const configuration = {
    authenticate: async () => {
      authentications++;
      if (entrance === 'local') await beforeBoundary();
      return 'principal-a';
    },
    authorizeConnection: () => authorized,
    negotiate: () => profile,
    prepareSubmit: request => {
      preparations++;
      received.push(structuredClone({input: request.input, parameters: request.parameters}));
      return prepare(request);
    },
    check: Object.assign(request => {
      received.push(structuredClone({input: request.input, parameters: request.parameters}));
      return check(request);
    }, {unavailable: check.unavailable}),
    async submit({preparedProgram, requestId}) {
      submits++;
      const identity = moon.clientProgramRequestIdentity(preparedProgram,
        scope.authorityScopeCid, requestId, cid('b'));
      assert.ok(identity);
      const accepted = await journal.admitOrLookupDefinition(identity, {
        namespaceId: scope.namespaceId, lookupExpiresAt: '2099-01-01T00:00:00.000Z',
        issueDefinition: () => {
          issues++;
          return sourceFreeValuesPlan({moon, control, preparedProgram,
            ...scope, storeAuthorityCid: cid('7'),
            now: () => '2026-10-04T00:00:00.000Z'}).runDefinition;
        },
      }, moon, control);
      return {ref: accepted.ref, durability: 'durable', revision: accepted.revision};
    },
    lookupRequest: installNodeClientRequestLookup({journal, control: moon,
      authorizedScope: () => authorized ? scope : undefined}),
    maxRowBytes: 1024,
  };
  let pendingLoss = loss;
  if (entrance === 'local') {
    const port = createNodeInProcessClientHost(configuration);
    client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {
      async perform(operation, body, signal) {
        operations.push(operation);
        const phase = operation === 'submit' ? pendingLoss : undefined;
        if (phase) pendingLoss = undefined;
        if (phase === 'before-dispatch') throw new Error('private-submission-cause');
        const answer = await port.perform(operation, body, signal);
        if (phase === 'after-commit') throw new Error('private-submission-cause');
        return answer;
      },
    });
  } else {
    const handler = createClientHttpHandler(configuration);
    server = createServer({key: tlsKey, cert: tlsCertificate}, (request, response) => {
      const operation = request.url.split('/').at(-1);
      operations.push(operation);
      const phase = operation === 'submit' ? pendingLoss : undefined;
      if (phase) pendingLoss = undefined;
      if (phase === 'before-dispatch') {
        request.resume(); response.destroy(); return;
      }
      if (phase === 'after-commit') {
        response.end = () => {
          assert.equal(response.statusCode, 200);
          response.destroy(); return response;
        };
      }
      void handler(request, response);
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    endpoint = `https://127.0.0.1:${server.address().port}/`;
    client = await sdk.connect({mode: 'local', owner: 'local',
      endpoint, token: async () => {
        credentials++;
        await beforeBoundary();
        return 'private-token';
      }});
  }
  return {client, endpoint, operations, received,
    activity: () => ({credentials, authentications, preparations}),
    pauseNext: () => {
      let release; pause = new Promise(resolve => { release = resolve; });
      return release;
    }, revoke: () => { authorized = false; },
    counts: () => ({submits, issues}),
    stored: () => observer.prepare(`SELECT caller_request_id, namespace_id,
      authority_scope_cid, program_definition_cid, run_definition_cid,
      dispatch_reserved, physical_start_reserved FROM client_requests`).all().map(row => ({...row}))};
}

for (const entrance of ['local', 'https']) {
  for (const kind of ['program', 'aql-json']) {
    for (const loss of ['before-dispatch', 'after-commit', undefined]) {
      test(`${entrance}: ${kind} submission inputs survive ${loss ?? 'acceptance'}`, async t => {
        const f = await fixture(t, entrance, loss);
        const program = JSON.parse(document), parameters = {};
        const options = {requestId: 'saved-request', parameters};
        const operation = kind === 'program' ? f.client.start(program, options)
          : f.client.aql(document, {...options, format: 'json'});
        program.stages[0].steps[0].values.rows[0].id = 9999;
        parameters.changed = 'private-edit';
        let result;
        try { result = await operation; }
        catch (cause) {
          assert.equal(cause.code, 'SubmissionUnknown');
          assert.equal(cause.requestId, 'saved-request');
          result = cause;
        }
        assert.equal(result instanceof sdk.ClientError, loss !== undefined);
        assert.equal(result.code, loss ? 'SubmissionUnknown' : undefined);
        const committed = loss !== 'before-dispatch';
        const stored = f.stored();
        assert.equal(stored.length, committed ? 1 : 0);
        assert.deepEqual(f.counts(), {submits: committed ? 1 : 0, issues: committed ? 1 : 0});
        if (committed) {
          assert.equal(stored[0].caller_request_id, 'saved-request');
          // Independently assembled current Values Program semantics and
          // Definition preimages include the adopted typed-JSON expression contract.
          assert.equal(stored[0].program_definition_cid,
            'sha256:666d7674d445fbd6c81cdd499cd8691cf12840b77f90bcff02d7e06af9abfeac');
          assert.equal(stored[0].dispatch_reserved, 0);
          assert.equal(stored[0].physical_start_reserved, 0);
        }
        assert.deepEqual(f.operations, ['connect', 'submit']);
        const snapshot = sdk.getSubmissionInput?.(result);
        assert.deepEqual(snapshot?.input, kind === 'program' ? JSON.parse(document)
          : {text: document, format: 'json'}, '[check-mutation:submission-input]');
        assert.deepEqual(snapshot.parameters, {}, '[check-mutation:submission-input]');
        assert.equal(snapshot.requestId, 'saved-request');
        assert.equal(snapshot.lookupContext.scopeRef, 'principal-a');
        assert.equal(snapshot.lookupContext.endpoint, f.endpoint);
        assert.equal(Object.isFrozen(snapshot), true);
        assert.equal(Object.isFrozen(snapshot.parameters), true);
        assert.ok(!JSON.stringify(snapshot).includes('private-token'));
        assert.ok(!JSON.stringify(result).includes('client-values'));
        assert.equal(sdk.getSubmissionInput({...result}), undefined);
        const explanation = sdk.explainSubmission?.(result);
        const expectedExplanation = loss ? {
          observation: 'acceptance_unknown',
          summary: 'Submission acceptance is unknown. Work may already have started.',
          next: {operation: 'lookupRequest', requestId: 'saved-request',
            lookupContext: {endpoint: f.endpoint, scopeRef: 'principal-a'}},
        } : {
          observation: 'run_reference_received',
          summary: 'The Host returned a validated Run reference. Check the current Run state for execution progress.',
          next: {operation: 'status', ref: {namespaceId: 'namespace-a',
            authorityScopeCid: cid('a'), runDefinitionCid: stored[0].run_definition_cid}},
        };
        assert.deepEqual(explanation, expectedExplanation,
          '[check-mutation:submission-explanation]');
        const callsBeforeLocale = [...f.operations];
        for (const format of ['text', 'html', 'json']) {
          const output = sdk.formatSubmission(result, {format});
          assert.ok(output);
          assert.doesNotMatch(output, /private-token|private-submission-cause|client-values/);
          if (format === 'json') assert.deepEqual(JSON.parse(output).explanation, expectedExplanation,
            '[check-mutation:operation-submit-public-format]');
        }
        const japanese = {...expectedExplanation, summary: loss
          ? '送信の受理を確認できません。処理は既に始まっている可能性があります。'
          : 'Hostは検証済みのRun参照を返しました。実行の進行はRunの現在状態で確認してください。'};
        assert.deepEqual(sdk.explainSubmission(result, {locale: 'ja-JP'}), japanese,
          '[check-mutation:operation-submit-public-locale]');
        assert.equal(sdk.explainSubmission(result, {get locale() {throw new Error('private-locale');}}), explanation);
        assert.equal(sdk.explainSubmission({...result}, {locale: 'ja'}), undefined);
        assert.deepEqual(f.operations, callsBeforeLocale, '[check-mutation:operation-submit-public-passive]');
        assert.equal(Object.isFrozen(explanation), true);
        assert.equal(Object.isFrozen(explanation.next), true);
        for (const privateText of ['private-token', 'private-submission-cause', 'client-values']) {
          assert.equal(JSON.stringify(explanation).includes(privateText), false);
        }
        assert.equal(sdk.explainSubmission({...result}), undefined);
        if (loss) {
          result.code = 'Accepted';
          result.message = 'Work completed successfully';
          result.requestId = 'edited-request';
          assert.deepEqual(sdk.explainSubmission(result), expectedExplanation);
        }
        const found = await f.client.lookupRequest(snapshot.requestId);
        assert.equal(found.kind, committed ? 'found' : 'not_found');
        if (committed) assert.equal(found.ref.runDefinitionCid, stored[0].run_definition_cid);
        assert.deepEqual(f.stored(), stored);
        f.revoke();
        await assert.rejects(f.client.lookupRequest(snapshot.requestId), {code: 'ClientConnectionDenied'});
        assert.deepEqual(f.stored(), stored);
        assert.equal(f.operations.filter(value => value === 'submit').length, 1);
        assert.equal(sdk.getSubmissionInput(result), snapshot);
        assert.deepEqual(sdk.explainSubmission(result), expectedExplanation);
      });
    }
  }
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: bound count input refusal precedes Run acceptance`, async t => {
    const f = await fixture(t, entrance);
    const program = {version: 'actql/0.1', id: 'bound-count',
      params: {n: {type: 'number', nullable: true}}, stages: [{id: 'main', inputs: {},
        steps: [{values: {schema: {id: {type: 'number', nullable: false}}, rows: [{id: 1}]}, as: 'rows'},
          {take: {$param: 'n'}, as: 'selected'}],
        results: {out: {from: 'selected', fields: ['id']}}}],
      results: {out: {from: {stage: 'main', result: 'out'}}}};
    for (const [index, n] of [0, -1, 1.5, 9007199254740992, null].entries()) {
      for (const kind of ['program', 'aql-json']) {
        const options = {requestId: `${kind}-${index}`, parameters: {n}};
        await assert.rejects(kind === 'program' ? f.client.start(program, options)
          : f.client.aql(JSON.stringify(program), {...options, format: 'json'}),
        error => {
          assert.equal(error.code, 'ClientProgramRejected', '[check-mutation:bound-count-category]');
          return true;
        });
        assert.deepEqual(f.counts(), {submits: 0, issues: 0});
        assert.deepEqual(f.stored(), []);
      }
    }
    await assert.rejects(f.client.start(program, {requestId: 'missing-count'}),
      {code: 'ClientProgramNeedsInputs'});
    assert.deepEqual(f.counts(), {submits: 0, issues: 0});
    assert.deepEqual(f.stored(), []);
  });
}


for (const entrance of ['local', 'https']) {
  test(`${entrance}: temporal input refusal precedes Run acceptance`, async t => {
    const f = await fixture(t, entrance);
    for (const field of ['size', 'step', 'offset']) {
      const program = {version: 'actql/0.1', id: 'temporal-input',
        params: {n: {type: 'number'}}, stages: [{id: 'main', inputs: {},
          steps: [{values: {schema: {id: {type: 'number', nullable: false}},
            rows: [{id: 1}]}, as: 'rows'},
          {row_window: {time: 'id', kind: 'sliding', size: 1, step: 1,
            [field]: {$param: 'n'}}, as: 'selected'}],
          results: {out: {from: 'selected', fields: ['id']}}}],
        results: {out: {from: {stage: 'main', result: 'out'}}}};
      const invalid = field === 'offset' ? [1.5, 9007199254740992]
        : [0, -1, 1.5, 9007199254740992];
      for (const [index, n] of invalid.entries()) {
        for (const kind of ['program', 'aql-json']) {
          const options = {requestId: `${field}-${kind}-${index}`, parameters: {n}};
          await assert.rejects(kind === 'program' ? f.client.start(program, options)
            : f.client.aql(JSON.stringify(program), {...options, format: 'json'}),
          error => {
            assert.equal(error.code, 'ClientProgramRejected', '[check-mutation:temporal-input-category]');
            return true;
          });
          assert.deepEqual(f.counts(), {submits: 0, issues: 0});
          assert.deepEqual(f.stored(), []);
        }
      }
      for (const kind of ['program', 'aql-json']) {
        const options = {requestId: `${field}-${kind}-missing`, parameters: {}};
        await assert.rejects(kind === 'program' ? f.client.start(program, options)
          : f.client.aql(JSON.stringify(program), {...options, format: 'json'}),
        {code: 'ClientProgramNeedsInputs'});
        await assert.rejects(kind === 'program'
          ? f.client.start(program, {...options, parameters: {n: null}})
          : f.client.aql(JSON.stringify(program), {...options, parameters: {n: null}, format: 'json'}),
        {code: 'ClientProgramRejected'});
      }
      assert.deepEqual(f.counts(), {submits: 0, issues: 0});
      assert.deepEqual(f.stored(), []);
    }
  });
}


for (const entrance of ['local', 'https']) {
  test(`${entrance}: valid signed temporal offsets preserve Run acceptance`, async t => {
    const f = await fixture(t, entrance);
    for (const [index, n] of [-1, 0, 1].entries()) {
      const program = {version: 'actql/0.1', id: 'signed-temporal-input',
        params: {n: {type: 'number'}}, stages: [{id: 'main', inputs: {},
          steps: [{values: {schema: {id: {type: 'number', nullable: false}},
            rows: [{id: 1}]}, as: 'rows'},
          {row_window: {time: 'id', kind: 'sliding', size: 1, step: 1,
            offset: {$param: 'n'}}, as: 'selected'}],
          results: {out: {from: 'selected', fields: ['id']}}}],
        results: {out: {from: {stage: 'main', result: 'out'}}}};
      for (const kind of ['program', 'aql-json']) {
        const options = {requestId: `signed-${kind}-${index}`, parameters: {n}};
        const result = await (kind === 'program' ? f.client.start(program, options)
          : f.client.aql(JSON.stringify(program), {...options, format: 'json'}));
        assert.equal(typeof result.ref.runDefinitionCid, 'string');
        assert.equal(sdk.explainSubmission(result).observation, 'run_reference_received');
      }
      assert.deepEqual(f.counts(), {submits: (index + 1) * 2, issues: (index + 1) * 2});
      assert.equal(f.stored().length, (index + 1) * 2);
    }
  });
}


// Independently authored public inputs. The real preparation, checker, Run
// issuer and SQLite journal above observe only the SDK's one detached request.
const nestedDeclaration = () => ({type: 'object', fields: {nested:
  {type: 'array', items: {type: 'number', nullable: true}}}});
const nestedParameterProgram = declaration => {
  const program = JSON.parse(document);
  program.params = {x: declaration};
  program.stages[0].steps.push({from: 'selected',
    derive: {value: {$param: 'x'}}, as: 'bound'});
  program.stages[0].results.rows = {from: 'bound', fields: ['value']};
  return program;
};
const scalarProgram = value => {
  const program = JSON.parse(document);
  program.stages[0].steps[0].values.schema.id.nullable = true;
  program.stages[0].steps[0].values.rows = [{id: value}];
  return program;
};
const numericInputCases = value => {
  const nested = {nested: [value]};
  const declaration = nestedDeclaration();
  const defaultDeclaration = {...nestedDeclaration(), default: nested};
  return [
    ['start parameters', 'submit', client => client.start(nestedParameterProgram(declaration),
      {requestId: 'numeric-start-parameters', parameters: {x: nested}})],
    ['start Program values', 'submit', client => client.start(scalarProgram(value),
      {requestId: 'numeric-start-values'})],
    ['start default', 'submit', client => client.start(nestedParameterProgram(defaultDeclaration),
      {requestId: 'numeric-start-default', parameters: {}})],
    ['aql parameters', 'submit', client => client.aql('SELECT @x AS n',
      {format: 'sql', requestId: 'numeric-aql-parameters',
        parameterDeclarations: {x: declaration}, parameters: {x: nested}})],
    ['aql default', 'submit', client => client.aql('SELECT @x AS n',
      {format: 'sql', requestId: 'numeric-aql-default',
        parameterDeclarations: {x: defaultDeclaration}, parameters: {}})],
    ['check parameters', 'check', client => client.check('SELECT @x AS n',
      {format: 'sql', parameterDeclarations: {x: declaration}, parameters: {x: nested}})],
    ['check default', 'check', client => client.check('SELECT @x AS n',
      {format: 'sql', parameterDeclarations: {x: defaultDeclaration}, parameters: {}})],
  ];
};

for (const entrance of ['local', 'https']) {
  test(`${entrance}: all SDK input paths refuse lossy numbers before credentials and Host admission`, async t => {
    const f = await fixture(t, entrance), before = f.activity();
    for (const value of [NaN, Infinity, -Infinity, -0,
      ...[NaN, Infinity, -Infinity, -0].map(value => new Number(value)),
      {toJSON: () => Infinity}, {toJSON: () => -0},
      Object.assign(new Number(1), {valueOf: () => NaN}),
      Object.assign(new Number(1), {[Symbol.toPrimitive]: () => -0})]) {
      for (const [name, operation, invoke] of numericInputCases(value)) {
        await assert.rejects(invoke(f.client), error => {
          assert.equal(error.code, operation === 'check' ? 'InvalidCheckRequest' : 'InvalidClientPayload',
            `[request-snapshot:local-refusal] ${name}`);
          assert.equal(sdk.getSubmissionInput(error), undefined);
          assert.equal(sdk.explainSubmission(error), undefined);
          return true;
        });
        assert.deepEqual(f.activity(), before, '[request-snapshot:before-credentials]');
        assert.deepEqual(f.operations, ['connect'], '[request-snapshot:zero-exchange]');
        assert.deepEqual(f.counts(), {submits: 0, issues: 0}, '[request-snapshot:zero-admission]');
        assert.deepEqual(f.stored(), []);
        assert.deepEqual(f.received, []);
      }
    }
  });

  test(`${entrance}: finite and null SDK inputs retain real check and Run acceptance`, async t => {
    // Each independently authored value gets a fresh request journal so the
    // fixed request IDs exercise input admission, not request-ID collisions.
    for (const value of [null, 0, 1.25, -2, Number.MAX_VALUE, Number.MIN_VALUE, new Number(3.5)]) {
      const f = await fixture(t, entrance);
      let submits = 0, checks = 0;
      for (const [name, operation, invoke] of numericInputCases(value)) {
        const result = await invoke(f.client);
        if (operation === 'check') {
          checks++;
          assert.equal(result.outcome, 'completed', name);
          assert.equal(result.report.verdict, 'verified', name);
        } else {
          submits++;
          assert.equal(sdk.explainSubmission(result).observation, 'run_reference_received', name);
          const snapshot = sdk.getSubmissionInput(result);
          assert.deepEqual(f.received.at(-1), {input: snapshot.input, parameters: snapshot.parameters},
            '[request-snapshot:received-value]');
          assert.ok(Object.isFrozen(snapshot.input));
          assert.ok(snapshot.parameters === null || Object.isFrozen(snapshot.parameters));
        }
      }
      assert.equal(checks, 2);
      assert.deepEqual(f.counts(), {submits: 5, issues: 5});
      assert.equal(f.stored().length, 5);
      assert.equal(f.operations.filter(operation => operation === 'submit').length, submits);
    }
  });

  test(`${entrance}: SDK snapshots serialize caller values once before the first await`, async t => {
    for (const operation of ['start', 'aql', 'check']) {
      const f = await fixture(t, entrance);
      let conversions = 0, serializations = 0;
      const boxed = Object.assign(new Number(1), {valueOf: () => { conversions++; return 3.5; }});
      const parameters = {x: {toJSON() { serializations++; return {nested: [boxed, null]}; }}};
      const declarations = {x: nestedDeclaration()};
      const program = nestedParameterProgram(declarations.x);
      const expectedInput = operation === 'start' ? structuredClone(program) :
        {text: 'SELECT @x AS n', format: 'sql', parameterDeclarations: structuredClone(declarations)};
      const release = f.pauseNext();
      const pending = operation === 'start'
        ? f.client.start(program, {requestId: 'one-snapshot', parameters})
        : f.client[operation]('SELECT @x AS n', {format: 'sql',
          requestId: 'one-snapshot', parameterDeclarations: declarations, parameters});
      assert.equal(conversions, 1);
      assert.equal(serializations, 1);
      // Mutation during the real Local authentication / HTTPS credential wait
      // cannot change the already-owned request or introduce a second snapshot.
      parameters.x = {nested: [Infinity]};
      declarations.x.type = 'number';
      program.stages[0].steps[0].values.rows[0].id = -0;
      release();
      const result = await pending;
      assert.equal(conversions, 1, '[request-snapshot:one-conversion]');
      assert.equal(serializations, 1, '[request-snapshot:one-serialization]');
      assert.deepEqual(f.received, [{input: expectedInput,
        parameters: {x: {nested: [3.5, null]}}}], '[request-snapshot:pre-await-custody]');
      if (operation === 'check') {
        assert.equal(result.report.verdict, 'verified');
        assert.deepEqual(sdk.getCheckInput(result, 'parameters').value, {x: {nested: [3.5, null]}});
        assert.deepEqual(f.counts(), {submits: 0, issues: 0});
      } else {
        const snapshot = sdk.getSubmissionInput(result);
        assert.deepEqual(snapshot.input, expectedInput);
        assert.deepEqual(snapshot.parameters, {x: {nested: [3.5, null]}});
        assert.ok(Object.isFrozen(snapshot.parameters.x.nested));
        assert.deepEqual(f.counts(), {submits: 1, issues: 1});
      }
    }
  });
}
