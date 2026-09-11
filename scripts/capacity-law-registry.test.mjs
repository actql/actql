import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { validateRegistry, loadRegistry, renderRegistry } from './capacity-law-registry.mjs';

test('registry fixes its identity, rejects missing Host entries and malformed names', () => {
  const { body, policy } = loadRegistry();
  assert.equal(validateRegistry(body, policy), 'sha256:f7b4eccb94ab84d61367bb89e84f9ede39bf14d459df18b23dd214ad7c510796');
  const family = JSON.parse(readFileSync(new URL('../spec/spec-family.json', import.meta.url), 'utf8'));
  const owner = family.documents.find(document => document.spec_id === 'actql.protocol.contracts');
  assert.deepEqual(owner.machine_contracts.filter(ref => ref.path === 'spec/contracts/actql-bound-law-registry.json'), [{
    path: 'spec/contracts/actql-bound-law-registry.json', pointer: '',
    cid: validateRegistry(body, policy), version: body.version,
  }]);
  for (const mutate of [
    value => { value.version = 'actql-bound-law-registry/1.0'; },
    value => { value.law_ids = []; },
    value => { value.law_ids.push(value.law_ids[0]); },
    value => { value.law_ids.reverse(); },
    value => { value.law_ids = value.law_ids.filter(id => id !== 'actql.host.relation-output'); },
    value => { value.law_ids[0] = ' actql.bound.append'; },
    value => { value.extra = true; },
  ]) {
    const variant = structuredClone(body);
    mutate(variant);
    assert.throws(() => validateRegistry(variant, policy));
  }
  const generated = renderRegistry(body);
  for (const id of body.law_ids) assert.ok(generated.includes(`${JSON.stringify(id)} => Some(RegisteredLaw(law))`));
});
