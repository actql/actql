import test from 'node:test';
import assert from 'node:assert/strict';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';

function deferred() {
  let resolve;
  const promise = new Promise(done => {resolve = done;});
  return {promise, resolve};
}
function fixture() {
  const registry = createEmbeddedHostRegistry(() => true);
  const installation = {};
  const calls = [];
  const arrivals = [];
  const host = {
    port: {perform(operation, request) {
      assert.equal(operation, 'connect');
      const done = deferred();
      const item = {request, done};
      calls.push(item);
      arrivals.shift()?.(item);
      return done.promise;
    }},
    dispatchOwner: {async drain() {}},
    retireTerminalEffects() {},
    journal: {async close() {}},
    store: {async close() {}},
  };
  registry.registerPreparation(host, installation, host);
  return {registry, installation, host,
    next() {return new Promise(resolve => arrivals.push(resolve));},
    connect(first = true) {
      const result = registry.connect('alias-test', {}, async () => host,
        {mode: 'local', owner: 'local'}, first ? host : undefined);
      // The profile is deliberately invalid after the pending-operation checks.
      // This exercises real registry custody and its real failure cleanup.
      const rejected = assert.rejects(result, error => error.code === 'InvalidHostProfile');
      return rejected;
    },
    bind(parent, alias) {registry.bindSourceRequest(host, installation, host, parent, alias);},
    original(value) {return registry.originalSourceRequest(host, installation, host, value);},
  };
}

test('registry weak aliases preserve original identity through await and refuse stale generation', async () => {
  const f = fixture();
  const next = f.next();
  const finished = f.connect();
  const {request, done} = await next;
  const alias = {};
  f.bind(request, alias);
  assert.equal(f.original(request), request);
  assert.equal(f.original(alias), request);
  await Promise.resolve();
  assert.equal(f.original(alias), request);
  assert.throws(() => f.original({}), /InstalledHostPreparationChanged/);
  assert.throws(() => f.registry.originalSourceRequest(f.host, {}, f.host, alias), /InstalledHostPreparationChanged/);
  done.resolve({});
  await finished;
  assert.throws(() => f.original(alias), /InstalledHostPreparationChanged/);
  assert.throws(() => f.original(request), /InstalledHostPreparationChanged/);
});

test('registry weak aliases keep the sixteen unique alias guard and duplicate idempotence', async () => {
  const f = fixture();
  const next = f.next();
  const finished = f.connect();
  const {request, done} = await next;
  const aliases = Array.from({length: 16}, () => ({}));
  for (const alias of aliases) {
    f.bind(request, alias);
    f.bind(alias, alias);
    f.bind(alias, request);
  }
  for (const alias of aliases) assert.equal(f.original(alias), request);
  assert.throws(() => f.bind(request, {}), /SourceManagedPreparationUnavailable/);
  f.bind(request, aliases[0]);
  done.resolve({});
  await finished;
});

test('registry weak aliases cannot transfer identities between simultaneous original calls', async () => {
  const f = fixture();
  const firstArrival = f.next();
  const first = f.connect();
  const a = await firstArrival;
  const secondArrival = f.next();
  const second = f.connect(false);
  const b = await secondArrival;
  const alias = {};
  f.bind(a.request, alias);
  assert.throws(() => f.bind(b.request, alias), /InstalledHostPreparationChanged/);
  assert.throws(() => f.bind(b.request, a.request), /InstalledHostPreparationChanged/);
  assert.equal(f.original(alias), a.request);
  a.done.resolve({});
  b.done.resolve({});
  await Promise.all([first, second]);
});
