// Invalid source encoding is refused before analysis. Expected bytes and
// envelopes are independent literals; the admitted control uses the checker.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer, request as httpsRequest} from 'node:https';
import {join} from 'node:path';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath, pathToFileURL} from 'node:url';
import test, {after} from 'node:test';
import {ClientError, connect, getCheckInput, resolveCheckLocation,
  resolveCheckTextRange, explainCheckReason, getCheckContextRequirements,
  getCheckFixes, createCheckSupplementationSession, createCheckDocumentSession} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {validCheckOutcome} from '../../packages/client-wire/index.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {sourceAliasPublication} from './source-alias-publication.mjs';
import {createNodeAuthorizationGate} from './authorization.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const scratch = join(root, '_build', 'client-check-text-boundary');
await mkdir(scratch, {recursive: true});
const tls = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'key.pem', '-out', 'cert.pem', '-days', '1',
  '-subj', '/CN=localhost', '-addext', 'subjectAltName=IP:127.0.0.1'],
{cwd: tls, stdio: 'ignore'});
const key = await readFile(join(tls, 'key.pem'));
const cert = await readFile(join(tls, 'cert.pem'));
const previousCertificates = getCACertificates('default');
setDefaultCACertificates([...previousCertificates, cert.toString('utf8')]);
after(async () => {
  setDefaultCACertificates(previousCertificates);
  await rm(tls, {recursive: true, force: true});
});

const moon = await import(pathToFileURL(join(root,
  '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js')).href);
const wire = JSON.parse(await readFile(join(root,
  'adapters/host-node/fixtures/query-amount-environment.json'), 'utf8'));
const environment = moon.clientProgramCheckEnvironment(canonicalText(wire),
  wire.evidence_bundle_cid, false, false, true, true, false, false, false);

async function publicCheck(t, entrance, {program = false, environmentWire = wire,
  visibility, contextKey, principalId = 'reader', afterCheck, transformOwnerOutcome} = {}) {
  const selected = environmentWire === wire ? environment
    : moon.clientProgramCheckEnvironment(canonicalText(environmentWire),
      environmentWire.evidence_bundle_cid, false, false, true, true, false, false, false);
  const counts = {exchanges: 0, authorization: 0, analysis: 0};
  const sourceRef = 'connector://crm/main/r#v';
  const aliases = visibility && visibility !== 'absent' ? [{name: 'records', sourceRef,
    sourceViewContractCid: wire.source_views[0].contract_cid,
    schemaContractCid: wire.source_views[0].output.schema.cid}] : [];
  const authorization = aliases.length ? await createNodeAuthorizationGate({
    configuration: canonicalText({version: 'actql-execution-account-config/0.1',
      account_id: 'authoring-source', entries: [{entry_id: 'source-read',
        outcome: visibility === 'denied' ? 'deny' : 'allow', principal: {all: true},
        connection: {all: true}, resource: {all: true}, operation: {any_of: ['read']}, exclusions: []}]}),
    context: {principal: principalId, contextCid: `sha256:${'3'.repeat(64)}`}}) : undefined;
  if (authorization) t.after(() => authorization.close());
  if (visibility === 'unpublished') authorization.close();
  const check = installNodeClientCheck({moon: {...moon,
    clientProgramCheckProgram: (...args) => {
      assert.equal(program, true, 'Text fixture must not check a structured Program');
      counts.analysis++;
      const outcome = moon.clientProgramCheckProgram(...args);
      return transformOwnerOutcome?.(outcome, args[7]) ?? outcome;
    },
    clientProgramCheckSource: (...args) => {
      counts.analysis++;
      const outcome = moon.clientProgramCheckSource(...args);
      return transformOwnerOutcome?.(outcome, args[10]) ?? outcome;
    }}, environment: selected, publication: sourceAliasPublication(moon, selected, aliases),
    ...(contextKey === undefined ? {} : {contextKey}),
    sourceAccesses: authorization ? [{authorization, connection: 'local-database',
      resource: '/records.duckdb', sourceRef}] : []});
  const connection = {mode: entrance === 'local' ? 'local' : 'remote',
    owner: entrance === 'local' ? 'local' : 'remote', runners: [], consentRefs: []};
  const configuration = {authenticate: () => principalId,
    authorizeConnection: ({operation}) => {
      if (operation === 'check') counts.authorization++;
      return true;
    }, negotiate: () => ({version: 'actql-client-host/0.1',
      mode: connection.mode, owner: connection.owner, durability: 'durable',
      scopeRef: 'text-boundary-scope', capabilities: [],
      limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
        maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
        maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}}),
    async check(request) {
      const outcome = await check(request);
      await afterCheck?.(request, outcome);
      return outcome;
    }, maxRowBytes: 1024, maxRequestBytes: 65536};
  const body = text => ({connection, kind: 'text', scope: 'bound_input', input: {text, format: 'sql'}, parameters: null});
  if (entrance === 'local') {
    const host = createNodeInProcessClientHost(configuration);
    const client = await connectInProcess({mode: 'local', owner: 'local'}, {
      perform(operation, ...args) {
        if (operation === 'check') counts.exchanges++;
        return host.perform(operation, ...args);
      },
    });
    t.after(() => client.close());
    return {client, counts, body, async post(text) {
      return host.perform('check', body(text)).then(value => ({body: value}), error => {
        if (!(error instanceof ClientError)) throw error;
        return {body: {code: error.code}};
      });
    }};
  }
  const handler = createClientHttpHandler(configuration);
  let acknowledgeChunk, receivedChunks = 0;
  const server = createServer({key, cert}, (request, response) => {
    if (request.url.endsWith('/check')) {
      counts.exchanges++;
      const original = request[Symbol.asyncIterator].bind(request);
      request[Symbol.asyncIterator] = async function* () {
        for await (const chunk of original()) {
          receivedChunks++;
          acknowledgeChunk?.();
          yield chunk;
        }
      };
    }
    return handler(request, response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  });
  const endpoint = `https://127.0.0.1:${server.address().port}/`;
  const client = await connect({mode: 'remote', endpoint, token: 'reader-token'});
  t.after(() => client.close());
  const send = (chunks, {split = false} = {}) => new Promise((resolve, reject) => {
    receivedChunks = 0;
    const request = httpsRequest(new URL('actql/client/0.1/check', endpoint), {
      method: 'POST', ca: cert, headers: {'content-type': 'application/json',
        authorization: 'Bearer reader-token'}, signal: AbortSignal.timeout(5000),
    }, response => {
      const received = [];
      response.on('data', chunk => received.push(chunk));
      response.on('error', reject);
      response.on('end', () => {
        try { resolve({status: response.statusCode, receivedChunks,
          body: JSON.parse(Buffer.concat(received).toString('utf8'))}); }
        catch (error) { reject(error); }
      });
    });
    request.on('error', reject);
    (async () => {
      for (const chunk of chunks) {
        if (split) await new Promise(resolve => {
          acknowledgeChunk = resolve;
          request.write(chunk);
        });
        else request.write(chunk);
      }
      acknowledgeChunk = undefined;
      request.end();
    })().catch(reject);
  });
  return {client, counts, body, send,
    post: text => send([Buffer.from(JSON.stringify(body(text)))]), connection};
}

const authoringProgram = () => ({version: 'actql/0.1', id: 'scoped-authoring',
  params: {x: {type: 'number'}}, stages: [{id: 'first', inputs: {}, steps: [
    {values: {schema: {id: {type: 'number', nullable: false}}, rows: [{id: 1}]}, as: 'seed'},
    {derive: {n: 'id + $x'}}, {select: ['n'], as: 'output'}],
  results: {out: {from: 'output', fields: ['n']}}}],
  results: {out: {from: {stage: 'first', result: 'out'}}}});

