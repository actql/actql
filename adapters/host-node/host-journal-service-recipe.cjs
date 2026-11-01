'use strict';

// Fixed support selection for the separately adopted Host/Journal service.
// This module is DATA/argument selection, not an operational issuer. Only the
// actual installed prefix may bind the complete service to its startup/native
// originals and the same Host generation before covered acquisition.
const {types} = require('node:util');
const {isAbsolute} = require('node:path');
const {sql} = require('./host-journal-schema-support.cjs');
const freeze = Object.freeze, descriptor = Object.getOwnPropertyDescriptor;
const own = Object.hasOwn, keys = Reflect.ownKeys, isProxy = types.isProxy;
const create = Object.create, assign = Object.assign;
const NativeError = Error;
const MiB = 1024 * 1024;
const record = value => freeze(assign(create(null), value));
const unavailable = () => {
  const cause = new NativeError('HostJournalServiceArgumentsUnavailable');
  cause.code = 'HostJournalServiceArgumentsUnavailable';
  throw cause;
};

// These restrict this selected service, not the public language or an
// unselected Journal. They are neither backed amounts nor success promises.
// Database/source extent and record limits retain the existing Journal
// defaults. SQL limits bound each operation and genuinely retained statements;
// primary and optional observation connections still have separate lifetimes.
const journalDatabaseBytes = 64 * MiB;
const journalInspectionBytes = 64 * MiB;
// One metadata/statement envelope is necessary within BOTH existing durable
// and inspection policies. It is not another allocation grant or a prep Ledger.
const journalParameterBytes = Math.min(journalDatabaseBytes, journalInspectionBytes);
const journal = record({maxRecords: 100000, maxInspectionEntries: 100000,
  maxInspectionBytes: journalInspectionBytes, maxDatabaseBytes: journalDatabaseBytes,
  maxWalFrames: 268435456,
  // Metadata is bounded by the selected native statement operand envelope.
  // The journal still sums every operand against that envelope before bind;
  // these per-object checks do not allocate it independently per field.
  maxRunDefinitionWireBytes: journalParameterBytes,
  primarySqlLimits: record({maxPreparedStatements: 1024,
    maxSqlBytes: 8192, maxTotalSqlBytes: 32 * MiB}),
  primaryExecutionLimits: record({maxParameters: 64,
    maxParameterBytes: journalParameterBytes, maxResultRows: 100000}),
  primarySchemaLimits: record({maxSchemaBytes: 65536, maxSchemaEntries: 128,
    maxSchemaPages: 256, maxWalFrames: 131072}),
  primarySchemaSqlSupport: sql,
  sourceOperationLimits: record({maxRecords: 100000, maxWireBytes: 65536}),
});
const ownershipBounds = record({maxWireBytes: 16384, maxDirectoryEntries: 64});
const ownershipDirectoryLimits = record({maxEntries: 64, maxNameBytes: 1024,
  maxWork: 65536, maxInspections: 128});
const rootFormatDirectoryLimits = record({maxEntries: 1, maxNameBytes: 1024,
  maxWork: 4096, maxInspections: 2});
const directoryLimits = record({maxEntries: journal.maxInspectionEntries,
  maxNameBytes: 1024, maxWork: 268435456, maxInspections: 32,
  maxImageBytes: 8 * MiB});

