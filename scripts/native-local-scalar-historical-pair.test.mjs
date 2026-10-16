import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {historicalScalarPairInputs, verifyHistoricalScalarPairManifests,
  scalarPairHistoricalSource, scalarPairHistoricalFixture, assertScalarPairEvidenceFresh} from './native-local-scalar-pair-evidence.mjs';

const inputs = historicalScalarPairInputs();
const sha = value => createHash('sha256').update(value).digest('hex');

test('historical manifest and complete build-time proof bind authentic old109 and a3b inputs', () => {
  assert.equal(sha(inputs.originalBytes), '80731853b15f4d600ef391b3778c734bc40bfb6caed246c0c145916b419e49bd');
  assert.equal(inputs.historicalBytes.length, 2289);
  assert.equal(sha(inputs.historicalBytes), '585e5959c972a801335103217d2dede6cb12f72333a58f6b88bf88c85075fd85');
  assert.equal(inputs.historical.sourceSha, 'a3b1643fbedc5180db38b6e08459a188f05b1135');
  assert.equal(inputs.evidence.body_pairs.length, 11);
  assert.equal(inputs.evidence.asset_pairs.length, 6);
});

test('historical generated inputs reject unknown manifest bytes source platform and closure', () => {
  assert(Buffer.from(JSON.stringify(inputs.historical, null, 2) + '\n').equals(inputs.historicalBytes));
  for (const mutate of [
    x => { x.sourceSha = 'b'.repeat(40); },
    x => { x.platform = 'linux-x64-gnu'; },
    x => { x.libraries[0].bytes += 1; },
    x => { x.libraries[0].abi.minimumMacOS = '25.0'; },
    x => { x.libraries[0].dependencies.pop(); },
    x => { x.licenses[0].sha256 = '0'.repeat(64); },
    x => { x.assets[0].role = 'other'; },
    x => { x.assets[0].bytes += 1; },
    x => { x.assets[0].sha256 = '0'.repeat(64); },
    x => { x.assets.push(x.assets[0]); },
    x => { x.permission = true; },
  ]) {
    const changed = structuredClone(inputs.historical);
    mutate(changed);
    assert.throws(() => verifyHistoricalScalarPairManifests(inputs.originalBytes, Buffer.from(JSON.stringify(changed, null, 2) + '\n')));
  }
  assert.throws(() => verifyHistoricalScalarPairManifests(inputs.historicalBytes, inputs.originalBytes));
  assert.throws(() => verifyHistoricalScalarPairManifests(inputs.originalBytes, Buffer.concat([inputs.historicalBytes, Buffer.from('\n')])));
});

test('generated historical production metadata and independent vectors are fresh', () => {
  assert.equal(readFileSync('src/run_publication_host/client_native_local_scalar_historical_pair.generated.mbt', 'utf8'), scalarPairHistoricalSource());
  assert.equal(readFileSync('src/run_publication_host/client_native_local_scalar_historical_pair_fixture.generated_wbtest.mbt', 'utf8'), scalarPairHistoricalFixture());
  assertScalarPairEvidenceFresh();
});

test('independent Python saved-pair vector retains the original preimage and evidence identity', () => {
  const v = JSON.parse(readFileSync('scripts/fixtures/native-local-scalar-historical-pair-vector.json'));
  assert.equal(v.sha256, '2b06a81d8266f98c954a76556c3312e3abba0acb8615f19c501ce3df920d367b');
  assert.equal(sha(v.body), v.sha256);
  assert.equal(v.cid, 'sha256:' + v.sha256);
  const body = JSON.parse(v.body);
  assert.equal(body.evidence_cid, 'sha256:8bdf483589d04809f0e2e198708adc8335b38179f332e58d25a8a09497633a22');
  assert.equal(body.current_manifest_sha256, sha(inputs.historicalBytes));
  assert.equal(body.original_manifest_sha256, sha(inputs.originalBytes));
  assert.equal(Object.keys(body).length, 8);
});