for (const entrance of ['local', 'http']) for (const visibility of ['allow', 'absent', 'denied', 'unpublished']) {
  for (const suppliedViolation of [false, true]) {
  test(`${entrance}: richer audience reports retain ${visibility} custody with ${suppliedViolation ? 'a supplied violation' : 'no violation'}`, async t => {
    const directory = await mkdtemp(join(scratch, 'audience-binding-'));
    t.after(async () => {
      if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
        console.error(`Audience-binding evidence retained: ${directory}`);
      } else await rm(directory, {recursive: true, force: true});
    });
    // The same private key and exact bytes deliberately produce equal input
    // revisions: only the authoritative audience/disclosure context differs.
    const contextKey = Buffer.alloc(32, 0x31);
    let richRaw;
    const rich = await publicCheck(t, entrance, {visibility: 'allow', contextKey,
      transformOwnerOutcome(raw) {richRaw = raw; return raw;}});
    for (const format of ['sql', 'aql-text']) {
      const input = suppliedViolation ? 'SELECT missing, @x AS n FROM records'
        : 'SELECT missing FROM records';
      const options = {kind: 'text', scope: 'bound_input', format,
        ...(suppliedViolation ? {parameterDeclarations: {x: {type: 'number'}},
          parameters: {x: 'caller-private-wrong-value'}} : {})};
      const original = await rich.client.check(input, options);
      const originalRaw = richRaw;
      assert.equal(original.report.verdict, 'invalid');
      assert.ok(original.report.reasons.some(reason => reason.code === 'query_expression_invalid'));
      assert.deepEqual(original.report.coverage, {limits: [], unresolved: []});
      {
        const emitted = [];
        let substitute = false;
        const restricted = await publicCheck(t, entrance, {visibility, contextKey,
          principalId: 'other-reader', transformOwnerOutcome(raw) {
            emitted.push(JSON.parse(raw));
            // Substitute the actual richer Owner outcome before public
            // validation; no facts, contexts or document metadata are forged.
            return substitute ? originalRaw : raw;
          }});
        const fresh = await restricted.client.check(input, options);
        assert.deepEqual(fresh.report.inputs, original.report.inputs);
        assert.deepEqual(fresh.report.scope, original.report.scope);
        assert.notEqual(fresh.report.context_ref, original.report.context_ref);
        if (visibility === 'allow') {
          assert.deepEqual(fresh.report.reasons, original.report.reasons);
          assert.deepEqual(fresh.report.coverage, original.report.coverage);
        } else {
          const parameters = getCheckInput(fresh, 'parameters');
          assert.deepEqual({verdict: fresh.report.verdict, reasons: fresh.report.reasons,
            requirements: fresh.report.requirements, coverage: fresh.report.coverage},
          {verdict: suppliedViolation ? 'invalid' : 'undetermined',
            reasons: suppliedViolation ? [{code: 'supplied_value_type_mismatch',
              facts: {parameter: 'x', expected_type: 'number', actual_type: 'string'},
              location: {document_id: 'parameters', revision: parameters.revision,
                kind: 'structured', pointer: '/x'}}] : [], requirements: [],
            coverage: {limits: [], unresolved: [{boundary: 'source_resolution',
              reason: 'unresolved_protected'}]}});
        }
        substitute = true;
        const replayed = await restricted.client.check(input, options);
        substitute = false;
        await writeFile(join(directory, `${format}-${visibility}-${suppliedViolation}.json`),
          JSON.stringify({entrance, format, visibility, suppliedViolation, input,
            original, fresh, freshOwnerOutcome: emitted.at(-1), replayed,
            originalInput: getCheckInput(original, 'source'),
            replayedInput: getCheckInput(replayed, 'source'),
            richCounts: rich.counts, restrictedCounts: restricted.counts}), {mode: 0o600});
        assert.deepEqual({outcome: replayed.outcome, problem: replayed.problem,
          report: replayed.report ?? null, partialReport: replayed.partial_report ?? null,
          input: getCheckInput(replayed, 'source') ?? null,
          parameters: getCheckInput(replayed, 'parameters') ?? null},
        {outcome: 'failed', problem: {code: 'check_internal'}, report: null,
          partialReport: null, input: null, parameters: null},
        '[check-mutation:owner-audience-binding]');
        const restored = await restricted.client.check(input, options);
        assert.deepEqual(restored, fresh);
        assert.equal(getCheckInput(restored, 'source').text, input);
        assert.equal(getCheckInput(original, 'source').text, input);
        assert.equal(getCheckInput(structuredClone(original), 'source'), undefined);
        assert.equal(getCheckInput(structuredClone(restored), 'source'), undefined);
        if (visibility !== 'allow') assert.doesNotMatch(JSON.stringify(restored),
          /query_expression_invalid|caller-private-wrong-value|crm\/main/);
        assert.deepEqual(restricted.counts, {exchanges: 3, authorization: 3, analysis: 3});
      }
    }
    assert.deepEqual(rich.counts, {exchanges: 2, authorization: 2, analysis: 2});
  });
  }
}

for (const entrance of ['local', 'http']) for (const kind of ['text', 'program']) {
  for (const fault of ['replay', 'context', 'documents', 'scope']) {
    test(`${entrance}: ${kind} Owner results retain the current ${fault} binding`, async t => {
      const directory = await mkdtemp(join(scratch, 'owner-binding-'));
      t.after(async () => {
        if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
          console.error(`Owner-binding evidence retained: ${directory}`);
        } else await rm(directory, {recursive: true, force: true});
      });
      const emitted = [];
      let replay = false;
      const {client, counts} = await publicCheck(t, entrance, {program: kind === 'program',
        transformOwnerOutcome(raw) {
          emitted.push(JSON.parse(raw));
          if (!replay) return raw;
          // Probe the adapter with a previously emitted real Owner report.
          // Hybrid probes substitute only metadata emitted for this call;
          // no verdict, Requirement, revision or context is invented.
          const old = structuredClone(emitted.at(-2));
          const current = emitted.at(-1);
          if (fault === 'documents' || fault === 'scope') old.report.context_ref = current.report.context_ref;
          if (fault === 'context' || fault === 'scope') old.report.inputs = current.report.inputs;
          assert.equal(validCheckOutcome(old), true, 'Probe must remain a well-formed Owner outcome');
          return JSON.stringify(old);
        }});
      const formats = kind === 'text' ? ['sql', 'aql-text'] : [undefined];
      for (const format of formats) {
        const input = kind === 'text' ? 'SELECT @x AS n' : authoringProgram();
        if (kind === 'program') {
          input.params.x.type = 'boolean';
          input.stages[0].steps[1].derive.n = '$x';
        }
        const options = {kind, scope: 'bound_input', ...(kind === 'text'
          ? {format, parameterDeclarations: {x: {type: 'boolean'}}} : {})};
        // Equal byte lengths deliberately defeat length-only association.
        assert.equal(Buffer.byteLength('{"x":true}'), 10);
        assert.equal(Buffer.byteLength('{"x":null}'), 10);
        const firstOptions = fault === 'scope' ? {...options, scope: 'template_only'}
          : {...options, parameters: {x: true}};
        const first = await client.check(input, firstOptions);
        assert.equal(first.report.verdict, 'verified');
        assert.equal(first.report.scope.kind, firstOptions.scope);
        if (fault === 'scope') assert.equal(first.report.requirements[0].code, 'parameter_value_required');
        else assert.equal(getCheckInput(first, 'parameters').value.x, true);
        replay = true;
        const secondOptions = fault === 'scope' ? options : {...options, parameters: {x: null}};
        const second = await client.check(input, secondOptions).catch(error => {
          if (!(error instanceof ClientError)) throw error;
          return {error: error.code};
        });
        replay = false;
        const fresh = emitted.at(-1);
        await writeFile(join(directory, `${format ?? 'program'}-observation.json`),
          JSON.stringify({entrance, kind, fault, input, firstOptions, secondOptions,
            first, freshOwnerOutcome: fresh, replayedPublicOutcome: second, counts}), {mode: 0o600});
        assert.equal(fresh.report.scope.kind, 'bound_input');
        assert.equal(fresh.report.verdict, fault === 'scope' ? 'undetermined' : 'invalid');
        if (fault !== 'scope') assert.deepEqual(fresh.report.reasons[0].facts,
          {parameter: 'x', expected_type: 'boolean', actual_type: 'null'});
        assert.deepEqual({outcome: second.outcome, problem: second.problem,
          report: second.report ?? null, partialReport: second.partial_report ?? null,
          original: getCheckInput(second, kind === 'text' ? 'source' : 'program') ?? null,
          parameters: getCheckInput(second, 'parameters') ?? null},
        {outcome: 'failed', problem: {code: 'check_internal'}, report: null,
          partialReport: null, original: null, parameters: null},
        `[check-mutation:owner-${fault}-binding]`);
        const third = await client.check(input, secondOptions);
        assert.equal(third.report.verdict, fault === 'scope' ? 'undetermined' : 'invalid');
        assert.equal(third.report.scope.kind, 'bound_input');
        assert.notEqual(third.report.context_ref, first.report.context_ref);
        if (fault !== 'scope') {
          assert.equal(getCheckInput(third, 'parameters').value.x, null);
          assert.equal(getCheckInput(first, 'parameters').value.x, true);
          assert.notEqual(getCheckInput(third, 'parameters').revision,
            getCheckInput(first, 'parameters').revision);
        }
        assert.equal(getCheckInput(structuredClone(third), kind === 'text' ? 'source' : 'program'), undefined);
      }
      assert.deepEqual(counts, {exchanges: formats.length * 3,
        authorization: formats.length * 3, analysis: formats.length * 3});
    });
  }
  for (const fault of ['context', 'documents']) {
    test(`${entrance}: ${kind} partial Owner reports retain the current ${fault} binding`, async t => {
      const directory = await mkdtemp(join(scratch, 'owner-partial-binding-'));
      t.after(async () => {
        if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
          console.error(`Owner-binding evidence retained: ${directory}`);
        } else await rm(directory, {recursive: true, force: true});
      });
      const emitted = [];
      let replay = false;
      const {client, counts} = await publicCheck(t, entrance, {program: kind === 'program',
        transformOwnerOutcome(raw, correlationRef) {
          const current = JSON.parse(raw);
          emitted.push(current);
          // Simulate a public reporting failure with its actual invalid Owner
          // report, then substitute that same partial report for a later call.
          const report = structuredClone(replay ? emitted.at(-2).report : current.report);
          if (replay && fault === 'documents') report.context_ref = current.report.context_ref;
          if (replay && fault === 'context') {
            report.inputs = current.report.inputs;
            for (const reason of report.reasons) if (reason.location) {
              reason.location.revision = current.report.inputs.find(document =>
                document.document_id === reason.location.document_id).revision;
            }
          }
          const outcome = {version: current.version, reason_schema_cid: current.reason_schema_cid,
            outcome_schema_cid: current.outcome_schema_cid, outcome: 'failed',
            correlation_ref: correlationRef, problem: {code: 'check_internal'}, partial_report: report};
          assert.equal(validCheckOutcome(outcome), true, 'Probe must remain a well-formed partial outcome');
          return JSON.stringify(outcome);
        }});
      const input = kind === 'text' ? 'SELECT @x AS n' : authoringProgram();
      if (kind === 'program') {
        input.params.x.type = 'boolean';
        input.stages[0].steps[1].derive.n = '$x';
      }
      const options = {kind, scope: 'bound_input', ...(kind === 'text'
        ? {format: 'sql', parameterDeclarations: {x: {type: 'boolean'}}} : {})};
      const first = await client.check(input, {...options, parameters: {x: null}});
      assert.equal(first.outcome, 'failed');
      assert.equal(first.partial_report.verdict, 'invalid');
      assert.deepEqual(first.partial_report.runnable, {verdict: 'no',
        reasons: [{code: 'supplied_value_type_mismatch'}]});
      assert.equal(getCheckInput(first, 'parameters').value.x, null);
      assert.deepEqual(first.partial_report.reasons[0].facts,
        {parameter: 'x', expected_type: 'boolean', actual_type: 'null'});
      assert.ok(resolveCheckLocation(first, first.partial_report.reasons[0].location));
      replay = true;
      const second = await client.check(input, {...options, parameters: {x: true}}).catch(error => {
        if (!(error instanceof ClientError)) throw error;
        return {error: error.code};
      });
      await writeFile(join(directory, 'partial-observation.json'), JSON.stringify({
        entrance, kind, fault, input, options, first, freshOwnerOutcome: emitted.at(-1),
        replayedPublicOutcome: second, counts}), {mode: 0o600});
      assert.equal(emitted.at(-1).report.verdict, 'verified');
      assert.deepEqual({outcome: second.outcome, problem: second.problem,
        report: second.report ?? null, partialReport: second.partial_report ?? null,
        parameters: getCheckInput(second, 'parameters') ?? null},
      {outcome: 'failed', problem: {code: 'check_internal'}, report: null,
        partialReport: null, parameters: null}, `[check-mutation:owner-${fault}-binding]`);
      assert.equal(getCheckInput(first, 'parameters').value.x, null);
      assert.equal(getCheckInput(structuredClone(first), 'parameters'), undefined);
      assert.deepEqual(counts, {exchanges: 2, authorization: 2, analysis: 2});
    });
  }
}

