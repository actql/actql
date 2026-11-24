import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {withScopedStrategy} from '../host-common/scoped-strategy.mjs';
import {installStrategyContributions} from '../connectors-workers/strategy.generated.mjs';

import type {WorkersFiniteAuthorization, WorkersFiniteConfiguration, WorkersFiniteCore, WorkersFiniteExecution,
  WorkersFiniteHandle, WorkersFiniteHost, WorkersFiniteLedger, WorkersFiniteOriginal,
  WorkersFinitePreparation, WorkersFiniteSetup} from '../../packages/run-host-core/workers-finite.js';
import type {SynchronousResultCheck} from '../host-common/runtime-result.mjs';
import type {createAuthorizationGate} from '../host-common/authorization-gate.mjs';

type Configuration = WorkersFiniteConfiguration;
type FragmentLimits = NonNullable<Configuration['fragments']>['limits'];
type Opaque<Kind extends string> = WorkersFiniteHandle<Kind>;
type Environment = Opaque<'environment'>;
type Contracts = Opaque<'contracts'>;
type Manifests = Opaque<'manifests'>;
type Fragment = Opaque<'fragment-contract'>;
type Ordered = Opaque<'ordered-contract'>;
type Program = Opaque<'program'>;
type Compilation = Opaque<'compilation'>;
type Preparation = WorkersFinitePreparation & Readonly<{program: Program; compilation: Compilation}>;
type Admission = WorkersFiniteOriginal['admission'];
type Definition = WorkersFiniteOriginal['definition'];
type Result<Value> = Readonly<{$tag: 1; _0: Value} | {$tag: 0; _0: unknown}>;
type Pair<First, Second> = Readonly<{_0: First; _1: Second}>;
type Materials = Pair<Program, Compilation> & Readonly<{_2: Admission; _3: Definition}>;
type ScopedStrategyArguments = Parameters<typeof withScopedStrategy>;
type CurrentAuthorization = NonNullable<NonNullable<ScopedStrategyArguments[5]>['authorization']>;
type GateRuntime = NonNullable<NonNullable<Parameters<typeof createAuthorizationGate>[0]>['runtime']>;

type FiniteAbi = Readonly<{
  workersFiniteEnvironment(wire: string, cid: string, expressions: Configuration['environment']['expressions'],
    operations: Configuration['environment']['operations'], numericProfileCid: string | undefined): Result<Environment>;
  workersFiniteContracts(registry: string, values: string): Result<Contracts>;
  workersFiniteFragmentContracts(contracts: Contracts, fragment: string, ordered: string | undefined,
    limits: FragmentLimits['physical']): Result<Pair<Fragment, Ordered | undefined>>;
  workersFiniteManifests(grammar: string, barriers: string): Result<Manifests>;
  workersFinitePrepare(document: string, environment: Environment): Result<Program>;
  workersFiniteCompile(program: Program, manifests: Manifests, sequence: Configuration['sequence'],
    work: number, entries: number): Result<Compilation>;
  workersFiniteTemplate(compilation: Compilation): Opaque<'template'>;
  workersFiniteCompiledPlan(compilation: Compilation): Opaque<'compiled-plan'>;
  workersFiniteOpen(program: Program, compilation: Compilation, admission: Admission, definition: Definition,
    contracts: Contracts, sequence: Configuration['sequence'], execution: Configuration['execution'],
    measurement: Configuration['measurement'], capacity: Configuration['capacity'] & {common_fragment: undefined},
    ledger: WorkersFiniteLedger, search: Configuration['search'], milliseconds: bigint, work: number, entries: number,
    fragment: Fragment | undefined, ordered: Ordered | undefined, limits: FragmentLimits | undefined): Result<WorkersFiniteSetup>;
  workersFiniteAdmitMaterials(body: string, definitionCid: string, expressions: Configuration['environment']['expressions'],
    operations: Configuration['environment']['operations'], manifests: Manifests, sequence: Configuration['sequence'],
    work: number, entries: number, numericProfileCid: string | undefined): Result<Materials>;
  workersFiniteLedger(limits: Configuration['ledger']): Result<WorkersFiniteLedger>;
  strategyPublicationContractIdentity(definition: Definition): string;
  strategyHostUsage(setup: object): bigint[];
  strategyHostAuthorizeActivation: unknown;
  strategyHostRequireActivation: unknown;
  strategyHostProgramDefinitionCid: unknown;
}>;
export type WorkersRuntime = FiniteAbi & GateRuntime & Parameters<typeof installStrategyContributions>[0];

