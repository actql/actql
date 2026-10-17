import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../host-common/runtime-result.mjs';
import * as google from '../../_build/js/release/build/connectors/google_service_account/host_node/host_node.js';

// Independent fake response material. No key, secret resolver, token endpoint,
// Credential issuer, journal, current authority or transport is substituted.
const valid = '{"access_token":"fixture-token/+._~=","token_type":"Bearer","expires_in":3600}';
const read = (body, {status = 200, bytes = 4096, nodes = 64, depth = 8,
  token = 256, lifetime = 3600, scopes = 4, scopeBytes = 256} = {}) =>
  checked(google.googleServiceAccountReadTokenResponse(status,
    typeof body === 'string' ? Buffer.from(body) : body,
    bytes, nodes, depth, token, lifetime, scopes, scopeBytes));
const refusal = (body, limits) => {
  assert.throws(() => read(body, limits), error => {
    assert.equal(error.code, 'MoonBitHostFailure');
    assert.equal(error.message, 'MoonBitHostFailure');
    assert.equal(JSON.stringify(error).includes('PRIVATE_TOKEN'), false);
    assert.equal(JSON.stringify(error.cause).includes('PRIVATE_TOKEN'), false);
    return true;
  });
};

test('actual private Google Node codec returns exact token and explicit advertised duration', () => {
  const response = read(valid);
  assert.equal(google.googleServiceAccountTokenResponseAccessToken(response), 'fixture-token/+._~=');
  assert.equal(google.googleServiceAccountTokenResponseLifetimeSeconds(response), 3600);
  const lower = read('{"access_token":"b","token_type":"bearer","expires_in":1,"ignored":[0,true,null]}');
  assert.equal(google.googleServiceAccountTokenResponseAccessToken(lower), 'b');
  assert.equal(google.googleServiceAccountTokenResponseLifetimeSeconds(lower), 1);
});

test('actual private Google Node codec refuses duplicate decoded members without native JSON fallback', () => {
  for (const body of [
    '{"access_token":"PRIVATE_TOKEN","access_token":"b","token_type":"Bearer","expires_in":1}',
    '{"access_token":"PRIVATE_TOKEN","\\u0061ccess_token":"b","token_type":"Bearer","expires_in":1}',
    '{"access_token":"PRIVATE_TOKEN","token_type":"Bearer","expires_in":1,"extra":{"x":1,"x":2}}',
    Buffer.from([0xff]), valid + '{}',
  ]) refusal(body);
});

test('actual private Google Node codec rejects errors statuses schemes and header injection without disclosing material', () => {
  refusal('{"access_token":"PRIVATE_TOKEN","token_type":"Bearer","expires_in":1,"error":"invalid_grant","error_description":"PRIVATE_TOKEN"}');
  for (const status of [201, 302, 400, 401, 403, 429, 500]) refusal(valid, {status});
  refusal('{"access_token":"PRIVATE_TOKEN","token_type":"Basic","expires_in":1}');
  refusal('{"access_token":"PRIVATE_TOKEN\\r\\nInjected:x","token_type":"Bearer","expires_in":1}');
});

test('actual private Google Node codec enforces original exact response and semantic bounds', () => {
  const length = Buffer.byteLength(valid);
  assert.equal(google.googleServiceAccountTokenResponseLifetimeSeconds(read(valid, {bytes: length})), 3600);
  // Source/decode depth counts containers: one flat object fits depth 1.
  assert.equal(google.googleServiceAccountTokenResponseLifetimeSeconds(read(valid, {depth: 1})), 3600);
  for (const limits of [{bytes: length - 1}, {nodes: 3},
    {token: 1}, {lifetime: 3599}, {bytes: 0}]) refusal(valid, limits);
  refusal('{"access_token":"a","token_type":"Bearer","expires_in":1,"ignored":[[0]]}', {depth: 1});
  const scopes = '{"access_token":"PRIVATE_TOKEN","token_type":"Bearer","expires_in":1,"scope":"a b"}';
  refusal(scopes, {scopes: 1});
  refusal(scopes, {scopeBytes: 2});
});
