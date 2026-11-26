'use strict';

// Selected-recipe accounting DATA, never an operational issuer. The actual
// early preload owns the runtime/module original and adopts this finite
// disposition before image capture. Importing this file supplies no scope.
const freeze = Object.freeze, descriptor = Object.getOwnPropertyDescriptor;
const hasOwn = Object.hasOwn, integer = Number.isSafeInteger as (value: unknown) => value is number, array = Array.isArray;
const ownKeys = Reflect.ownKeys;
const NativeError = Error;
const MiB = 1024 * 1024;
const mockAnswerReadLimits = freeze({contractDepth:64,contractNodes:4096,contractTextBytes:65536,
  maxBytes:65536,maxDepth:64,maxEntries:128,maxMembers:256,maxNodes:4096,
  maxTasks:128,maxWork:2097152,valueDepth:64,valueNodes:4096,valueTextBytes:65536});

// This is a bounded selected-control implementation, not a public API limit,
// normal resource profile, general RSS guarantee or business-Run allowance.
// A retired installation does not replenish the process-lifetime counters.
const limits = freeze({imageFiles: 2048, packages: 64, dependencyEdges: 512,
  sourceBytes: 128 * MiB, imageBytes: 64 * MiB, pathCodeUnits: 4096,
  generations: 1, preparations: 1, projectTasks: 128,
  configurationBytes: 65536, taskBytes: 65536, sourceNodes: 4096,
  sourceDepth: 64, taskWork: 2097152, opaqueCallerAliases: 0,
  // Installation-time definition DATA only. Each answer selection rereads its
  // original Task and retains a separate answer document. Neither document,
  // checked value nor a typed mock Provider supplies Model invocation funds.
  mockAnswerDocuments: 128, mockAnswerTaskRereads: 128, mockAnswerReadLimits,
  // External child backing is separate from the managed/native assumption.
  // The existing journal inspectors enforce combined DB+WAL extent BEFORE
  // creating their isolated copy. The source and copy coexist; their original
  // FDs/Dir/SQLite connection and pending close remain with that child Owner.
  journalInspectionBytes: 64 * MiB, journalInspectionEntries: 100000,
  journalCopyReadBufferBytes: 65536, journalMarkerBackingBytes: MiB,
  // Actual selected V8 heap ceiling is read by the early runtime original;
  // these distinct native/compiler terms are declared runtime assumptions.
  // They are not obtained from heap usage, a source CID or an unused arena.
  heapCeilingBytes: 5 * 1024 * MiB,
  fixedNativeBytes: 256 * MiB, compilerBytesPerSourceByte: 16,
  moduleNativeBytes: 65536,
  // Forty-eight simultaneous/cumulatively retained external encodings per
  // bounded Task/configuration/registry and per additional Task reread/answer
  // document. No old Task allowance is reassigned to these extra originals.
  // Managed decoded/checked trees, writer Strings, original records, Provider
  // definitions, clocks/callbacks and escaped closures share the one heap.
  preparationExternalBytes: (128 + 2 + 128 + 128) * 65536 * 48});

const unavailable: () => never = () => {
  const cause = new NativeError('NodeInitialControlEnvelopeUnavailable') as NodeJS.ErrnoException;
  cause.code = 'NodeInitialControlEnvelopeUnavailable';
  throw cause;
};
const own = (value: unknown, name: PropertyKey): unknown => {
  const field = value === null || typeof value !== 'object' ? undefined : descriptor(value, name);
  if (field === undefined || !hasOwn(field, 'value')) unavailable();
  return field.value;
};

