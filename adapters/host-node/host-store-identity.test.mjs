import test from 'node:test';
import assert from 'node:assert/strict';
import {localHostStoreAuthorityCid} from './host-store-identity.mjs';

test('Host Store identity retains its existing exact JSON preimage', () => {
  // Independent fixed vector for the pre-existing ordered JSON bytes:
  // {"version":"actql-local-store-owner/0.1","root":"/fixture/root","principalId":"person"}
  assert.equal(localHostStoreAuthorityCid('/fixture/root', 'person'),
    'sha256:39340574936a32d36841727a6bba39b48500ebff672a5e2103a7492230075865');
  assert.notEqual(localHostStoreAuthorityCid('/fixture/root/', 'person'),
    localHostStoreAuthorityCid('/fixture/root', 'person'));
  assert.notEqual(localHostStoreAuthorityCid('/fixture/root', 'other'),
    localHostStoreAuthorityCid('/fixture/root', 'person'));
});
