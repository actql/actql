// Common in-process Site placement and lifecycle. A Site is an execution and
// retention location/generation, not a Connector registration. These opaque
// handles carry no task completion or content-identity authority.
const sites = new WeakMap();
const policies = new WeakMap();
const installations = new WeakMap();
const bindings = new WeakMap();
const operations = new WeakMap();
const transferOperations = new WeakMap();
const holdings = new WeakMap();
const cleanupResponsibilities = new WeakMap();

const fail = (code, details) => {
  const error = Object.assign(new Error(code), {code});
  if (details !== undefined) error.details = details;
  throw error;
};
const text = value => typeof value === 'string' && value.length > 0;
const count = value => Number.isSafeInteger(value) && value >= 0;
const duration = value => value === null ||
  (typeof value === 'bigint' && value >= 0n);
const bytes = value => typeof value === 'bigint' && value >= 0n;
const maximumBytes = 9223372036854775807n;
const siteState = site => sites.get(site) ?? fail('ForeignExecutionSite');
const sameInputOccurrence = (left, right) =>
  left.task === right.task &&
  left.material === right.material &&
  left.site === right.site &&
  left.siteMaterial === right.siteMaterial &&
  left.materialGeneration === right.materialGeneration;

export function createInProcessExecutionSite({
  key,
  generation,
  runtimeRevision,
  startupMilliseconds = 0n,
  transferMilliseconds = 0n,
  maxConcurrentOperations = 1,
  maxConcurrentTransfers = 1,
  maxRetainedBytes = maximumBytes,
  maxExecutionBytes = maximumBytes,
} = {}) {
  if (!text(key) || !count(generation) || !text(runtimeRevision) ||
      !duration(startupMilliseconds) || !duration(transferMilliseconds) ||
      !count(maxConcurrentOperations) || maxConcurrentOperations === 0) {
    fail('InvalidExecutionSite');
  }
  if (!count(maxConcurrentTransfers) || maxConcurrentTransfers === 0 ||
      !bytes(maxRetainedBytes) || !bytes(maxExecutionBytes)) {
    fail('InvalidExecutionSite');
  }
  const site = Object.freeze({});
  sites.set(site, {
    identity: {},
    key,
    generation,
    runtimeRevision,
    startupMilliseconds,
    transferMilliseconds,
    maxConcurrentOperations,
    maxConcurrentTransfers,
    maxRetainedBytes,
    maxExecutionBytes,
    reservedRetentionBytes: 0n,
    heldBytes: 0n,
    reservedExecutionBytes: 0n,
    peakRetainedBytes: 0n,
    accepting: true,
    revoked: false,
    active: new Set(),
    activeTransfers: new Set(),
    holdings: new Set(),
    cleanup: new Set(),
  });
  return site;
}

export function executionSiteDescription(site) {
  const state = siteState(site);
  return Object.freeze({
    key: state.key,
    generation: state.generation,
    runtimeRevision: state.runtimeRevision,
    accepting: state.accepting && !state.revoked,
  });
}

// Policy is Host installation, not Program input. Placement keys are stable
// registration keys assigned by the Host. One implementation may be placed at
// several Sites and one Site may host several implementations.
export function prepareExecutionSitePolicy({
  sites: supplied,
  placements = new Map(),
  defaultSites,
  transferProvider,
  maxSites = 64,
  maxPlacements = 256,
} = {}) {
  if (!Array.isArray(supplied) || !count(maxSites) || !count(maxPlacements) ||
      supplied.length === 0 || supplied.length > maxSites ||
      !(placements instanceof Map) ||
      (transferProvider !== undefined &&
        (transferProvider === null ||
         typeof transferProvider.estimate !== 'function' ||
         typeof transferProvider.copy !== 'function' ||
         !text(transferProvider.contract?.version) ||
         !text(transferProvider.contract?.codec) ||
         !text(transferProvider.contract?.preservationRule) ||
         !text(transferProvider.contract?.trustBoundary) ||
         !text(transferProvider.contract?.integrityModel) ||
         !text(transferProvider.contract?.contentDigest) ||
         !text(transferProvider.contract?.logicalIdentity)))) {
    fail('InvalidExecutionSitePolicy');
  }
  const unique = new Set();
  for (const site of supplied) {
    const state = siteState(site);
    const identity = `${state.key}\u0000${state.generation}`;
    if (unique.has(identity)) fail('DuplicateExecutionSiteGeneration');
    unique.add(identity);
  }
  const siteSet = new Set(supplied);
  const selectedDefaults = defaultSites === undefined
    ? [supplied[0]] : [...defaultSites];
  if (selectedDefaults.length === 0 ||
      selectedDefaults.some(site => !siteSet.has(site))) {
    fail('InvalidExecutionSitePolicy');
  }
  const ownedPlacements = new Map();
  let placementCount = selectedDefaults.length;
  for (const [key, values] of placements) {
    if (!text(key) || !Array.isArray(values) || values.length === 0 ||
        values.some(site => !siteSet.has(site)) ||
        new Set(values).size !== values.length) {
      fail('InvalidExecutionSitePolicy');
    }
    placementCount += values.length;
    if (placementCount > maxPlacements) fail('ExecutionSitePlacementLimit');
    ownedPlacements.set(key, Object.freeze([...values]));
  }
  const policy = Object.freeze({});
  policies.set(policy, {
    sites: Object.freeze([...supplied]),
    placements: ownedPlacements,
    defaultSites: Object.freeze(selectedDefaults),
    transferProvider,
    maxPlacements,
  });
  return policy;
}

