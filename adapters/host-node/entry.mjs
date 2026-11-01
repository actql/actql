// Standard composition entry. Callers cannot replace the runtime, installed
// implementation factories, verification or SQL through execution options.
import {runInstalledStrategy} from '../host-common/strategy.mjs';
import {installStrategyContributions} from '../connectors-builtin/strategy.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {snapshotConfigurations} from './installation.mjs';
import {completionObserver, taskStartObserver} from '../host-common/completion-observer.mjs';
import {preparedManagedIdentityPolicy} from './managed-identity-policy.mjs';
import {enableNodeCompileCache} from './compile-cache.mjs';
import {prepareCompletedEffectFreeRunPublication} from
  '../host-common/run-publication-preflight.mjs';
import {missingAuthorizationGate} from '../host-common/authorization-gate.mjs';
import {completeCapturedEffectRun as completeEffectRun,
  completeRecoveredEffectRun as completeRecoveredRun,
  completeInterruptedEffectRun as completeInterruptedRun,
  settleRefusedEffectRun as settleRefusedRun} from
  './effect-run-completion.mjs';
import {recoverAdmittedEffectRun as recoverAdmittedRun} from
  './effect-run-recovery.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);

async function runCapturedStrategyTarget({
  setup,
  options,
  composition: {loadRuntime, install},
  control: {signal, observer, taskObservation} = {},
  results: {publishCheckedResults, publication} = {},
  cleanup: {retainPreflightCleanup, preparationHolder} = {},
}) {
  signal?.throwIfAborted();
  const observeCompletion = completionObserver(observer);
  const configurations = snapshotConfigurations(options);
  const identityPolicy = preparedManagedIdentityPolicy(
    configurations.managedIdentityPolicy,
  );
  enableNodeCompileCache();
  const moon = await loadRuntime();
  signal?.throwIfAborted();
  if (publishCheckedResults && moon.strategyHostHasEffects(setup)) {
    throw new TypeError('EffectfulProgramRequiresEffectRun');
  }
  if (!moon.strategyHostConfigureManagedIdentity(
    setup,
    publishCheckedResults,
    identityPolicy.publication,
    identityPolicy.consumer,
    // Mandatory policy is owned by this installed Host entry, not by caller
    // options or connector contributions. This initial Host registers none.
    false,
  )) {
    throw new TypeError('Managed identity policy is not admissible');
  }
  const core = runtimeCore(moon);
  // Host-installed gate (never Program input). Without one the Host has no
  // account configuration: protected boundaries deny, covered in-process
  // compute still runs.
  const authorization = configurations.authorization ??
    missingAuthorizationGate();
  // Seal the activation requirement before any contribution is installed.
  core.requireActivation(setup);
  const installed = await install(moon, setup, checked, configurations, signal);
  signal?.throwIfAborted();
  return runInstalledStrategy({
    setup,
    runtime: {core, contributions: installed,
      sitePolicy: configurations.executionSitePolicy, authorization},
    control: {signal, observeCompletion,
      observeTaskStart: taskStartObserver(observer), taskObservation},
    publication: {
      beforeCompute: publication === undefined
        ? undefined
        : facts => prepareCompletedEffectFreeRunPublication({
          store: publication.store,
          control: facts.publicationControl,
          publicationInventory: facts.publicationInventory,
          plan: publication.plan,
        }),
    },
    cleanup: {retainPreflightCleanup, preparationHolder},
  });
}

// The standard entry executes the checked Program's named Result request.
// Until an installed implementation can satisfy its publication identity,
// that task is rejected before start rather than silently treated as internal.
export class CapturedRunPublicationError extends Error {
  constructor(cause, execution) {
    super('CapturedRunPublicationFailed', {cause});
    this.code = 'CapturedRunPublicationFailed';
    this.primaryFailure = cause;
    this.execution = execution;
    this.cleanupPending = cause?.cleanupPending === true;
    this.cleanupHandle = cause?.cleanupHandle;
  }
}

// Preserve the exact failed execution and its cleanup owner without replacing
// the first typed cause with the publication guard's StrategyNotComplete.
export class CapturedRunExecutionError extends CapturedRunPublicationError {
  constructor(execution) {
    super(execution.failure, execution);
    this.message = this.code = 'CapturedRunExecutionFailed';
  }
}

