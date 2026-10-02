import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:https';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import test from 'node:test';
import {connect} from '../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';

const oneRowInfer = () => ({version: 'actql/0.1', id: 'installed-infer',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: {type: 'string', nullable: false},
      text: {type: 'string', nullable: true}},
      rows: [{id: 'a', text: 'hello'}]}, as: 'input'},
    {assert_rows: {unique_by: ['id']}, as: 'unique'},
    {infer: {contract: 'model-task:risk-score.v1', key: 'id',
      input: {text: {field: 'text'}}}, as: 'captured'},
  ], results: {captured: {from: 'captured',
    fields: ['id', 'outcome', 'value']}}}],
  results: {answer: {from: {stage: 'main', result: 'captured'}}}});

async function installedHost(t, options = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-installed-infer-'));
  const priorCertificates = getCACertificates('default');
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'host.key', '-out', 'host.crt', '-days', '1',
    '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
  {cwd: root, stdio: 'ignore'});
  let host, server;
  t.after(async () => {
    try {
      if (server !== undefined) {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
      }
      await host?.close();
    } finally {
      setDefaultCACertificates(priorCertificates);
      await rm(root, {recursive: true, force: true});
    }
  });
  const certificate = await readFile(join(root, 'host.crt'));
  setDefaultCACertificates([...priorCertificates, certificate.toString()]);
  let physicalStarts = 0;
  host = await openInstalledRemoteHttpHost({directory: join(root, 'state'),
    authenticate: () => userInfo().username,
    beforeDispatch: () => { physicalStarts++; }, ...options});
  server = createServer({key: await readFile(join(root, 'host.key')),
    cert: certificate}, host.handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const client = await connect({mode: 'remote',
    endpoint: `https://127.0.0.1:${server.address().port}/`,
    token: 'fixture-owner', durability: 'durable'});
  return {client, root, physicalStarts: () => physicalStarts};
}

test('ordinary public INFER refuses a missing installed ModelTask before Run admission',
  async t => {
    const {client, root, physicalStarts} = await installedHost(t);
    await assert.rejects(client.start(oneRowInfer(), {requestId: 'infer-missing'}),
      error => {
        t.diagnostic(`Public preparation refusal: ${error.code}`);
        assert.equal(error.code, 'ClientProgramRejected');
        return true;
      });
    assert.equal(physicalStarts(), 0);
    const journal = new DatabaseSync(join(root, 'state', 'requests',
      'client-requests.sqlite3'), {readOnly: true});
    try {
      assert.equal(journal.prepare('SELECT COUNT(*) AS count FROM client_requests')
        .get().count, 0);
    } finally { journal.close(); }
  });

test('installed ModelTask reaches normal public preparation but cannot bypass missing dispatch admission',
  async t => {
    const base = JSON.parse(await readFile(new URL(
      '../../spec/local-check-environment.json', import.meta.url), 'utf8'));
    const taskSource = await readFile(new URL(
      '../../src/stage_results/infer_program_test.mbt', import.meta.url), 'utf8');
    // Independently pinned typing fixture, not a body derived from execution.
    const task = JSON.parse(taskSource.match(/let body =\n\s+#\|(.+)/u)[1]);
    const {evidence_bundle_cid: ignored, ...body} = base;
    void ignored;
    body.model_task_contracts = [task];
    const environmentWire = canonicalJson({...body,
      evidence_bundle_cid: contentCid(body)});
    const {client, root, physicalStarts} = await installedHost(t,
      {modelInstallation: {environmentWire}});
    await assert.rejects(client.start(oneRowInfer(), {requestId: 'infer-installed'}),
      {code: 'ClientProgramUnsupported'});
    assert.equal(physicalStarts(), 0);
    const journal = new DatabaseSync(join(root, 'state', 'requests',
      'client-requests.sqlite3'), {readOnly: true});
    try {
      assert.equal(journal.prepare('SELECT COUNT(*) AS count FROM client_requests')
        .get().count, 0);
    } finally { journal.close(); }
  });
