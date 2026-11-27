import assert from 'node:assert/strict';
import {maxRecordUpdateFixtureTextUnits, recordUpdateFixtureSeed} from './cases.mjs';
import type {RecordMutationFixtureSeed} from './cases.mjs';
import type {Exchange} from '../../../adapters/site-node/https-exchange-fixture.mjs';
import type {recordApprovalOrderedMockProject} from './mock-project.mjs';
type FailureView = {name?: unknown; code?: unknown; message?: unknown} | undefined;

// Three finite fixture phases share one request history. The limit also bounds
// failed route observations and leaves room for a single overflow witness.
const maxRouteAttempts = 64;

type Operation = 'create' | 'update' | 'delete';
type ExpectedWrite = Readonly<{key: string; operation: Operation}>;
type Target<Row> = readonly [key: string, row: Row | null];
type CasePlan = Pick<ReturnType<typeof recordApprovalOrderedMockProject>, 'resources' | 'writes'>;

export function createRecordApprovalProviderState<Row extends object>(
  seed: Readonly<{targets: readonly Target<Row>[]; control: Row; keyOf(row: Readonly<Row>): string;
    writes: readonly ExpectedWrite[]}>,
  {includeMethodOverride = false}: {includeMethodOverride?: boolean} = {},
) {
  assert(seed.targets.length > 0 && seed.targets.length <= maxRouteAttempts && seed.writes.length <= maxRouteAttempts,
    'InvalidRecordApprovalFixtureLimit');
  const {keyOf} = seed;
  const boundedKey = (key: string) => typeof key === 'string' &&
    key.length > 0 && key.length <= maxRecordUpdateFixtureTextUnits;
  const retain = (row: Row) => Object.freeze(structuredClone(row));
  const control = retain(seed.control);
  const controlKey = keyOf(control);
  assert(boundedKey(controlKey), 'InvalidRecordApprovalFixtureControl');
  const originals = new Map<string, Readonly<Row> | null>();
  for (const [key, row] of seed.targets) {
    assert(boundedKey(key) && key !== controlKey && !originals.has(key), 'InvalidRecordApprovalFixtureTarget');
    const selected = row === null ? null : retain(row);
    assert(selected === null || keyOf(selected) === key, 'ForeignRecordApprovalFixtureRow');
    originals.set(key, selected);
  }
  const plan = seed.writes.map(write => {
    assert(originals.has(write.key) && ['create', 'update', 'delete'].includes(write.operation),
      'InvalidRecordApprovalFixtureOperation');
    return {...write};
  });
  let targets = new Map(originals), writes = 0, attempts = 0;
  let requests: {method: string; pathname: string; methodOverride?: Exchange['headers'][string] | null}[],
    failures: {name: unknown; code: unknown; message: unknown}[];
  function reset() {
    targets = new Map(originals);
    writes = 0;
    requests = [];
    failures = [];
    attempts = 0;
  }
  reset();

  function target(key: string) {
    assert(targets.has(key), 'UnknownRecordApprovalFixtureTarget');
    return targets.get(key)!;
  }

  function apply(operation: Operation, key: string, row: Row | null) {
    const next = plan[writes];
    assert(next?.key === key && next.operation === operation, 'UnexpectedRecordApprovalFixtureWrite');
    const current = target(key);
    assert(operation === 'create' ? current === null : current !== null,
      'InvalidRecordApprovalFixturePredecessor');
    assert(operation === 'delete' ? row === null : row !== null, 'InvalidRecordApprovalFixtureSuccessor');
    const selected = row === null ? null : retain(row);
    assert(selected === null || keyOf(selected) === key, 'ForeignRecordApprovalFixtureRow');
    targets.set(key, selected);
    writes++;
    return selected;
  }

  function route(method: string, pathname: string, action: (exchange: Exchange) => unknown) {
    return {method, pathname, handle(exchange: Exchange) {
      if (attempts >= maxRouteAttempts) {
        const error = new Error('RecordApprovalFixtureRequestLimit');
        if (attempts === maxRouteAttempts) {
          attempts++;
          failures.push({name: error.name, code: (error as NodeJS.ErrnoException).code, message: error.message});
        }
        throw error;
      }
      attempts++;
      try {
        assert.equal(exchange.method, method);
        assert.equal(exchange.pathname, pathname);
        assert.equal(exchange.authorized, true, 'The original credential header must be present');
        requests.push({method, pathname, ...(includeMethodOverride
          ? {methodOverride: exchange.headers['x-http-method-override'] ?? null} : {})});
        return {body: action(exchange)};
      } catch (error) {
        const message = typeof (error as FailureView)?.message === 'string'
          ? ((error as FailureView)!.message as string).slice(0, 512) : undefined;
        failures.push({name: (error as FailureView)?.name, code: (error as FailureView)?.code, message});
        throw error;
      }
    }};
  }

  return Object.freeze({target, control, route, apply, reset,
    snapshot: () => structuredClone({writes, targets: [...targets], control, requests, failures})});
}

