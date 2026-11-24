import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parse, type AnyNode, type FunctionExpression, type Identifier } from 'acorn';
type Method = Omit<FunctionExpression, 'params'> & {
    params: Identifier[];
};
type FixtureResult = Readonly<{
    $tag: number;
    _0: unknown;
}>;
type SnapshotPorts = Partial<Readonly<{
    strategyHostOutputSnapshotBegin(...args: unknown[]): unknown;
    strategyHostOutputSnapshotAdvance(value: unknown, quantum: number): unknown;
    strategyHostOutputSnapshotFinish(value: unknown): unknown;
    strategyHostOutputSnapshotCancel(value: unknown): void;
}>>;
type Snapshot = (handle: object, limits: unknown, signal?: AbortSignal) => Promise<unknown>;
const root = process.env.SNAPSHOT_RELAY_SOURCE_ROOT;
function source(name: string) { return readFileSync(root ? `${root}/adapters/host-common/${name}` : new URL(`../host-common/${name}`, import.meta.url), 'utf8'); }
function find(source: string, predicate: (node: AnyNode) => boolean): AnyNode { const ast = parse(source, { ecmaVersion: 'latest', sourceType: 'module' }); let found!: AnyNode; function walk(n: AnyNode) { if (!n || typeof n !== 'object')
    return; if (predicate(n))
    found = n; for (const x of Object.values(n)) {
    if (Array.isArray(x))
        x.forEach(walk);
    else if (x && typeof x === 'object')
        walk(x);
} } walk(ast); assert(found); return found; }
const checked = (value: FixtureResult) => { if (value.$tag === 0)
    throw value._0; return value._0; };
const ok = (value: unknown) => ({ $tag: 1, _0: value });
function snapshot(moon: SnapshotPorts): Snapshot {
    const text = source('runtime-captured-publication-control.mjs');
    const node = find(text, n => n.type === 'Property' && (n.key as Identifier)?.name === 'admitCompletedResultSnapshot') as AnyNode & {
        value: Method;
    };
    const args = node.value.params.map(parameter => parameter.name).join(',');
    const body = text.slice(node.value.body.start, node.value.body.end);
    return new Function('moon', 'checked', 'inspectSnapshot', `return async function(${args})${body}`)(moon, checked, (x: unknown) => x) as Snapshot;
}
const policy = () => ({ maxWireBytes: 101, maxWireNodes: 103, maxWireDepth: 107, maxNodes: 109, maxDepth: 113, maxLogicalWireBytes: 2000003, maxLogicalWireNodes: 300007, maxLogicalWireDepth: 73 });
test('snapshot writer uses distinct original logical byte/node/depth fields, not payload or contract bounds', async () => {
    const handle = {}, prep = {}, result = {}, calls: unknown[][] = [];
    const run = snapshot({ strategyHostOutputSnapshotBegin(...args) { calls.push(args); return ok(prep); }, strategyHostOutputSnapshotAdvance(value, q) { assert.equal(value, prep); assert.equal(q, 256); return ok(true); }, strategyHostOutputSnapshotFinish(value) { assert.equal(value, prep); return ok(result); }, strategyHostOutputSnapshotCancel() { assert.fail('unexpected cancel'); } });
    assert.equal(await run(handle, policy()), result);
    assert.deepEqual(calls, [[handle, 2000003, 300007, 73]]);
});
test('snapshot policy rejects missing, negative and unrepresentable dimensions before Core', async () => {
    const run = snapshot({ strategyHostOutputSnapshotBegin() { assert.fail('invalid policy reached Core'); } });
    for (const bad of [null, {}, { maxLogicalWireBytes: 1, maxLogicalWireNodes: -1, maxLogicalWireDepth: 1 }, { maxLogicalWireBytes: 2147483648, maxLogicalWireNodes: 1, maxLogicalWireDepth: 1 }])
        await assert.rejects(run({}, bad), TypeError);
});
test('snapshot encoding refusal retains the existing exact cancellation path', async () => {
    const prep = {}, issue = new Error('original encoding refusal');
    let cancels = 0;
    const run = snapshot({ strategyHostOutputSnapshotBegin() { return ok(prep); }, strategyHostOutputSnapshotAdvance() { return { $tag: 0, _0: issue }; }, strategyHostOutputSnapshotCancel(value) { assert.equal(value, prep); cancels++; } });
    await assert.rejects(run({}, policy()), error => error === issue);
    assert.equal(cancels, 1);
});
test('snapshot abort before begin does not manufacture a preparation or cleanup acknowledgement', async () => {
    let starts = 0;
    const run = snapshot({ strategyHostOutputSnapshotBegin() { starts++; } }), controller = new AbortController();
    controller.abort();
    await assert.rejects(run({}, policy(), controller.signal));
    assert.equal(starts, 0);
});
test('durable publication relays exact original output policy while metadata keeps its distinct contract policy', async () => {
    const text = source('durable-result-payload.mjs'), node = find(text, n => n.type === 'FunctionDeclaration' && n.id?.name === 'storeCompletedResultPublicationPayload');
    const handle = {}, output = policy(), contracts = { maxWireBytes: 11, maxNodes: 13, maxDepth: 17 }, seen: string[] = [];
    const control = { issueResultEvidence(h: unknown, context: unknown, limits: unknown) { assert.equal(h, handle); assert.equal(limits, contracts); seen.push('evidence'); return {}; } };
    const publication = { runDefinition: { identity: 'sha256:' + 'a'.repeat(64) }, limits: contracts, control: { issueResultArtifact(h: unknown, invocation: unknown, retention: unknown, limits: unknown) { assert.equal(h, handle); assert.equal(limits, contracts); seen.push('artifact'); return {}; }, issueDurableResultBinding() { }, async admitCompletedResultSnapshot(h: unknown, limits: unknown) { assert.equal(h, handle); assert.equal(limits, output); seen.push('snapshot'); return {}; } } };
    const store = { createPreparedObjectWriter() { }, putPreparedResultSchema() { } };
    const fn = new Function('validStore', 'validResultControl', 'fail', 'storeCompletedPayload', `return ${text.slice(node.start, node.end)}`)(() => true, () => true, (code: string) => { throw Error(code); }, async (...args: [
        unknown,
        unknown,
        unknown,
        unknown,
        unknown,
        (handle: object) => unknown
    ]) => { assert.equal(args[3], output); return args[5](handle); });
    await fn(store, control, {}, 0, output, publication);
    assert.deepEqual(seen, ['evidence', 'artifact', 'snapshot']);
});