export function prepareSingleExecutionSitePolicy() {
  const site = createInProcessExecutionSite({
    key: 'in-process-default',
    generation: 0,
    runtimeRevision: 'actql-in-process-site/0.1',
    maxConcurrentOperations: 1,
  });
  return prepareExecutionSitePolicy({sites: [site]});
}

export function installExecutionSites(policy, contributions) {
  const configured = policies.get(policy) ?? fail('ForeignExecutionSitePolicy');
  if (!Array.isArray(contributions) || contributions.length === 0) {
    fail('InvalidExecutionSiteInstallation');
  }
  const placement = new Map();
  let total = 0;
  for (const contribution of contributions) {
    const key = contribution?.managedSelectionKey;
    if (placement.has(contribution)) {
      fail('InvalidExecutionSiteInstallation');
    }
    const selected = text(key)
      ? configured.placements.get(key) ?? configured.defaultSites
      : configured.defaultSites;
    total += selected.length;
    if (total > configured.maxPlacements) fail('ExecutionSitePlacementLimit');
    placement.set(contribution, selected);
  }
  const installation = Object.freeze({});
  installations.set(installation, {policy: configured, placement});
  return installation;
}

export function executionSitePlacements(installation, contribution) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  const placed = state.placement.get(contribution);
  if (!placed) fail('ForeignExecutionSiteContribution');
  return placed;
}

