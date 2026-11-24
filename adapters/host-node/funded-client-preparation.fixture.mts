import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import type {TestContext} from 'node:test';
import {snapshotClientRequest} from '../../packages/client-wire/index.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';
import {freezeInput} from '../../packages/sdk/internal/private-source-preparation.mjs';

type FixtureRequest = Readonly<{
  kind: string;
  input: unknown;
  parameters?: unknown;
  connection?: unknown;
  signal?: AbortSignal;
}>;
type InstallPreparation = typeof installNodeClientProgramPreparation<FixtureRequest>;
type Preparation = ReturnType<InstallPreparation>;
type ActualPreparationContext = NonNullable<ReturnType<
  NonNullable<Parameters<typeof prepareOrdinarySourceManagedInstallation>[1]['preparationContext']>
>>;
type FixtureMoon = Parameters<InstallPreparation>[0]['moon'] & ActualPreparationContext['runtime'] & Readonly<{
  clientProgramCheckingEnvironmentCid(environment: unknown): string;
  clientProgramPreparePublicSourceEnvironment(environment: unknown, publication: string): unknown;
  clientPrepareInstalledSequenceContracts(registry: string, values: string, fragment: string, ordered: string): unknown;
}>;
type FixtureOriginals = Readonly<{
  host: object;
  generation: object;
  installation: {sequenceContractOriginal: {moon: FixtureMoon; admission: unknown}};
}>;
type PreparationContext = Readonly<{
  runtime: FixtureMoon;
  environment: unknown;
  preparedEnvironment: unknown;
  retainedRelationOutput: boolean;
  valuesMaxRows?: number;
  sourceFreeMaxWork?: number;
}>;
type FundedOriginal = NonNullable<Awaited<ReturnType<
  NonNullable<Parameters<InstallPreparation>[0]['getFundedPreparation']>
>>> & Readonly<{kind: 'effect_free' | 'effectful'; prepared: object}>;
type Terminal = 'failed' | 'returned';
type OrdinaryManager = Awaited<ReturnType<typeof prepareOrdinarySourceManagedInstallation>>;
type PreparationPorts = Readonly<{
  installNodeClientProgramPreparation: InstallPreparation;
  prepareOrdinarySourceManagedInstallation(originals: FixtureOriginals, callbacks: Readonly<{
    validator(originals: FixtureOriginals): void;
    retainedValidator(originals: FixtureOriginals): void;
    preparationContext(originals: FixtureOriginals): PreparationContext;
    retireInitialPreparation(originals: FixtureOriginals, prepared: object): undefined;
  }>, retained: false): Promise<OrdinaryManager>;
}>;
type FixtureOptions = Readonly<{
  moon: FixtureMoon;
  environment: unknown;
  allowEffects?: boolean;
  http?: boolean;
  valuesMaxRows?: number;
  sourceFreeMaxWork?: number;
  retainedRelationOutput?: boolean;
  sourcePublication?: unknown;
  preparationPorts?: PreparationPorts;
}>;
type OpenFixtureOptions = FixtureOptions & Readonly<{
  sequenceContracts?: Readonly<{values: string; fragment: string; ordered: string}>;
}>;
type DirectFixture = Readonly<{
  prepare: Preparation;
  close(): Promise<void>;
  manager: OrdinaryManager;
  retireOriginal(prepared: object): void;
  installedContracts: unknown;
}>;
type HttpPreparation = Readonly<{
  prepare: Preparation;
  prepareRequest(operation: string, request: FixtureRequest): Readonly<{
    body: FixtureRequest;
    beforeReply(): void;
    bindRequest(derived: FixtureRequest): void;
    finish(terminal: Terminal): void;
  }>;
  prepareSubmit: ((request: FixtureRequest, selected?: unknown) => ReturnType<Preparation>) &
    Pick<Preparation, 'assertSubmittedIntent'>;
  submission: Readonly<{
    bindOwnedRequest(parent: FixtureRequest, derived: FixtureRequest): void;
    submittedIntentOriginal(request: FixtureRequest): unknown;
  }>;
}>;
type HttpFixture = DirectFixture & HttpPreparation &
  Readonly<{originalRequest(request: FixtureRequest): FixtureRequest}>;

