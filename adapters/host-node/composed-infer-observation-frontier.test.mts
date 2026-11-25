import assert from 'node:assert/strict';
import test from 'node:test';
import {registerHooks} from 'node:module';
import type {runInstalledComposedInfers} from './installed-composed-infer-run.mjs';

type ObservationRun = typeof runInstalledComposedInfers;
type Owner = Parameters<Parameters<ObservationRun>[0]['retainExecution']>[0];
type OriginalOperation = Readonly<{component: number}>;
type ComponentContext = Readonly<{
  retainOperation(operation: OriginalOperation): void;
  retainCompleted(): boolean;
}>;
type Issuance = Readonly<{operations: readonly OriginalOperation[]; maxSlots: number;
  maxWireBytes: number; maxWork: number; ledger?: unknown}>;
type Settings = Readonly<{
  counts?: readonly (number | undefined)[]; missingOriginal?: boolean;
  startIssue?: Error; advanceIssue?: object; neverComplete?: boolean;
  setupIssue?: Error;
  scope?: Readonly<{retire(): boolean; held(): bigint}>;
  closeCapture?(): boolean;
}>;
type RunCompletion = (callbacks: readonly (() => boolean)[]) => void;

let fixtureSequence = 0;

// The real Run binds each component and retains the original cleanup owner.
// Only the physical driver and issuer are substituted here. The installed
// capture receipt verifier is the production export and sees no funded receipt.
function fixture(settings: Settings = {}) {
  const counts = settings.counts ?? [2];
  const events: string[] = [];
  const issuer = Object.freeze({});
  const setup = Object.freeze({});
  const controller = new AbortController();
  const contexts: ComponentContext[] = [];
  const operations = counts.map((_, component) => Object.freeze({component,
    physicalStopped: () => true, releaseOriginalPublicationCapacity: () => true}));
  const selections = operations.map(operation => Object.freeze({
    graph: operation, occurrence: operation, localMock: false}));
  const originals = selections.map(selection => ({
    selection, component: {provider: selection,
      bindOriginal(context: ComponentContext) {contexts.push(context);}},
  }));
  const original = {components: originals, retain() {},
    openCapturedHost() {return setup;}, retire() {
      if (settings.scope === undefined) return true;
      events.push('retire-scope');
      return settings.scope.retire();
    }};
  const multiple = counts.length > 1;
  const tag = (event: string, component: number) => multiple ? event + component : event;
  let current = true, advances = 0;
  let owner: Owner | undefined;
  const cleanupIssuances: unknown[] = [];

  const moon = {
    clientProgramResultCount: () => 0,
    clientProgramInferPlanBoundary: (graph: OriginalOperation) => [graph.component],
    clientProgramOpenCapturedComposedInferHost: () => setup,
    strategyHostRun: () => setup,
    strategyHostStop(actual: unknown) {
      assert.strictEqual(actual, setup);
      if (settings.scope !== undefined) events.push('stop-setup');
    },
    strategyHostCloseOutputs(actual: unknown) {
      assert.strictEqual(actual, setup);
      if (settings.scope !== undefined) events.push('close-outputs');
    },
    strategyHostUsage(actual: unknown) {
      assert.strictEqual(actual, setup);
      if (settings.scope !== undefined) events.push('usage');
      return [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, settings.scope?.held() ?? 0n, 0n, 0n, 0n];
    },
    clientProgramAdvanceInferObservationIssuance(actual: unknown, quantum: number) {
      assert.strictEqual(actual, issuer);
      assert.equal(quantum, 1);
      assert.equal(current, true, 'observation advances before the dependent output handoff');
      if (!multiple) events.push('advance');
      advances++;
      if (settings.advanceIssue !== undefined) return {$tag: 0, _0: settings.advanceIssue};
      return {$tag: 1, _0: {_0: !settings.neverComplete &&
        advances === counts.reduce<number>((sum, count) => sum + (count ?? 0), 2)}};
    },
    clientProgramCancelInferObservationIssuance(actual: unknown) {
      assert.strictEqual(actual, issuer);
      return false;
    },
    clientProgramCleanupInferObservationIssuance(actual: unknown) {
      assert.strictEqual(actual, issuer);
      cleanupIssuances.push(actual);
      return {$tag: 1, _0: true};
    },
  };
  const capture = {capture: {source: () => setup, retainTask() {}}};
  const captures = operations.map(() => capture);
  const source = captures.map(captured => ({captured}));
  const args = {
    moon, plan: {runDefinition: {wire: '{"run_id":"original-run"}'}},
    control: {admitComposedInferSources() {return source;}},
    selected: {components: selections}, acquiredInfer: {
      captured: captures[0] ?? capture, ...(multiple ? {sources: source, sourceEvidence: []} : {}),
    },
    modelController: {discover: () => []}, computeConfigurations: {},
    signal: controller.signal, retainExecution(originalOwner: Owner) {owner = originalOwner;},
    beginPhysicalWork() {assert(owner, 'driver starts with retained custody');},
    originalPreparation: settings.missingOriginal ? undefined : original,
  };

  async function run(complete: RunCompletion) {
    const key = Symbol.for('actql.test.composed-issuance.' + ++fixtureSequence);
    const ports = {
      component(context: ComponentContext) {contexts.push(context); return {provider: setup};},
      capture({operation}: {operation: OriginalOperation}) {
        const {component} = operation;
        return {
          retainCompleted(funding: OriginalOperation) {
            assert.strictEqual(funding, operations[0], 'every capture borrows the first original owner');
            events.push(tag('retain', component)); return true;
          },
          completedCallCount() {events.push(tag('count', component)); return counts[component];},
          custody: {
            close() {return settings.closeCapture?.() ?? true;},
            cleanup() {return settings.closeCapture?.() ?? true;},
            cleanupPending() {return false;},
            retirePublication() {return true;},
          },
        };
      },
      start(input: Issuance) {
        assert.equal(current, true);
        assert.deepEqual(input.operations, operations);
        assert.equal(input.ledger, undefined);
        const count = counts.reduce<number>((sum, value) => sum + (value ?? 0), 0);
        assert.deepEqual([input.maxSlots, input.maxWireBytes, input.maxWork], [count, 16384, count + 2]);
        if (!multiple) events.push('start');
        if (settings.startIssue !== undefined) throw settings.startIssue;
        return issuer;
      },
      drive(actual: unknown) {
        assert.strictEqual(actual, setup);
        assert.equal(contexts.length, operations.length);
        contexts.forEach((context, index) => context.retainOperation(operations[index]));
        if (settings.setupIssue !== undefined) throw settings.setupIssue;
        complete(contexts.map(context => () => context.retainCompleted()));
        return {status: 'host-tasks-waiting', checkpoint: setup,
          close() {}, cleanup() {return true;}, cleanupPending() {return false;}};
      },
    };
    const globals = globalThis as typeof globalThis & Record<symbol, typeof ports>;
    globals[key] = ports;
    const url = new URL('./installed-composed-infer-run.mjs?frontier=' + fixtureSequence, import.meta.url).href;
    const originalInfer = new URL('./infer-operation.mjs', import.meta.url).href;
    const sources = new Map([
      ['./entry.mjs', 'export const runCapturedInternalStrategy = ports.drive;'],
      ['./infer-capture-custody.mjs', 'export const openNodeInferCaptureCustody = ports.capture;'],
      ['./infer-operation.mjs', `
        export {fundedInferCaptureInventoryCount, originalInferEvidenceCopyFunding} from ${JSON.stringify(originalInfer)};
        export const openNodeComposedInferProvider = ports.component;
        export const startCompleteInferObservation = ports.start;
      `],
    ]);
    const hooks = registerHooks({resolve(specifier, context, next) {
      const body = context.parentURL === url ? sources.get(specifier) : undefined;
      if (body === undefined) return next(specifier, context);
      const code = `const ports = globalThis[Symbol.for(${JSON.stringify(Symbol.keyFor(key))})];\n${body}`;
      return {url: 'data:text/javascript,' + encodeURIComponent(code), shortCircuit: true};
    }});
    try {
      const {runInstalledComposedInfers: run} = await import(url) as {runInstalledComposedInfers: ObservationRun};
      // This early driver fixture supplies only the ports reached before
      // waiting, refusal or cleanup. It never issues real publication data.
      return await run(args as unknown as Parameters<ObservationRun>[0]);
    } finally { hooks.deregister(); delete globals[key]; }
  }

  return {events, issuer, cleanupIssuances, run,
    advances: () => advances,
    handoff() {current = false;},
    async cleanup() {assert(owner); return owner.cleanup();},
  };
}

