// Invalid source encoding is refused before analysis. Expected bytes and
// envelopes are independent literals; the admitted control uses the checker.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer, request as httpsRequest} from 'node:https';
import {join} from 'node:path';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath, pathToFileURL} from 'node:url';
import test, {after} from 'node:test';
import {ClientError, connect, getCheckInput, resolveCheckLocation,
  resolveCheckTextRange} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {installNodeClientCheck} from './client-check.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {sourceAliasPublication} from './source-alias-publication.mjs';

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

async function publicCheck(t, entrance) {
  const counts = {exchanges: 0, authorization: 0, analysis: 0};
  const check = installNodeClientCheck({moon: {...moon,
    clientProgramCheckSource: (...args) => {
      counts.analysis++;
      return moon.clientProgramCheckSource(...args);
    }}, environment, publication: sourceAliasPublication(moon, environment, [])});
  const connection = {mode: entrance === 'local' ? 'local' : 'remote',
    owner: entrance === 'local' ? 'local' : 'remote', runners: [], consentRefs: []};
  const configuration = {authenticate: () => 'reader',
    authorizeConnection: ({operation}) => {
      if (operation === 'check') counts.authorization++;
      return true;
    }, negotiate: () => ({version: 'actql-client-host/0.1',
      mode: connection.mode, owner: connection.owner, durability: 'durable',
      scopeRef: 'text-boundary-scope', capabilities: [],
      limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
        maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
        maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}}),
    check, maxRowBytes: 1024, maxRequestBytes: 65536};
  const body = text => ({connection, input: {text, format: 'sql'}, parameters: null});
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

test('HTTPS: malformed UTF-8 check bytes never enter analysis', async t => {
  const {client, counts, send} = await publicCheck(t, 'http');
  const prefix = Buffer.from('{"connection":{"mode":"remote","owner":"remote","runners":[],"consentRefs":[]},"input":{"text":"SELECT \'');
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
  const admitted = await client.check("SELECT '\ufffd' AS label", {format: 'sql'});
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
      const result = await client.check(text, {format: 'sql'}).then(() => ({}), error => {
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
    const outcome = await client.check(text, {format: 'sql'});
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
