import test from 'node:test';
import assert from 'node:assert/strict';
import {
  prepareManagedIdentityPolicy,
  preparedManagedIdentityPolicy,
} from './managed-identity-policy.mjs';

test('managed identity policy is opaque, immutable and defaults to local use', () => {
  assert.deepEqual(preparedManagedIdentityPolicy(undefined), {
    publication: false,
    consumer: false,
  });
  const policy = prepareManagedIdentityPolicy({
    publication: true,
    consumer: true,
  });
  assert.equal(Object.isFrozen(policy), true);
  assert.deepEqual(preparedManagedIdentityPolicy(policy), {
    publication: true,
    consumer: true,
  });
  assert.throws(() => preparedManagedIdentityPolicy({...policy}), TypeError);
  assert.throws(
    () => prepareManagedIdentityPolicy({publication: 1}),
    TypeError,
  );
  assert.throws(
    () => prepareManagedIdentityPolicy({hostPolicy: true}),
    TypeError,
  );
});