export function createRecordUpdateProviderState<Fields extends Record<string, unknown>>(
  selection: RecordMutationFixtureSeed, initialFields: Fields, options: Readonly<{
    operation: Operation; allowCreate?: boolean;
    additionalTargets?: readonly Readonly<{id: string; name: string}>[];
    writes?: readonly ExpectedWrite[];
  }>,
) {
  const {allowCreate = false, additionalTargets = [], writes} = options;
  const seed = recordUpdateFixtureSeed(selection, {allowAbsent: allowCreate});
  assert(additionalTargets.length < maxRouteAttempts, 'InvalidRecordApprovalFixtureLimit');
  const targetId = selection.recordId;
  type Row = Partial<Fields> & {id: string; name: string};
  const targets: Target<Row>[] = [[targetId, seed.target === null ? null : {...initialFields, ...seed.target}]];
  for (const row of additionalTargets) {
    assert([row.id, row.name].every(value => typeof value === 'string' && value.length > 0 &&
      value.length <= maxRecordUpdateFixtureTextUnits), 'InvalidRecordApprovalFixtureTarget');
    targets.push([row.id, {...initialFields, ...row}]);
  }
  const state = createRecordApprovalProviderState<Row>({
    targets,
    control: {...initialFields, ...seed.control}, keyOf: row => row.id,
    writes: writes ?? [{key: targetId, operation: options.operation}],
  }, {includeMethodOverride: allowCreate});
  function replace(operation: 'create' | 'update', key: string, name: string, fields: Partial<Fields>) {
    assert(typeof name === 'string' && name.length <= maxRecordUpdateFixtureTextUnits, 'InvalidRecordApprovalFixtureValue');
    return state.apply(operation, key, {...state.target(key), ...fields, id: key, name})!;
  }
  return Object.freeze({get target() {return state.target(targetId);}, control: state.control,
    route: state.route, reset: state.reset, readTarget: state.target,
    targets: () => targets.flatMap(([key]) => {
      const row = state.target(key); return row === null ? [] : [row];
    }),
    updateTarget: (name: string, fields: Partial<Fields>, key = targetId) => replace('update', key, name, fields),
    createTarget: (name: string, fields: Partial<Fields>) => replace('create', targetId, name, fields),
    deleteTarget: () => {state.apply('delete', targetId, null);},
    snapshot() {
      const {targets, ...view} = state.snapshot();
      return {...view, target: targets[0][1]};
    },
  });
}

// Both transports use the same authored case. The HTTPS endpoint still owns
// its wire codec and can apply only the next original checked row.
export function createOrderedRecordApprovalProviderState(plan: CasePlan) {
  const {resources, writes} = structuredClone({resources: plan.resources, writes: plan.writes});
  const byResource = new Map(resources.map(resource => [resource.resource, resource]));
  const identity = (resource: string, key: string) => JSON.stringify([resource, key]);
  type Row = Record<string, unknown>;
  type BoundRow = {resource: string; row: Row};
  const keyOf = ({resource, row}: BoundRow) => {
    const binding = byResource.get(resource);
    assert(binding, 'Foreign Record fixture resource');
    return identity(resource, JSON.stringify(binding.keyFields.map(field => row[field])));
  };
  const original = new Map<string, BoundRow | null>();
  for (const resource of resources) {
    for (const row of resource.before) {
      const bound = {resource: resource.resource, row};
      original.set(keyOf(bound), bound);
    }
  }
  const controlKey = identity(resources[0].resource, resources[0].controlKeys[0]);
  const control = original.get(controlKey);
  assert(control, 'Expected the independent provider control');
  original.delete(controlKey);
  const expected = writes.map(write => ({...write, heldKey: identity(write.resource, write.key)}));
  for (const write of expected) {
    if (!original.has(write.heldKey) && write.operation === 'create') original.set(write.heldKey, null);
  }
  const state = createRecordApprovalProviderState<BoundRow>({
    targets: [...original], control, keyOf,
    writes: expected.map(write => ({key: write.heldKey, operation: write.operation})),
  });
  function apply(resource: string, key: readonly unknown[], operation: Operation, after: Row | null) {
    const {writes: offset} = state.snapshot();
    const selected = expected[offset];
    const heldKey = identity(resource, JSON.stringify(key));
    assert(selected?.heldKey === heldKey && selected.operation === operation,
      'Unexpected original ordered HTTPS write');
    assert.deepEqual(state.target(heldKey)?.row ?? null, selected.before);
    assert.deepEqual(after, selected.after, 'Expected the independent HTTPS successor');
    return state.apply(operation, heldKey, after === null ? null : {resource, row: after})?.row ?? null;
  }
  function snapshot() {
    const observed = state.snapshot();
    const retained = new Map(observed.targets);
    retained.set(controlKey, observed.control);
    const rows = resources.map(resource => {
      const keys = new Set(resource.before.map(row => keyOf({resource: resource.resource, row})));
      for (const write of expected.slice(0, observed.writes)) {
        if (write.resource !== resource.resource) continue;
        if (write.operation === 'create') keys.add(write.heldKey);
        else if (write.operation === 'delete') keys.delete(write.heldKey);
      }
      return {resource: resource.resource, rows: [...keys].map(key => {
        const value = retained.get(key);
        assert(value, 'Expected the original provider row');
        return value.row;
      })};
    });
    return {rows, writes: observed.writes, requests: observed.requests, failures: observed.failures};
  }
  return Object.freeze({route: state.route, apply, snapshot});
}
