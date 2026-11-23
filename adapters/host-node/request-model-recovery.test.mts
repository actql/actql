import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { parse, type AnyNode, type Identifier, type Property } from 'acorn';
type WireAt = (index: number) => string;
type Definition = Readonly<{
    wire: string;
}>;
type Original = Readonly<{
    materialsWire: string;
    resultPolicyOriginal: Readonly<{
        wire: string;
    }>;
}>;
type Restored = Readonly<{
    prepared: object;
    compiled: object;
    graph: object;
    runDefinition: Definition;
}>;
type FixtureOptions = Readonly<{
    reserveFailure?: unknown;
    constructFailure?: unknown;
}>;
type ProviderBinding = (id: string, installation: string, contract: string, configuration: string) => object;
type State = {
    parent: object;
    context: {
        runtime?: {
            clientProgramModelProviderBinding: ProviderBinding;
        };
    };
    recovery?: {
        request: object;
        definition: Definition;
        assertCurrent(): void;
        restored?: Restored;
    };
    prepared?: object;
    modelProviderBinding?: object;
};
type Call = string | {
    reserve: readonly string[];
    containers: number;
} | {
    binding: readonly string[];
};
type RecoveryMethods = {
    restoreModelOriginal(request: object, original: Original, definition: Definition, identity: object, read: (parent: object, input: object) => Restored): Restored;
    prepareModelMaterials(prepared: object, request: object, count: number, wireAt: WireAt, containers: number): unknown;
    prepareModelBinding(prepared: object, request: object, ...args: Parameters<ProviderBinding>): object;
};
// Execute the actual recovery/material/binding methods with explicit Core
// ports. Real nominal reservation/current/cleanup controls live in the paired
// Core WB; these ports cannot grant Model IO or a saved Run.
const source = readFileSync(new URL('./ordinary-source-managed.mjs', import.meta.url), 'utf8');
const names = ['restoreModelOriginal', 'prepareModelMaterials', 'prepareModelBinding'];
const selected: Property[] = [];
function visit(value: AnyNode) {
    if (value === null || typeof value !== 'object')
        return;
    if (value.type === 'Property' && value.method && names.includes((value.key as Identifier).name))
        selected.push(value);
    for (const child of Object.values(value)) {
        if (Array.isArray(child))
            child.forEach(visit);
        else if (child && typeof child === 'object')
            visit(child);
    }
}
visit(parse(source, { ecmaVersion: 'latest', sourceType: 'module' }));
assert.equal(selected.length, names.length);
const helpers = source.slice(source.indexOf('  function constructRequestDomain('), source.indexOf('  function registerRequestRun('));
const methods = selected.map(node => source.slice(node.start, node.end)).join(',');
const fail = (code: string) => { throw Object.assign(new Error(code), { code }); };
function fixture({ reserveFailure, constructFailure }: FixtureOptions = {}) {
    const request = {}, identity = {}, definition = { wire: 'definition' }, parent = {}, receipt = {};
    const restored = { prepared: {}, compiled: {}, graph: {}, runDefinition: definition };
    const original = { materialsWire: 'saved', resultPolicyOriginal: { wire: 'policy' } };
    const calls: Call[] = [], binding = {}, bindings: object[] = [];
    let active = true;
    const state: State = { parent, context: {}, recovery: { request: identity, definition, assertCurrent() {
                calls.push('original current');
                if (!active)
                    fail('OriginalRecoveryRetired');
            } } };
    const producer: {
        receipt: object;
        request: object;
        preparation: State;
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
    const moon = state.context.runtime = {
        clientProgramModelProviderBinding(id: string, installation: string, contract: string, configuration: string) {
            const value = bindings.length === 0 ? binding : {};
            bindings.push(value);
            calls.push({ binding: [id, installation, contract, configuration] });
            return value;
        },
    };
    const api = Function('current', 'producerForRequest', 'fail', 'checked', 'runtimeCore', helpers + `return ({${methods}});`)(() => { }, (actual: unknown) => {
        assert.equal(actual, request);
        return producer;
    }, fail, (value: unknown) => value, (actual: unknown) => {
        assert.equal(actual, moon);
        return { publicationControl: control };
    }) as RecoveryMethods;
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
