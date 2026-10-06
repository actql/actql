import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const number = {type: 'number', nullable: false};
const arrayInput = {parameterDeclarations: {items: {type: 'array', nullable: false,
  max_items: 3, items: number}}, parameters: {items: [2, 1, 2]}};
// Expected rows and order follow the authored predicates and three input
// occurrences. They are never derived from compiler output or actual results.
const cases = [
  {name: 'select-different', text: 'SELECT COUNT(* WHERE FALSE) AS n_false, COUNT(* WHERE TRUE) + 0 AS n_true',
    expected: [{n_false: 0, n_true: 1}]},
  {name: 'select-absent', text: 'SELECT COUNT(*) AS total, COUNT(* WHERE FALSE) + 0 AS n_false',
    expected: [{total: 1, n_false: 0}]},
  {name: 'having-different', text: 'SELECT COUNT(* WHERE FALSE) AS n_false HAVING COUNT(* WHERE TRUE) > 0',
    expected: [{n_false: 0}]},
  {name: 'equal-control', text: 'SELECT COUNT(* WHERE TRUE) AS n, COUNT(* WHERE TRUE) + 0 AS same',
    expected: [{n: 1, same: 1}]},
  {name: 'order-different', text: 'SELECT x, COUNT(* WHERE FALSE) AS n_false FROM UNNEST(@items) AS x GROUP BY x ORDER BY COUNT(* WHERE x = 1) DESC, x DESC',
    ...arrayInput, expected: [{x: 1, n_false: 0}, {x: 2, n_false: 0}]},
  {name: 'having-alias-filter', text: 'SELECT x AS k FROM UNNEST(@items) AS x GROUP BY x HAVING COUNT(* WHERE k > 1) > 0 ORDER BY k',
    ...arrayInput, expected: [{k: 2}]},
  {name: 'order-alias-filter', text: 'SELECT x AS k FROM UNNEST(@items) AS x GROUP BY x ORDER BY COUNT(* WHERE k = 1) DESC, k DESC',
    ...arrayInput, expected: [{k: 1}, {k: 2}]},
];

async function fixture(t, mode) {
  const parent = new URL('../../_build/aggregate-filter-reuse/', import.meta.url);
  await mkdir(parent, {recursive: true});
  const directory = await mkdtemp(new URL(mode + '-', parent));
  t.diagnostic(`Aggregate-filter Host evidence: ${directory}`);
  const keys = generateKeyPairSync('ed25519');
  let dispatches = 0;
  const authorization = {accountConfiguration: canonicalJson({
    version: 'actql-execution-account-config/0.1', account_id: 'aggregate-filter',
    entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true}, operation: {all: true}, exclusions: []}],
  }), hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  faultInjection(name) { if (name === 'dispatch_reserved') dispatches++; }};
  let client, host, server;
  t.after(async () => {
    await client?.close();
    if (server) { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
    await host?.close();
    // Preserve failed and final fixture custody for fixed-source review.
  });
  if (mode === 'local') {
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory: join(directory, 'host'), authorization}});
  } else {
    execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
      '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: directory, stdio: 'ignore'});
    const cert = await readFile(join(directory, 'host.crt'));
    setDefaultCACertificates([...getCACertificates('default'), cert.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({directory: join(directory, 'host'), authorization,
      authenticate: header => header === 'Bearer aggregate-filter-fixture' ? userInfo().username : undefined});
    server = createServer({key: await readFile(join(directory, 'host.key')), cert}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'remote', token: 'aggregate-filter-fixture',
      endpoint: `https://127.0.0.1:${server.address().port}/`});
  }
  return {client, dispatches: () => dispatches};
}

for (const mode of ['local', 'https']) {
  test(`${mode}: filtered aggregate reuse and alias dependencies preserve public rows`,
    {timeout: 90_000}, async t => {
      const {client, dispatches} = await fixture(t, mode);
      for (const item of cases) {
        const options = {format: 'sql', requestId: item.name,
          ...(item.parameterDeclarations ? {parameterDeclarations: item.parameterDeclarations,
            parameters: item.parameters} : {})};
        const run = await client.aql(item.text, options);
        const state = await run.wait({signal: AbortSignal.timeout(15_000)});
        assert.equal(state.status, 'succeeded', item.name + ': ' + JSON.stringify(state));
        assert.deepEqual(await run.result('answer').all(), item.expected, item.name);
        assert.deepEqual((await run.result('answer').describe()).columns,
          Object.keys(item.expected[0]).map(name => ({name, contract: number})), item.name);
        const before = dispatches();
        assert.deepEqual((await client.aql(item.text, options)).ref, run.ref);
        assert.deepEqual(await (await client.attach(run.ref)).result('answer').all(), item.expected, item.name);
        assert.equal(dispatches(), before, item.name + ': resend/attach must not execute again');
      }
    });
  test(`${mode}: different aggregate filters retain validation and demanded errors`,
    {timeout: 45_000}, async t => {
      const {client, dispatches} = await fixture(t, mode);
      await assert.rejects(client.aql('SELECT COUNT(*) AS n, COUNT(* WHERE 1) + 0 AS invalid',
        {format: 'sql', requestId: 'invalid-filter'}), {code: 'ClientProgramRejected'});
      assert.equal(dispatches(), 0, 'invalid filter must fail before dispatch');
      const run = await client.aql('SELECT SUM(1 / 0 WHERE FALSE) AS skipped, SUM(1 / 0 WHERE TRUE) + 0 AS demanded',
        {format: 'sql', requestId: 'demanded-error'});
      const state = await run.wait({signal: AbortSignal.timeout(15_000)});
      assert.equal(state.status, 'failed', JSON.stringify(state));
      await assert.rejects(run.result('answer').all());
      await assert.rejects(run.result('answer').describe());
    });
}