test('HTTPS: malformed UTF-8 check bytes never enter analysis', async t => {
  const {client, counts, send} = await publicCheck(t, 'http');
  const prefix = Buffer.from('{"connection":{"mode":"remote","owner":"remote","runners":[],"consentRefs":[]},"kind":"text","scope":"bound_input","input":{"text":"SELECT \'');
  const suffix = Buffer.from('\' AS label","format":"sql"},"parameters":null}');
  // Isolated continuation, overlong scalar, truncated scalar, surrogate,
  // out-of-range scalar and truncated non-BMP scalar, inside a JSON string.
  for (const invalid of [[0x80], [0xc0, 0xaf], [0xe2, 0x82],
    [0xed, 0xa0, 0x80], [0xf4, 0x90, 0x80, 0x80], [0xf0, 0x9f, 0x98]]) {
    const response = await send([prefix, Buffer.from(invalid), suffix]);
    assert.equal(response.body.code, 'InvalidClientRequest', '[check-mutation:invalid-wire-utf8]');
    assert.equal(response.status, 400);
    assert.deepEqual(response.body, {code: 'InvalidClientRequest'});
    assert.equal(counts.authorization, 0);
    assert.equal(counts.analysis, 0);
  }
  // The same stream may split an admitted non-BMP scalar between body chunks.
  const split = await send([prefix, Buffer.from([0xf0, 0x9f]),
    Buffer.from([0x98, 0x80]), suffix], {split: true});
  assert.equal(split.receivedChunks, 4);
  assert.equal(split.body.report?.verdict, 'verified', '[check-mutation:split-wire-scalar]');
  assert.equal(split.status, 200);
  assert.deepEqual(split.body.report.inputs.map(({document_id, byte_length}) =>
    ({document_id, byte_length})), [{document_id: 'source', byte_length: 22}]);
  // U+FFFD supplied as a real scalar is valid data, unlike replacement decoding.
  const admitted = await client.check("SELECT '\ufffd' AS label", {kind: 'text', scope: 'bound_input', format: 'sql'});
  assert.equal(admitted.report.verdict, 'verified');
  assert.equal(getCheckInput(admitted, 'source').text, "SELECT '\ufffd' AS label");
  assert.equal(counts.authorization, 2);
  assert.equal(counts.analysis, 2);
});

for (const entrance of ['local', 'http']) {
  test(`${entrance}: unpaired source surrogates are refused before checking`, async t => {
    const {post, counts} = await publicCheck(t, entrance);
    for (const invalid of ["SELECT '\ud800' AS label", "SELECT '\udfff' AS label",
      "SELECT '\ud800x\udfff' AS label"]) {
      const response = await post(invalid);
      assert.equal(response.body.code, 'InvalidClientRequest', '[check-mutation:source-scalar-refusal]');
      assert.deepEqual(response.body, {code: 'InvalidClientRequest'});
      if (entrance === 'http') assert.equal(response.status, 400);
      assert.equal(counts.authorization, 0);
      assert.equal(counts.analysis, 0);
    }
  });

  test(`${entrance}: SDK refuses unpaired source surrogates without exchange`, async t => {
    const {client, counts} = await publicCheck(t, entrance);
    for (const text of ["SELECT '\ud800' AS label", "SELECT '\udfff' AS label",
      "SELECT '\ud800x\udfff' AS label"]) {
      const result = await client.check(text, {kind: 'text', scope: 'bound_input', format: 'sql'}).then(() => ({}), error => {
        if (!(error instanceof ClientError)) throw error;
        return {code: error.code};
      });
      assert.equal(result.code, 'InvalidCheckRequest', '[check-mutation:sdk-scalar-refusal]');
      assert.deepEqual(counts, {exchanges: 0, authorization: 0, analysis: 0});
    }
  });

  test(`${entrance}: valid source encoding preserves the exact editable EOF`, async t => {
    const {client, counts} = await publicCheck(t, entrance);
    // BOM: 3, emoji comment: 8, CRLF: 2, SELECT plus open paren: 8 bytes.
    const text = '\ufeff/*😀*/\r\nSELECT (';
    const outcome = await client.check(text, {kind: 'text', scope: 'bound_input', format: 'sql'});
    assert.equal(outcome.report.verdict, 'invalid');
    const input = getCheckInput(outcome, 'source');
    assert.equal(input.text, text, '[check-mutation:original-source-encoding]');
    assert.deepEqual(outcome.report.reasons, [{code: 'query_syntax_invalid',
      location: {kind: 'text', document_id: 'source', revision: input.revision,
        start_byte: 21, end_byte: 21, precision: 'exact'}}]);
    assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).text, '');
    assert.deepEqual(resolveCheckTextRange(outcome, outcome.report.reasons[0].location).range,
      {start: {line: 1, character: 8}, end: {line: 1, character: 8}});
    assert.equal(counts.authorization, 1);
    assert.equal(counts.analysis, 1);
  });
}

for (const entrance of ['local', 'http']) {
  test(`${entrance}: document sessions retain original spans across buffer edits and reply reordering`, async t => {
    const directory = await mkdtemp(join(scratch, 'document-session-'));
    t.after(async () => {
      if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
        console.error(`Document-session evidence retained: ${directory}`);
      } else await rm(directory, {recursive: true, force: true});
    });
    const gates = [0, 1].map(() => {
      let enter, release;
      const entered = new Promise(resolve => {enter = resolve;});
      const waiting = new Promise(resolve => {release = resolve;});
      return {enter, release, entered, waiting};
    });
    t.after(() => gates.forEach(gate => gate.release()));
    let replies = 0;
    const {client, counts} = await publicCheck(t, entrance, {
      async afterCheck(request, outcome) {
        const gate = gates[replies++];
        if (!gate) return;
        // Delay the actual checker outcome before the ordinary Host returns
        // it. No response fields, input revisions or verdicts are fabricated.
        gate.enter({request, outcome});
        await gate.waiting;
      },
    });
    const originalText = '/*é😀e\u0301*/\r\nSELECT (';
    const editedText = originalText + ' ';
    const session = createCheckDocumentSession(client, {text: originalText, version: 1});
    t.after(() => session.close());
    const options = {scope: 'bound_input', format: 'sql'};
    const firstPending = session.check(options);
    await gates[0].entered;
    session.update(editedText, 2);
    gates[0].release();
    const first = await firstPending;
    const syntax = observation => observation.outcome.report.reasons.find(
      reason => reason.code === 'query_syntax_invalid');
    const firstLocation = syntax(first).location;
    const firstInput = getCheckInput(first.outcome, 'source');
    const staleRange = session.resolveTextRange(first, firstLocation);
    await writeFile(join(directory, 'edit-observation.json'), JSON.stringify({
      entrance, originalText, editedText, first, firstInput, staleRange,
      originalRange: resolveCheckTextRange(first.outcome, firstLocation), counts,
    }), {mode: 0o600});
    assert.equal(staleRange, undefined, '[check-mutation:document-public-edit]');
    assert.equal(firstInput.text, originalText);
    assert.deepEqual(first.outcome.report.inputs.map(({document_id, byte_length}) =>
      ({document_id, byte_length})), [{document_id: 'source', byte_length: 23}]);
    assert.deepEqual({start: firstLocation.start_byte, end: firstLocation.end_byte},
      {start: 23, end: 23});
    assert.deepEqual(resolveCheckTextRange(first.outcome, firstLocation).range,
      {start: {line: 1, character: 8}, end: {line: 1, character: 8}});
    assert.equal(JSON.parse(session.format(first, {format: 'json'})).entries[0].location, undefined);
    await assert.rejects(session.applyFixes(first, [], {version: 3, reviewed: true}),
      {code: 'CheckFixStale'});

    // Same bytes/version, different scope/context: the later bound check is
    // current even when the earlier actual template reply arrives afterwards.
    const earlierPending = session.check({...options, scope: 'template_only'});
    await gates[1].entered;
    const current = await session.check(options);
    gates[1].release();
    const earlier = await earlierPending;
    const earlierLocation = syntax(earlier).location;
    const currentLocation = syntax(current).location;
    const reorderedRange = session.resolveTextRange(earlier, earlierLocation);
    const currentRange = session.resolveTextRange(current, currentLocation);
    await writeFile(join(directory, 'order-observation.json'), JSON.stringify({
      entrance, editedText, earlier, current, reorderedRange, currentRange, counts,
    }), {mode: 0o600});
    assert.equal(reorderedRange, undefined, '[check-mutation:document-public-order]');
    assert.deepEqual(earlier.outcome.report.scope, {kind: 'template_only'});
    assert.deepEqual(current.outcome.report.scope, {kind: 'bound_input'});
    assert.notEqual(earlier.outcome.report.context_ref, current.outcome.report.context_ref);
    assert.equal(getCheckInput(current.outcome, 'source').text, editedText);
    assert.deepEqual({start: currentLocation.start_byte, end: currentLocation.end_byte},
      {start: 24, end: 24});
    assert.deepEqual(currentRange.range,
      {start: {line: 1, character: 9}, end: {line: 1, character: 9}});
    assert.equal(currentRange.positionEncoding, 'utf-16');
    assert.equal(JSON.parse(session.format(earlier, {format: 'json'})).entries[0].location, undefined);
    assert.deepEqual(JSON.parse(session.format(current, {format: 'json'})).entries[0].location.range,
      currentRange.range);
    const copied = structuredClone(current);
    assert.equal(session.resolveTextRange(copied, currentLocation), undefined);
    assert.equal(getCheckInput(copied.outcome, 'source'), undefined);

    session.update('SELECT 1 AS n', 3);
    const corrected = await session.check(options);
    assert.equal(corrected.outcome.report.verdict, 'verified');
    assert.equal(session.resolveTextRange(current, currentLocation), undefined);
    const reopened = createCheckDocumentSession(client, {text: editedText, version: 2});
    assert.equal(reopened.resolveTextRange(current, currentLocation), undefined);
    reopened.close(); session.close();
    assert.equal(session.resolveTextRange(corrected, currentLocation), undefined);
    assert.deepEqual(counts, {exchanges: 4, authorization: 4, analysis: 4});
  });
}