type ValueRule = (value: unknown) => boolean;
interface Shape {readonly [member: string]: ValueRule | Shape}
type ConfigurationShape<Value> = {
  readonly [Key in keyof Value]-?: NonNullable<Value[Key]> extends object
    ? ConfigurationShape<NonNullable<Value[Key]>> : ValueRule;
};

const invalid: () => never = () => { throw new TypeError('InvalidWorkersFiniteInstallation'); };
const integer = (value: unknown) => Number.isInteger(value) && (value as number) >= 0 && (value as number) <= 2147483647;
const quantity = (value: unknown) => typeof value === 'bigint' && value >= 0n && value <= 9223372036854775807n;
const text = (value: unknown) => typeof value === 'string' && value.length > 0;
const boolean = (value: unknown) => typeof value === 'boolean';
const optionalShapes = new WeakSet<Shape | ValueRule>();
const optional = <Rule extends Shape | ValueRule>(shape: Rule): Rule => {optionalShapes.add(shape); return shape;};
const numericProfile = optional((value: unknown) => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value));

// Private ABI projection of the existing Owner's records. All fields are
// mandatory except selected capabilities; no physical capacity, known estimate
// or capability is inferred from an omitted selection.
function snapshot(value: unknown, shape: Shape): Readonly<Record<string, unknown>> {
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).some(key => !Object.hasOwn(shape, key)) ||
      Object.entries(shape).some(([key, type]) =>
        !optionalShapes.has(type) && !Object.hasOwn(value, key))) invalid();
  return Object.freeze(Object.fromEntries(Object.entries(shape)
    .filter(([key, type]) => !optionalShapes.has(type) || Object.hasOwn(value, key))
    .map(([key, type]) => {
    const item = (value as Record<string, unknown>)[key];
    if (typeof type === 'function') {
      if (!type(item)) invalid();
      return [key, item];
    }
    return [key, snapshot(item, type)];
  })));
}
const values = {max_nodes: integer, max_text_bytes: integer, max_depth: integer, max_work: integer};
const fragmentShape = {
  contract: text, ordered: optional((value: unknown) => text(value)),
  limits: {
    roots: {max_roots: integer, max_pointer_bytes: integer, max_work: integer},
    demands: {max_roots: integer, max_nodes: integer, max_work: integer,
      max_text_bytes: integer, max_links: integer},
    physical: {max_body_bytes: integer, max_body_nodes: integer, max_body_depth: integer},
    logical: {max_input_rows: quantity, max_value_bytes: quantity,
      max_live_value_bytes: quantity, max_work: quantity},
    max_input_rows: quantity, max_value_bytes: quantity,
  },
};
const configurationShape: ConfigurationShape<Configuration> = {
  fragments: optional(fragmentShape),
  environment: {wire: text, cid: text, numeric_profile_cid: numericProfile,
    expressions: {text_time: boolean, veca: boolean},
    operations: {rela: boolean, sga: boolean, tea: boolean, calendar: boolean, text_rank: boolean}},
  contracts: {registry: text, values: text, grammar: text, barriers: text},
  sequence: {max_steps: integer, max_rows: integer, max_cells: integer,
    max_bindings: integer, max_name_bytes: integer,
    expressions: {max_nodes: integer, max_work: integer, max_depth: integer,
      max_literal_nodes: integer, max_literal_text_bytes: integer}},
  execution: {rows: {max_rows: integer, metadata_entries: integer,
    retained_entries: integer, operation_entries: integer,
    input_values: values, output_values: values}, max_work: integer, max_frames: integer},
  measurement: {max_work: integer, max_bytes: integer, max_nodes: integer, max_depth: integer},
  capacity: {contract_cid: text, max_rows: integer, max_value_bytes: integer},
  search: {max_offers: integer, max_strategies: integer, max_work: integer, max_revisions: integer},
  ledger: {planning_work: integer, attempts: integer, holdings: integer,
    transfer_bytes: quantity, retained_bytes: quantity, execution_bytes: quantity},
  milliseconds: quantity, max_work: integer, max_entries: integer,
};
const requiredExports = ['workersFiniteEnvironment', 'workersFiniteContracts',
  'workersFiniteManifests', 'workersFinitePrepare', 'workersFiniteCompile',
  'workersFiniteTemplate', 'workersFiniteCompiledPlan', 'workersFiniteOpen',
  'workersFiniteAdmitMaterials', 'workersFiniteLedger', 'strategyPublicationContractIdentity',
  'strategyHostAuthorizeActivation', 'strategyHostRequireActivation',
  'strategyHostUsage', 'strategyHostProgramDefinitionCid'] as const;

