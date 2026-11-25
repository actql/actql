import assert from 'node:assert/strict';
import test from 'node:test';
import {createOrdinarySourceModelMaterials, type OrdinaryModelMaterialsState} from './ordinary-source-model-materials.mjs';
type WireAt = (index: number) => string;
type FixtureOptions = Readonly<{
    reserveFailure?: unknown;
    constructFailure?: unknown;
}>;
type Call = string | {
    reserve: readonly string[];
    containers: number;
} | {
    binding: readonly string[];
};
// The real installer methods with explicit Core ports. Physical reservation
// and Journal admission stay in their existing end-to-end controls.
const fail = (code: string) => { throw Object.assign(new Error(code), { code }); };
function fixture({ reserveFailure, constructFailure }: FixtureOptions = {}) {
    const request = {}, identity = {}, definition = { wire: 'definition' }, parent = {}, receipt = {};
    const restored = { prepared: {}, compiled: {}, graph: {}, runDefinition: definition };
    const original = { materialsWire: 'saved', resultPolicyOriginal: { wire: 'policy' } };
    const calls: Call[] = [], binding = {}, bindings: object[] = [];
    let active = true;
    const moon = {
        clientProgramModelProviderBinding(id: string, installation: string, contract: string, configuration: string) {
            const value = bindings.length === 0 ? binding : {};
            bindings.push(value);
            calls.push({ binding: [id, installation, contract, configuration] });
            return value;
        },
    };
    const state: OrdinaryModelMaterialsState = { parent, context: {runtime: moon}, recovery: { request: identity, definition, assertCurrent() {
                calls.push('original current');
                if (!active)
                    fail('OriginalRecoveryRetired');
            } } };
    const producer: {
        receipt: object;
        request: object;
        preparation: OrdinaryModelMaterialsState;
        finished?: boolean;
    } = { receipt, request, preparation: state };
    const control = {
        reserveCheckedClientRequestModelRecoveryMaterials(p: unknown, input: unknown, r: unknown, d: unknown, count: number, wireAt: WireAt, containers: number) {
            assert.equal(this, control);
            assert.deepEqual([p, input, r, d], [parent, receipt, identity, definition]);
            calls.push({ reserve: Array.from({ length: count }, (_, i) => wireAt(i)), containers });
            if (reserveFailure !== undefined)
                throw reserveFailure;
        },
    };
    const materials = createOrdinarySourceModelMaterials({
      current() {},
      producerForRequest(actual) {assert.equal(actual, request); return producer;},
      fail,
      checked(value) {return value;},
      checkedRequestProgramPreparation() {return assert.fail('Recovery uses retained Model originals');},
      runtimeCore(actual) {
        assert.equal(actual, moon);
        return {publicationControl: control};
      },
    });
    const api = {restoreModelOriginal: materials.restoreModelOriginal, ...materials.modelMaterials};
    let constructed = 0;
    const restore = () => api.restoreModelOriginal(request, original, definition, identity, (actualParent, actualInput) => {
        assert.strictEqual(actualParent, parent);
        assert.strictEqual(actualInput, receipt);
        constructed++;
        calls.push('original reader');
        if (constructFailure !== undefined)
            throw constructFailure;
        return restored;
    });
    return { api, restore, calls, state, producer, request, identity, definition, restored, binding, bindings,
        constructed: () => constructed, revoke: () => { active = false; } };
}
test('saved original and both material constructors reserve on one restoration parent without fresh compilation', () => {
    const f = fixture();
    assert.equal(f.restore(), f.restored);
    assert.equal(f.state.prepared, f.restored.prepared);
    f.api.prepareModelMaterials(f.restored.prepared, f.request, 2, i => ['prompt', 'retry'][i], 4);
    assert.equal(f.api.prepareModelBinding(f.restored.prepared, f.request, 'provider', 'installation', 'contract', 'configuration'), f.binding);
    assert.deepEqual(f.calls.filter(value => typeof value === 'object'), [
        { reserve: ['saved', 'policy', 'definition'], containers: 4 },
        { reserve: ['prompt', 'retry'], containers: 4 },
        { reserve: ['installation', 'contract', 'configuration'], containers: 3 },
        { binding: ['provider', 'installation', 'contract', 'configuration'] },
    ]);
    assert.equal(f.constructed(), 1);
    assert.throws(f.restore, { code: 'ForeignInstalledSourceProducer' });
    assert.throws(() => f.api.prepareModelMaterials({}, f.request, 0, () => '', 0), { code: 'ForeignInstalledSourceProducer' });
    assert.throws(() => f.api.prepareModelBinding({}, f.request, 'provider', 'installation', 'contract', 'configuration'), { code: 'ForeignInstalledSourceProducer' });
});
test('restored Model occurrences retain distinct bindings funded by the same original recovery', () => {
    const f = fixture();
    f.restore();
    const first = f.api.prepareModelBinding(f.restored.prepared, f.request, 'first', 'installation-1', 'contract-1', 'configuration-1');
    const second = f.api.prepareModelBinding(f.restored.prepared, f.request, 'second', 'installation-2', 'contract-2', 'configuration-2');
    assert.notEqual(first, second);
    assert.deepEqual(f.bindings, [first, second]);
    assert.deepEqual(f.calls.filter(value => typeof value === 'object'), [
        { reserve: ['saved', 'policy', 'definition'], containers: 4 },
        { reserve: ['installation-1', 'contract-1', 'configuration-1'], containers: 3 },
        { binding: ['first', 'installation-1', 'contract-1', 'configuration-1'] },
        { reserve: ['installation-2', 'contract-2', 'configuration-2'], containers: 3 },
        { binding: ['second', 'installation-2', 'contract-2', 'configuration-2'] },
    ]);
    assert.equal(f.state.prepared, f.restored.prepared);
    assert.equal(f.state.recovery!.restored, f.restored);
    assert.equal(f.constructed(), 1);
});
test('a later restored binding preserves current refusal and the already returned original', () => {
    const f = fixture();
    f.restore();
    const first = f.api.prepareModelBinding(f.restored.prepared, f.request, 'first', 'installation-1', 'contract-1', 'configuration-1');
    f.revoke();
    const next = () => f.api.prepareModelBinding(f.restored.prepared, f.request, 'second', 'installation-2', 'contract-2', 'configuration-2');
    assert.throws(next, { code: 'OriginalRecoveryRetired' });
    assert.throws(next, { code: 'OriginalRecoveryRetired' });
    assert.deepEqual(f.bindings, [first]);
    assert.equal(f.state.modelProviderBinding, first);
    assert.equal(f.state.recovery!.restored, f.restored);
});
test('original reservation and reader failures latch without a second constructor or substituted preparation', () => {
    for (const kind of ['reserveFailure', 'constructFailure']) {
        const primary = new Error('same original ' + kind), f = fixture({ [kind]: primary });
        assert.throws(f.restore, cause => cause === primary);
        assert.throws(f.restore, cause => cause === primary);
        assert.equal(f.constructed(), kind === 'reserveFailure' ? 0 : 1);
        assert.equal(f.state.prepared, undefined);
    }
});
test('restoration current refusal stops later binding without replacing the restored original', () => {
    const f = fixture();
    f.restore();
    f.revoke();
    assert.throws(() => f.api.prepareModelMaterials(f.restored.prepared, f.request, 1, () => 'prompt', 1), { code: 'OriginalRecoveryRetired' });
    assert.throws(() => f.api.prepareModelBinding(f.restored.prepared, f.request, 'provider', 'installation', 'contract', 'configuration'), { code: 'OriginalRecoveryRetired' });
    assert.equal(f.state.recovery!.restored, f.restored);
    assert.equal(f.calls.filter(value => (value as {
        binding?: readonly string[];
    })?.binding).length, 0);
});
test('the same current callback cannot revive a retired restoration or replace its alias', () => {
    for (const retire of [(f: ReturnType<typeof fixture>) => { f.producer.finished = true; }, (f: ReturnType<typeof fixture>) => { f.state.recovery = undefined; }]) {
        const f = fixture();
        f.restore();
        f.state.recovery!.assertCurrent = () => retire(f);
        assert.throws(() => f.api.prepareModelMaterials(f.restored.prepared, f.request, 1, () => 'prompt', 1), { code: 'ForeignInstalledSourceProducer' });
        assert.equal(f.constructed(), 1);
        assert.equal(f.calls.filter(value => (value as {
            binding?: readonly string[];
        })?.binding).length, 0);
    }
});
