// Standard composition entry. Callers cannot replace the runtime, installed
// implementation factories, verification or SQL through execution options.
import {runInstalledStrategy} from '../host-common/strategy.mjs';
import {installStrategyContributions} from '../connectors-builtin/strategy.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {snapshotConfigurations} from './installation.mjs';
import {completionObserver} from '../host-common/completion-observer.mjs';
import {preparedManagedIdentityPolicy} from './managed-identity-policy.mjs';
import {enableNodeCompileCache} from './compile-cache.mjs';
import {prepareCompletedEffectFreeRunPublication} from
  '../host-common/run-publication-preflight.mjs';
import {missingAuthorizationGate} from '../host-common/authorization-gate.mjs';
import {completeCapturedEffectRun as completeEffectRun,
  completeRecoveredEffectRun as completeRecoveredRun} from
  './effect-run-completion.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);

async function runCapturedStrategyTarget(
  setup,
  options,
  signal,
  observer,
  publishCheckedResults,
  publication,
  loadRuntime,
  install,
) {
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
  return runInstalledStrategy(
    setup,
    core,
    installed,
    signal,
    observeCompletion,
    configurations.executionSitePolicy,
    publication === undefined
      ? undefined
      : facts => prepareCompletedEffectFreeRunPublication({
        store: publication.store,
        control: facts.publicationControl,
        publicationInventory: facts.publicationInventory,
        plan: publication.plan,
      }),
    authorization,
  );
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

// Execute and publish one ordinary checked Effect-free Program. Immutable
// publication inputs and current Store capacity are admitted before any
// Compute starts. The returned owner keeps internal completion and publication
// cleanup explicit; publication failure never rewrites the Compute outcome.
async function runPublishedCapturedStrategyTarget(
  setup,
  publication,
  options,
  signal,
  observer,
  loadRuntime,
  install,
) {
  if (publication === null || typeof publication !== 'object' ||
      Array.isArray(publication) ||
      Object.keys(publication).sort().join('\0') !== 'plan\0store') {
    throw new TypeError('InvalidCapturedRunPublication');
  }
  const execution = await runCapturedStrategyTarget(
    setup,
    options,
    signal,
    observer,
    true,
    publication,
    loadRuntime,
    install,
  );
  try {
    const result = await execution.publishEffectFreeRun(
      publication.store,
      execution.publicationPreflight.plan,
      signal,
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
    throw new CapturedRunPublicationError(error, execution);
  }
}

// Compute an admitted Effect Run through the installed Host without claiming
// apply or publication success. The exact captured owner remains with the
// caller for Result pins, Preview, and subsequent durable Effect progress.
async function runCapturedEffectComputationTarget(
  owner, options, signal, observer, loadRuntime, install,
) {
  const moon = await loadRuntime();
  if (typeof moon.clientProgramLocalEffectHostRuntime !== 'function') {
    throw new TypeError('Effect computation Host is unavailable');
  }
  let setup;
  try { setup = moon.clientProgramLocalEffectHostRuntime(owner); }
  catch { throw new TypeError('InvalidCapturedEffectComputation'); }
  if (setup === undefined || !moon.strategyHostHasEffects(setup)) {
    throw new TypeError('InvalidCapturedEffectComputation');
  }
  return runCapturedStrategyTarget(setup, options, signal, observer,
    false, undefined, loadRuntime, install);
}

// Build-time composition selects a concrete MoonBit artifact and its matching
// implementation set. Call options cannot substitute either component.
export function createNodeHostEntry(loadRuntime, install) {
  let runtime;
  const load = () => (runtime ??= loadRuntime());
  return Object.freeze({
    runCapturedStrategy: (setup, options = {}, signal, observer) =>
      runCapturedStrategyTarget(setup, options, signal, observer, true,
        undefined, load, install),
    runCapturedInternalStrategy: (setup, options = {}, signal, observer) =>
      runCapturedStrategyTarget(setup, options, signal, observer, false,
        undefined, load, install),
    runCapturedEffectComputation: (
      owner, options = {}, signal, observer,
    ) => runCapturedEffectComputationTarget(owner, options, signal,
      observer, load, install),
    runPublishedCapturedStrategy: (
      setup, publication, options = {}, signal, observer,
    ) => runPublishedCapturedStrategyTarget(setup, publication, options,
      signal, observer, load, install),
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