// Independent authored inputs and expected classifications, not producer output.
for (const entrance of ['local', 'http']) {
  test(`${entrance}: runnable comes from the actual text Owner without granting execution`, async t => {
    const {client, counts} = await publicCheck(t, entrance);
    const options = {kind: 'text', scope: 'bound_input', format: 'sql'};
    const literal = await client.check('SELECT 1 AS n', options);
    assert.equal(validCheckOutcome(literal), true);
    assert.deepEqual(literal.report.runnable, {verdict: 'yes', reasons: []});
    const templateOptions = {...options, scope: 'template_only',
      parameterDeclarations: {x: {type: 'number'}}};
    const template = await client.check('SELECT @x AS n', templateOptions);
    assert.equal(template.report.verdict, 'verified');
    assert.deepEqual(template.report.runnable, {verdict: 'no',
      reasons: [{code: 'parameter_value_required'}]});
    const missing = await client.check('SELECT @x AS n', {...templateOptions, scope: 'bound_input'});
    assert.equal(missing.report.verdict, 'undetermined');
    assert.deepEqual(missing.report.runnable, {verdict: 'no',
      reasons: [{code: 'bound_values_missing'}, {code: 'parameter_value_required'}]});
    const bound = await client.check('SELECT @x AS n', {...templateOptions,
      scope: 'bound_input', parameters: {x: 7}});
    assert.deepEqual(bound.report.runnable, {verdict: 'yes', reasons: []});
    // A declaration default is an actual binding, not a fabricated value.
    const defaulted = await client.check('SELECT @x AS n', {...templateOptions,
      parameterDeclarations: {x: {type: 'number', default: 7}}});
    assert.deepEqual(defaulted.report.runnable, {verdict: 'yes', reasons: []});
    const invalid = await client.check('SELECT @x AS n', {...templateOptions,
      scope: 'bound_input', parameters: {x: 'private-invalid-value'}});
    assert.equal(invalid.report.verdict, 'invalid');
    assert.deepEqual(invalid.report.runnable, {verdict: 'no',
      reasons: [{code: 'supplied_value_type_mismatch'}]});
    assert.doesNotMatch(JSON.stringify(invalid.report.runnable), /private-invalid-value|facts|location/u);
    assert.deepEqual(counts, {exchanges: 6, authorization: 6, analysis: 6});
  });

  test(`${entrance}: Group templates retain original runtime checks and Parameter inputs`, async t => {
    const {client} = await publicCheck(t, entrance);
    for (const format of ['sql', 'aql-text']) {
      for (const text of [
        'SELECT COUNT(*) AS n',
        'SELECT COUNT(1) AS n',
        'SELECT COUNTIF(TRUE) AS n',
        'SELECT MIN(1) AS n',
        'SELECT MAX(1) AS n',
        'SELECT 1 AS id |> AGGREGATE COUNT(*) AS n',
      ]) {
        for (const scope of ['template_only', 'bound_input']) {
          const checked = await client.check(text, {kind: 'text', scope, format});
          assert.equal(checked.outcome, 'completed');
          assert.equal(checked.report.verdict, 'verified', text);
          assert.deepEqual(checked.report.requirements, []);
          assert.deepEqual(checked.report.coverage, {limits: [], unresolved: []});
          assert.deepEqual(checked.report.runnable, {verdict: 'yes', reasons: []});
          assert.equal(getCheckInput(checked, 'source').text, text);
        }
      }
      const text = 'SELECT COUNTIF(@flag) AS n';
      const options = {kind: 'text', scope: 'template_only', format,
        parameterDeclarations: {flag: {type: 'boolean'}}};
      const template = await client.check(text, options);
      assert.equal(template.report.verdict, 'verified');
      assert.deepEqual(template.report.runnable, {verdict: 'no',
        reasons: [{code: 'parameter_value_required'}]});
      assert.equal(template.report.requirements[0].facts.parameter, 'flag');
      assert.ok(resolveCheckLocation(template, template.report.requirements[0].location));
      const missing = await client.check(text, {...options, scope: 'bound_input'});
      assert.equal(missing.report.verdict, 'undetermined');
      assert.equal(missing.report.requirements[0].code, 'parameter_value_required');
      assert.equal(missing.report.runnable.verdict, 'no');
      const defaulted = await client.check(text, {...options,
        parameterDeclarations: {flag: {type: 'boolean', default: false}}});
      assert.equal(defaulted.report.verdict, 'verified');
      assert.deepEqual(defaulted.report.requirements, []);
      const bound = await client.check(text,
        {...options, scope: 'bound_input', parameters: {flag: false}});
      assert.equal(bound.report.verdict, 'verified');
      assert.deepEqual(bound.report.requirements, []);
      const wrong = await client.check(text,
        {...options, scope: 'bound_input', parameters: {flag: 0}});
      assert.equal(wrong.report.verdict, 'invalid');
      assert.equal(wrong.report.reasons[0].code, 'supplied_value_type_mismatch');
      const numeric = await client.check('SELECT SUM(1) AS n',
        {kind: 'text', scope: 'template_only', format});
      assert.equal(numeric.report.verdict, 'undetermined');
      assert.equal(numeric.report.runnable.verdict, 'no');
    }
  });

  test(`${entrance}: documented NUMBER casts use the original numeric checker`, async t => {
    const {client} = await publicCheck(t, entrance);
    for (const format of ['sql', 'aql-text']) {
      for (const target of ['NUMBER', 'number', 'NuMbEr', 'FLOAT64', 'DOUBLE']) {
        for (const text of [
          `SELECT CAST('1.25' AS ${target}) AS n, CAST(NULL AS ${target}) AS missing`,
          `SELECT '1.25' AS raw |> SELECT CAST(raw AS ${target}) AS n`,
          `SELECT CAST(@value AS ${target}) AS n`,
        ]) {
          const options = {kind: 'text', scope: 'bound_input', format,
            ...(text.includes('@value') ? {
              parameterDeclarations: {value: {type: 'string'}}, parameters: {value: '1.25'},
            } : {})};
          const checked = await client.check(text, options);
          assert.equal(checked.outcome, 'completed');
          assert.equal(checked.report.verdict, 'verified', text);
          assert.deepEqual(checked.report.runnable, {verdict: 'yes', reasons: []});
          assert.deepEqual(checked.report.coverage, {limits: [], unresolved: []});
          assert.deepEqual(checked.report.requirements, []);
          assert.equal(getCheckInput(checked, 'source').text, text);
        }
      }
      const wrongType = await client.check('SELECT CAST(TRUE AS NUMBER) AS n',
        {kind: 'text', scope: 'bound_input', format});
      assert.equal(wrongType.report.verdict, 'invalid');
      for (const target of ['`NUMBER`', 'NUMBERISH']) {
        const invalid = await client.check(`SELECT CAST('1.25' AS ${target}) AS n`,
          {kind: 'text', scope: 'bound_input', format});
        assert.equal(invalid.report.verdict, 'invalid');
        assert.equal(invalid.report.reasons[0].code, 'query_syntax_invalid');
      }
    }
  });

  test(`${entrance}: documented NULL ARRAY context preserves checked membership domains`, async t => {
    const {client} = await publicCheck(t, entrance);
    for (const format of ['sql', 'aql-text']) {
      const options = {kind: 'text', scope: 'bound_input', format};
      for (const text of [
        'SELECT 1 IN UNNEST(CAST(NULL AS ARRAY<INT64>)) AS found',
        'SELECT 1 NOT IN UNNEST(CAST(((NULL)) AS ARRAY<INT64>)) AS absent',
        'SELECT CAST(NULL AS ARRAY<INT64>) IS NULL AS missing, ARRAY<INT64>[] IS NULL AS empty',
        'SELECT 9007199254740992.0 IN UNNEST(ARRAY<INT64>[]) AS found',
        'SELECT NULL IN UNNEST(CAST(NULL AS ARRAY<INT64>)) AS found',
        'SELECT ARRAY<INT64>[NULL] AS nullable_items',
      ]) {
        const checked = await client.check(text, options);
        assert.equal(checked.report.verdict, 'verified', text);
        assert.deepEqual(checked.report.runnable, {verdict: 'yes', reasons: []});
        assert.equal(getCheckInput(checked, 'source').text, text);
      }
      for (const text of [
        'SELECT 9007199254740992 IN UNNEST(ARRAY<INT64>[]) AS found',
        'SELECT 1.5 IN UNNEST(CAST(NULL AS ARRAY<INT64>)) AS found',
        'SELECT 9223372036854775808.0 IN UNNEST(CAST(NULL AS ARRAY<INT64>)) AS found',
        "SELECT '1' IN UNNEST(CAST(NULL AS ARRAY<INT64>)) AS found",
        'SELECT ARRAY<INT64>[1] AS no_constructor_promotion',
        'SELECT @value IN UNNEST(CAST(NULL AS ARRAY<INT64>)) AS no_parameter_promotion',
      ]) {
        const checked = await client.check(text, {...options,
          ...(text.includes('@value') ? {parameterDeclarations: {value: {type: 'number'}}, parameters: {value: 1}} : {})});
        assert.equal(checked.report.verdict, 'invalid', text);
      }
      for (const value of ['-9223372036854775808', '9223372036854775807', '9007199254740993', null]) {
        const checked = await client.check('SELECT ARRAY<INT64>[@value] AS exact', {...options,
          parameterDeclarations: {value: {type: 'int64', nullable: value === null}}, parameters: {value}});
        assert.equal(checked.report.verdict, 'verified');
      }
      const unsupported = await client.check('SELECT CAST(ARRAY<INT64>[] AS ARRAY<INT64>) AS items', options);
      assert.equal(unsupported.report.verdict, 'undetermined');
      assert.equal(unsupported.report.coverage.limits[0].code, 'implementation_limit');
      assert.deepEqual(unsupported.report.runnable, {verdict: 'no', reasons: [{code: 'implementation_limit'}]});
    }
  });

  test(`${entrance}: runnable uses the same structured Program Owner and original inputs`, async t => {
    const {client, counts} = await publicCheck(t, entrance, {program: true});
    const program = authoringProgram();
    const template = await client.check(program, {kind: 'program', scope: 'template_only'});
    assert.equal(template.report.verdict, 'verified');
    assert.deepEqual(template.report.runnable, {verdict: 'no',
      reasons: [{code: 'parameter_value_required'}]});
    const bound = await client.check(program, {kind: 'program', scope: 'bound_input', parameters: {x: 7}});
    assert.deepEqual(bound.report.runnable, {verdict: 'yes', reasons: []});
    const missing = await client.check(program, {kind: 'program', scope: 'bound_input'});
    assert.equal(missing.report.verdict, 'undetermined');
    assert.deepEqual(missing.report.runnable, {verdict: 'no',
      reasons: [{code: 'bound_values_missing'}, {code: 'parameter_value_required'}]});
    assert.deepEqual(template.report.runnable, {verdict: 'no',
      reasons: [{code: 'parameter_value_required'}]}, 'Supplementation cannot rewrite the older observation');
    assert.deepEqual(counts, {exchanges: 3, authorization: 3, analysis: 3});
  });

  test(`${entrance}: runnable preserves protected Source indistinguishability`, async t => {
    const outcomes = [];
    for (const visibility of ['absent', 'denied', 'unpublished']) {
      const {client} = await publicCheck(t, entrance, {visibility});
      const outcome = await client.check('SELECT id FROM records',
        {kind: 'text', scope: 'bound_input', format: 'sql'});
      assert.equal(outcome.report.verdict, 'undetermined');
      assert.deepEqual(outcome.report.runnable, {verdict: 'no',
        reasons: [{code: 'unresolved_protected'}]});
      outcomes.push(outcome.report.runnable);
    }
    assert.deepEqual(outcomes[0], outcomes[1]);
    assert.deepEqual(outcomes[1], outcomes[2]);
  });

  test(`${entrance}: LIMIT count parameter diagnostics keep the original supplied and default inputs`, async t => {
    const {client} = await publicCheck(t, entrance, {visibility: 'allowed'});
    const text = 'SELECT id FROM records ORDER BY id LIMIT @count';
    for (const type of ['number', 'int64']) {
      for (const defaulted of [false, true]) {
        const zero = type === 'number' ? 0 : '0';
        const declarations = {count: {type, ...(defaulted ? {default: zero} : {})}};
        const outcome = await client.check(text, {kind: 'text', scope: 'bound_input', format: 'sql',
          parameterDeclarations: declarations, ...(defaulted ? {} : {parameters: {count: zero}})});
        assert.equal(outcome.outcome, 'completed');
        assert.equal(outcome.report.verdict, 'invalid');
        const [reason] = outcome.report.reasons;
        assert.deepEqual({code: reason.code, facts: reason.facts}, {code: 'operation_parameter_invalid',
          facts: {parameter: 'count', domain: 'positive_safe_integer'}});
        const documentId = defaulted ? 'parameter_declarations' : 'parameters';
        assert.deepEqual(reason.location, {kind: 'structured', document_id: documentId,
          revision: outcome.report.inputs.find(input => input.document_id === documentId).revision,
          pointer: defaulted ? '/count/default' : '/count'});
        assert.ok(resolveCheckLocation(outcome, reason.location));
        assert.equal(explainCheckReason(reason).hint, 'Supply an integer from 1 through 9007199254740991.');
        assert.equal(resolveCheckLocation(structuredClone(outcome), reason.location), undefined);
        assert.deepEqual(outcome.report.requirements, []);
      }
    }
  });

  test(`${entrance}: ordered SQL and Pipe templates close original Sort and literal LIMIT obligations`, async t => {
    const {client} = await publicCheck(t, entrance);
    for (const [format, text] of [
      ['sql', 'SELECT @x AS n ORDER BY n DESC LIMIT 1 OFFSET 0'],
      ['aql-text', 'SELECT @x AS n |> ORDER BY n DESC |> LIMIT 1 OFFSET 0'],
    ]) {
      const options = {kind: 'text', scope: 'template_only', format,
        parameterDeclarations: {x: {type: 'number'}}};
      const outcome = await client.check(text, options);
      assert.equal(outcome.outcome, 'completed');
      assert.equal(outcome.report.verdict, 'verified');
      assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
      assert.deepEqual(outcome.report.reasons, []);
      assert.equal(outcome.report.requirements.length, 1);
      const requirement = outcome.report.requirements[0];
      assert.equal(requirement.code, 'parameter_value_required');
      assert.equal(requirement.facts.parameter, 'x');
      assert.equal(resolveCheckLocation(outcome, requirement.location).pointer, '/x');
      assert.deepEqual(outcome.report.runnable, {verdict: 'no', reasons: [{code: 'parameter_value_required'}]});
      // A complete template is not bound input or an executable Run.
      const bound = await client.check(text, {...options, scope: 'bound_input', parameters: {x: 2}});
      assert.equal(bound.report.verdict, 'verified');
      assert.deepEqual(bound.report.requirements, []);
      assert.equal(resolveCheckLocation(structuredClone(outcome), requirement.location), undefined);
    }
    const conditional = await client.check('SELECT 1 AS n ORDER BY n LIMIT @count',
      {kind: 'text', scope: 'template_only', format: 'sql', parameterDeclarations: {count: {type: 'int64'}}});
    assert.equal(conditional.report.verdict, 'verified');
    assert.deepEqual(conditional.report.coverage, {limits: [], unresolved: []});
    assert.equal(conditional.report.requirements[1].code, 'parameter_consumer_condition');
    assert.equal(conditional.report.requirements[0].facts.parameter, 'count');
  });

  test(`${entrance}: Take defaults and overrides retain separate binding conditions`, async t => {
    const {client} = await publicCheck(t, entrance);
    for (const type of ['number', 'int64']) {
      const value = n => type === 'int64' ? String(n) : n;
      for (const format of ['sql', 'aql-text']) {
        const text = format === 'sql'
          ? 'SELECT 1 AS n ORDER BY n LIMIT @count OFFSET @offset'
          : 'SELECT 1 AS n |> ORDER BY n |> LIMIT @count OFFSET @offset';
        for (const countDefault of [undefined, value(0), value(1)]) {
          const count = countDefault === undefined ? {type} : {type, default: countDefault};
          const options = {kind: 'text', format, scope: 'template_only',
            parameterDeclarations: {count, offset: {type, default: value(0)}}};
          const template = await client.check(text, options);
          assert.equal(template.report.verdict, 'verified');
          assert.deepEqual(template.report.coverage, {limits: [], unresolved: []});
          const conditions = template.report.requirements.filter(r => r.code === 'parameter_consumer_condition');
          assert.deepEqual(conditions.map(r => r.facts), [
            {parameter: 'count', expected_type: type, operation: 'take', argument: 'count',
              constraint: 'safe_integer', minimum: 1, maximum: 9007199254740991, stage: 'binding'},
            {parameter: 'offset', expected_type: type, operation: 'take', argument: 'offset',
              constraint: 'safe_integer', minimum: 0, maximum: 9007199254740991, stage: 'binding'},
          ]);
          for (const condition of conditions) {
            assert.equal(resolveCheckLocation(template, condition.location).pointer, '/' + condition.facts.parameter);
            assert.equal(resolveCheckLocation(structuredClone(template), condition.location), undefined);
          }
          assert.equal(template.report.runnable.verdict, 'no');
          assert.ok(template.report.runnable.reasons.some(r => r.code === 'parameter_consumer_condition'));
          assert.equal(template.report.requirements.some(r => r.code === 'parameter_value_required'), countDefault === undefined);
          const bound = {...options, scope: 'bound_input'};
          const valid = await client.check(text, {...bound, parameters: {count: value(1)}});
          assert.equal(valid.report.verdict, 'verified');
          assert.deepEqual(valid.report.requirements, []);
          const maximum = await client.check(text, {...bound,
            parameters: {count: value(9007199254740991), offset: value(9007199254740991)}});
          assert.equal(maximum.report.verdict, 'verified');
          const foreignType = await client.check(text, {...bound,
            parameters: {count: type === 'int64' ? 1 : '1'}});
          assert.equal(foreignType.report.verdict, 'invalid');
          assert.ok(foreignType.report.reasons.some(r => r.code === 'supplied_value_type_mismatch'));
          for (const parameters of [{count: value(0)}, {count: value(-1)},
            {count: value(9007199254740992)}, {count: value(1), offset: value(-1)},
            {count: value(1), offset: value(9007199254740992)},
            ...(type === 'number' ? [{count: 1.5}, {count: 1, offset: 0.5}] : [])]) {
            const invalid = await client.check(text, {...bound, parameters});
            assert.equal(invalid.report.verdict, 'invalid');
            assert.ok(invalid.report.reasons.some(r => r.code === 'operation_parameter_invalid'));
          }
          if (countDefault !== undefined) {
            const omitted = await client.check(text, bound);
            assert.equal(omitted.report.verdict, countDefault === value(0) ? 'invalid' : 'verified');
            if (countDefault === value(0)) {
              assert.equal(omitted.report.reasons[0].code, 'operation_parameter_invalid');
              assert.equal(omitted.report.requirements.some(r => r.code === 'parameter_value_required'), false);
            }
          }
        }
      }
    }
  });

  test(`${entrance}: SQL and Pipe DISTINCT templates retain typed Parameter and Result obligations`, async t => {
    const {client} = await publicCheck(t, entrance);
    for (const [format, text] of [
      ['sql', 'SELECT DISTINCT @x AS n'],
      ['aql-text', 'SELECT @x AS n |> DISTINCT'],
    ]) {
      for (const [declaration, value] of [
        [{type: 'number', nullable: true}, null],
        [{type: 'int64'}, '-9223372036854775808'],
        [{type: 'int64'}, '9007199254740993'],
      ]) {
        const options = {kind: 'text', scope: 'template_only', format,
          parameterDeclarations: {x: declaration}};
        const outcome = await client.check(text, options);
        assert.equal(outcome.outcome, 'completed');
        assert.equal(outcome.report.verdict, 'verified');
        assert.deepEqual(outcome.report.coverage, {limits: [], unresolved: []});
        assert.deepEqual(outcome.report.reasons, []);
        assert.equal(outcome.report.requirements.length, 1);
        const requirement = outcome.report.requirements[0];
        assert.equal(requirement.code, 'parameter_value_required');
        assert.equal(requirement.facts.parameter, 'x');
        assert.equal(resolveCheckLocation(outcome, requirement.location).pointer, '/x');
        assert.deepEqual(outcome.report.runnable, {verdict: 'no', reasons: [{code: 'parameter_value_required'}]});
        const bound = await client.check(text, {...options, scope: 'bound_input', parameters: {x: value}});
        assert.equal(bound.report.verdict, 'verified');
        assert.deepEqual(bound.report.requirements, []);
        assert.equal(resolveCheckLocation(structuredClone(outcome), requirement.location), undefined);
      }
    }
  });

  test(`${entrance}: DATE_DIFF SQL and Pipe use original temporal Parameter contracts`, async t => {
    const {client} = await publicCheck(t, entrance);
    for (const format of ['sql', 'aql-text']) {
      for (const [type, unit, finish, begin] of [
        ['timestamp', 'ms', '1969-12-31T23:59:59.999999999Z', '1970-01-01T00:00:00.000Z'],
        ['timestamp', 's', null, '1970-01-01T00:00:00.000Z'],
        ['date', 'd', '2000-03-01', '2000-02-28'],
      ]) {
        const text = format === 'sql'
          ? `SELECT DATE_DIFF(@finish, @begin, '${unit}') AS n`
          : `SELECT @finish AS finish, @begin AS begin |> SELECT DATE_DIFF(finish, begin, '${unit}') AS n`;
        const options = {kind: 'text', format, scope: 'template_only', parameterDeclarations: {
          begin: {type}, finish: {type, nullable: true},
        }};
        const template = await client.check(text, options);
        assert.equal(template.report.verdict, 'verified');
        assert.deepEqual(template.report.coverage, {limits: [], unresolved: []});
        assert.deepEqual(template.report.requirements.map(item => item.facts.parameter), ['begin', 'finish']);
        const bound = await client.check(text, {...options, scope: 'bound_input', parameters: {finish, begin}});
        assert.equal(bound.report.verdict, 'verified');
        assert.deepEqual(bound.report.requirements, []);
        const wrong = await client.check(text, {...options, scope: 'bound_input', parameters: {finish: 1, begin}});
        assert.equal(wrong.report.verdict, 'invalid');
        assert.equal(wrong.report.reasons[0].code, 'supplied_value_type_mismatch');
      }
    }
    for (const text of [
      "SELECT DATE_DIFF(NULL, NULL, 'month') AS n",
      "SELECT DATE_DIFF(NULL, NULL, LOWER('ms')) AS n",
    ]) {
      const outcome = await client.check(text, {kind: 'text', format: 'sql', scope: 'template_only'});
      assert.equal(outcome.report.verdict, 'invalid');
      assert.equal(outcome.report.reasons[0].code, 'query_expression_invalid');
      assert.equal(outcome.report.reasons[0].facts.issue, 'invalid_arguments');
    }
  });

  test(`${entrance}: scoped SQL and AQL templates close complete obligations and retain runtime Requirements`, async t => {
    const {client} = await publicCheck(t, entrance);
    for (const format of ['sql', 'aql-text']) {
      const declarations = {x: {type: 'number'}};
      const template = {kind: 'text', scope: 'template_only', format, parameterDeclarations: declarations};
      const unused = await client.check('SELECT 1 AS n', template);
      assert.equal(unused.report.verdict, 'invalid');
      assert.equal(unused.report.scope.kind, 'template_only');
      assert.equal(unused.report.reasons.some(reason => reason.code === 'parameter_unused'), true);
      const checked = await client.check('SELECT @x AS n', template);
      assert.equal(checked.outcome, 'completed');
      assert.equal(checked.report.verdict, 'verified', '[check-mutation:template-public-proof]');
      assert.equal(checked.report.scope.kind, 'template_only');
      assert.deepEqual(checked.report.coverage, {limits: [], unresolved: []});
      assert.equal(checked.report.requirements.length, 1);
      assert.equal(checked.report.requirements[0].code, 'parameter_value_required');
      assert.equal(checked.report.requirements[0].facts.parameter, 'x');
      const location = checked.report.requirements[0].location;
      assert.equal(location.document_id, 'parameter_declarations');
      assert.equal(location.pointer, '/x');
      assert.ok(resolveCheckLocation(checked, location));
      const bound = await client.check('SELECT @x AS n', {...template, scope: 'bound_input'});
      assert.equal(bound.report.verdict, 'undetermined');
      assert.equal(bound.report.scope.kind, 'bound_input');
      assert.notEqual(bound.report.context_ref, checked.report.context_ref);
      assert.equal(bound.report.inputs[0].revision, checked.report.inputs[0].revision);
      assert.equal(getCheckInput(structuredClone(checked), 'source'), undefined);
      assert.equal(resolveCheckLocation(structuredClone(checked), location), undefined);
    }
  });

  test(`${entrance}: scoped structured Program checks retain original pointers without submission`, async t => {
    const {client} = await publicCheck(t, entrance, {program: true});
    const program = {version: 'actql/0.1', id: 'scoped-authoring', params: {x: {type: 'number'}},
      stages: [{id: 'first', inputs: {}, steps: [
        {values: {schema: {id: {type: 'number', nullable: false}}, rows: [{id: 1}]}, as: 'seed'},
        {derive: {n: 'id + $x'}}, {select: ['n'], as: 'output'}],
        results: {out: {from: 'output', fields: ['n']}}}],
      results: {out: {from: {stage: 'first', result: 'out'}}}};
    const template = await client.check(program, {kind: 'program', scope: 'template_only'});
    assert.equal(template.outcome, 'completed');
    assert.equal(template.report.verdict, 'verified', '[check-mutation:program-template-public-proof]');
    assert.equal(template.report.scope.kind, 'template_only');
    assert.equal(template.report.inputs[0].document_id, 'program');
    const requirement = template.report.requirements[0];
    assert.equal(requirement.code, 'parameter_value_required');
    assert.equal(requirement.location.pointer, '/params/x');
    assert.equal(requirement.location.kind, 'structured');
    assert.ok(resolveCheckLocation(template, requirement.location));
    const original = getCheckInput(template, 'program');
    program.params.x.type = 'string';
    assert.equal(original.value.params.x.type, 'number');
    const wrong = await client.check(original.value, {kind: 'program', scope: 'bound_input', parameters: {x: 'wrong'}});
    assert.equal(wrong.report.verdict, 'invalid');
    assert.equal(wrong.report.reasons.some(reason => reason.code === 'supplied_value_type_mismatch'), true);
    assert.equal(getCheckInput(template, 'program'), original);
    assert.equal(getCheckInput(structuredClone(template), 'program'), undefined);
  });

  test(`${entrance}: scoped supplementation uses fresh bindings and preserves older source custody`, async t => {
    const {client, counts} = await publicCheck(t, entrance);
    for (const format of ['sql', 'aql-text']) {
      const text = '/*e\u0301😀*/\r\nSELECT @x AS n';
      const options = {kind: 'text', scope: 'template_only', format,
        parameterDeclarations: {x: {type: 'number'}}};
      const session = createCheckSupplementationSession(client, {maxAttempts: 3});
      const template = await session.check(text, options);
      assert.equal(template.outcome.report.verdict, 'verified');
      assert.deepEqual(template.decision, {kind: 'more_checks'});
      const requirement = template.outcome.report.requirements[0];
      assert.equal(explainCheckReason(requirement).kind, 'known');
      assert.ok(explainCheckReason(requirement).hint);
      const original = getCheckInput(template.outcome, 'source');
      const completed = await session.check(text, {...options, scope: 'bound_input', parameters: {x: 7}});
      assert.equal(completed.outcome.report.verdict, 'verified', '[check-mutation:scoped-bound-recheck]');
      assert.deepEqual(completed.outcome.report.requirements, []);
      assert.deepEqual(completed.decision, {kind: 'stop', reason: 'no_known_supplement'});
      assert.notEqual(completed.outcome.report.context_ref, template.outcome.report.context_ref);
      assert.equal(getCheckInput(completed.outcome, 'source').revision, original.revision);
      const wrong = await client.check(text, {...options, scope: 'bound_input', parameters: {x: null}});
      assert.equal(wrong.report.verdict, 'invalid');
      assert.deepEqual(wrong.report.reasons[0].facts,
        {parameter: 'x', expected_type: 'number', actual_type: 'null'});
      assert.equal(resolveCheckLocation(wrong, wrong.report.reasons[0].location).pointer, '/x');
      const changed = await client.check(text + ' +', options);
      assert.equal(changed.report.verdict, 'invalid');
      assert.equal(changed.report.reasons.some(reason => reason.code === 'query_syntax_invalid'), true);
      assert.notEqual(getCheckInput(changed, 'source').revision, original.revision);
      assert.equal(getCheckInput(template.outcome, 'source'), original);
      const newDeclaration = await client.check(text, {...options,
        parameterDeclarations: {x: {type: 'number', minimum: 1}}});
      assert.equal(newDeclaration.report.verdict, 'verified');
      assert.notEqual(newDeclaration.report.context_ref, template.outcome.report.context_ref);
      assert.equal(resolveCheckLocation(template.outcome, requirement.location,
        getCheckInput(newDeclaration, 'parameter_declarations')), undefined);
      assert.equal(getCheckInput({...template.outcome}, 'source'), undefined);
      assert.equal(getCheckInput(template.outcome, 'source', getCheckInput(changed, 'source').revision), undefined);
    }
    assert.equal(counts.analysis, 10, 'Retrieving diagnostic advice starts no new check');
  });

  test(`${entrance}: scoped mixed missing and invalid inputs retain independent reasons and Requirements`, async t => {
    const {client} = await publicCheck(t, entrance, {program: true});
    const declarations = {a: {type: 'number'}, b: {type: 'number'}, unused: {type: 'number'}};
    for (const format of ['sql', 'aql-text']) {
      const options = {kind: 'text', format, parameterDeclarations: declarations};
      const mixed = await client.check('SELECT @a + @b AS n',
        {...options, scope: 'bound_input', parameters: {b: 'private-wrong-value'}});
      assert.equal(mixed.report.verdict, 'invalid', '[check-mutation:scoped-mixed-verdict]');
      assert.deepEqual(mixed.report.reasons.map(({code, facts}) => ({code, facts})),
        [{code: 'supplied_value_type_mismatch', facts: {parameter: 'b', expected_type: 'number', actual_type: 'string'}}]);
      assert.equal(resolveCheckLocation(mixed, mixed.report.reasons[0].location).pointer, '/b');
      assert.deepEqual(mixed.report.requirements.map(reason => reason.facts.parameter), ['a', 'unused'],
        '[check-mutation:scoped-mixed-requirements]');
      for (const requirement of mixed.report.requirements) {
        assert.equal(resolveCheckLocation(mixed, requirement.location).pointer, '/' + requirement.facts.parameter);
      }
      assert.doesNotMatch(JSON.stringify(mixed), /private-wrong-value/);
      const unused = await client.check('SELECT @a + @b AS n', {...options, scope: 'template_only'});
      assert.equal(unused.report.verdict, 'invalid');
      assert.equal(unused.report.reasons.some(reason => reason.code === 'parameter_unused'), true);
      const reference = await client.check('SELECT @a + missing AS n', {...options, scope: 'template_only'});
      assert.equal(reference.report.verdict, 'invalid');
      assert.equal(reference.report.reasons.some(reason =>
        ['query_expression_invalid', 'program_invalid'].includes(reason.code)), true);
    }
    const program = authoringProgram();
    program.params = declarations;
    program.stages[0].steps[1].derive.n = 'id + $a + $b';
    const mixed = await client.check(program, {kind: 'program', scope: 'bound_input',
      parameters: {b: 'private-wrong-value'}});
    assert.equal(mixed.report.verdict, 'invalid');
    assert.deepEqual(mixed.report.requirements.map(reason => reason.location.pointer), ['/params/a', '/params/unused']);
    assert.equal(resolveCheckLocation(mixed, mixed.report.reasons[0].location).pointer, '/b');
    const unused = await client.check(program, {kind: 'program', scope: 'template_only'});
    assert.equal(unused.report.verdict, 'invalid');
    assert.equal(unused.report.reasons[0].code, 'parameter_unused');
    assert.equal(resolveCheckLocation(unused, unused.report.reasons[0].location).pointer, '/params/unused');
  });

  test(`${entrance}: scoped static type violations cannot become template verification`, async t => {
    const {client} = await publicCheck(t, entrance, {program: true});
    for (const format of ['sql', 'aql-text']) {
      const invalid = await client.check('SELECT @x + TRUE AS n', {kind: 'text', scope: 'template_only',
        format, parameterDeclarations: {x: {type: 'number'}}});
      assert.equal(invalid.report.verdict, 'invalid', '[check-mutation:scoped-static-type]');
      assert.equal(invalid.report.reasons.length > 0, true);
      assert.equal(invalid.report.requirements[0].facts.parameter, 'x');
    }
    const program = authoringProgram(); program.stages[0].steps[1].derive.n = '$x + true';
    const invalid = await client.check(program, {kind: 'program', scope: 'template_only'});
    assert.equal(invalid.report.verdict, 'invalid');
    assert.equal(invalid.report.requirements[0].facts.parameter, 'x');
  });

  test(`${entrance}: scoped protected Sources preserve equivalent public reasons, pointers and Requirements`, async t => {
    const clients = [];
    for (const visibility of ['absent', 'denied', 'unpublished']) {
      clients.push((await publicCheck(t, entrance, {program: true, visibility,
        contextKey: Buffer.alloc(32, 0x31)})).client);
    }
    const parameterDeclarations = {x: {type: 'number'}, y: {type: 'number'}};
    const text = 'SELECT private_field + @x AS n FROM records';
    const program = authoringProgram(); program.params = parameterDeclarations;
    program.stages[0].inputs = {rows: {connector: 'crm/main', resource: 'r', view: 'v'}};
    program.stages[0].steps.shift();
    program.stages[0].steps[0].derive.n = 'private_field + $x';
    for (const scope of ['template_only', 'bound_input']) {
      for (const [input, kind, other] of [[text, 'text', {format: 'sql', parameterDeclarations}],
        [program, 'program', {}]]) {
        const outcomes = [];
        for (const client of clients) {
          const checked = await client.check(input, {kind, scope, ...other,
            ...(scope === 'template_only' ? {} : {parameters: {x: 'private-wrong-value'}})});
          assert.equal(checked.report.verdict, scope === 'template_only' ? 'undetermined' : 'invalid',
            '[check-mutation:scoped-source-verdict]');
          assert.deepEqual(checked.report.coverage.unresolved,
            [{boundary: 'source_resolution', reason: 'unresolved_protected'}]);
          assert.deepEqual(checked.report.reasons.map(({code, facts}) => ({code, facts})),
            scope === 'template_only' ? [] : [{code: 'supplied_value_type_mismatch',
              facts: {parameter: 'x', expected_type: 'number', actual_type: 'string'}}]);
          assert.deepEqual(checked.report.requirements.map(reason => reason.facts.parameter),
            scope === 'template_only' ? ['x', 'y'] : ['y']);
          assert.doesNotMatch(JSON.stringify(checked), /private_field|private-wrong-value|crm\/main/);
          for (const requirement of checked.report.requirements) assert.ok(resolveCheckLocation(checked, requirement.location));
          if (scope === 'bound_input') assert.equal(resolveCheckLocation(checked,
            checked.report.reasons[0].location).pointer, '/x');
          outcomes.push(checked);
        }
        assert.deepEqual(outcomes[0], outcomes[1], '[check-mutation:scoped-source-disclosure]');
        assert.deepEqual(outcomes[0], outcomes[2], '[check-mutation:scoped-source-disclosure]');
      }
    }
  });

  test(`${entrance}: scoped Program locations distinguish missing nodes, null and original Unicode keys`, async t => {
    const {client} = await publicCheck(t, entrance, {program: true});
    for (const scope of ['template_only', 'bound_input']) {
      const missing = authoringProgram(); delete missing.stages[0].steps;
      const nullSteps = authoringProgram(); nullSteps.stages[0].steps = null;
      for (const [program, issue, pointer] of [[missing, 'missing_field', '/stages/0'],
        [nullSteps, 'unexpected_null', '/stages/0/steps']]) {
        const outcome = await client.check(program, {kind: 'program', scope});
        assert.equal(outcome.report.verdict, 'invalid');
        assert.deepEqual(outcome.report.reasons[0].facts, {issue});
        const location = outcome.report.reasons[0].location;
        assert.equal(location.kind, 'structured');
        assert.equal(location.document_id, 'program');
        assert.equal(location.pointer, pointer, '[check-mutation:scoped-program-parent]');
        assert.equal(resolveCheckLocation(outcome, location).pointer, pointer,
          '[check-mutation:scoped-program-parent]');
        assert.equal(resolveCheckTextRange(outcome, location), undefined);
        assert.deepEqual(getCheckFixes(outcome), []);
      }
    }
    const key = 'e\u0301/~😀';
    const program = authoringProgram();
    program.params = {payload: {type: 'object', fields: {[key]: {type: 'number'}}}};
    program.stages[0].steps[1].derive.n = '$payload';
    for (const [value, actual_type] of [['private-leaf', 'string'], [null, 'null']]) {
      const outcome = await client.check(program, {kind: 'program', scope: 'bound_input',
        parameters: {payload: {[key]: value}}});
      assert.equal(outcome.report.verdict, 'invalid');
      assert.deepEqual(outcome.report.reasons[0].facts,
        {parameter: 'payload', expected_type: 'number', actual_type});
      assert.equal(outcome.report.reasons[0].location.pointer, '/payload/e\u0301~1~0😀',
        '[check-mutation:scoped-program-unicode]');
      const owned = getCheckInput(outcome, 'parameters');
      assert.equal(Object.hasOwn(owned.value.payload, key), true);
      assert.equal(owned.value.payload[key], value);
      assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).input, owned);
      assert.doesNotMatch(JSON.stringify(outcome), /private-leaf/);
    }
    const absent = await client.check(program, {kind: 'program', scope: 'bound_input', parameters: {}});
    assert.equal(absent.report.verdict, 'undetermined');
    assert.equal(absent.report.requirements[0].location.pointer, '/params/payload');
    assert.equal(Object.hasOwn(getCheckInput(absent, 'parameters').value, 'payload'), false);
  });

  test(`${entrance}: scoped declaration defaults use actual admission rather than fabricated values`, async t => {
    const {client} = await publicCheck(t, entrance, {program: true});
    const options = {kind: 'text', scope: 'template_only', format: 'sql'};
    const wrong = await client.check('SELECT @x AS n', {...options,
      parameterDeclarations: {x: {type: 'number', default: 'private-default'}}});
    assert.equal(wrong.report.verdict, 'invalid');
    assert.equal(wrong.report.reasons[0].code, 'parameter_default_type_mismatch');
    assert.equal(wrong.report.reasons[0].location.pointer, '/x/default');
    const right = await client.check('SELECT @x AS n', {...options,
      parameterDeclarations: {x: {type: 'number', default: 7}}});
    assert.equal(right.report.verdict, 'verified');
    assert.deepEqual(right.report.requirements, []);
    const program = authoringProgram(); program.params.x.default = 'private-default';
    const rejected = await client.check(program, {kind: 'program', scope: 'template_only'});
    assert.equal(rejected.report.verdict, 'invalid');
    assert.equal(rejected.report.reasons[0].code, 'parameter_default_type_mismatch');
    assert.equal(rejected.report.reasons[0].location.pointer, '/params/x/default');
    assert.doesNotMatch(JSON.stringify([wrong, rejected]), /private-default/);
  });

  test(`${entrance}: scoped unsupported paths and parser budgets cannot verify an incomplete template`, async t => {
    const {client} = await publicCheck(t, entrance, {program: true});
    const unsupported = await client.check('SELECT UNKNOWN_FUNCTION(1) AS n',
      {kind: 'text', scope: 'template_only', format: 'sql'});
    assert.equal(unsupported.report.verdict, 'undetermined');
    assert.equal(unsupported.report.coverage.limits[0].code, 'implementation_limit');
    assert.deepEqual(unsupported.report.scope, {kind: 'template_only'});
    assert.deepEqual(unsupported.report.runnable, {verdict: 'no', reasons: [{code: 'implementation_limit'}]});
    let nested = 'leaf'; for (let i = 0; i < 40; i++) nested = [nested];
    const exhausted = await client.check('SELECT @payload AS n',
      {kind: 'text', scope: 'template_only', format: 'sql',
        parameterDeclarations: {payload: {type: 'number', default: nested}}});
    assert.equal(exhausted.report.verdict, 'undetermined');
    assert.deepEqual(exhausted.report.reasons, []);
    assert.deepEqual(exhausted.report.coverage.limits, [{code: 'analysis_budget_exhausted'}]);
    assert.deepEqual(exhausted.report.runnable, {verdict: 'no', reasons: [{code: 'analysis_budget_exhausted'}]});
    const program = authoringProgram(); program.stages[0].steps.splice(2, 0, {take: 1});
    const incomplete = await client.check(program, {kind: 'program', scope: 'template_only'});
    assert.equal(incomplete.report.verdict, 'undetermined');
    assert.equal(incomplete.report.coverage.limits[0].code, 'implementation_limit');
    assert.deepEqual(incomplete.report.scope, {kind: 'template_only'});
  });

  test(`${entrance}: scoped missing Host capacity retains known context Requirements without input blame`, async t => {
    const environmentWire = JSON.parse(await readFile(join(root,
      'adapters/host-node/fixtures/check-missing-capacity.environment.json'), 'utf8'));
    const {client} = await publicCheck(t, entrance, {program: true, environmentWire});
    for (const [input, options] of [
      ['SELECT 1 AS n', {kind: 'text', scope: 'template_only', format: 'sql'}],
      [authoringProgram(), {kind: 'program', scope: 'template_only'}],
    ]) {
      const outcome = await client.check(input, options);
      assert.equal(outcome.report.verdict, 'undetermined');
      assert.deepEqual(outcome.report.scope, {kind: 'template_only'});
      const expected = {code: 'host_capacity_policy_required', facts: {
        // Independent current contract/schema pins, adopted by #2456.
        contract_cid: 'sha256:6a419d77cad73380825177f80901a12e24eb742055e89bbb27ffa5a3cc9e7da9',
        schema_cid: 'sha256:3cc98bb9d2850a8070a6c9e66f6e3baf52e5f32e997488a3d91dd809fe95b265',
        schema_pointer: '/schema', supplier: 'checking_context_owner', stage: 'checking'}};
      assert.deepEqual(getCheckContextRequirements(outcome), [expected]);
      assert.deepEqual(outcome.report.reasons, []);
      assert.equal(Object.hasOwn(expected, 'location'), false);
      assert.deepEqual(outcome.report.coverage.limits, [{code: 'checking_context_missing'}]);
      assert.equal(outcome.report.runnable.verdict, 'no');
      assert.ok(outcome.report.runnable.reasons.some(reason => reason.code === 'host_capacity_policy_required'));
      assert.ok(outcome.report.runnable.reasons.some(reason => reason.code === 'checking_context_missing'));
      for (const reason of outcome.report.runnable.reasons) assert.deepEqual(Object.keys(reason), ['code']);
      assert.equal(getCheckContextRequirements(structuredClone(outcome)), undefined);
    }
  });

  test(`${entrance}: scoped reporting truncation cannot publish template verification`, async t => {
    const {client, counts} = await publicCheck(t, entrance);
    const names = Array.from({length: 129}, (_, i) => `p${String(i).padStart(3, '0')}`);
    const parameterDeclarations = Object.fromEntries(names.map(name => [name, {type: 'number'}]));
    const text = 'SELECT ' + names.map((name, i) => `@${name} AS n${i}`).join(', ');
    const checked = await client.check(text,
      {kind: 'text', scope: 'template_only', format: 'sql', parameterDeclarations});
    assert.equal(checked.outcome, 'completed', '[check-mutation:scoped-report-truncation]');
    assert.equal(checked.report.verdict, 'undetermined', '[check-mutation:scoped-report-truncation]');
    assert.deepEqual(checked.report.scope, {kind: 'template_only'});
    assert.deepEqual(checked.report.omissions, {requirements: true});
    assert.equal(checked.report.coverage.limits.some(limit => limit.code === 'reporting_budget_exhausted'), true);
    assert.deepEqual(checked.report.requirements.map(reason => reason.facts.parameter), names.slice(0, 64));
    assert.equal(counts.analysis, 1, 'Encoding retries do not repeat analysis');
    assert.deepEqual(checked.report.runnable, {verdict: 'no', reasons: [
      {code: 'parameter_value_required'}, {code: 'reporting_budget_exhausted'}]});
  });
}
