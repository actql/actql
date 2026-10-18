'use strict';

// Selected-recipe accounting DATA, never an operational issuer. The actual
// early preload owns the runtime/module original and adopts this finite
// disposition before image capture. Importing this file supplies no scope.
const freeze = Object.freeze, descriptor = Object.getOwnPropertyDescriptor;
const hasOwn = Object.hasOwn, integer = Number.isSafeInteger, array = Array.isArray;
const ownKeys = Reflect.ownKeys;
const NativeError = Error;
const MiB = 1024 * 1024;

// This is a bounded selected-control implementation, not a public API limit,
// normal resource profile, general RSS guarantee or business-Run allowance.
// A retired installation does not replenish the process-lifetime counters.
const limits = freeze({imageFiles: 2048, packages: 64, dependencyEdges: 512,
  sourceBytes: 128 * MiB, imageBytes: 64 * MiB, pathCodeUnits: 4096,
  generations: 1, preparations: 1, projectTasks: 128,
  configurationBytes: 65536, taskBytes: 65536, sourceNodes: 4096,
  sourceDepth: 64, taskWork: 2097152, opaqueCallerAliases: 0,
  // External child backing is separate from the managed/native assumption.
  // The existing journal inspectors enforce combined DB+WAL extent BEFORE
  // creating their isolated copy. The source and copy coexist; their original
  // FDs/Dir/SQLite connection and pending close remain with that child Owner.
  journalInspectionBytes: 64 * MiB, journalInspectionEntries: 100000,
  journalCopyReadBufferBytes: 65536,
  // Actual selected V8 heap ceiling is read by the early runtime original;
  // these distinct native/compiler terms are declared runtime assumptions.
  // They are not obtained from heap usage, a source CID or an unused arena.
  heapCeilingBytes: 5 * 1024 * MiB,
  fixedNativeBytes: 256 * MiB, compilerBytesPerSourceByte: 16,
  moduleNativeBytes: 65536,
  // Forty-eight simultaneous/cumulatively retained external encodings per
  // bounded Task, plus the configuration/registry pair. Managed decoded trees,
  // writer Strings, records and closure backing remain in the heap term.
  preparationExternalBytes: (128 + 2) * 65536 * 48});

const unavailable = () => {
  const cause = new NativeError('NodeInitialControlEnvelopeUnavailable');
  cause.code = 'NodeInitialControlEnvelopeUnavailable';
  throw cause;
};
const own = (value, name) => {
  const field = value === null || typeof value !== 'object' ? undefined : descriptor(value, name);
  if (field === undefined || !hasOwn(field, 'value')) unavailable();
  return field.value;
};

function declareInitialControlPhaseEnvelope(heapCeilingBytes) {
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
  const bytes = heapCeilingBytes + nativeBytes + sourceBackingBytes +
    limits.preparationExternalBytes;
  if (!integer(bytes)) unavailable();
  return freeze({limits, heapCeilingBytes, compilerBytes, moduleNativeBytes, sourceBackingBytes,
    nativeBytes, preparationExternalBytes: limits.preparationExternalBytes, bytes,
    journalInspection: freeze({pinnedSourceBytes: limits.journalInspectionBytes,
      isolatedCopyBytes: limits.journalInspectionBytes,
      readBufferBytes: limits.journalCopyReadBufferBytes,
      names: limits.journalInspectionEntries, sequential: true,
      lifetime: 'same-original-physical-child-until-its-close-acknowledgement'}),
    lifetime: 'original-process-and-escaped-module-lifetime'});
}

function inspectInitialControlPhaseEnvelope(inventory, declaration, runtimeOriginal) {
  if (declaration?.limits !== limits) unavailable();
  // The generated recipe must describe this actual selected backend, not just
  // a similarly sized image graph. This comparison is DATA correspondence;
  // only the real early preload retains the runtime/module original and can
  // operationally adopt the declaration. It authenticates no caller factory.
  const engine = own(inventory, 'engine');
  for (const name of ['node', 'v8', 'openssl', 'platform', 'arch', 'eager']) {
    if (own(engine, name) !== own(runtimeOriginal, name)) unavailable();
  }
  const libraries = own(engine, 'libraries'), originalLibraries = own(runtimeOriginal, 'libraries');
  const names = ownKeys(originalLibraries), declaredNames = ownKeys(libraries);
  if (names.length > 64 || declaredNames.length !== names.length) unavailable();
  for (let index = 0; index < names.length; index++) {
    const name = names[index];
    if (typeof name !== 'string' || declaredNames[index] !== name ||
        own(libraries, name) !== own(originalLibraries, name)) unavailable();
  }
  const packages = own(inventory, 'packages');
  if (!array(packages) || packages.length > limits.packages) unavailable();
  let files = 0, sourceBytes = 0, edges = 0;
  function images(values) {
    if (!array(values) || values.length > limits.imageFiles - files) unavailable();
    files += values.length;
    for (let index = 0; index < values.length; index++) {
      const value = values[index], bytes = own(value, 'bytes'), path = own(value, 'path');
      if (!integer(bytes) || bytes < 0 || bytes > limits.imageBytes ||
          bytes > limits.sourceBytes - sourceBytes ||
          typeof path !== 'string' || path.length > limits.pathCodeUnits) unavailable();
      sourceBytes += bytes;
    }
  }
  function dependencies(values) {
    if (!array(values) || values.length > limits.dependencyEdges - edges) unavailable();
    edges += values.length;
  }
  images(own(inventory, 'images'));
  dependencies(own(inventory, 'dependencies'));
  for (let index = 0; index < packages.length; index++) {
    images(own(packages[index], 'images'));
    dependencies(own(packages[index], 'dependencies'));
  }
  const publicNode = own(inventory, 'publicNode');
  if (publicNode !== null) {
    images(own(publicNode, 'images'));
    dependencies(own(publicNode, 'dependencies'));
  }
  // The actual facts select only a member of the already declared finite
  // runtime/control recipe. They authenticate no operational admission.
  return freeze({limits, images: files, packages: packages.length, dependencyEdges: edges,
    sourceBytes, declaration, runtimeOriginal});
}

module.exports = freeze({declareInitialControlPhaseEnvelope, inspectInitialControlPhaseEnvelope});
