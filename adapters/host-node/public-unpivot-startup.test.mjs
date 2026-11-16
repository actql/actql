import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {unpivotRowLabelSuccesses} from '../../scripts/fixtures/unpivot-row-label-source-input.mjs';

test('public Unpivot label chain starts within the original default budget',
  {timeout: 45_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-unpivot-startup-'));
    const keys = generateKeyPairSync('ed25519');
    const failures = [];
    let computations = 0;
    const authorization = {
      accountConfiguration: JSON.stringify({account_id: 'unpivot-startup', entries: [{
        connection: {all: true}, entry_id: 'allow', exclusions: [], operation: {all: true},
        outcome: 'allow', principal: {all: true}, resource: {all: true}}],
      version: 'actql-execution-account-config/0.1'}),
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      observe(event, detail) {
        if (event === 'dispatch_failed') failures.push(detail);
        if (event === 'computed') computations++;
      },
    };
    const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, authorization}});
    t.after(async () => {await client.close(); await rm(directory, {recursive: true});});
    // Keep the exact original JSON control and its independent duplicate/NULL
    // row oracle from the packed query acceptance input.
    const fixture = unpivotRowLabelSuccesses.find(item =>
      item.name === 'unpivot-row-label-json-control');
    const submissionRef = client.newSubmission({nonce: 'unpivot-startup'});
    const execution = await client.startSource(fixture.text, {format: fixture.format, submissionRef});
    const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
    assert.equal(state.status, 'succeeded', JSON.stringify({state, failures}));
    assert.deepEqual(await execution.result('answer').all(), fixture.expected);
    assert.deepEqual(failures, []);
    assert.equal(computations, 1);
    assert.deepEqual((await client.startSource(fixture.text,
      {format: fixture.format, submissionRef})).ref, execution.ref);
    assert.equal(computations, 1);
  });