// Test-only provenance for the same funded Request. The fixture transports
// the manager's retained original; it never issues a replacement annotation
// context or converts a prepared token into a proof.
const preparationOriginals = new WeakMap<object, Readonly<{
  moon: FixtureMoon; manager: OrdinaryManager; request: FixtureRequest;
}>>();
export function fundedAuthoringContextOriginalFixture(moon: FixtureMoon, prepared: object) {
  const original = preparationOriginals.get(prepared);
  assert.ok(original, 'The publication fixture requires its original funded preparation');
  assert.strictEqual(original.moon, moon);
  return original.manager.authoringContextOriginal(prepared, original.request);
}

// Existing caller tests use the actual Request/Resource owner and compiler.
// Only the installation identity/current port is supplied by this fixture;
// no shaped preparation, standalone Root or fallback compiler is admitted.
export function fundedClientPreparation(t: Pick<TestContext, 'after'>,
  options: FixtureOptions & {http: true}): Promise<HttpPreparation>;
export function fundedClientPreparation(t: Pick<TestContext, 'after'>,
  options: FixtureOptions & {http?: false}): Promise<Preparation>;
export function fundedClientPreparation(t: Pick<TestContext, 'after'>,
  options: FixtureOptions): Promise<HttpPreparation | Preparation>;
export async function fundedClientPreparation(t: Pick<TestContext, 'after'>, {moon, environment, allowEffects = false, http = false,
  valuesMaxRows, sourceFreeMaxWork, retainedRelationOutput = false, sourcePublication, preparationPorts}: FixtureOptions) {
  const fixture = await openFundedClientPreparation({moon, environment, allowEffects, http,
    valuesMaxRows, sourceFreeMaxWork, retainedRelationOutput, sourcePublication, preparationPorts});
  t.after(fixture.close);
  return http ? Object.freeze({prepare: fixture.prepare, prepareRequest: (fixture as HttpFixture).prepareRequest,
    prepareSubmit: (fixture as HttpFixture).prepareSubmit, submission: (fixture as HttpFixture).submission}) : fixture.prepare;
}

