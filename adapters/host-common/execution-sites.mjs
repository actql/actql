// Environment-facing handles for portable MoonBit Site control. This module
// binds Connector placements and opaque physical values; it does not decide
// mutable Site lifecycle, capacity, or terminal state.
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
const maximumBytes = 9223372036854775807n;
const duration = value => value === null ||
  (typeof value === 'bigint' && value >= 0n && value <= maximumBytes);
const bytes = value => typeof value === 'bigint' &&
  value >= 0n && value <= maximumBytes;
const siteState = site => sites.get(site) ?? fail('ForeignExecutionSite');
const sameInputOccurrence = (left, right) =>
  left.task === right.task &&
  left.material === right.material &&
  left.site === right.site &&
  left.siteMaterial === right.siteMaterial &&
  left.materialGeneration === right.materialGeneration;
const controlMethods = [
  'create', 'available', 'revoked', 'capacitySupports', 'bindingCurrent',
  'startOperation', 'operationAvailable', 'settleOperation',
  'retainOperationHolding', 'startTransfer', 'transferAvailable',
  'settleTransferSource', 'settleTransferDestination',
  'retainTransferHolding', 'retainHolding', 'releaseHolding',
  'retainCleanup', 'releaseCleanup', 'beginTeardown', 'revoke', 'status',
  'selectCandidate', 'planCandidate', 'managedCandidateFallback',
  'failedOperationAction',
];

function checkedControl(control) {
  if (control === null || typeof control !== 'object' ||
      controlMethods.some(name => typeof control[name] !== 'function')) {
    fail('MissingExecutionSiteControl');
  }
  return control;
}

function bindSiteControl(state, control) {
  if (state.control !== undefined) {
    if (state.control !== control) fail('ForeignExecutionSiteControl');
    return;
  }
  const handle = control.create(Object.freeze({
    key: state.key,
    generation: state.generation,
    runtimeRevision: state.runtimeRevision,
    maxConcurrentOperations: state.maxConcurrentOperations,
    maxConcurrentTransfers: state.maxConcurrentTransfers,
    maxRetainedBytes: state.maxRetainedBytes,
    maxExecutionBytes: state.maxExecutionBytes,
  }));
  if (handle === undefined || handle === null) fail('InvalidExecutionSite');
  state.control = control;
  state.handle = handle;
  if (state.pendingRevocation) control.revoke(handle);
  else if (state.pendingTeardown) control.beginTeardown(handle);
}

function controlled(state) {
  if (state.control === undefined || state.handle === undefined) {
    fail('UnboundExecutionSite');
  }
  return state;
}

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
      !count(maxConcurrentOperations) || maxConcurrentOperations === 0 ||
      !count(maxConcurrentTransfers) || maxConcurrentTransfers === 0 ||
      !bytes(maxRetainedBytes) || !bytes(maxExecutionBytes)) {
    fail('InvalidExecutionSite');
  }
  const site = Object.freeze({});
  sites.set(site, {
    identity: {}, key, generation, runtimeRevision, startupMilliseconds,
    transferMilliseconds, maxConcurrentOperations, maxConcurrentTransfers,
    maxRetainedBytes, maxExecutionBytes, control: undefined,
    handle: undefined, pendingTeardown: false, pendingRevocation: false,
  });
  return site;
}

