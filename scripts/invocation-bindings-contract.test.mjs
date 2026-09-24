import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';
import {
  assertInvocationBindingNames, boundInvocationTemplateCid,
  checkInvocationBindingsSchema, invocationBindingsCid,
} from './invocation-bindings-contract.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const corpus = read('portability/corpus/invocation-bindings.json');
const registry = read('spec/contracts/actql-protocol-schemas.json');

test('Invocation Bindings schema and registry retain their pins', () => {
  checkInvocationBindingsSchema(registry);
});

test('independent vectors bind exact declared reference identities', () => {
  assert.equal(corpus.version, 'actql-invocation-bindings-vectors/0.1');
  for (const fixture of corpus.cases) {
    const preimage = {
      version: 'actql-invocation-bindings/0.1',
      bindings: fixture.bindings,
    };
    verifyIdentity(preimage, fixture.expected_cid,
      fixture.expected_canonical_bytes);
    assertInvocationBindingNames(fixture.declarations, fixture.bindings);
    assert.equal(invocationBindingsCid(fixture.bindings), fixture.expected_cid);
  }
  const full = corpus.cases[1];
  assert.throws(() => assertInvocationBindingNames(full.declarations,
    {asset: full.bindings.asset}));
  assert.throws(() => assertInvocationBindingNames({}, full.bindings));
  assert.throws(() => assertInvocationBindingNames(full.declarations,
    {...full.bindings, target_file: 'sha256:INVALID'}));
});

test('Bound Template preimage includes every registered required member', () => {
  const fixture = corpus.template;
  verifyIdentity(fixture.body, fixture.expected_cid,
    fixture.expected_canonical_bytes);
  assert.deepEqual(Object.keys(fixture.body).sort(),
    registry.artifact_schemas.bound_invocation_template.required
      .filter(name => name !== 'bound_invocation_template_cid').sort());
  assert.equal(boundInvocationTemplateCid(fixture.body), fixture.expected_cid);
  assert.notEqual(boundInvocationTemplateCid({...fixture.body,
    invocation_bindings_cid: corpus.cases[0].expected_cid}),
  fixture.expected_cid);
  const {grammar_manifest_cid: _omitted, ...incomplete} = fixture.body;
  assert.throws(() => boundInvocationTemplateCid(incomplete));
  assert.equal(canonicalText(fixture.body), fixture.expected_canonical_bytes);
});