// Process fixtures have their own finally block, not a Node TestContext.
// Both entrances use this SAME owner and its original teardown below.
export function openFundedClientPreparation(options: OpenFixtureOptions & {http: true}): Promise<HttpFixture>;
export function openFundedClientPreparation(options: OpenFixtureOptions & {http?: false}): Promise<DirectFixture>;
export function openFundedClientPreparation(options: OpenFixtureOptions): Promise<DirectFixture | HttpFixture>;
export async function openFundedClientPreparation({moon, environment, allowEffects = false, http = false,
  valuesMaxRows, sourceFreeMaxWork, sequenceContracts, retainedRelationOutput = false, sourcePublication, preparationPorts}: OpenFixtureOptions): Promise<DirectFixture | HttpFixture> {
  // A retained normal Common must use its SAME installed Request/CJS owner.
  // These explicit fixture ports select actual modules, never shaped parents.
  const ports: PreparationPorts = preparationPorts ?? {prepareOrdinarySourceManagedInstallation,
    installNodeClientProgramPreparation};
  assert.equal(typeof ports.prepareOrdinarySourceManagedInstallation, 'function');
  assert.equal(typeof ports.installNodeClientProgramPreparation, 'function');
  if (typeof retainedRelationOutput !== 'boolean') {
    throw new TypeError('InvalidFixtureRetainedOutputProfile');
  }
  if (valuesMaxRows !== undefined && (!Number.isSafeInteger(valuesMaxRows) ||
      valuesMaxRows < 1 || valuesMaxRows > 2147483647 || allowEffects)) {
    throw new TypeError('InvalidLocalValuesRowLimit');
  }
  const suppliedContracts = sequenceContracts === undefined ? undefined :
    {values: sequenceContracts.values, fragment: sequenceContracts.fragment, ordered: sequenceContracts.ordered};
  const publication = sourcePublication ?? {environmentCid: moon.clientProgramCheckingEnvironmentCid(environment), aliases: []};
  const preparedEnvironment = moon.clientProgramPreparePublicSourceEnvironment(environment, JSON.stringify(publication));
  assert.ok(preparedEnvironment);
  const registry = await readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8');
  const contracts = JSON.parse(await readFile(new URL('../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
  const admission = checked(moon.clientPrepareInstalledSequenceContracts(registry,
    suppliedContracts === undefined ? JSON.stringify(contracts.execution_contracts['REL.values']) : suppliedContracts.values,
    suppliedContracts === undefined ? JSON.stringify(contracts.execution_contracts['ACTQL.expression_fragment/0.1']) : suppliedContracts.fragment,
    suppliedContracts === undefined ? JSON.stringify(contracts.execution_contracts['REL.derive.ordered']) : suppliedContracts.ordered));
  const host = {};
  const originals = {host, generation: host,
    installation: {sequenceContractOriginal: {moon, admission}}};
  const httpRegistry = http ? createEmbeddedHostRegistry((left, right) => left === right) : undefined;
  httpRegistry?.registerPreparation(host, originals.installation, host);
  const context = Object.freeze({runtime: moon, environment, preparedEnvironment, retainedRelationOutput,
    ...(valuesMaxRows === undefined ? {} : {valuesMaxRows}),
    ...(sourceFreeMaxWork === undefined ? {} : {sourceFreeMaxWork})});
  const connection = Object.freeze({mode: 'local', owner: 'local',
    consentRefs: Object.freeze([]), runners: Object.freeze([])});
  const receipts = new Set<object>(), requestReceipts = new WeakMap<FixtureRequest, object>(),
    retained = new Map<object, FundedOriginal['kind']>();
  let closed = false, prepare: Preparation;
  const current = (actual: unknown) => {
    assert.strictEqual(actual, originals); assert.equal(closed, false);
    httpRegistry?.assertPreparation(host, originals.installation, host);
  };
  const retireOriginal = (prepared: object) => {
    assert.equal(retained.has(prepared), true, 'Retire only the same retained caller alias');
    const kind = retained.get(prepared);
    retained.delete(prepared);
    preparationOriginals.delete(prepared);
    if (kind === 'effect_free') prepare.retireOriginal(prepared);
  };
  const view = await ports.prepareOrdinarySourceManagedInstallation(originals, {
    validator: current, retainedValidator: current,
    preparationContext(actual) {current(actual); return context;},
    retireInitialPreparation(actual, prepared): undefined {
      current(actual);
      retireOriginal(prepared);
      // Effect membership is weak; clearing this fixture's actual alias is
      // followed by the manager returning its same typed Effect borrower.
    },
  }, false);
  prepare = ports.installNodeClientProgramPreparation({moon, environment, allowEffects, valuesMaxRows,
    async getFundedPreparation(request, selected, verifier, signal) {
      assert.strictEqual(selected, environment);
      // HTTP already retained this SAME original before snapshot/dispatch.
      // Direct component calls remain their separate explicit fixture entry.
      if (!requestReceipts.has(request)) {
        const input = request.kind === 'program' ? request.input : (request.input as {text: unknown}).text;
        const receipt = view.beforeSourceSnapshot(request.kind, input, {parameters: request.parameters}, connection);
        receipts.add(receipt);
        const body = view.captureSourceSnapshot(receipt, request, snapshotClientRequest) as FixtureRequest;
        view.bindSourceSnapshot(receipt, body);
        view.bindSourceRequest(receipt, body, request);
      }
      const original = await view.fundedPreparation(request, selected, verifier, signal) as FundedOriginal;
      assert.equal(retained.has(original.prepared), false);
      retained.set(original.prepared, original.kind);
      if (original.kind === 'effect_free') {
        preparationOriginals.set(original.prepared, {moon, manager: view, request});
      }
      return original;
    }});
  const close = async () => {
    if (closed) return;
    for (const receipt of receipts) view.finishSourceProducer(receipt, 'returned');
    assert.equal(retained.size, 0);
    assert.deepEqual(await view.close(), {pending: false});
    prepare.retireReferences();
    httpRegistry?.retirePreparation(host, originals.installation, host);
    closed = true;
  };
  if (!http) return Object.freeze({prepare, close, manager: view, retireOriginal,
    installedContracts: admission});
  const originalRequest = (request: FixtureRequest) => httpRegistry!.originalSourceRequest(host,
    originals.installation, host, request) as FixtureRequest;
  const prepareRequest = (operation: string, request: FixtureRequest) => {
    current(originals);
    let settle!: () => void;
    const pending = new Promise<void>(resolve => {settle = resolve;});
    httpRegistry!.retainRequest(host, originals.installation, host, request, pending);
    let receipt: object | undefined, body = request, finished = false;
    const finish = (terminal: Terminal) => {
      if (finished) return;
      try {
        if (receipt !== undefined) {
          view.finishSourceProducer(receipt, terminal);
          receipts.delete(receipt);
        }
        finished = true;
      } finally {settle();}
    };
    try {
      if (['plan', 'submit', 'submit-intent', 'submit-named-intent', 'restart-intent'].includes(operation)) {
        receipt = view.beforeSourceSnapshot(request.kind, request.input, request,
          request.connection as Parameters<OrdinaryManager['beforeSourceSnapshot']>[3]);
        receipts.add(receipt);
        body = view.captureSourceSnapshot(receipt, request, snapshotClientRequest) as FixtureRequest;
        view.assertSourceSnapshotCurrent(receipt);
        freezeInput(body);
        view.bindSourceSnapshot(receipt, body);
        view.bindSourceRequest(receipt, body, request);
        requestReceipts.set(request, receipt);
        if (operation !== 'plan' && operation !== 'submit') view.intentCid(receipt, body);
      }
      return Object.freeze({body,
        beforeReply() {
          current(originals);
          // A completed dispatch may already have severed its input. The
          // original pending ingress still belongs to this SAME registry;
          // do not re-read a spent pre-adoption Core input to send its reply.
          assert.strictEqual(originalRequest(request), request);
        },
        bindRequest(derived: FixtureRequest) {
          httpRegistry!.bindSourceRequest(host, originals.installation, host, request, derived);
        }, finish});
    } catch (cause) {
      try {finish('failed');} catch { /* SAME manager retains failed cleanup for teardown. */ }
      throw cause;
    }
  };
  const assertSubmittedIntent = prepare.assertSubmittedIntent;
  assert.equal(typeof assertSubmittedIntent, 'function');
  const prepareSubmit = Object.freeze(Object.assign(
    (request: FixtureRequest, selected: unknown) => prepare(originalRequest(request), selected), {
      assertSubmittedIntent: (prepared: Parameters<Preparation['assertSubmittedIntent']>[0],
        intent: Parameters<Preparation['assertSubmittedIntent']>[1]) =>
        Reflect.apply(assertSubmittedIntent, prepare, [prepared, intent]),
    }));
  return Object.freeze({prepare, prepareRequest, close, manager: view, retireOriginal, originalRequest,
    installedContracts: admission,
    prepareSubmit,
    submission: Object.freeze({
      bindOwnedRequest(parent: FixtureRequest, derived: FixtureRequest) {
        httpRegistry!.bindSourceRequest(host, originals.installation, host, parent, derived);
      },
      submittedIntentOriginal(request: FixtureRequest) {return view.submittedIntentOriginal(originalRequest(request));},
    })});
}