export function executionSiteDescription(site) {
  const state = siteState(site);
  const accepting = state.control === undefined
    ? !state.pendingTeardown && !state.pendingRevocation
    : state.control.available(state.handle);
  return Object.freeze({
    key: state.key,
    generation: state.generation,
    runtimeRevision: state.runtimeRevision,
    accepting,
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

export function installExecutionSites(policy, contributions, suppliedControl) {
  const configured = policies.get(policy) ?? fail('ForeignExecutionSitePolicy');
  const control = checkedControl(suppliedControl);
  if (!Array.isArray(contributions) || contributions.length === 0) {
    fail('InvalidExecutionSiteInstallation');
  }
  for (const site of configured.sites) bindSiteControl(siteState(site), control);
  const placement = new Map();
  let total = 0;
  for (const contribution of contributions) {
    const key = contribution?.managedSelectionKey;
    if (placement.has(contribution)) fail('InvalidExecutionSiteInstallation');
    const selected = text(key)
      ? configured.placements.get(key) ?? configured.defaultSites
      : configured.defaultSites;
    total += selected.length;
    if (total > configured.maxPlacements) fail('ExecutionSitePlacementLimit');
    placement.set(contribution, selected);
  }
  const installation = Object.freeze({});
  installations.set(installation, {policy: configured, placement, control});
  return installation;
}

export function executionSitePlacements(installation, contribution) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  const placed = state.placement.get(contribution);
  if (!placed) fail('ForeignExecutionSiteContribution');
  return placed;
}

export function classifyManagedExecutionSiteFallback(
  installation,
  retainedInputCount,
  exclusionCodes,
) {
  const state = installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation');
  if (!count(retainedInputCount) || !Array.isArray(exclusionCodes) ||
      exclusionCodes.some(code => !Number.isSafeInteger(code))) {
    fail('InvalidManagedCandidateFallback');
  }
  const result = state.control.managedCandidateFallback(
    retainedInputCount,
    exclusionCodes,
  );
  if (!Number.isSafeInteger(result) || result < 0 || result > 3) {
    fail('InvalidManagedCandidateFallback');
  }
  return result;
}

// Candidate facts are produced by environment placement adapters, while the
// portable Site control owns the cost and stable-key decision.
export function selectExecutionSiteCandidateIndex(
  candidates,
  {
    invalid = 'InvalidExecutionSiteCandidateSet',
    duplicate = 'DuplicateExecutionSiteSelectionKey',
  } = {},
) {
  if (!Array.isArray(candidates)) fail(invalid);
  if (candidates.length === 0) return -1;
  let control;
  for (const candidate of candidates) {
    if (candidate === null || typeof candidate !== 'object' ||
        candidate.excluded !== undefined) {
      fail(invalid);
    }
    const state = controlled(siteState(candidate.site));
    if (control !== undefined && control !== state.control) fail(invalid);
    control = state.control;
  }
  const selected = control.selectCandidate(
    candidates.map(candidate => candidate.durationMilliseconds),
    candidates.map(candidate => candidate.selectionKey),
  );
  if (selected === -3) fail(duplicate);
  if (!Number.isSafeInteger(selected) || selected < 0 ||
      selected >= candidates.length) {
    fail(invalid);
  }
  return selected;
}

export function executionSiteTransferProvider(installation) {
  return (installations.get(installation) ??
    fail('ForeignExecutionSiteInstallation')).policy.transferProvider;
}

// The physical adapter receives only the opaque MoonBit Site authority. Site
// generation, revocation, and capacity remain owned by the portable control.
export function createExecutionSiteRemoteJournal(site, remoteControl) {
  const state = controlled(siteState(site));
  if (remoteControl === null || typeof remoteControl !== 'object' ||
      typeof remoteControl.createJournal !== 'function') {
    fail('MissingRemoteSiteControl');
  }
  return remoteControl.createJournal(state.handle);
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
  const destination = controlled(siteState(site));
  if (!destination.control.available(destination.handle)) return undefined;
  const capacitySupported = destination.control.capacitySupports(
    destination.handle,
    capacity.retainedBytes,
    capacity.executionBytes,
  );
  const transfers = [];
  const inputSites = [];
  const provider = installed.policy.transferProvider;
  const transferRequired = [];
  const sharedTransfer = [];
  const sourceRevoked = [];
  const estimateAvailable = [];
  const transferBytes = [];
  const retainedBytes = [];
  const executionBytes = [];
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
    const source = controlled(siteState(input.site));
    if (source.control !== installed.control) {
      fail('ForeignExecutionSiteControl');
    }
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
    if (input.site === site && !independentCopy) {
      transferRequired.push(false);
      sharedTransfer.push(false);
      sourceRevoked.push(false);
      estimateAvailable.push(false);
      transferBytes.push(0n);
      retainedBytes.push(0n);
      executionBytes.push(0n);
      continue;
    }
    if (input.task < 1) fail('InvalidExecutionSiteCandidate');
    const shared = transfers.find(value =>
      sameInputOccurrence(value.input, input));
    const estimate = shared?.estimate ?? provider?.estimate(input.siteMaterial);
    if (estimate !== undefined &&
        ![estimate.transferBytes, estimate.retainedBytes,
          estimate.executionBytes].every(value => bytes(value))) {
      fail('InvalidTransferEstimate');
    }
    transferRequired.push(true);
    sharedTransfer.push(shared !== undefined);
    sourceRevoked.push(source.control.revoked(source.handle));
    estimateAvailable.push(estimate !== undefined);
    transferBytes.push(estimate?.transferBytes ?? 0n);
    retainedBytes.push(estimate?.retainedBytes ?? 0n);
    executionBytes.push(estimate?.executionBytes ?? 0n);
    if (estimate !== undefined) {
      transfers.push(Object.freeze({input, estimate, sharedWith: shared?.input}));
    }
  }
  const plan = destination.control.planCandidate(Object.freeze({
    durationMilliseconds,
    startupMilliseconds: destination.startupMilliseconds,
    capacitySupported,
    acceptsSiteTransfer,
    transferProviderAvailable: provider !== undefined,
    transferMilliseconds: destination.transferMilliseconds,
    transferRequired: Object.freeze(transferRequired),
    sharedTransfer: Object.freeze(sharedTransfer),
    sourceRevoked: Object.freeze(sourceRevoked),
    estimateAvailable: Object.freeze(estimateAvailable),
    transferBytes: Object.freeze(transferBytes),
    retainedBytes: Object.freeze(retainedBytes),
    executionBytes: Object.freeze(executionBytes),
  }));
  if (!Array.isArray(plan) || plan.length !== 2 ||
      !Number.isSafeInteger(plan[0]) || typeof plan[1] !== 'bigint') {
    fail('InvalidExecutionSiteCandidate');
  }
  const exclusions = [undefined, 'MissingDurationEstimate',
    'ExecutionSiteCapacityEstimateExceeded',
    'UnsupportedTransferRepresentation', 'MissingTransferProvider',
    'SourceSiteRevoked', 'MissingTransferEstimate'];
  if (plan[0] !== 0) {
    const excluded = exclusions[plan[0]];
    if (excluded === undefined) fail('InvalidExecutionSiteCandidate');
    return Object.freeze({excluded, exclusionCode: plan[0]});
  }
  return Object.freeze({
    excluded: undefined,
    exclusionCode: 0,
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
    durationMilliseconds: plan[1],
    selectionKey: `${contribution.managedSelectionKey}\u0000${destination.key}\u0000${destination.generation}`,
  });
}

// Binding occurs only after common candidate comparison. It rechecks exact
// placement, estimate, and MoonBit-owned Site state without starting I/O.
export function bindExecutionSiteCandidate(candidate) {
  if (!candidate || candidate.excluded !== undefined) {
    fail('ExecutionSiteCandidateExcluded', candidate?.excluded);
  }
  const installed = installations.get(candidate.installation) ??
    fail('ForeignExecutionSiteInstallation');
  const state = controlled(siteState(candidate.site));
  const provider = installed.policy.transferProvider;
  const inputsCurrent = candidate.inputSites.length === candidate.inputs.length &&
    candidate.inputSites.every((fixed, index) => {
      const source = controlled(siteState(candidate.inputs[index].site));
      return source.control === installed.control &&
        fixed.site === candidate.inputs[index].site &&
        source.identity === fixed.identity &&
        source.generation === fixed.generation &&
        source.runtimeRevision === fixed.runtimeRevision &&
        source.control.bindingCurrent(
          source.handle,
          fixed.generation,
          fixed.runtimeRevision,
        );
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
      state.control !== installed.control ||
      state.identity !== candidate.siteIdentity ||
      !state.control.bindingCurrent(
        state.handle,
        candidate.siteGeneration,
        candidate.runtimeRevision,
      ) || !inputsCurrent || !transfersCurrent) {
    fail('StaleExecutionSiteBinding');
  }
  const binding = Object.freeze({});
  bindings.set(binding, {candidate, state, consumed: false});
  return binding;
}

export function startExecutionSiteOperation(binding) {
  const bound = bindings.get(binding) ?? fail('ForeignExecutionSiteBinding');
  if (bound.consumed) fail('ExecutionSiteAdmissionRejected');
  const handle = bound.state.control.startOperation(
    bound.state.handle,
    bound.candidate.capacity.retainedBytes,
    bound.candidate.capacity.executionBytes,
  );
  if (handle === undefined || handle === null) {
    fail('ExecutionSiteAdmissionRejected');
  }
  bound.consumed = true;
  const operation = Object.freeze({});
  operations.set(operation, {control: bound.state.control, handle});
  return operation;
}

export function settleExecutionSiteOperation(operation) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  return state.control.settleOperation(state.handle);
}

export function failedExecutionSiteOperationAction(
  operation,
  cleanupRequired,
  cleanupStopped,
  operationSettled,
) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  const action = state.control.failedOperationAction(
    cleanupRequired,
    cleanupStopped,
    operationSettled,
  );
  if (!Number.isSafeInteger(action) || action < 0 || action > 2) {
    fail('InvalidExecutionSiteFailureAction');
  }
  return action;
}

