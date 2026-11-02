import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir, userInfo} from 'node:os';
import {setTimeout as delay} from 'node:timers/promises';
import {openInstalledClientHostFixture, installedClientSdk} from './fixtures/installed-client-host.fixture.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

const {explainRunObservationFailure, formatRunObservationFailure} = installedClientSdk;

for (const entrance of ['local', 'https']) {
  test(`${entrance}: real publication and physical-stop revisions retain private SDK control custody`,
    {timeout: 30000}, async t => {
      const scratch = await createOwnedScratch({parent: tmpdir(),
        prefix: 'actql-run-control-revisions-', label: `${entrance} original Run control`});
      const keys = generateKeyPairSync('ed25519');
      let reachedPublication, releasePublication;
      const publicationReady = new Promise(resolve => {reachedPublication = resolve;});
      const publicationHeld = new Promise(resolve => {releasePublication = resolve;});
      const counts = {computes: 0, modelCalls: 0, effectCalls: 0, sourceCalls: 0};
      const authorization = {
        accountConfiguration: canonicalJson({version: 'actql-execution-account-config/0.1',
          account_id: 'run-control-revision-fixture', entries: [{entry_id: 'control-result-read', outcome: 'allow',
            principal: {any_of: [userInfo().username]}, connection: {any_of: ['actql-remote-host']},
            resource: {any_of: ['result/answer', 'run']}, operation: {any_of: ['read']}, exclusions: []},
          {entry_id: 'write', outcome: 'allow',
            principal: {all: true}, connection: {all: true}, resource: {all: true},
            operation: {any_of: ['write']}, exclusions: []}]}),
        reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
          publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
        hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
        observe(name) {
          if (name === 'computed') counts.computes++;
          if (name === 'model_call_entered') counts.modelCalls++;
          if (name === 'effect_application_observed') counts.effectCalls++;
          if (name === 'acquisition_started') counts.sourceCalls++;
        },
        async faultInjection(name) {
          if (name === 'computed') {reachedPublication(); await publicationHeld;}
        },
      };
      const installation = {directory: join(scratch.path, 'host'), authorization};
      const exchanges = [];
      let client, installedHost, replay;
      try {
        let certificates;
        if (entrance === 'https') {
          execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
            '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
            '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: scratch.path, stdio: 'ignore'});
          const [key, cert] = await Promise.all(['host.key', 'host.crt'].map(name => readFile(join(scratch.path, name))));
          certificates = {key, cert, ca: cert};
        }
        installedHost = await openInstalledClientHostFixture(t, {
          entrance: entrance === 'local' ? 'in-process' : 'HTTP', installation,
          authenticate: () => userInfo().username, certificates,
          serve(request, response, handler) {
            exchanges.push(request.url);
            if (/\/(status|wait|reconcile)$/u.test(request.url)) {
              const end = response.end.bind(response);
              response.end = (bytes, ...args) => {
                // Delay/replay only a valid response previously issued by the
                // real Owner. The journal, publication and stop stay unchanged.
                const original = JSON.parse(bytes);
                return end(JSON.stringify(replay ?? original), ...args);
              };
            }
            return handler(request, response).catch(error => response.destroy(error));
          },
        });
        client = installedHost.client;
        const program = JSON.parse(await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8'));
        const submissionRef = client.newSubmission({nonce: 'original-control-revision'});
        const run = await client.start(program, {submissionRef});
        await publicationReady;
        const beforeStop = await run.status();
        assert.equal(beforeStop.status, 'succeeded');
        assert.equal(beforeStop.result_available, true);
        assert.equal(beforeStop.control.physical_stop, 'unknown');
        const savedBeforeStop = structuredClone(beforeStop);
        releasePublication();
        const signal = AbortSignal.timeout(15000);
        let stopped;
        do {
          stopped = await run.status();
          if (stopped.control.physical_stop === 'confirmed') break;
          await delay(10, undefined, {signal});
        } while (true);
        assert.equal(stopped.status, 'succeeded');
        assert.ok(stopped.control.revision > savedBeforeStop.control.revision);
        const savedStopped = structuredClone(stopped.control);
        stopped.control.revision = Number.MAX_SAFE_INTEGER;
        stopped.control.cancellation_requested = true;
        const unchanged = await run.status().then(state => ({state}), error => ({error}));
        assert.equal(unchanged.error, undefined, '[check-mutation:run-control-public-custody]');
        assert.deepEqual(unchanged.state.control, savedStopped);
        if (entrance === 'https') {
          replay = savedBeforeStop;
          for (const operation of ['status', 'wait', 'reconcile']) {
            const failure = await run[operation]().then(() => undefined, error => error);
            const explanation = explainRunObservationFailure(failure);
            assert.equal(explanation?.problem, 'stale_observation', '[check-mutation:run-control-public-revision]');
            assert.equal(failure.code, 'InvalidHostRunState');
            assert.deepEqual(explanation.next, {operation: 'status', ref: run.ref});
            const sent = [...exchanges];
            for (const format of ['text', 'html', 'json']) assert.ok(formatRunObservationFailure(failure, {format}));
            assert.equal(explainRunObservationFailure({...failure}), undefined);
            assert.deepEqual(exchanges, sent);
          }
          replay = undefined;
        }
        assert.deepEqual((await run.status()).control, savedStopped);
        assert.deepEqual(await run.result('answer').all(), [{id: 1}, {id: 2}]);
        assert.deepEqual(counts, {computes: 1, modelCalls: 0, effectCalls: 0, sourceCalls: 0});
        console.log('RUN_CONTROL_REVISION_PUBLIC_EVIDENCE', JSON.stringify({entrance, ref: run.ref,
          priorControl: savedBeforeStop.control, currentControl: savedStopped,
          publication: 'succeeded', replayOperations: entrance === 'https' ? ['status', 'wait', 'reconcile'] : [], counts}));
      } finally {
        releasePublication();
        await installedHost?.close();
      }
      scratch.passed();
    });
}