test('original Model observation seals at completion before the Local output ownership handoff', async () => {
  const f = fixture();
  await f.run(([complete]) => {
    assert.equal(complete(), true);
    assert.deepEqual(f.events, ['retain', 'count', 'start', 'advance', 'advance', 'advance', 'advance']);
    f.handoff();
    assert.equal(complete(), true, 'repeated completion observes the already sealed issuer');
    assert.equal(f.events.filter(event => event === 'start').length, 1);
    assert.equal(f.advances(), 4);
  });
  assert.equal(await f.cleanup(), true);
  assert.deepEqual(f.cleanupIssuances, [f.issuer]);
});

test('original Model observation constructor refusal remains exact before Local handoff', async () => {
  const issue = new Error('OriginalObservationCurrentRefused');
  const f = fixture({startIssue: issue});
  await assert.rejects(f.run(([complete]) => {complete();}), error => error === issue);
  assert.deepEqual(f.events, ['retain', 'count', 'start']);
  assert.equal(await f.cleanup(), true);
  assert.deepEqual(f.cleanupIssuances, []);
});

test('original Model observation retains zero and maximum slot inventories under the existing bound', async () => {
  for (const count of [0, 128]) {
    const f = fixture({counts: [count]});
    await f.run(([complete]) => {assert.equal(complete(), true);});
    assert.equal(f.advances(), count + 2);
  }
});