function declareInitialControlPhaseEnvelope(heapCeilingBytes: unknown) {
  if (!integer(heapCeilingBytes) || heapCeilingBytes <= 0 ||
      heapCeilingBytes > limits.heapCeilingBytes) unavailable();
  // Declare the WHOLE supported recipe before reading its generated inventory.
  // Smaller actual source facts do not retroactively issue capacity or create
  // free credit. Buffer slabs are conservatively retained per image through
  // process end, including a separate small backing and lookahead allocation.
  const compilerBytes = limits.sourceBytes * limits.compilerBytesPerSourceByte;
  const moduleNativeBytes = limits.imageFiles * limits.moduleNativeBytes;
  const sourceBackingBytes = limits.sourceBytes + limits.imageFiles * 16384;
  const nativeBytes = limits.fixedNativeBytes + compilerBytes + moduleNativeBytes;
  const journalExternalBytes = limits.journalCopyReadBufferBytes + limits.journalMarkerBackingBytes;
  const bytes = heapCeilingBytes + nativeBytes + sourceBackingBytes +
    limits.preparationExternalBytes + journalExternalBytes;
  if (!integer(bytes)) unavailable();
  return freeze({limits, heapCeilingBytes, compilerBytes, moduleNativeBytes, sourceBackingBytes,
    nativeBytes, preparationExternalBytes: limits.preparationExternalBytes,
    mockAnswerPreparation:freeze({documents:limits.mockAnswerDocuments,
      taskRereads:limits.mockAnswerTaskRereads,readLimits:mockAnswerReadLimits,
      additionalExternalBytes:256*65536*48,
      lifetime:'same-original-preparation-and-all-escaped-definition-aliases',
      coversInvocation:false}),
    journalExternalBytes, bytes,
    journalInspection: freeze({pinnedSourceBytes: limits.journalInspectionBytes,
      isolatedCopyBytes: limits.journalInspectionBytes,
      readBufferBytes: limits.journalCopyReadBufferBytes,
      names: limits.journalInspectionEntries, sequential: true,
      lifetime: 'same-original-physical-child-until-its-close-acknowledgement'}),
    lifetime: 'original-process-and-escaped-module-lifetime'});
}

function declareOrdinaryInitialControlPhaseEnvelope(heapCeilingBytes: unknown) {
  const base = declareInitialControlPhaseEnvelope(heapCeilingBytes);
  // Ordinary import has no eager-bytecode original. Retain a separate finite
  // lazy compilation/tiering/cache disposition for the selected package code
  // and all escaped functions through process end. This is the selected
  // runtime premise, not a measured free-credit or universal V8/RSS claim.
  const lazyCompilerBytes = limits.sourceBytes * 64;
  const bytes = base.bytes - base.compilerBytes + lazyCompilerBytes;
  if (!integer(bytes)) unavailable();
  return freeze({...base, compilerBytes:lazyCompilerBytes,
    nativeBytes:base.nativeBytes-base.compilerBytes+lazyCompilerBytes,bytes,
    recipe:'ordinary-installed-public-prefix',compilation:'ordinary-lazy',eager:false});
}

type PhaseDeclaration = {readonly limits?: unknown};
type OrdinaryPhaseDeclaration = PhaseDeclaration & {
  readonly recipe?: unknown;
  readonly eager?: unknown;
  readonly compilation?: unknown;
};

function inspectInitialControlPhaseEnvelope<Declaration extends PhaseDeclaration, Runtime>(
  inventory: unknown, declaration: Declaration, runtimeOriginal: Runtime) {
  return inspectPhaseEnvelope(inventory, declaration, runtimeOriginal, false);
}

function inspectOrdinaryInitialControlPhaseEnvelope<Declaration extends OrdinaryPhaseDeclaration, Runtime>(
  inventory: unknown, declaration: Declaration, runtimeOriginal: Runtime, externalPackages: readonly unknown[] = []) {
  if (declaration?.recipe !== 'ordinary-installed-public-prefix' || declaration.eager !== false ||
      declaration.compilation !== 'ordinary-lazy') unavailable();
  return inspectPhaseEnvelope(inventory, declaration, runtimeOriginal, true, externalPackages);
}

function matchesEngine(engine: unknown, runtimeOriginal: unknown) {
  for (const name of ['node', 'v8', 'openssl', 'platform', 'arch', 'eager']) {
    if (own(engine, name) !== own(runtimeOriginal, name)) return false;
  }
  const libraries = own(engine, 'libraries'), originalLibraries = own(runtimeOriginal, 'libraries');
  if (libraries === null || typeof libraries !== 'object' || array(libraries)) unavailable();
  const names = ownKeys(originalLibraries as object), declaredNames = ownKeys(libraries);
  if (names.length > 64 || declaredNames.length !== names.length) return false;
  for (let index = 0; index < names.length; index++) {
    const name = names[index];
    if (typeof name !== 'string' || declaredNames[index] !== name ||
        own(libraries, name) !== own(originalLibraries, name)) return false;
  }
  return true;
}