export function executionSiteTransferProvider(installation) {
  return (installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation')).policy.transferProvider;
}

export function executionSiteCandidate({
  installation,
  contribution,
  site,
  task,
  registration,
  inputs,
  durationMilliseconds,
  acceptsSiteTransfer = false,
  capacity = Object.freeze({retainedBytes: 0n, executionBytes: 0n}),
} = {}) {
  const installed = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  if (!installed.placement.get(contribution)?.includes(site) ||
      contribution.registration !== registration ||
      !Number.isSafeInteger(task) || task < 1 || registration == null ||
      !Array.isArray(inputs) || !duration(durationMilliseconds) ||
      !bytes(capacity?.retainedBytes) || !bytes(capacity?.executionBytes)) {
    fail('InvalidExecutionSiteCandidate');
  }
  const destination = siteState(site);
  if (!destination.accepting || destination.revoked) return undefined;
  if (durationMilliseconds === null || destination.startupMilliseconds === null) {
    return Object.freeze({excluded: 'MissingDurationEstimate'});
  }
  if (capacity.retainedBytes > destination.maxRetainedBytes ||
      capacity.executionBytes > destination.maxExecutionBytes) {
    return Object.freeze({excluded: 'ExecutionSiteCapacityEstimateExceeded'});
  }
  let estimated = durationMilliseconds + destination.startupMilliseconds;
  const transfers = [];
  const inputSites = [];
  const provider = installed.policy.transferProvider;
  for (const input of inputs) {
    if (!input || typeof input !== 'object' ||
        !Number.isSafeInteger(input.task) || input.task < 0 ||
        input.material === null || typeof input.material !== 'object' ||
        input.site == null || input.siteMaterial === null ||
        typeof input.siteMaterial !== 'object' ||
        input.materialGeneration === null ||
        typeof input.materialGeneration !== 'object') {
      fail('InvalidExecutionSiteCandidate');
    }
    const source = siteState(input.site);
    inputSites.push(Object.freeze({
      site: input.site,
      identity: source.identity,
      generation: source.generation,
      runtimeRevision: source.runtimeRevision,
    }));
    const independentCopy =
      input.transferMode === 'preserve-to-independent-material';
    if (input.transferMode !== undefined && !independentCopy) {
      fail('InvalidExecutionSiteCandidate');
    }
    if (input.site === site && !independentCopy) continue;
    if (input.task < 1) fail('InvalidExecutionSiteCandidate');
    if (acceptsSiteTransfer !== true) {
      return Object.freeze({excluded: 'UnsupportedTransferRepresentation'});
    }
    if (!provider) return Object.freeze({excluded: 'MissingTransferProvider'});
    if (source.revoked) return Object.freeze({excluded: 'SourceSiteRevoked'});
    const shared = transfers.find(value =>
      sameInputOccurrence(value.input, input));
    const estimate = shared?.estimate ?? provider.estimate(input.siteMaterial);
    if (!estimate) return Object.freeze({excluded: 'MissingTransferEstimate'});
    if (![estimate.transferBytes, estimate.retainedBytes,
      estimate.executionBytes].every(value =>
      typeof value === 'bigint' && value >= 0n)) {
      fail('InvalidTransferEstimate');
    }
    if (destination.transferMilliseconds === null) {
      return Object.freeze({excluded: 'MissingDurationEstimate'});
    }
    if (!shared) estimated += destination.transferMilliseconds;
    transfers.push(Object.freeze({
      input,
      estimate,
      sharedWith: shared?.input,
    }));
  }
  return Object.freeze({
    excluded: undefined,
    installation,
    contribution,
    site,
    siteIdentity: destination.identity,
    siteGeneration: destination.generation,
    runtimeRevision: destination.runtimeRevision,
    task,
    registration,
    inputs: Object.freeze([...inputs]),
    inputSites: Object.freeze(inputSites),
    transfers: Object.freeze(transfers),
    capacity: Object.freeze({...capacity}),
    durationMilliseconds: estimated,
    selectionKey: `${contribution.managedSelectionKey}\u0000${destination.key}\u0000${destination.generation}`,
  });
}

// Binding occurs only after common candidate comparison. It rechecks the exact
// Site generation and placement but does not itself start an operation.
export function bindExecutionSiteCandidate(candidate) {
  if (!candidate || candidate.excluded !== undefined) {
    fail('ExecutionSiteCandidateExcluded', candidate?.excluded);
  }
  const installed = installations.get(candidate.installation) ??
    fail('ForeignExecutionSiteInstallation');
  const state = siteState(candidate.site);
  const provider = installed.policy.transferProvider;
  const inputsCurrent = candidate.inputSites.length === candidate.inputs.length &&
    candidate.inputSites.every((fixed, index) => {
      const source = siteState(candidate.inputs[index].site);
      return fixed.site === candidate.inputs[index].site &&
        source.identity === fixed.identity &&
        source.generation === fixed.generation &&
        source.runtimeRevision === fixed.runtimeRevision &&
        !source.revoked;
    });
  const transfersCurrent = candidate.transfers.every(planned => {
    if (!provider) return false;
    const current = provider.estimate(planned.input.siteMaterial);
    return current !== undefined &&
      current.transferBytes === planned.estimate.transferBytes &&
      current.retainedBytes === planned.estimate.retainedBytes &&
      current.executionBytes === planned.estimate.executionBytes;
  });
  if (!installed.placement.get(candidate.contribution)?.includes(candidate.site) ||
      candidate.contribution.registration !== candidate.registration ||
      state.identity !== candidate.siteIdentity ||
      state.generation !== candidate.siteGeneration ||
      state.runtimeRevision !== candidate.runtimeRevision ||
      !state.accepting || state.revoked || !inputsCurrent ||
      !transfersCurrent) {
    fail('StaleExecutionSiteBinding');
  }
  const binding = Object.freeze({});
  bindings.set(binding, {candidate, site: state, consumed: false});
  return binding;
}

export function startExecutionSiteOperation(binding) {
  const bound = bindings.get(binding) ?? fail('ForeignExecutionSiteBinding');
  if (bound.consumed || !bound.site.accepting || bound.site.revoked ||
      bound.site.identity !== bound.candidate.siteIdentity ||
      bound.site.generation !== bound.candidate.siteGeneration ||
      bound.site.active.size >= bound.site.maxConcurrentOperations ||
      bound.candidate.capacity.retainedBytes >
        bound.site.maxRetainedBytes - bound.site.heldBytes -
          bound.site.reservedRetentionBytes ||
      bound.candidate.capacity.executionBytes >
        bound.site.maxExecutionBytes - bound.site.reservedExecutionBytes) {
    fail('ExecutionSiteAdmissionRejected');
  }
  bound.consumed = true;
  const operation = Object.freeze({});
  const retention = bound.candidate.capacity.retainedBytes;
  const execution = bound.candidate.capacity.executionBytes;
  bound.site.reservedRetentionBytes += retention;
  bound.site.reservedExecutionBytes += execution;
  const peak = bound.site.heldBytes + bound.site.reservedRetentionBytes;
  if (peak > bound.site.peakRetainedBytes) {
    bound.site.peakRetainedBytes = peak;
  }
  operations.set(operation, {
    site: bound.site,
    stopped: false,
    retention,
    execution,
    holding: undefined,
  });
  bound.site.active.add(operation);
  return operation;
}

export function settleExecutionSiteOperation(operation) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  if (state.stopped) return false;
  state.stopped = true;
  state.site.reservedExecutionBytes -= state.execution;
  state.execution = 0n;
  state.site.reservedRetentionBytes -= state.retention;
  state.retention = 0n;
  state.site.active.delete(operation);
  return true;
}