export function retainExecutionSiteOperationHolding(operation, value, valueBytes) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  if (value == null || !bytes(valueBytes)) fail('ExecutionSiteHoldingRejected');
  const handle = state.control.retainOperationHolding(state.handle, valueBytes);
  if (handle === undefined || handle === null) {
    fail('ExecutionSiteHoldingRejected');
  }
  const holding = Object.freeze({});
  holdings.set(holding, {control: state.control, handle, value});
  return holding;
}

export function executionSiteOperationAvailable(operation) {
  const state = operations.get(operation) ?? fail('ForeignExecutionSiteOperation');
  return state.control.operationAvailable(state.handle);
}

export function startExecutionSiteTransferOperation(
  sourceSite,
  destinationSite,
  capacity = Object.freeze({retainedBytes: 0n, executionBytes: 0n}),
) {
  const source = controlled(siteState(sourceSite));
  const destination = controlled(siteState(destinationSite));
  if (source.control !== destination.control ||
      !bytes(capacity?.retainedBytes) || !bytes(capacity?.executionBytes)) {
    fail(source.control !== destination.control
      ? 'ForeignExecutionSiteControl'
      : 'InvalidExecutionSiteTransferCapacity');
  }
  const handle = source.control.startTransfer(
    source.handle,
    destination.handle,
    capacity.retainedBytes,
    capacity.executionBytes,
  );
  if (handle === undefined || handle === null) {
    fail('ExecutionSiteTransferAdmissionRejected');
  }
  const operation = Object.freeze({});
  transferOperations.set(operation, {control: source.control, handle});
  return operation;
}

