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

const runtimeUrl = new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
let runtime;

async function runCapturedStrategyTarget(
  setup,
  options,
  signal,
  observer,
  publishCheckedResults,
  publication,
) {
  signal?.throwIfAborted();
  const observeCompletion = completionObserver(observer);
  const configurations = snapshotConfigurations(options);
  const identityPolicy = preparedManagedIdentityPolicy(
    configurations.managedIdentityPolicy,
  );
  enableNodeCompileCache();
  const moon = await (runtime ??= import(runtimeUrl.href));
  signal?.throwIfAborted();
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
  const installed = await installStrategyContributions(moon, setup, checked, configurations, signal);
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
  );
}

// The standard entry executes the checked Program's named Result request.
// Until an installed implementation can satisfy its publication identity,
// that task is rejected before start rather than silently treated as internal.
export function runCapturedStrategy(setup, options = {}, signal, observer) {
  return runCapturedStrategyTarget(setup, options, signal, observer, true);
}

// Explicit task-only entry. It does not request Program Result publication;
// caller policy can still strengthen it, and cannot weaken consumer/Host rules.
export function runCapturedInternalStrategy(
  setup, options = {}, signal, observer,
) {
  return runCapturedStrategyTarget(setup, options, signal, observer, false);
}

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
export async function runPublishedCapturedStrategy(
  setup,
  publication,
  options = {},
  signal,
  observer,
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