// Convert an admitted task's retained-byte reservation into exactly one Site
// holding. The same allocation is already charged by the authoritative Run
// ledger; this scope only enforces the selected Site's stricter byte ceiling.
export function retainExecutionSiteOperationHolding(operation, value, bytes) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  if (state.stopped || state.holding !== undefined || value == null ||
      !bytesValue(bytes) || bytes > state.retention) {
    fail('ExecutionSiteHoldingRejected');
  }
  state.site.reservedRetentionBytes -= bytes;
  state.retention -= bytes;
  state.site.heldBytes += bytes;
  const holding = Object.freeze({});
  holdings.set(holding, {site: state.site, value, bytes, live: true});
  state.site.holdings.add(holding);
  state.holding = holding;
  return holding;
}

export function executionSiteOperationAvailable(operation) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  return !state.stopped && !state.site.revoked;
}

// A Transfer is not a language task and does not consume a connector's task
// operation slot. It nevertheless remains visible to both Sites until source
// access and destination mutation have independently stopped.
export function startExecutionSiteTransferOperation(
  sourceSite, destinationSite, capacity = Object.freeze({
    retainedBytes: 0n,
    executionBytes: 0n,
  }),
) {
  const source = siteState(sourceSite);
  const destination = siteState(destinationSite);
  if (!bytes(capacity?.retainedBytes) || !bytes(capacity?.executionBytes)) {
    fail('InvalidExecutionSiteTransferCapacity');
  }
  const sameSite = source === destination;
  if (!source.accepting || source.revoked ||
      !destination.accepting || destination.revoked ||
      source.activeTransfers.size >= source.maxConcurrentTransfers ||
      (!sameSite &&
        destination.activeTransfers.size >= destination.maxConcurrentTransfers) ||
      capacity.retainedBytes >
        destination.maxRetainedBytes - destination.heldBytes -
          destination.reservedRetentionBytes ||
      capacity.executionBytes >
        destination.maxExecutionBytes - destination.reservedExecutionBytes) {
    fail('ExecutionSiteTransferAdmissionRejected');
  }
  destination.reservedRetentionBytes += capacity.retainedBytes;
  destination.reservedExecutionBytes += capacity.executionBytes;
  const peak = destination.heldBytes + destination.reservedRetentionBytes;
  if (peak > destination.peakRetainedBytes) {
    destination.peakRetainedBytes = peak;
  }
  const operation = Object.freeze({});
  transferOperations.set(operation, {
    source,
    destination,
    sourceStopped: false,
    destinationStopped: false,
    retention: capacity.retainedBytes,
    execution: capacity.executionBytes,
    holding: undefined,
  });
  source.activeTransfers.add(operation);
  destination.activeTransfers.add(operation);
  return operation;
}

export function settleExecutionSiteTransferSource(operation) {
  const state = transferOperations.get(operation) ??
    fail('ForeignExecutionSiteTransferOperation');
  if (state.sourceStopped) return false;
  state.sourceStopped = true;
  if (state.source !== state.destination || state.destinationStopped) {
    state.source.activeTransfers.delete(operation);
  }
  return true;
}

