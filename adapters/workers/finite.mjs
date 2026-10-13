import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {withScopedStrategy} from '../host-common/scoped-strategy.mjs';
import {installStrategyContributions} from '../connectors-workers/strategy.generated.mjs';

const invalid = () => { throw new TypeError('InvalidWorkersFiniteInstallation'); };
const integer = value => Number.isInteger(value) && value >= 0 && value <= 2147483647;
const quantity = value => typeof value === 'bigint' && value >= 0n && value <= 9223372036854775807n;
const text = value => typeof value === 'string' && value.length > 0;
const boolean = value => typeof value === 'boolean';

// Private ABI projection of the existing Owner's records. All fields are
// mandatory; no physical capacity, known estimate or capability is inferred.
function snapshot(value, shape) {
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).sort().join() !== Object.keys(shape).sort().join()) invalid();
  return Object.freeze(Object.fromEntries(Object.entries(shape).map(([key, type]) => {
    const item = value[key];
    if (typeof type === 'function') {
      if (!type(item)) invalid();
      return [key, item];
    }
    return [key, snapshot(item, type)];
  })));
}
const values = {max_nodes: integer, max_text_bytes: integer, max_depth: integer, max_work: integer};
const configurationShape = {
  environment: {wire: text, cid: text,
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
  'strategyHostUsage', 'strategyHostProgramDefinitionCid'];

function protectedGate(authorization) {
  if (authorization === null || typeof authorization !== 'object' ||
      typeof authorization.authorize !== 'function' ||
      typeof authorization.cover !== 'function' ||
      typeof authorization.isProtectedSite !== 'function' ||
      authorization.isProtectedSite('in-process-default') !== true) {
    throw new TypeError('WorkersFiniteProtectedAuthorizationRequired');
  }
  return authorization;
}

// Trusted installation, never request JSON. Preparation and original Run
// admission MUST share this runtime/link unit. No separately built package's
// opaque handle can stand in for a checked preparation or authorization.
export function bindWorkersFiniteHost(runtime, configuration) {
  const moon = Object.freeze({...runtime});
  if (requiredExports.some(name => typeof moon[name] !== 'function')) invalid();
  const selected = snapshot(configuration, configurationShape);
  const environment = checked(moon.workersFiniteEnvironment(selected.environment.wire,
    selected.environment.cid, selected.environment.expressions, selected.environment.operations));
  const contracts = checked(moon.workersFiniteContracts(selected.contracts.registry, selected.contracts.values));
  const manifests = checked(moon.workersFiniteManifests(selected.contracts.grammar, selected.contracts.barriers));
  const capacity = Object.freeze({...selected.capacity, common_fragment: undefined});
  const core = runtimeCore(moon);
  const preparations = new WeakSet();
  const openedDefinitions = new Set();
  const setups = new WeakMap();
  const started = new WeakSet();
  const retainPreparation = (program, compilation) => {
    const preparation = Object.freeze({program, compilation,
      template: moon.workersFiniteTemplate(compilation),
      compiledPlan: moon.workersFiniteCompiledPlan(compilation)});
    preparations.add(preparation);
    return preparation;
  };
  return Object.freeze({
    core,
    createLedger() {
      return checked(moon.workersFiniteLedger(selected.ledger));
    },
    admitMaterials(body, expectedRunDefinitionCid) {
      if (typeof body !== 'string' || typeof expectedRunDefinitionCid !== 'string') {
        throw new TypeError('InvalidWorkersFiniteMaterials');
      }
      const value = checked(moon.workersFiniteAdmitMaterials(body,
        expectedRunDefinitionCid, selected.environment.expressions,
        selected.environment.operations, manifests, selected.sequence,
        selected.max_work, selected.max_entries));
      return Object.freeze({preparation: retainPreparation(value._0, value._1),
        admission: value._2, definition: value._3});
    },
    prepare(document) {
      if (typeof document !== 'string') throw new TypeError('InvalidWorkersFiniteDocument');
      const program = checked(moon.workersFinitePrepare(document, environment));
      const compilation = checked(moon.workersFiniteCompile(program, manifests,
        selected.sequence, selected.max_work, selected.max_entries));
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
      if (openedDefinitions.has(identity)) {
        throw new TypeError('WorkersFiniteRunAlreadyOpened');
      }
      // An unsuccessful open may already have charged planning work. Keep the
      // original caller's Ledger and refusal; never silently reopen this Run.
      openedDefinitions.add(identity);
      const setup = checked(moon.workersFiniteOpen(preparation.program, preparation.compilation,
        admission, definition, contracts, selected.sequence, selected.execution,
        selected.measurement, capacity, ledger, selected.search,
        selected.milliseconds, selected.max_work, selected.max_entries));
      setups.set(setup, authorization);
      return setup;
    },
    // Current authorization is checked by the original strategy immediately
    // before activation on its actual selected Site and exact Program subject.
    // No Site override, fallback, auto-retry or cross-request recovery exists.
    withExecution(setup, authorization, consume, signal) {
      protectedGate(authorization);
      if (!setups.has(setup) || setups.get(setup) !== authorization) invalid();
      if (typeof consume !== 'function') throw new TypeError('A scoped consumer is required');
      if (started.has(setup)) throw new TypeError('WorkersFiniteExecutionAlreadyStarted');
      started.add(setup);
      return withScopedStrategy(setup, core,
        installStrategyContributions(moon, setup, checked, {}), consume, signal,
        {authorization});
    },
    usage(setup) {
      if (!setups.has(setup)) invalid();
      return moon.strategyHostUsage(setup);
    },
  });
}