test('original Model observation failed advance retains the same partial issuer for cleanup', async () => {
  const issue = {}, f = fixture({advanceIssue: issue});
  await assert.rejects(f.run(([complete]) => {complete();}), error =>
    error instanceof Error && error.cause === issue);
  assert.deepEqual(f.events, ['retain', 'count', 'start', 'advance']);
  assert.equal(await f.cleanup(), true);
  assert.deepEqual(f.cleanupIssuances, [f.issuer]);
});

test('original Model observation uses the existing finite work bound without an unbounded completion loop', async () => {
  const f = fixture({neverComplete: true});
  await assert.rejects(f.run(([complete]) => {complete();}), /InstalledComposedInferOriginalObservationUnavailable/);
  assert.equal(f.advances(), 4);
  assert.equal(await f.cleanup(), true);
  assert.deepEqual(f.cleanupIssuances, [f.issuer]);
});

test('original Model observation rejects missing or malformed call inventory without issuing metadata', async () => {
  for (const count of [undefined, -1, 129, 1.5]) {
    const f = fixture({counts: [count]});
    await assert.rejects(f.run(([complete]) => {complete();}), /InstalledComposedInferOriginalObservationUnavailable/);
    assert.deepEqual(f.events, ['retain', 'count']);
  }
});

test('composed completion refuses missing Request ownership before retaining output', async () => {
  const f = fixture({missingOriginal: true});
  await assert.rejects(f.run(([complete]) => {complete();}), /InstalledComposedInferOriginalObservationUnavailable/);
  assert.deepEqual(f.events, []);
});

test('multi original observation seals once at the last retained component before handoff', async () => {
  const f = fixture({counts: [1, 2]});
  await f.run(([first, second]) => {
    assert.equal(first(), true);
    assert.deepEqual(f.events, ['retain0']);
    assert.equal(f.advances(), 0);
    assert.equal(second(), true);
    assert.deepEqual(f.events, ['retain0', 'retain1', 'count0', 'count1']);
    assert.equal(f.advances(), 5);
    f.handoff();
    assert.equal(first(), true);
    assert.equal(f.advances(), 5);
  });
});


test('composed cleanup drains its original Scope before requiring whole-parent zero usage', async () => {
  const setupIssue = new Error('OriginalSetupPending');
  let held = 10n;
  const f = fixture({counts: [], setupIssue,
    scope: {retire() {held = 0n; return true;}, held: () => held}});
  await assert.rejects(f.run(() => assert.fail('uninstalled setup must not complete')), error => error === setupIssue);
  assert.equal(await f.cleanup(), true);
  assert.deepEqual(f.events, ['stop-setup', 'close-outputs', 'retire-scope', 'usage']);
  assert.equal(await f.cleanup(), true);
  assert.deepEqual(f.events, ['stop-setup', 'close-outputs', 'retire-scope', 'usage']);
});

test('composed cleanup keeps the original setup while a Model child or same Scope is pending', async () => {
  const setupIssue = new Error('OriginalSetupPending');
  let closed = false, closes = 0, held = 10n, scopeReady = true;
  const f = fixture({counts: [1], setupIssue, closeCapture() {closes++; return closed;},
    scope: {retire() {if (!scopeReady) return false; held = 0n; return true;}, held: () => held}});
  await assert.rejects(f.run(() => assert.fail('uninstalled setup must not complete')), error => error === setupIssue);
  assert.equal(await f.cleanup(), false);
  assert.deepEqual(f.events, ['stop-setup', 'close-outputs']);
  closed = true;
  scopeReady = false;
  assert.equal(await f.cleanup(), false);
  assert.deepEqual(f.events, ['stop-setup', 'close-outputs', 'stop-setup', 'close-outputs', 'retire-scope']);
  const childCloses = closes;
  scopeReady = true;
  assert.equal(await f.cleanup(), true);
  assert.equal(closes, childCloses);
  assert.deepEqual(f.events.slice(-4), ['stop-setup', 'close-outputs', 'retire-scope', 'usage']);
});
