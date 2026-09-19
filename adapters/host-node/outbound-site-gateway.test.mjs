import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {X509Certificate} from 'node:crypto';
import {request as httpsRequest} from 'node:https';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteDispatchJournal} from
  '../site-node/sqlite-dispatch-journal.mjs';
import {openSqliteCoordinatorDispatchJournal} from
  './sqlite-coordinator-journal.mjs';
import {startHttpsOutboundSiteGateway} from './outbound-site-gateway.mjs';
import {createRemoteSiteCoordinator} from './remote-site-coordinator.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const runtime = runtimeCore(moon);
const control = runtime.remoteSiteControl;
const scratch = fileURLToPath(new URL('../../../.codex-scratch/', import.meta.url));

function openssl(root, ...arguments_) {
  execFileSync('openssl', arguments_, {cwd: root, stdio: 'ignore'});
}

function issue(root, name, subject, extension) {
  openssl(root, 'genrsa', '-out', `${name}.key`, '2048');
  openssl(
    root,
    'req',
    '-new',
    '-key', `${name}.key`,
    '-out', `${name}.csr`,
    '-subj', subject,
  );
  openssl(
    root,
    'x509',
    '-req',
    '-in', `${name}.csr`,
    '-CA', 'ca.crt',
    '-CAkey', 'ca.key',
    '-CAcreateserial',
    '-out', `${name}.crt`,
    '-days', '1',
    ...(extension === undefined ? [] : ['-extfile', extension]),
  );
}

async function certificates(root) {
  openssl(root, 'genrsa', '-out', 'ca.key', '2048');
  openssl(
    root,
    'req',
    '-x509',
    '-new',
    '-key', 'ca.key',
    '-out', 'ca.crt',
    '-subj', '/CN=ActQL Outbound Test CA',
    '-days', '1',
  );
  await writeFile(
    join(root, 'server.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n' +
      'extendedKeyUsage=serverAuth\n',
  );
  await writeFile(
    join(root, 'client.ext'),
    'extendedKeyUsage=clientAuth\n',
  );
  issue(root, 'server', '/CN=localhost', 'server.ext');
  issue(root, 'site', '/CN=site-a', 'client.ext');
  issue(root, 'foreign', '/CN=foreign-site', 'client.ext');
  const read = name => readFile(join(root, name));
  const siteCertificate = await read('site.crt');
  return Object.freeze({
    ca: await read('ca.crt'),
    serverKey: await read('server.key'),
    serverCertificate: await read('server.crt'),
    siteKey: await read('site.key'),
    siteCertificate,
    siteFingerprint: new X509Certificate(siteCertificate).fingerprint256,
    foreignKey: await read('foreign.key'),
    foreignCertificate: await read('foreign.crt'),
  });
}

function post(origin, path, material, body = '{}') {
  const bytes = Buffer.from(body, 'utf8');
  return new Promise((resolve, reject) => {
    const request = httpsRequest(new URL(path, origin), {
      method: 'POST',
      ca: material.ca,
      cert: material.cert,
      key: material.key,
      servername: 'localhost',
      minVersion: 'TLSv1.3',
      headers: {
        'content-type': 'application/json',
        'content-length': String(bytes.byteLength),
      },
    }, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('error', reject);
      response.on('end', () => resolve(Object.freeze({
        status: response.statusCode,
        body: Buffer.concat(chunks).toString('utf8'),
      })));
    });
    request.on('error', reject);
    request.end(bytes);
  });
}

function dispatch() {
  return control.prepare({
    coordinatorAuthority: 'coordinator-a',
    runDefinitionCid: cid('0'),
    taskKey: 'task-a',
    taskAttempt: 1,
    dispatchId: 'dispatch-outbound-a',
    siteKey: 'site-a',
    siteGeneration: 1,
    runtimeBundleCid: cid('a'),
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
    inputBindingCid: cid('1'),
    obligationsCid: cid('2'),
    budgetCid: cid('3'),
    evidenceIssuerCapabilityCid: cid('b'),
    grantCid: cid('4'),
  });
}

test('outbound gateway durably dispatches without an inbound Site listener',
  async t => {
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch, 'outbound-gateway-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const certificates_ = await certificates(root);
    const gateway = await startHttpsOutboundSiteGateway({
      key: certificates_.serverKey,
      cert: certificates_.serverCertificate,
      ca: certificates_.ca,
      siteAuthorities: new Map([[
        certificates_.siteFingerprint,
        {siteKey: 'site-a', siteGeneration: 1},
      ]]),
      control,
    });
    t.after(() => gateway.close());
    const coordinatorStore = openSqliteCoordinatorDispatchJournal(
      join(root, 'coordinator'),
      {coordinatorAuthority: 'coordinator-a'},
    );
    t.after(() => coordinatorStore.close());
    const coordinator = createRemoteSiteCoordinator({
      control,
      journal: control.createCoordinatorJournal('coordinator-a'),
      store: coordinatorStore,
      send: gateway.dispatch,
      query: gateway.query,
      cancel: async () => {
        throw Object.assign(new Error('OutboundCancelUnsupported'), {
          code: 'OutboundCancelUnsupported',
        });
      },
    });
    const request = dispatch();
    const completion = coordinator.dispatch({dispatch: request});
    assert.equal(gateway.pending(), 1);
    const path = '/v1/sites/site-a/generations/1/outbound';
    const siteMaterial = {
      ca: certificates_.ca,
      cert: certificates_.siteCertificate,
      key: certificates_.siteKey,
    };
    const polled = await post(gateway.origin, `${path}/poll`, siteMaterial);
    assert.equal(polled.status, 200);
    const envelope = JSON.parse(polled.body);
    const received = control.admitJson(
      envelope.request_json,
      envelope.dispatch_request_cid,
    );
    assert.equal(control.identity(received), control.identity(request));
    const altered = await post(
      gateway.origin,
      `${path}/observations`,
      siteMaterial,
      '{"dispatch_request_cid":"sha256:' + 'f'.repeat(64) + '"}',
    );
    assert.equal(altered.status, 404);
    assert.equal(gateway.pending(), 1);

    const site = runtime.siteControl.create({
      key: 'site-a',
      generation: 1,
      runtimeRevision: cid('a'),
      maxConcurrentOperations: 4,
      maxConcurrentTransfers: 4,
      maxRetainedBytes: 1_048_576n,
      maxExecutionBytes: 1_048_576n,
    });
    const siteJournal = control.createJournal(site);
    const siteStore = openSqliteDispatchJournal(join(root, 'site'), {
      siteKey: 'site-a',
      siteGeneration: 1,
      runtimeRevision: cid('a'),
    });
    t.after(() => siteStore.close());
    const record = siteStore.accept(
      control.prepareAdmission(siteJournal, received),
      received,
      control,
    );
    const observed = await post(
      gateway.origin,
      `${path}/observations`,
      siteMaterial,
      control.replyJson(record),
    );
    assert.equal(observed.status, 200);
    const result = await completion;
    assert.equal(result.dispatchRequestCid, control.identity(request));
    assert.deepEqual(result.state, [0, 0, 0, 0, 0]);
    assert.equal(gateway.pending(), 0);
    assert.equal(coordinatorStore.contains(request, control), true);

    const empty = await post(gateway.origin, `${path}/poll`, siteMaterial);
    assert.equal(empty.status, 204);
    const foreign = await post(gateway.origin, `${path}/poll`, {
      ca: certificates_.ca,
      cert: certificates_.foreignCertificate,
      key: certificates_.foreignKey,
    });
    assert.equal(foreign.status, 404);
  });