export function settleExecutionSiteTransferDestination(operation) {
  const state = transferOperations.get(operation) ??
    fail('ForeignExecutionSiteTransferOperation');
  if (state.destinationStopped) return false;
  state.destinationStopped = true;
  state.destination.reservedExecutionBytes -= state.execution;
  state.execution = 0n;
  state.destination.reservedRetentionBytes -= state.retention;
  state.retention = 0n;
  if (state.source !== state.destination || state.sourceStopped) {
    state.destination.activeTransfers.delete(operation);
  }
  return true;
}

export function retainExecutionSiteTransferHolding(operation, value, bytes) {
  const state = transferOperations.get(operation) ??
    fail('ForeignExecutionSiteTransferOperation');
  if (state.destinationStopped || state.holding !== undefined || value == null ||
      !bytesValue(bytes) || bytes > state.retention) {
    fail('ExecutionSiteHoldingRejected');
  }
  state.destination.reservedRetentionBytes -= bytes;
  state.retention -= bytes;
  state.destination.heldBytes += bytes;
  const holding = Object.freeze({});
  holdings.set(holding, {
    site: state.destination,
    value,
    bytes,
    live: true,
  });
  state.destination.holdings.add(holding);
  state.holding = holding;
  return holding;
}

const bytesValue = value => typeof value === 'bigint' && value >= 0n;

export function retainExecutionSiteHolding(site, value, retainedBytes = 0n) {
  const state = siteState(site);
  if (state.revoked || value == null || !bytesValue(retainedBytes) ||
      retainedBytes > state.maxRetainedBytes - state.heldBytes -
        state.reservedRetentionBytes) {
    fail('ExecutionSiteHoldingRejected');
  }
  const holding = Object.freeze({});
  holdings.set(holding, {site: state, value, bytes: retainedBytes, live: true});
  state.holdings.add(holding);
  state.heldBytes += retainedBytes;
  if (state.heldBytes > state.peakRetainedBytes) {
    state.peakRetainedBytes = state.heldBytes;
  }
  return holding;
}

export function releaseExecutionSiteHolding(holding) {
  const held = holdings.get(holding) ?? fail('ForeignExecutionSiteHolding');
  if (!held.live) return false;
  held.live = false;
  held.site.heldBytes -= held.bytes;
  held.site.holdings.delete(holding);
  return true;
}

// A stopped operation and a reclaimed physical generation are separate facts.
// Site-owned cleanup tokens keep teardown pending during the interval where no
// retained holding exists yet (or no holding will ever be published) but an
// admitted operation can still have destination state to reclaim.
export function retainExecutionSiteCleanup(site, value) {
  const state = siteState(site);
  if (value == null) fail('ExecutionSiteCleanupRejected');
  const cleanup = Object.freeze({});
  cleanupResponsibilities.set(cleanup, {site: state, value, live: true});
  state.cleanup.add(cleanup);
  return cleanup;
}

export function releaseExecutionSiteCleanup(cleanup) {
  const owned = cleanupResponsibilities.get(cleanup) ??
    fail('ForeignExecutionSiteCleanup');
  if (!owned.live) return false;
  owned.live = false;
  owned.site.cleanup.delete(cleanup);
  return true;
}

export function beginExecutionSiteTeardown(site) {
  const state = siteState(site);
  state.accepting = false;
  return executionSiteStatus(site);
}

export function revokeExecutionSite(site) {
  const state = siteState(site);
  state.accepting = false;
  state.revoked = true;
  return executionSiteStatus(site);
}

export function executionSiteStatus(site) {
  const state = siteState(site);
  return Object.freeze({
    key: state.key,
    generation: state.generation,
    accepting: state.accepting && !state.revoked,
    revoked: state.revoked,
    activeOperations: state.active.size,
    activeTransfers: state.activeTransfers.size,
    holdings: state.holdings.size,
    cleanupResponsibilities: state.cleanup.size,
    heldBytes: state.heldBytes,
    reservedRetentionBytes: state.reservedRetentionBytes,
    reservedExecutionBytes: state.reservedExecutionBytes,
    peakRetainedBytes: state.peakRetainedBytes,
    teardownComplete: !state.accepting && state.active.size === 0 &&
      state.activeTransfers.size === 0 &&
      state.holdings.size === 0 && state.cleanup.size === 0 &&
      state.heldBytes === 0n && state.reservedRetentionBytes === 0n &&
      state.reservedExecutionBytes === 0n,
  });
}
