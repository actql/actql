import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the actual Local wait and its private subscription statements with
// explicit observation/work ports. This is not a full Host or Common fixture.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declarations = new Map();
function visit(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'VariableDeclaration') {
    for (const declaration of node.declarations) {
      if (['waitWork', 'subscribeWaitWork', 'wait'].includes(declaration.id.name)) {
        assert(!declarations.has(declaration.id.name));
        declarations.set(declaration.id.name, source.slice(node.start, node.end));
      }
    }
  }
  for (const child of Object.values(node)) {
    if (Array.isArray(child)) child.forEach(visit);
    else if (child && typeof child === 'object') visit(child);
  }
}
visit(ast);
assert(declarations.has('wait'));
const compile = new Function('dispatchOwner', 'effectResumeFlights', 'modelResumeFlights',
  'observeRun', 'installedRunWaitDecision', 'moon', 'clientOperationError',
  'setTimeout', 'clearTimeout', [...declarations.values()].join('\n') +
  ';return {wait, work: typeof waitWork === "undefined" ? undefined : waitWork};');
const flush = async () => { for (let i = 0; i < 24; i++) await Promise.resolve(); };
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => {resolve = yes; reject = no;});
  let reactions = 0;
  const originalThen = promise.then;
  promise.then = function(...args) {reactions++; return Reflect.apply(originalThen, this, args);};
  return {promise, resolve, reject, reactions: () => reactions};
}
function fixture(observe, {original, kind = 'dispatch'} = {}) {
  const ref = {runDefinitionCid: 'original-run'}, timers = new Map();
  let reads = 0, work = original, nextTimer = 0;
  const effect = new Map(), model = new Map();
  const setWork = value => {
    work = kind === 'dispatch' ? value : undefined;
    const selected = kind === 'effect' ? effect : model;
    if (kind !== 'dispatch') {
      if (value === undefined) selected.delete(ref.runDefinitionCid);
      else selected.set(ref.runDefinitionCid, value);
    }
  };
  setWork(original);
  const held = compile({operation: actual => {assert.strictEqual(actual, ref); return work;}},
    effect, model,
    async facts => {
      assert.strictEqual(facts.ref, ref);
      assert.equal(facts.principalId, 'actor');
      return observe(++reads);
    }, (_moon, state) => state.decision, {},
    code => Object.assign(new Error(code), {code}),
    (callback, delay) => {assert.equal(delay, 100); const id = ++nextTimer; timers.set(id, callback); return id;},
    id => timers.delete(id));
  return {ref, ...held, reads: () => reads, timers, setWork,
    start: (signal, extra = {}) => held.wait({ref, principalId: 'actor',
      until: null, since: null, signal, ...extra}),
    tick() {const [id, callback] = timers.entries().next().value; timers.delete(id); callback();},
  };
}
const pending = {decision: 'pending'}, ready = {decision: 'ready', revision: 7};

for (const kind of ['dispatch', 'effect', 'model']) {
  test(`same original ${kind} settlement wakes Local wait without a fallback tick`, async () => {
    const original = deferred(), abort = new AbortController();
    const f = fixture(read => read === 1 ? pending : ready, {original: original.promise, kind});
    const flight = f.start(abort.signal);
    try {
      await flush(); assert.equal(f.reads(), 1); assert.equal(f.timers.size, 1);
      original.resolve(); await flush();
      assert.equal(f.reads(), 2, 'Completion must reobserve before the fallback timer fires');
      assert.strictEqual(await flight, ready);
      assert.equal(f.timers.size, 0);
      assert.equal(original.reactions(), 1);
    } finally {abort.abort(); await flight.catch(() => {});}
  });
}

test('settlement during the asynchronous pending observation is latched', async () => {
  const original = deferred(), abort = new AbortController();
  const f = fixture(async read => {
    if (read !== 1) return ready;
    original.resolve(); await Promise.resolve(); return pending;
  }, {original: original.promise});
  const flight = f.start(abort.signal);
  try {
    await flush(); assert.equal(f.reads(), 2);
    assert.strictEqual(await flight, ready); assert.equal(f.timers.size, 0);
  } finally {abort.abort(); await flight.catch(() => {});}
});