function protectedGate(authorization: WorkersFiniteAuthorization) {
  if (authorization === null || typeof authorization !== 'object' ||
      typeof authorization.authorize !== 'function' ||
      typeof authorization.cover !== 'function' ||
      typeof authorization.isProtectedSite !== 'function' ||
      authorization.isProtectedSite('in-process-default') !== true) {
    throw new TypeError('WorkersFiniteProtectedAuthorizationRequired');
  }
  return authorization;
}

// Trusted invocation-scoped installation, never request JSON. Preparation and original Run
// admission MUST share this runtime/link unit. No separately built package's
// opaque handle can stand in for a checked preparation or authorization.
export function bindWorkersFiniteHost(runtime: WorkersRuntime, configuration: Configuration): WorkersFiniteHost {
  const moon = Object.freeze({...runtime});
  if (requiredExports.some(name => typeof moon[name] !== 'function')) invalid();
  const selected = snapshot(configuration, configurationShape) as unknown as Configuration;
  const environment = checked(moon.workersFiniteEnvironment(selected.environment.wire,
    selected.environment.cid, selected.environment.expressions, selected.environment.operations,
    selected.environment.numeric_profile_cid)) as Environment;
  const contracts = checked(moon.workersFiniteContracts(selected.contracts.registry, selected.contracts.values)) as Contracts;
  const manifests = checked(moon.workersFiniteManifests(selected.contracts.grammar, selected.contracts.barriers)) as Manifests;
  if (selected.fragments !== undefined &&
      typeof moon.workersFiniteFragmentContracts !== 'function') invalid();
  const fragments = selected.fragments === undefined ? undefined :
    checked(moon.workersFiniteFragmentContracts(contracts, selected.fragments.contract,
      selected.fragments.ordered, selected.fragments.limits.physical)) as Pair<Fragment, Ordered | undefined>;
  const capacity = Object.freeze({...selected.capacity, common_fragment: undefined});
  const core = runtimeCore(moon);
  const preparations = new WeakSet<WorkersFinitePreparation>();
  let originalDefinitionCid: string | null = null;
  const setups = new WeakMap<WorkersFiniteSetup, WorkersFiniteAuthorization>();
  const started = new WeakSet<WorkersFiniteSetup>();
  const retainPreparation = (program: Program, compilation: Compilation) => {
    const preparation = Object.freeze({program, compilation,
      template: moon.workersFiniteTemplate(compilation),
      compiledPlan: moon.workersFiniteCompiledPlan(compilation)}) as unknown as Preparation;
    preparations.add(preparation);
    return preparation;
  };
  return Object.freeze<WorkersFiniteHost>({
    core: core as unknown as WorkersFiniteCore,
    createLedger() {
      return checked(moon.workersFiniteLedger(selected.ledger)) as WorkersFiniteLedger;
    },
    admitMaterials(body, expectedRunDefinitionCid) {
      if (typeof body !== 'string' || typeof expectedRunDefinitionCid !== 'string') {
        throw new TypeError('InvalidWorkersFiniteMaterials');
      }
      const value = checked(moon.workersFiniteAdmitMaterials(body,
        expectedRunDefinitionCid, selected.environment.expressions,
        selected.environment.operations, manifests, selected.sequence,
        selected.max_work, selected.max_entries, selected.environment.numeric_profile_cid)) as Materials;
      return Object.freeze({preparation: retainPreparation(runtimeField(value, 0) as Program, runtimeField(value, 1) as Compilation),
        admission: runtimeField(value, 2) as Admission, definition: runtimeField(value, 3) as Definition});
    },
    prepare(document) {
      if (typeof document !== 'string') throw new TypeError('InvalidWorkersFiniteDocument');
      const program = checked(moon.workersFinitePrepare(document, environment)) as Program;
      const compilation = checked(moon.workersFiniteCompile(program, manifests,
        selected.sequence, selected.max_work, selected.max_entries)) as Compilation;
      return retainPreparation(program, compilation);
    },
    // Only the caller's accepted request Owner supplies these original nominal
    // Run and Ledger handles. No admission is issued here and no retry opens a
    // second task owner. Retain this exact setup through completion/cleanup.
    open(preparation, {admission, definition, ledger}, authorization) {
      protectedGate(authorization);
      if (!preparations.has(preparation) || definition === null ||
          typeof definition !== 'object') invalid();
      const identity = moon.strategyPublicationContractIdentity(definition);
      if (!text(identity)) invalid();
      if (originalDefinitionCid !== null) {
        if (originalDefinitionCid === identity) {
          throw new TypeError('WorkersFiniteRunAlreadyOpened');
        }
        // A different original Run requires its own invocation/link unit.
        // This installation refusal is not a restriction on Program meaning.
        invalid();
      }
      // An unsuccessful open may already have charged planning work. Keep the
      // original caller's Ledger and refusal; never silently reopen this Run.
      originalDefinitionCid = identity;
      const setup = checked(moon.workersFiniteOpen((preparation as Preparation).program, (preparation as Preparation).compilation,
        admission, definition, contracts, selected.sequence, selected.execution,
        selected.measurement, capacity, ledger, selected.search,
        selected.milliseconds, selected.max_work, selected.max_entries,
        fragments === undefined ? undefined : runtimeField(fragments, 0) as Fragment,
        fragments === undefined ? undefined : runtimeField(fragments, 1) as Ordered | undefined,
        selected.fragments?.limits)) as WorkersFiniteSetup;
      setups.set(setup, authorization);
      return setup;
    },
    // Current authorization is checked by the original strategy immediately
    // before activation on its actual selected Site and exact Program subject.
    // No Site override, fallback, auto-retry or cross-request recovery exists.
    withExecution<Value>(setup: WorkersFiniteSetup, authorization: WorkersFiniteAuthorization,
      consume: (execution: WorkersFiniteExecution) => Value | Promise<Value>, signal?: AbortSignal) {
      protectedGate(authorization);
      if (!setups.has(setup) || setups.get(setup) !== authorization) invalid();
      if (typeof consume !== 'function') throw new TypeError('A scoped consumer is required');
      if (started.has(setup)) throw new TypeError('WorkersFiniteExecutionAlreadyStarted');
      started.add(setup);
      return withScopedStrategy<Value | Promise<Value>>(setup, core,
        installStrategyContributions(moon, setup, checked as SynchronousResultCheck, {}),
        consume as Parameters<typeof withScopedStrategy<Value | Promise<Value>>>[3], signal, {authorization: authorization as CurrentAuthorization});
    },
    usage(setup) {
      if (!setups.has(setup)) invalid();
      return moon.strategyHostUsage(setup);
    },
  });
}
