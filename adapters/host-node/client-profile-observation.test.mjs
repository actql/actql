import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import * as sdk from '../../packages/sdk/index.mjs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {installNodeClientCheck} from './client-check.mjs';

const environmentWire = await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8');
const environmentBody = JSON.parse(environmentWire);
const environment = moon.clientProgramCheckEnvironment(environmentWire.trimEnd(),
  environmentBody.evidence_bundle_cid, false, false, true, true, false, false, false);
assert.ok(environment);

async function installed(t, entrance, getters = false, profileFault) {
  const mode = entrance === 'local' ? 'local' : 'remote', calls = [], reads = {scopeRef: 0, maxRows: 0};
  const profile = {version: 'actql-client-host/0.1', mode, owner: mode,
    durability: 'volatile', scopeRef: 'principal', capabilities: [],
    limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
      maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
      maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
  const services = {authenticate: () => 'principal',
    authorizeConnection: ({operation}) => {calls.push(operation); return true;},
    negotiate: () => profile,
    check: installNodeClientCheck({moon, environment}), maxRowBytes: 1024};
  if (entrance === 'local') {
    const host = createNodeInProcessClientHost(services);
    return {profile, calls, reads, connect: () => sdk.connectInProcess({mode, owner: mode}, {
      async perform(operation, ...args) {
        const reply = await host.perform(operation, ...args);
        if (operation === 'connect' && profileFault !== undefined) {
          // Mutate only the transport-owned reply after the real Host check.
          if (profileFault === 'missing-scope') delete reply.scopeRef;
          else reply.limits.maxRows = 0;
        }
        if (operation === 'connect' && getters) {
          Object.defineProperty(reply, 'scopeRef', {enumerable: true, configurable: true,
            get() {return ++reads.scopeRef === 1 ? 'principal' : 'foreign-principal';}});
          Object.defineProperty(reply.limits, 'maxRows', {enumerable: true, configurable: true,
            get() {return ++reads.maxRows === 1 ? 10 : 20;}});
        }
        return reply;
      },
    })};
  }
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-profile-check-', label: 'TLS profile/check'});
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: scratch.path, stdio: 'ignore'});
  const [key, cert] = await Promise.all(['host.key', 'host.crt'].map(name => readFile(join(scratch.path, name))));
  const originalCAs = getCACertificates('default');
  setDefaultCACertificates([...originalCAs, cert.toString('utf8')]);
  const handle = createClientHttpHandler(services);
  const server = createServer({key, cert}, (request, response) => {
    if (request.url?.endsWith('/connect') && profileFault !== undefined) {
      const end = response.end;
      response.end = function(data, ...args) {
        if (response.statusCode !== 200) return end.call(this, data, ...args);
        const value = JSON.parse(data.toString());
        if (profileFault === 'missing-scope') delete value.scopeRef;
        else value.limits.maxRows = 0;
        return end.call(this, JSON.stringify(value), ...args);
      };
    }
    return handle(request, response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    setDefaultCACertificates(originalCAs); scratch.passed();
  });
  return {profile, calls, reads, connect: () => sdk.connect({mode,
    endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'profile-fixture-token'})};
}

for (const entrance of ['local', 'https']) {
  test(`${entrance}: admitted profile retains its context through an actual syntax check`, {timeout: 10000}, async t => {
    const f = await installed(t, entrance, entrance === 'local'), client = await f.connect();
    t.after(() => client.close());
    assert.equal(client.profile.scopeRef, 'principal', '[check-mutation:profile-public-capture]');
    assert.equal(client.profile.limits.maxRows, 10);
    if (entrance === 'local') assert.deepEqual(f.reads, {scopeRef: 1, maxRows: 1});
    const outcome = await client.check('SELECT', {kind: 'text', scope: 'bound_input', format: 'sql'});
    assert.equal(outcome.outcome, 'completed');
    assert.equal(outcome.report.verdict, 'invalid');
    const input = sdk.getCheckInput(outcome, 'source');
    assert.equal(input.text, 'SELECT');
    assert.deepEqual(outcome.report.reasons, [{code: 'query_syntax_invalid', location: {
      kind: 'text', document_id: 'source', revision: input.revision,
      precision: 'exact', start_byte: 6, end_byte: 6}}]);
    const location = sdk.resolveCheckLocation(outcome, outcome.report.reasons[0].location);
    assert.equal(location.text, '');
    assert.equal(location.input, input);
    Object.defineProperty(f.profile, 'scopeRef', {value: 'foreign-principal', enumerable: true,
      writable: true, configurable: true});
    Object.defineProperty(f.profile.limits, 'maxRows', {value: 20, enumerable: true,
      writable: true, configurable: true});
    assert.equal(client.profile.scopeRef, 'principal');
    assert.equal(client.profile.limits.maxRows, 10);
    assert.deepEqual(f.calls, ['connect', 'check']);
  });
  for (const fault of ['replacement', 'mutation']) {
    test(`${entrance}: profile ${fault} clone cannot replace the original context`, {timeout: 10000}, async t => {
      const f = await installed(t, entrance), clone = globalThis.structuredClone;
      t.after(() => {globalThis.structuredClone = clone;});
      let conversions = 0;
      globalThis.structuredClone = value => {
        const copy = clone(value);
        if (value.version === 'actql-client-host/0.1') {
          conversions++;
          if (fault === 'replacement') copy.scopeRef = 'foreign-principal';
          else value.scopeRef = 'foreign-principal';
        }
        return copy;
      };
      let client, failure;
      try { client = await f.connect(); } catch (error) { failure = error; }
      if (client) t.after(() => client.close());
      assert.equal(failure, undefined, `[check-mutation:profile-public-${fault}]`);
      assert.equal(conversions, 0, `[check-mutation:profile-public-${fault}]`);
      assert.equal(client.profile.scopeRef, 'principal');
      assert.equal(client.profile.limits.maxRows, 10);
      assert.equal(sdk.explainCheckFailure(failure), undefined);
      assert.equal(sdk.getCheckFailureInput(failure), undefined);
      assert.deepEqual(f.calls, ['connect']);
    });
  }
  for (const fault of ['missing-scope', 'invalid-row-limit']) {
    test(`${entrance}: malformed profile ${fault} cannot start checking or issue a verdict`, {timeout: 10000}, async t => {
      const f = await installed(t, entrance, false, fault);
      let failure, client;
      try { client = await f.connect(); } catch (error) { failure = error; }
      if (client) t.after(() => client.close());
      assert.equal(failure?.code, 'InvalidHostProfile');
      assert.equal(sdk.explainCheckFailure(failure), undefined);
      assert.equal(sdk.getCheckFailureInput(failure), undefined);
      assert.deepEqual(f.calls, ['connect']);
    });
  }

}