// Execute and publish one ordinary checked Effect-free Program. Immutable
// publication inputs and current Store capacity are admitted before any
// Compute starts. The returned owner keeps internal completion and publication
// cleanup explicit; publication failure never rewrites the Compute outcome.
async function runPublishedCapturedStrategyTarget({
  setup,
  publication,
  options,
  composition,
  control: {signal, observer, taskObservation, beforePublication},
  cleanup: {retainExecution, preparationHolder},
}) {
  if (retainExecution !== undefined && typeof retainExecution !== 'function') {
    throw new TypeError('InvalidExecutionOwnerReceiver');
  }
  if (publication === null || typeof publication !== 'object' ||
      Array.isArray(publication) ||
      Object.keys(publication).sort().join('\0') !== 'plan\0store') {
    throw new TypeError('InvalidCapturedRunPublication');
  }
  const execution = await runCapturedStrategyTarget({
    setup,
    options,
    composition,
    control: {signal, observer, taskObservation},
    results: {publishCheckedResults: true, publication},
    // Reuse the installed custody receiver for a setup cleanup owner only.
    // Preflight failure never constructs a Compute or publication result.
    cleanup: {retainPreflightCleanup: retainExecution, preparationHolder},
  });
  try {
    // Transfer cleanup responsibility before publication can fail. The
    // installed supervisor must not depend on an exception surviving wrappers.
    retainExecution?.(execution);
    if (execution.status === 'host-tasks-failed') {
      throw new CapturedRunExecutionError(execution);
    }
    // Fixed installed manager grows the same original preparation token before
    // any publication material constructor. A failure retains normal cleanup.
    if (preparationHolder !== undefined && typeof beforePublication !== 'function') {
      throw new TypeError('PreparationPublicationUnavailable');
    }
    const publicationResource = beforePublication?.();
    if (preparationHolder !== undefined && publicationResource === undefined) {
      throw new TypeError('PreparationPublicationUnavailable');
    }
    const result = await execution.publishEffectFreeRun(
      publication.store,
      execution.publicationPreflight.plan,
      signal,
      publicationResource,
    );
    return Object.freeze({
      status: 'published',
      execution,
      publication: result,
      close: () => execution.close(),
      cleanupPending: () => execution.cleanupPending(),
      cleanup: () => execution.cleanup(),
    });
  } catch (error) {
    if (error instanceof CapturedRunExecutionError && error.execution === execution) throw error;
    throw new CapturedRunPublicationError(error, execution);
  }
}

// Compute an admitted Effect Run through the installed Host without claiming
// apply or publication success. The exact captured owner remains with the
// caller for Result pins, Preview, and subsequent durable Effect progress.
async function runCapturedEffectComputationTarget({
  owner, options, control, composition,
}) {
  const moon = await composition.loadRuntime();
  if (typeof moon.clientProgramLocalEffectHostRuntime !== 'function') {
    throw new TypeError('Effect computation Host is unavailable');
  }
  let setup;
  try { setup = moon.clientProgramLocalEffectHostRuntime(owner); }
  catch { throw new TypeError('InvalidCapturedEffectComputation'); }
  if (setup === undefined || !moon.strategyHostHasEffects(setup)) {
    throw new TypeError('InvalidCapturedEffectComputation');
  }
  return runCapturedStrategyTarget({setup, options, control, composition,
    results: {publishCheckedResults: false}});
}

// Build-time composition selects a concrete MoonBit artifact and its matching
// implementation set. Call options cannot substitute either component.
export function createNodeHostEntry(loadRuntime, install) {
  let runtime;
  const load = () => (runtime ??= loadRuntime());
  // Constructed only by installed composition, never read from caller options.
  const composition = Object.freeze({loadRuntime: load, install});
  return Object.freeze({
    recoverAdmittedEffectRun: options => recoverAdmittedRun(options, load),
    runCapturedStrategy: (setup, options = {}, signal, observer, cleanup) =>
      runCapturedStrategyTarget({setup, options, composition,
        control: {signal, observer}, results: {publishCheckedResults: true}, cleanup}),
    runCapturedInternalStrategy: (setup, options = {}, signal, observer) =>
      runCapturedStrategyTarget({setup, options, composition,
        control: {signal, observer}, results: {publishCheckedResults: false}}),
    runCapturedEffectComputation: (
      owner, options = {}, signal, observer,
    ) => runCapturedEffectComputationTarget({owner, options, composition,
      control: {signal, observer}}),
    runPublishedCapturedStrategy: (
     setup, publication, options = {}, signal, observer, retainExecution, taskObservation,
     preparationHolder, beforePublication,
    ) => runPublishedCapturedStrategyTarget({setup, publication, options,
      composition, control: {signal, observer, taskObservation, beforePublication},
      cleanup: {retainExecution, preparationHolder}}),
    completeCapturedEffectRun: async options => {
      const moon = await load();
      if (options?.apply?.moon !== moon) {
        throw new TypeError('InvalidCapturedEffectRunRuntime');
      }
      return completeEffectRun(options);
    },
    completeRecoveredEffectRun: async options => {
      const moon = await load();
      if (options?.apply?.moon !== moon) {
        throw new TypeError('InvalidCapturedEffectRunRuntime');
      }
      return completeRecoveredRun(options);
    },
    completeInterruptedEffectRun: async (options, recovered) => {
      const moon = await load();
      if (options?.apply?.moon !== moon) {
        throw new TypeError('InvalidCapturedEffectRunRuntime');
      }
      return completeInterruptedRun(options, recovered);
    },
    settleRefusedEffectRun: async options => {
      const moon = await load();
      if (options?.apply?.moon !== moon) {
        throw new TypeError('InvalidCapturedEffectRunRuntime');
      }
      return settleRefusedRun(options);
    },
  });
}

const standard = createNodeHostEntry(
  () => import(runtimeUrl.href), installStrategyContributions);
export const runCapturedStrategy = standard.runCapturedStrategy;
export const runCapturedInternalStrategy = standard.runCapturedInternalStrategy;
export const runCapturedEffectComputation =
  standard.runCapturedEffectComputation;
export const runPublishedCapturedStrategy =
  standard.runPublishedCapturedStrategy;
export const completeCapturedEffectRun =
  standard.completeCapturedEffectRun;
export const completeRecoveredEffectRun =
  standard.completeRecoveredEffectRun;
export const completeInterruptedEffectRun =
  standard.completeInterruptedEffectRun;
export const settleRefusedEffectRun = standard.settleRefusedEffectRun;
export const recoverAdmittedEffectRun = standard.recoverAdmittedEffectRun;
