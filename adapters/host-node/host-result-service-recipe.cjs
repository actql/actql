'use strict';

// Finite support for the separately selected Node Result/publication service.
// This DATA cannot supply a Host original, backed amount or authorization.
const freeze = Object.freeze, assign = Object.assign, create = Object.create;
const descriptor = Object.getOwnPropertyDescriptor, own = Object.hasOwn;
const {isProxy} = require('node:util').types;
const record = value => freeze(assign(create(null), value));
const unavailable = () => {
  throw Object.assign(new Error('HostResultPublicationUnavailable'), {code: 'HostResultPublicationUnavailable'});
};
const fields = freeze(['directory', 'storeAuthorityCid', 'capacityBytes',
  'maxObjectBytes', 'maxObjects', 'maxContractNodes', 'maxContractDepth']);
const storeWireBytes = 10000000;
// Structure support follows the already selected bounded object wire, rather
// than an unrelated 10000-node rejection. This recipe issues no memory grant.
const store = record({capacityBytes: 512 * 1024 * 1024, maxObjectBytes: storeWireBytes,
  maxObjects: 10000, maxContractNodes: storeWireBytes, maxContractDepth: 64});
const result = record({maxResults: 10, maxCollectedRows: 10000, maxRowWireBytes: 1048576,
  maxReadWireBytes: 10 * 1024 * 1024, maxBatchRows: 1000, maxValueNodes: 1000000,
  maxValueTextBytes: 10000000, maxValueDepth: 64, maxColumns: 100});
const phases = record({
  shared: freeze(['same selected managed runtime/module/lazy compiler and native controls',
    'same filesystem/crypto implementation, main-thread stack and allocator service',
    'same original Journal SQLite facilities and selected native directory image']),
  retained: freeze(['original initial/Project/configuration and checked Program/parameters/request aliases',
    'same Journal connections/VM/cache/WAL/request records and prepared exclusion',
    'same selected Source/Compute Run and retained DAG/output aliases, counted once',
    'file Store object/schema/contract/index/attempt/delivery and cleanup inventories',
    'encoded publication payloads, hashes, bounded FD buffers and original reader frames',
    'captured callbacks, asynchronous flights, failed constructors and escaped aliases']),
  publication: freeze(['same Run publication/evidence and metadata encoding alongside retained DAG output',
    'original file writers/sync/link/rename/directory duties and confirmed commit or Unknown']),
  read: freeze(['original authorized Result read and delivery attempt, incremental digest/frame/output buffers',
    'retained published objects and metadata beside returned/escaped reader aliases']),
  composition: 'shared once + all retained initial/Journal/selected Run/Store aliases + active publication/read + pending cleanup',
  excluded: freeze(['Content/Source/Model/Effect or external I/O purpose',
    'key creation or first-initialization/Account/Result permission']),
});

function selectHostResultStoreArguments(options, directory) {
  if (options === null || typeof options !== 'object' || isProxy(options)) unavailable();
  const names = Reflect.ownKeys(options);
  if (names.length !== fields.length && names.length !== fields.length + 1) unavailable();
  const selected = create(null);
  for (const name of names) {
    if (!fields.includes(name) && name !== 'privateEvidenceKey') unavailable();
    const property = descriptor(options, name);
    if (property === undefined || !own(property, 'value')) unavailable();
    selected[name] = property.value;
  }
  // Preserve the actual installed directory/authority binding. Selected
  // policy quantities remain DATA and never supply physical backing.
  if (selected.directory !== directory || typeof selected.storeAuthorityCid !== 'string' ||
      !/^sha256:[0-9a-f]{64}$/u.test(selected.storeAuthorityCid)) unavailable();
  // Validate selected policy DATA, not equality with one recipe's defaults.
  // The exact service/Journal/directory binding above remains the owner; these
  // numbers cannot issue physical backing or replace Store admission. Contract
  // decoding crosses Core Int; checked representation bounds remain finite.
  if (!Number.isSafeInteger(selected.capacityBytes) || selected.capacityBytes < 0 ||
      ['maxObjectBytes', 'maxObjects', 'maxContractNodes'].some(name =>
        !Number.isSafeInteger(selected[name]) || selected[name] < 1 || selected[name] > 2147483647) ||
      !Number.isSafeInteger(selected.maxContractDepth) || selected.maxContractDepth < 1 ||
      selected.maxContractDepth > store.maxContractDepth) unavailable();
  // Key authority is independent. This ordinary no-key purpose must not copy
  // the legacy create-on-absence fallback or accept an arbitrary key buffer.
  if (selected.privateEvidenceKey !== undefined) unavailable();
  return record(selected);
}

// Representation validation for DATA already projected by the fixed callback
// from the same checked Program/current request. This does not admit a Run,
// allocate rows or replace provider/Store capacity. Collection/read support is
// separate: maxCollectedRows bounds all(), not publication or rows().
function validOriginalResultPublicationExtent(resultCount, maxRows, maxContractBytes, minimumResults) {
  return Number.isSafeInteger(resultCount) && resultCount >= minimumResults &&
    Number.isSafeInteger(maxRows) && maxRows >= 0 && maxRows <= 2147483647 &&
    Number.isSafeInteger(maxContractBytes) && maxContractBytes >= 1 && maxContractBytes <= 2147483647;
}

function declareHostResultServiceRecipe(control, journal, sourceCompute, sourceFreeCompute) {
  if ([control, journal, sourceCompute, sourceFreeCompute].some(value =>
    value === null || typeof value !== 'object' || isProxy(value)) || journal.sharedControl !== control) unavailable();
  return record({kind: 'selected-node-local-result-publication-service', sharedControl: control,
    journal, sourceCompute, sourceFreeCompute, store, result, phases,
    // These guard this single installation constructor and checked Run
    // association. They are not Host-lifetime read/Store-operation quotas.
    installationAttempts: 1, runAttempts: 1,
    selectStoreArguments: selectHostResultStoreArguments,
    refilledOnClose: false, numericalBackingClaim: false, allocationSuccessGuaranteed: false});
}

// Correspondence with actual imported facilities, not resource issuance.
const facilityFields = record({
  promises: freeze(['lstat', 'link', 'mkdir', 'open', 'opendir', 'readdir', 'readFile',
    'rename', 'rm', 'rmdir', 'unlink', 'writeFile']),
  crypto: freeze(['createCipheriv', 'createDecipheriv', 'createHash', 'randomBytes', 'randomUUID']),
  buffer: freeze(['alloc', 'allocUnsafe', 'allocUnsafeSlow', 'byteLength', 'concat', 'from', 'isBuffer']),
});
module.exports = {declareHostResultServiceRecipe, facilityFields, validOriginalResultPublicationExtent};
freeze(module.exports);