test('work installed during observation is captured before sleeping', async () => {
  const original = deferred(), abort = new AbortController();
  const f = fixture(read => {
    if (read !== 1) return ready;
    f.setWork(original.promise); return pending;
  });
  const flight = f.start(abort.signal);
  try {
    await flush(); original.resolve(); await flush();
    assert.equal(f.reads(), 2); assert.strictEqual(await flight, ready);
  } finally {abort.abort(); await flight.catch(() => {});}
});

test('rejected physical work only wakes the original state owner, never rejects or fabricates its result', async () => {
  const original = deferred(), unknown = {...ready, status: 'needs_reconciliation'};
  const abort = new AbortController();
  const f = fixture(read => read === 1 ? pending : unknown, {original: original.promise});
  const flight = f.start(abort.signal);
  try {
    await flush(); original.reject(new Error('OriginalPhysicalUnknown')); await flush();
    assert.equal(f.reads(), 2); assert.strictEqual(await flight, unknown);
  } finally {abort.abort(); await flight.catch(() => {});}
});

test('a completion notification cannot bypass a newly observed current Deny', async () => {
  const original = deferred(), denied = Object.assign(new Error('RunStateAccessDenied'), {code: 'RunStateAccessDenied'});
  const f = fixture(read => {if (read === 1) return pending; throw denied;}, {original: original.promise});
  const flight = f.start();
  const rejection = assert.rejects(flight, error => error === denied);
  await flush(); original.resolve(); await rejection;
  assert.equal(f.reads(), 2); assert.equal(f.timers.size, 0);
});

test('unchanged pending work shares one settlement reaction across polling and concurrent waiters', async () => {
  const original = deferred(), a = new AbortController(), b = new AbortController();
  const f = fixture(() => pending, {original: original.promise});
  const first = f.start(a.signal), second = f.start(b.signal);
  const stopped = [assert.rejects(first, {code: 'WaitAborted'}), assert.rejects(second, {code: 'WaitAborted'})];
  await flush(); assert.equal(f.reads(), 2); assert.equal(f.timers.size, 2);
  f.tick(); await flush(); f.tick(); await flush();
  assert.equal(f.reads(), 4); assert.equal(original.reactions(), 1);
  assert.equal(f.work.get(original.promise).listeners.size, 2);
  a.abort(); b.abort(); await Promise.all(stopped);
  assert.equal(f.timers.size, 0); assert.equal(f.work.get(original.promise).listeners.size, 0);
  assert.equal(f.work.get(original.promise).pending, true, 'Aborting a waiter does not ACK or retire physical work');
  original.resolve(); await flush(); assert.equal(f.reads(), 4);
});

test('a retained settled operation does not spin while since still requires a later revision', async () => {
  const original = deferred(), abort = new AbortController();
  const f = fixture(() => pending, {original: original.promise});
  const flight = f.start(abort.signal, {since: 7});
  const stopped = assert.rejects(flight, {code: 'WaitAborted'});
  await flush(); original.resolve(); await flush();
  assert.equal(f.reads(), 2); assert.equal(f.timers.size, 1);
  await flush(); assert.equal(f.reads(), 2);
  f.tick(); await flush(); assert.equal(f.reads(), 3);
  assert.equal(original.reactions(), 1);
  abort.abort(); await stopped; assert.equal(f.timers.size, 0);
});

test('other-process changes remain observable through the unchanged fallback', async () => {
  let external = false;
  const f = fixture(() => external ? ready : pending);
  const flight = f.start();
  await flush(); assert.equal(f.reads(), 1); assert.equal(f.timers.size, 1);
  external = true; f.tick();
  assert.strictEqual(await flight, ready);
  assert.equal(f.reads(), 2); assert.equal(f.timers.size, 0);
});

test('deadline removes subscriptions without stopping an unfinished state read or physical work', async () => {
  const original = deferred(), observation = deferred(), abort = new AbortController();
  const f = fixture(() => observation.promise, {original: original.promise});
  const flight = f.start(abort.signal);
  const stopped = assert.rejects(flight, {code: 'WaitTimeout'});
  await flush(); abort.abort(new DOMException('Timed out', 'TimeoutError')); await stopped;
  assert.equal(f.timers.size, 0); assert.equal(f.work.get(original.promise).listeners.size, 0);
  assert.equal(f.work.get(original.promise).pending, true);
  observation.resolve(ready); original.resolve(); await flush(); assert.equal(f.reads(), 1);
});
