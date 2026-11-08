import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createServer, request} from 'node:https';
import {cancellationAckMatches, observationAckLossProxy} from
  './fixtures/observation-ack-loss-proxy.mjs';

const target = 'original-dispatch';
const status = (cid = target, state = 2) => JSON.stringify({
  version: 'actql-remote-dispatch-status/0.1',
  dispatch_request_cid: cid, state: [state, 0, 0, 0, 0],
});
const cancel = (cid = target) => JSON.stringify({
  version: 'actql-remote-poll-cancel/0.1', dispatch_request_cid: cid,
});
const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return {promise, resolve};
};

test('cancellation ACK selection requires the offered original and status phase', () => {
  const selected = (body, options = {}) => cancellationAckMatches(body, {
    dispatchRequestCid: target, executionState: 2,
    cancelOffers: [cancel()], lostReply: false, ...options,
  });
  assert.equal(selected(status(), {cancelOffers: []}), false);
  assert.equal(selected(status(), {cancelOffers: [cancel('foreign')]}), false);
  assert.equal(selected(status(), {cancelOffers: [JSON.stringify({
    version: 'actql-remote-poll-query/0.1', dispatch_request_cid: target,
  })]}), false);
  assert.equal(selected(status('foreign')), false);
  assert.equal(selected(status(target, 5)), false);
  assert.equal(selected(status().replace('dispatch-status', 'other-status')), false);
  assert.equal(selected(status()), true);
  assert.equal(selected(status(), {lostReply: true}), false);
  assert.equal(selected(status(target, 5), {executionState: 5}), true);
});

test('real HTTPS proxy snapshots selection before delayed ACK and drops once after Cancel',
  {timeout: 15000}, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-cancel-ack-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
      '-keyout', join(root, 'key.pem'), '-out', join(root, 'cert.pem'),
      '-subj', '/CN=localhost', '-addext', 'subjectAltName=IP:127.0.0.1',
      '-days', '1'], {stdio: 'ignore'});
    const key = await readFile(join(root, 'key.pem'));
    const cert = await readFile(join(root, 'cert.pem'));
    const arrived = deferred(), release = deferred();
    let holdNext = false, lostReply = false, droppedBody, committed = 0;
    let pollReply = cancel('foreign'), pollStatus = 200;
    const offers = [];
    const upstream = createServer({key, cert}, async (incoming, outgoing) => {
      for await (const _chunk of incoming) { /* Consume the actual request. */ }
      if (incoming.url.endsWith('/observations')) {
        committed++;
        if (holdNext) {
          holdNext = false;
          arrived.resolve();
          await release.promise;
        }
        outgoing.writeHead(200);
        outgoing.end('{}');
      } else {
        outgoing.writeHead(pollStatus);
        outgoing.end(pollReply);
      }
    });
    t.after(async () => {
      release.resolve();
      upstream.closeAllConnections();
      await new Promise(resolve => upstream.close(resolve));
    });
    await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
    const proxy = await observationAckLossProxy({
      origin: 'https://127.0.0.1:' + upstream.address().port, key, cert, ca: cert,
      allowDispatch: () => true,
      loseAck: body => cancellationAckMatches(body, {
        dispatchRequestCid: target, executionState: 2,
        cancelOffers: offers, lostReply,
      }),
      onAckLost: body => {
        assert.equal(lostReply, false);
        assert.ok(committed > 0, 'upstream accepted before losing ACK');
        lostReply = true;
        droppedBody = body; // Retain exactly one selected event, not a growing log.
      },
      transformReply: (_body, reply) => {
        if (reply.status === 200) {
          const envelope = reply.body.toString('utf8');
          const value = JSON.parse(envelope);
          if (value.version === 'actql-remote-poll-cancel/0.1' &&
              value.dispatch_request_cid === target) offers.push(envelope);
        }
        return reply;
      },
    });
    t.after(() => proxy.close());
    const post = (path, body = '{}') => new Promise((resolve, reject) => {
      const outgoing = request(proxy.origin + path,
        {method: 'POST', ca: cert, agent: false}, response => {
          response.resume();
          response.on('end', () => resolve(response.statusCode));
        });
      outgoing.on('error', reject);
      outgoing.end(body);
    });
    assert.equal(await post('/observations', status()), 200);
    await post('/poll'); // Foreign Cancel cannot arm the original.
    assert.equal(offers.length, 0);
    assert.equal(await post('/observations', status()), 200);
    pollReply = cancel(); pollStatus = 503;
    assert.equal(await post('/poll'), 503);
    assert.equal(offers.length, 0);
    holdNext = true;
    const delayed = post('/observations', status());
    await arrived.promise; // The proxy has already selected this request.
    pollStatus = 200;
    assert.equal(await post('/poll'), 200);
    assert.deepEqual(offers, [cancel()]);
    release.resolve();
    assert.equal(await delayed, 200, 'pre-Cancel request retains its ACK');
    assert.equal(lostReply, false);
    assert.equal(await post('/observations', status('foreign')), 200);
    assert.equal(await post('/observations', status(target, 5)), 200);
    await assert.rejects(post('/observations', status()), {code: 'ECONNRESET'});
    assert.equal(droppedBody, status());
    assert.equal(await post('/observations', status()), 200);
    assert.equal(committed, 7);
  });

test('resident cancellation uses the tested selector and exact refusal identity', async () => {
  const source = await readFile(new URL('./test-native-resident-site.mjs', import.meta.url), 'utf8');
  assert.match(source, /loseAck: body => cancellationAckMatches\(body, \{\s*dispatchRequestCid: siteControl.identity\(dispatch\),\s*executionState: mode === 'running-lost-reply' \? 2 : 5,\s*cancelOffers, lostReply,/u);
  assert.match(source, /line.kind === 'cancel-unreported' &&\s*line.request_cid === siteControl.identity\(dispatch\)/u);
  // Any resident fixture edit also has to retain its diagnostic's whole-source
  // fence. Run that real consumer here so the focused ACK gate closes the pin.
  const {rewriteResidentControlSpawn} = await import('./diagnose-native-resident-functions.mjs');
  const diagnostic = {python: '/usr/bin/python3', wrapper: '/test/wrapper.py', report: '/test/report.json'};
  assert.notEqual(rewriteResidentControlSpawn(source, diagnostic), source);
  assert.throws(() => rewriteResidentControlSpawn(source + '\n', diagnostic), /Source hash differs/u);
  const workflow = await readFile(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  assert.match(workflow, /^        run: node --test scripts\/test-native-core\.test\.mjs scripts\/native-query-coverage\.test\.mjs scripts\/native-resident-phase-watchdog\.test\.mjs scripts\/native-resident-function-diagnostic\.test\.mjs scripts\/observation-ack-loss-proxy\.test\.mjs$/mu);
});
