import test from 'node:test';
import assert from 'node:assert/strict';
import {installSelectedContributions, snapshotConfigurations} from './installation.mjs';
import {prepareDuckDBStrategyConfiguration, preparedStrategyConfiguration} from
  '../connectors/duckdb/node/configuration.mjs';

test('selected loading snapshots keys, loader functions and opaque settings before awaiting', async () => {
  const keys = ['a','b'], a = Object.freeze({}), b = Object.freeze({});
  const options = {a,b}, calls = [];
  let resume;
  const wait = new Promise(resolve => { resume = resolve; });
  const factory = key => (_, __, ___, configuration) => {
    calls.push(key); return configuration;
  };
  const loaders = new Map([
    ['a', async () => { await wait; return factory('a'); }],
    ['b', async () => factory('b')],
    ['unused', () => assert.fail('unselected import')],
  ]);
  const pending = installSelectedContributions(loaders,{strategyHostModules: () => keys},{},x=>x,options);
  keys.reverse(); options.a = {}; delete options.b; loaders.set('b', () => assert.fail('replaced loader'));
  resume();
  assert.deepEqual(await pending,[a,b]);
  assert.deepEqual(calls,['a','b']);
});

test('loading cancellation observes the started load but never starts another load or factory', async () => {
  let resume, settled = false, loads = 0, factories = 0, returned = false;
  const wait = new Promise(resolve => { resume = resolve; });
  const controller = new AbortController(), reason = new Error('cancel');
  const loaders = new Map(['a','b'].map(key => [key, async () => {
    loads++; await wait; settled = true; return () => { factories++; };
  }]));
  const pending = installSelectedContributions(loaders,{strategyHostModules: () => ['a','b']},{},x=>x,{},controller.signal);
  pending.then(() => { returned = true; },() => { returned = true; });
  controller.abort(reason);
  await Promise.resolve();
  assert.equal(returned,false); assert.equal(settled,false);
  resume();
  await assert.rejects(pending, error => error === reason);
  assert.equal(settled,true); assert.equal(loads,1); assert.equal(factories,0);
});

test('invalid selection and failed loading cannot partially install or fall back', async () => {
  for (const keys of [['a','missing'],['a','a'],['a','b']]) {
    let loads = 0, factories = 0;
    const loaders = new Map([
      ['a', async () => { loads++; return () => { factories++; }; }],
      ['b', async () => { loads++; throw new Error('failed load'); }],
    ]);
    await assert.rejects(installSelectedContributions(loaders,{strategyHostModules: () => keys},{},x=>x));
    assert.equal(loads,keys[1] === 'b' ? 2 : 0); assert.equal(factories,0);
  }
});

test('outer snapshot preserves handles without inspecting or freezing unused configurations', () => {
  const unused = new Proxy({}, {get() { assert.fail('provider settings inspected'); }});
  const options = {unused};
  const snapshot = snapshotConfigurations(options);
  assert.equal(snapshot.unused,unused);
  assert.equal(Object.isFrozen(options),false);
  assert.equal(Object.isFrozen(unused),false);
  assert.throws(() => snapshotConfigurations({get unsafe() { assert.fail('getter called'); }}), TypeError);
});

test('prepared DuckDB configuration is pure, immutable and not reconstructible from copied data', () => {
  const transportLimits = {maxRows:100,maxCells:1000,maxTransportBytes:100000,
    maxSqlBytes:10000,maxParameters:10,maxColumns:10,memoryBytes:134217728,threads:1};
  const importLimits = {maxRows:100,maxCells:1000};
  const handle = prepareDuckDBStrategyConfiguration({transportLimits,importLimits});
  transportLimits.threads = 0; importLimits.maxRows = 0;
  assert.equal(preparedStrategyConfiguration(handle).transportLimits.threads,1);
  assert.equal(preparedStrategyConfiguration(handle).importLimits.maxRows,100);
  assert.equal(Object.isFrozen(transportLimits),false);
  for (const fake of [{...handle},JSON.parse(JSON.stringify(handle)),undefined]) {
    assert.throws(() => preparedStrategyConfiguration(fake), {code:'UnpreparedStrategyConfiguration'});
  }
  assert.throws(() => prepareDuckDBStrategyConfiguration({transportLimits,importLimits}),{code:'InvalidLimits'});
});
