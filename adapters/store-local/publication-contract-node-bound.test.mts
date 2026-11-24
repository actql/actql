import test from 'node:test';
import assert from 'node:assert/strict';
import {createPublicationContractStore} from './publication-contract-store.mjs';

type ContractControl = Parameters<typeof createPublicationContractStore>[1];
type Limits = Parameters<ContractControl['admit']>[2];

// Use the real Store admission. Only the semantic control is an independent
// structural oracle, and any attempt to enter physical persistence fails.
const cid = 'sha256:' + '0'.repeat(64);

function admission(nodes: number, bytes = 200000) {
  const observed: Limits[] = [];
  const control: ContractControl = {
    admit(name, wire, limits) {
      observed.push(limits);
      const value: unknown = JSON.parse(wire);
      let count = 0;
      const visit = (child: unknown) => {
        count++;
        if (child !== null && typeof child === 'object') {
          for (const item of Object.values(child)) visit(item);
        }
      };
      visit(value);
      if (count > limits.maxNodes) throw new Error('NodeLimit');
      return {name, identityField: 'id', identity: cid, wire};
    },
  };
  const unexpected = () => assert.fail('Admission must not use a persistence port');
  const {admitContract: invoke} = createPublicationContractStore(
    {maxObjectBytes: bytes, maxObjects: 1, capacityBytes: bytes},
    control, {maxWireBytes: bytes, maxNodes: nodes, maxDepth: 64}, new Set(), {
      active: unexpected,
      currentDeliveryIndex: unexpected,
      nativePublicationContract: unexpected,
      contractPath: unexpected,
      readSemanticOriginal: unexpected,
      exactUtf8WireMatches: unexpected,
      reserveObjectCapacity: unexpected,
      accountNativePublication: unexpected,
      putSemantic: unexpected,
      putSemanticBatch: unexpected,
    },
  );
  return {invoke, observed};
}

test('wire-derived support crosses former10000 without replacing explicit narrower policy', () => {
  const wire = JSON.stringify({id: cid, values: Array(10001).fill(1)});
  const old = admission(10000);
  assert.throws(() => old.invoke('captured_run', wire), /InvalidPublicationContract/);
  const derived = admission(200000);
  assert.equal(derived.invoke('captured_run', wire).wire, wire);
  assert.equal(derived.observed[0].maxNodes, Buffer.byteLength(wire));
  const narrow = admission(100);
  assert.throws(() => narrow.invoke('captured_run', wire), /InvalidPublicationContract/);
  assert.equal(narrow.observed[0].maxNodes, 100);
});

test('object-byte refusal precedes control; malformed wire cannot be admitted', () => {
  const narrow = admission(200000, 4);
  assert.throws(() => narrow.invoke('captured_run', '[1,2]'), /InvalidPublicationContractWire/);
  assert.equal(narrow.observed.length, 0);
  const malformed = admission(200000);
  assert.throws(() => malformed.invoke('captured_run', '{"broken":'), /InvalidPublicationContract/);
});

test('multibyte bound uses UTF8 extent, does not change depth or explicit byte policy', () => {
  const a = admission(200000);
  const wire = JSON.stringify({id: cid, text: '数値'});
  a.invoke('captured_run', wire);
  assert.equal(a.observed[0].maxNodes, Buffer.byteLength(wire));
  assert.equal(a.observed[0].maxDepth, 64);
  assert.equal(a.observed[0].maxWireBytes, 200000);
});