// Service coverage describes the selected stock facility and finite supported
// work. It is distinct from the conditional per-allocation demand calculator
// and from numerical fields that require an actual reserved/backed extent.
// Internal allocator alternatives stay behind the same native receiver chain;
// no live zone pointer or exclusive whole-heap reservation is asserted here.
const phases = record({
  ownershipLease: record({descriptors: 2, anchorBytes: 36,
    lifetime: 'same Store owner before journal inspection through original child cleanup',
    domains: freeze(['same delivered Local Files native image/loader and fixed opaque root/lease wrappers',
      'original directory and regular-file descriptors, nonblocking flock, fixed UUID bytes and exact fstat/openat identity',
      'original Store token and independently retained constructor/close failure custody'])}),
  shared: record({lifetime: 'same-selected-process-and-all-escaped-module-aliases',
    domains: freeze(['same managed runtime and lazy compiled modules',
      'SQLite initialization, default-or-created zone, classes/regions and allocator controls',
      'selected main-thread native/managed stack and runtime control',
      'same builtin filesystem and crypto implementation',
      'one selected directory native module, loader/linker and retained native controls'])}),
  cold: record({connections: 1, sourceAndCopyEachBytes: journal.maxInspectionBytes,
    domains: freeze(['original DB/WAL descriptors, committed prefix and isolated copy',
      'bounded schema and table/index record worklists, page/WAL buffers and names',
      'same read-only native connection, own-DDL parser/schema/VM/cache and result aliases',
      'path conversion, temporary directory, current callbacks and partial cleanup'])}),
  writable: record({connections: 2, domains: freeze([
    'each original connection/schema/cache/Pager/WAL mapping and memory temporary Btree',
    'bounded SQL/parser/prepare old-new backing, statements, bindings, VM and result history',
    'native allocation/reallocation/free operations and retained larger/cache/control originals',
    'managed records, external encodings/ArrayBuffers, cursors, callbacks and escaped outputs',
    'original epoch random/HMAC work, bounded marker and Store exclusion metadata',
    'transaction/CAS/COMMIT state and independently pending native/Store cleanup'])}),
  composition: 'shared + retained aliases + ownership-lease + max(closed-cold, writable-primary + writable-observation)',
  phaseBarrier: 'original copy connection, source/output descriptors and temporary copy acknowledged closed',
  excludedPurposes: freeze(['publication or Content/Result payload', 'business Source or Compute',
    'Model or Effect', 'network or external VM', 'new key/Account/first-initialization authority']),
});

function selectHostJournalServiceArguments(options, directoryInspection,
  inspectionTemporaryDirectory, assertCurrent) {
  if (options === null || typeof options !== 'object' || isProxy(options) ||
      typeof directoryInspection !== 'function' || typeof assertCurrent !== 'function' ||
      typeof inspectionTemporaryDirectory !== 'string' ||
      inspectionTemporaryDirectory.length === 0 || inspectionTemporaryDirectory.length > 4096 ||
      !isAbsolute(inspectionTemporaryDirectory) || inspectionTemporaryDirectory.includes('\0')) unavailable();
  // The actual prefix covers and owns this fixed Host-created packet before
  // its first enumeration. This selector cannot authenticate arbitrary input.
  assertCurrent();
  const names = keys(options);
  if (names.length > 3) unavailable();
  const retained = create(null);
  for (let index = 0; index < names.length; index++) {
    const name = names[index];
    if (name !== 'updateOriginalControl' && name !== 'submissionEpochTtlMs' &&
        name !== 'submissionEpochNow') unavailable();
    const property = descriptor(options, name);
    if (property === undefined || !own(property, 'value')) unavailable();
    // The ordinary selected path does not acquire caller clock/fault closures.
    // Their unselected private diagnostic path is unchanged.
    if (name !== 'updateOriginalControl' && property.value !== undefined) unavailable();
    retained[name] = property.value;
  }
  assertCurrent();
  return record({...journal, ...retained,
    primaryCurrent: assertCurrent, primaryDirectoryInspection: directoryInspection,
    inspectionTemporaryDirectory});
}

function declareHostJournalServiceRecipe(sharedControl) {
  if (sharedControl === null || typeof sharedControl !== 'object' || isProxy(sharedControl)) unavailable();
  // Retain the same process/control declaration; do not copy its heap/native
  // quantities into another allowance. This recipe cannot certify or issue
  // its own actual all-phase service or numerical backing.
  return record({kind: 'selected-node-host-journal-service-recipe', sharedControl,
    journal, ownershipBounds, ownershipDirectoryLimits, rootFormatDirectoryLimits,
    directoryLimits, phases, selectArguments: selectHostJournalServiceArguments,
    installationAttempts: 1, ownershipLeaseDescriptors: 2, ownershipLeaseBytes: 36,
    writableConnections: 2, isolatedCopyConnections: 1,
    coldBeforeWritable: true, refilledOnClose: false,
    numericalBackingClaim: false, allocationSuccessGuaranteed: false});
}

module.exports = {declareHostJournalServiceRecipe};
freeze(module.exports);