export function executionSiteTransferOperationAvailable(operation) {
  const state = transferOperations.get(operation) ??
    fail('ForeignExecutionSiteTransferOperation');
  return state.control.transferAvailable(state.handle);
}

export function settleExecutionSiteTransferSource(operation) {
  const state = transferOperations.get(operation) ??
    fail('ForeignExecutionSiteTransferOperation');
  return state.control.settleTransferSource(state.handle);
}

export function settleExecutionSiteTransferDestination(operation) {
  const state = transferOperations.get(operation) ??
    fail('ForeignExecutionSiteTransferOperation');
  return state.control.settleTransferDestination(state.handle);
}

export function retainExecutionSiteTransferHolding(
  operation,
  value,
  valueBytes,
) {
  const state = transferOperations.get(operation) ??
    fail('ForeignExecutionSiteTransferOperation');
  if (value == null || !bytes(valueBytes)) fail('ExecutionSiteHoldingRejected');
  const handle = state.control.retainTransferHolding(state.handle, valueBytes);
  if (handle === undefined || handle === null) {
    fail('ExecutionSiteHoldingRejected');
  }
  const holding = Object.freeze({});
  holdings.set(holding, {control: state.control, handle, value});
  return holding;
}

export function retainExecutionSiteHolding(site, value, retainedBytes = 0n) {
  const state = controlled(siteState(site));
  if (value == null || !bytes(retainedBytes)) fail('ExecutionSiteHoldingRejected');
  const handle = state.control.retainHolding(state.handle, retainedBytes);
  if (handle === undefined || handle === null) {
    fail('ExecutionSiteHoldingRejected');
  }
  const holding = Object.freeze({});
  holdings.set(holding, {control: state.control, handle, value});
  return holding;
}