function requireEngine(inventory: unknown, runtimeOriginal: unknown, ordinary: boolean) {
  if (inventory === null || typeof inventory !== 'object') unavailable();
  if (!ordinary || descriptor(inventory, 'engineProfiles') === undefined) {
    if (!matchesEngine(own(inventory, ordinary ? 'ordinaryEngine' : 'engine'), runtimeOriginal)) unavailable();
    return;
  }
  // A combined artifact must attest the actual ordinary process. Its legacy
  // top-level record represents only one producer and does not fill a gap.
  const profiles = own(inventory, 'engineProfiles');
  if (!array(profiles) || profiles.length === 0 || profiles.length > 4) unavailable();
  let matched = false;
  for (let index = 0; index < profiles.length; index++) {
    if (!matchesEngine(own(own(profiles, index), 'ordinaryEngine'), runtimeOriginal)) continue;
    if (matched) unavailable();
    matched = true;
  }
  if (!matched) unavailable();
}

function inspectPhaseEnvelope<Declaration extends PhaseDeclaration, Runtime>(
  inventory: unknown, declaration: Declaration, runtimeOriginal: Runtime, ordinary: boolean,
  externalPackages: readonly unknown[] = []) {
  if (declaration?.limits !== limits) unavailable();
  // Engine facts describe the actual selected backend before image capture.
  // The operational lifetime and image checks still belong to the original
  // loader. This comparison does not authenticate a caller factory.
  requireEngine(inventory, runtimeOriginal, ordinary);
  const packages = own(inventory, 'packages');
  if (!array(packages) || packages.length + externalPackages.length > limits.packages) unavailable();
  let files = 0, sourceBytes = 0, edges = 0;
  function images(values: unknown) {
    if (!array(values) || values.length > limits.imageFiles - files) unavailable();
    files += values.length;
    for (let index = 0; index < values.length; index++) {
      const value = values[index], originalBytes = own(value, 'bytes'), path = own(value, 'path');
      if (!integer(originalBytes) || originalBytes < 0) unavailable();
      const releaseProperty = descriptor(value, 'npmRelease');
      let bytes = originalBytes;
      if (releaseProperty !== undefined) {
        if (!hasOwn(releaseProperty, 'value') || path !== 'package.json') unavailable();
        const releaseBytes = own(releaseProperty.value, 'bytes');
        if (!integer(releaseBytes) || releaseBytes < 0) unavailable();
        bytes = bytes > releaseBytes ? bytes : releaseBytes;
      }
      if (!integer(bytes) || bytes < 0 || bytes > limits.imageBytes ||
          bytes > limits.sourceBytes - sourceBytes ||
          typeof path !== 'string' || path.length > limits.pathCodeUnits) unavailable();
      sourceBytes += bytes;
    }
  }
  function dependencies(values: unknown) {
    if (!array(values) || values.length > limits.dependencyEdges - edges) unavailable();
    edges += values.length;
  }
  images(own(inventory, 'images'));
  dependencies(own(inventory, 'dependencies'));
  for (let index = 0; index < packages.length; index++) {
    images(own(packages[index], 'images'));
    dependencies(own(packages[index], 'dependencies'));
  }
  for (const external of externalPackages) {
    images(own(external, 'images'));
    dependencies(own(external, 'dependencies'));
  }
  const publicNode = own(inventory, 'publicNode');
  if (publicNode !== null) {
    images(own(publicNode, 'images'));
    dependencies(own(publicNode, 'dependencies'));
  }
  // The actual facts select only a member of the already declared finite
  // runtime/control recipe. They authenticate no operational admission.
  return freeze({limits, images: files, packages: packages.length + externalPackages.length, dependencyEdges: edges,
    sourceBytes, declaration, runtimeOriginal});
}

const exported = module.exports = {declareInitialControlPhaseEnvelope, inspectInitialControlPhaseEnvelope,
  declareOrdinaryInitialControlPhaseEnvelope, inspectOrdinaryInitialControlPhaseEnvelope};
freeze(module.exports);
export = exported as Readonly<typeof exported>;
