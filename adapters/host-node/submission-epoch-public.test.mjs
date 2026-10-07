// Source-execution acceptance. Fresh-packed identity is established separately
// by the existing packed consumer; these tests do not claim package evidence.
import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {connect as connectRemote, getSubmissionInput} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {fixtureCertificates} from '../site-node/https-exchange-fixture.mjs';

for (const [entrance, loseSubmissionReply] of [['local', false], ['https', false], ['https', true]]) {
  test(`${entrance}${loseSubmissionReply ? ' lost reply' : ''}: ordinary installed Program retains its submission identity and Run after Host restart`, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-d-submission-public-'));
    const directory = join(root, 'host');
    const principalId = userInfo().username;
    const keys = generateKeyPairSync('ed25519');
    let computes = 0, client, host, server, loseReply = loseSubmissionReply;
    const authorization = {
      accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
        account_id: 'submission-public', entries: [{entry_id: 'acceptance', outcome: 'allow',
          principal: {all: true}, connection: {all: true}, resource: {all: true},
          operation: {any_of: ['write']}, exclusions: []}]}),
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      reviewReaders: [principalId], hostKey: {keyId: 'host',
        privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      observe(name) {if (name === 'computed') computes++;},
    };
    const certificates = entrance === 'https' ? await fixtureCertificates(root) : undefined;
    const originalTrust = getCACertificates('default');
    if (certificates) setDefaultCACertificates([...originalTrust, certificates.ca.toString('utf8')]);
    const close = async () => {
      await client?.close(); client = undefined;
      if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); server = undefined;}
      await host?.close(); host = undefined;
    };
    t.after(async () => {
      await close();
      if (certificates) setDefaultCACertificates(originalTrust);
      await rm(root, {recursive: true, force: true});
    });
    const open = async () => {
      if (entrance === 'local') client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
        durability: 'durable', installation: {directory, authorization}});
      else {
        host = await openInstalledRemoteHttpHost({directory, authorization, authenticate: () => principalId});
        server = createServer({key: certificates.key, cert: certificates.cert}, (request, response) => {
          if (loseReply && request.url.endsWith('/submit-intent')) {
            loseReply = false;
            // The installed handler commits its answer before calling end.
            // Drop only that response, without retrying the submission.
            response.end = () => {response.destroy(); return response;};
          }
          return host.handler(request, response);
        });
        await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
        client = await connectRemote({mode: 'remote', token: 'fixture-principal', durability: 'durable',
          endpoint: `https://127.0.0.1:${server.address().port}/`});
      }
    };
    await open();
    const submissionRef = client.newSubmission({nonce: 'ordinary-original'});
    let run;
    if (loseSubmissionReply) {
      await assert.rejects(client.aql('SELECT 1 AS n', {format: 'sql', submissionRef}), error => {
        assert.deepEqual(getSubmissionInput(error).submissionRef, submissionRef);
        return error.code === 'SubmissionUnknown';
      });
      const original = await client.lookupSubmission(submissionRef);
      assert.equal(original.kind, 'ready');
      run = await client.attach(original.admission.ref);
    } else run = await client.aql('SELECT 1 AS n', {format: 'sql', submissionRef});
    assert.equal((await run.wait({signal: AbortSignal.timeout(15000)})).status, 'succeeded');
    assert.deepEqual(await run.result('answer').all(), [{n: 1}]);
    const first = await client.lookupSubmission(submissionRef);
    assert.equal(first.kind, 'ready');
    assert.deepEqual(first.admission.ref, run.ref);
    assert.equal(computes, 1);
    await close(); await open();
    assert.notDeepEqual(client.newSubmission({nonce: submissionRef.nonce}), submissionRef);
    const found = await client.lookupSubmission(submissionRef);
    assert.equal(found.kind, 'ready');
    assert.deepEqual(found.submissionRef, submissionRef);
    assert.deepEqual(found.admission.ref, run.ref);
    const repeated = await client.aql('SELECT 1 AS n', {format: 'sql', submissionRef});
    assert.deepEqual(repeated.ref, run.ref);
    assert.deepEqual(await repeated.result('answer').all(), [{n: 1}]);
    assert.equal(computes, 1);
  });
}