export function releaseExecutionSiteHolding(holding) {
  const held = holdings.get(holding) ?? fail('ForeignExecutionSiteHolding');
  return held.control.releaseHolding(held.handle);
}

export function retainExecutionSiteCleanup(site, value) {
  const state = controlled(siteState(site));
  if (value == null) fail('ExecutionSiteCleanupRejected');
  const handle = state.control.retainCleanup(state.handle);
  if (handle === undefined || handle === null) {
    fail('ExecutionSiteCleanupRejected');
  }
  const cleanup = Object.freeze({});
  cleanupResponsibilities.set(cleanup, {control: state.control, handle, value});
  return cleanup;
}

export function releaseExecutionSiteCleanup(cleanup) {
  const owned = cleanupResponsibilities.get(cleanup) ??
    fail('ForeignExecutionSiteCleanup');
  return owned.control.releaseCleanup(owned.handle);
}

export function beginExecutionSiteTeardown(site) {
  const state = siteState(site);
  state.pendingTeardown = true;
  if (state.control !== undefined) state.control.beginTeardown(state.handle);
  return executionSiteStatus(site);
}

export function revokeExecutionSite(site) {
  const state = siteState(site);
  state.pendingTeardown = true;
  state.pendingRevocation = true;
  if (state.control !== undefined) state.control.revoke(state.handle);
  return executionSiteStatus(site);
}

export function executionSiteStatus(site) {
  const state = siteState(site);
  if (state.control === undefined) {
    return Object.freeze({
      key: state.key,
      generation: state.generation,
      accepting: !state.pendingTeardown && !state.pendingRevocation,
      revoked: state.pendingRevocation,
      activeOperations: 0,
      activeTransfers: 0,
      holdings: 0,
      cleanupResponsibilities: 0,
      heldBytes: 0n,
      reservedRetentionBytes: 0n,
      reservedExecutionBytes: 0n,
      peakRetainedBytes: 0n,
      teardownComplete: state.pendingTeardown,
    });
  }
  const values = state.control.status(state.handle);
  if (!Array.isArray(values) || values.length !== 11 ||
      values.some(value => typeof value !== 'bigint')) {
    fail('InvalidExecutionSiteStatus');
  }
  return Object.freeze({
    key: state.key,
    generation: state.generation,
    accepting: values[0] === 1n,
    revoked: values[1] === 1n,
    activeOperations: Number(values[2]),
    activeTransfers: Number(values[3]),
    holdings: Number(values[4]),
    cleanupResponsibilities: Number(values[5]),
    heldBytes: values[6],
    reservedRetentionBytes: values[7],
    reservedExecutionBytes: values[8],
    peakRetainedBytes: values[9],
    teardownComplete: values[10] === 1n,
  });
}
