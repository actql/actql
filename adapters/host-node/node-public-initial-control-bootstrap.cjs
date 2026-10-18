'use strict';

// Actual installed public-package prefix. This instance is constructed by its
// fixed delivery module, not by a caller's factory, receipt or options. It is
// deliberately separate from the preload recipe: no eager bytecode, preload
// ancestor, frozen-intrinsic history or earlier application work is claimed.
const {createRequire} = require('node:module');
const {join, dirname} = require('node:path');
const {getHeapStatistics} = require('node:v8');
const {isMainThread,threadId} = require('node:worker_threads');
const {isProxy} = require('node:util').types;
const {Buffer} = require('node:buffer');
const {open: openSourceFile} = require('node:fs/promises');
const processOriginal = require('node:process');
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const own = Object.hasOwn, freeze = Object.freeze;
const {createInitialControlInstallationOwner} = require('./initial-control-installation-owner.cjs');
const {declareOrdinaryInitialControlPhaseEnvelope, inspectOrdinaryInitialControlPhaseEnvelope}
  = require('./initial-control-phase-envelope.cjs');
const {declareSourceManagedPhaseEnvelope} = require('./source-managed-phase-envelope.cjs');
const fail = code => {throw Object.assign(new TypeError(code), {code});};
const unavailable = () => fail('NodeInitialControlAdmissionUnavailable');
const inputUnavailable = () => fail('NodeInitialControlInputUnavailable');
const field = (value,name) => {
  const entry = value === undefined ? undefined : descriptor(value,name);
  if (entry === undefined || !own(entry,'value')) unavailable();
  return entry.value;
};
const localRoot = join(__dirname,'..','..');
const delivery = module.parent;
const loadingModule = module;
let state, firstFailure, preparation, intake, closed = false;
// These originals belong to this actual installed prefix, not to an exported
// factory accepting a runtime label, caller callback, capacity or trust flag.
let sourceInstallation;
const sourceChildren = new WeakMap();
const sourceUnavailable = () => fail('SourceManagedPreparationUnavailable');
function sourceOriginal(original, held, allowClosing = false) {
  const entry = sourceInstallation;
  if (entry === undefined || entry.original !== original || entry.originals !== held ||
      entry.closed || (!allowClosing && entry.closing)) sourceUnavailable();
  return entry;
}
function sourceCurrent(original, held) {
  const entry = sourceOriginal(original, held);
  assertSamePreparation(held);
  apply(state.source.validator, state.namespace, [held]);
  return entry;
}
function sourceReceipt(entry, receipt) {
  if (entry.receipt === undefined || entry.receipt.original !== receipt) sourceUnavailable();
  return entry.receipt;
}
function sourceFailure(entry, cause) {
  const error = freeze({cause});
  entry.firstError ??= error;
  entry.latestError = error;
}
function sourceStatus(entry) {
  return freeze({pending: !entry.closed, fdPending: entry.file !== undefined,
    childrenPending: entry.children.some(child => !child.stopped || !child.released),
    physicalBackingReleased: false});
}
async function closeSource(entry) {
  entry.closing = true;
  if (entry.closeFlight !== undefined) return entry.closeFlight;
  const flight = (async () => {
    if (entry.receipt !== undefined && !entry.receipt.finished) return sourceStatus(entry);
    if (entry.children.some(child => !child.stopped || !child.released || child.flight !== undefined)) {
      return sourceStatus(entry);
    }
    if (entry.openFlight !== undefined) {
      try {await entry.openFlight;} catch (cause) {sourceFailure(entry, cause);}
    }
    if (entry.file !== undefined) {
      try {
        if (entry.fileClose === undefined) entry.fileClose = entry.file.close;
        if (typeof entry.fileClose !== 'function' || await apply(entry.fileClose, entry.file, []) === false) {
          sourceUnavailable();
        }
        entry.file = undefined;
        entry.fileClose = entry.fileRead = entry.fileStat = undefined;
      } catch (cause) {sourceFailure(entry, cause);return sourceStatus(entry);}
    }
    entry.closed = true;
    // Body backings and escaped byte aliases remain charged for their actual
    // process lifetime. This managed retirement never returns byte credit.
    entry.bundle = undefined;
    return sourceStatus(entry);
  })();
  entry.closeFlight = flight;
  try {return await flight;} finally {if (entry.closeFlight === flight) entry.closeFlight = undefined;}
}
async function prepareSource(held) {
  if (state === undefined || sourceInstallation !== undefined || state.source === undefined ||
      Object.values(state.source).some(value => typeof value !== 'function')) sourceUnavailable();
  assertSamePreparation(held);
  const original = freeze(Object.create(null));
  const entry = sourceInstallation = {original, originals: held, bundle: undefined,
    closing: false, closed: false, children: [], receipt: undefined,
    file: undefined, fileClose: undefined, fileRead: undefined, fileStat: undefined,
    fileIdentity: undefined, openFlight: undefined, closeFlight: undefined,
    firstError: undefined, latestError: undefined, backings: [], lookahead: undefined};
  try {
    // Real distinct ArrayBuffers, not an unused arena lent to another allocator.
    // The two original full-document acquisitions retain these independent
    // backings even though the same file/managed declarations are shared.
    for (let ordinal = 0; ordinal < state.sourceEnvelope.limits.sourceOccurrences; ordinal++) {
      entry.backings.push(Buffer.alloc(state.sourceEnvelope.limits.responseBytes));
    }
    entry.lookahead = Buffer.alloc(1);
    sourceCurrent(original, held);
    await apply(state.source.prepare, state.namespace, [held, original]);
    sourceCurrent(original, held);
    const bundle = apply(state.source.read, state.namespace, [held]);
    if (bundle === null || typeof bundle !== 'object' || !Object.isFrozen(bundle) ||
        typeof bundle.dataPath !== 'string' || bundle.dataPath.length > 65536 ||
        !Array.isArray(bundle.sources) || bundle.sources.length !== entry.backings.length) sourceUnavailable();
    entry.bundle = bundle;
    sourceCurrent(original, held);
    return original;
  } catch (cause) {
    entry.closing = true;
    sourceFailure(entry, cause);
    const carrier = new Error('SourceManagedInstallationCleanupPending', {cause});
    carrier.code = 'SourceManagedInstallationCleanupPending';
    carrier.cleanupHandle = freeze({status: () => sourceStatus(entry), retry: () => closeSource(entry)});
    throw carrier;
  }
}
function assertSourceRequest(entry, derived) {
  sourceCurrent(entry.original, entry.originals);
  // Only the captured actual Host namespace can follow its own bounded
  // clone/preparation chain back to the original pending SDK packet.
  const request = apply(state.source.request, state.namespace, [entry.originals, derived]);
  if (entry.receipt === undefined || entry.receipt.request !== request || entry.receipt.finished) sourceUnavailable();
  return request;
}
function sourceFileIdentity(value) {
  return [value.dev, value.ino, value.size, value.mtimeNs, value.ctimeNs];
}
async function assertSourceFile(entry) {
  const observed = await apply(entry.fileStat, entry.file, [{bigint: true}]);
  const identity = sourceFileIdentity(observed);
  if (!observed.isFile() || observed.size > BigInt(state.sourceEnvelope.limits.responseBytes)) sourceUnavailable();
  if (entry.fileIdentity === undefined) entry.fileIdentity = identity;
  else if (identity.some((value, ordinal) => value !== entry.fileIdentity[ordinal])) sourceUnavailable();
}
async function readSourceBytes(entry, child) {
  assertSourceRequest(entry, child.derived);
  if (!child.admitted || child.stopped || child.released || child.readAttempted) sourceUnavailable();
  child.readAttempted = true;
  const flight = (async () => {
    if (entry.openFlight === undefined) {
      entry.openFlight = (async () => {
        // This happens only at the existing authorized read consumer, never
        // during Project/connection metadata preparation or a Source snapshot.
        entry.file = await openSourceFile(entry.bundle.dataPath, 'r');
        entry.fileClose = entry.file.close;
        entry.fileRead = entry.file.read;
        entry.fileStat = entry.file.stat;
        if (![entry.fileClose, entry.fileRead, entry.fileStat].every(value => typeof value === 'function')) {
          sourceUnavailable();
        }
      })();
    }
    await entry.openFlight;
    assertSourceRequest(entry, child.derived);
    await assertSourceFile(entry);
    assertSourceRequest(entry, child.derived);
    let used = 0;
    const backing = entry.backings[child.ordinal];
    while (used < backing.length) {
      const {bytesRead} = await apply(entry.fileRead, entry.file, [backing, used, backing.length - used, used]);
      assertSourceRequest(entry, child.derived);
      if (!Number.isSafeInteger(bytesRead) || bytesRead < 0 || bytesRead > backing.length - used) sourceUnavailable();
      if (bytesRead === 0) break;
      used += bytesRead;
    }
    if (used === backing.length) {
      const {bytesRead} = await apply(entry.fileRead, entry.file, [entry.lookahead, 0, 1, used]);
      assertSourceRequest(entry, child.derived);
      if (bytesRead !== 0) sourceUnavailable();
    }
    await assertSourceFile(entry);
    assertSourceRequest(entry, child.derived);
    const bytes = backing.subarray(0, used);
    const sibling = entry.children.find(value => value !== child && value.bytes !== undefined);
    if (sibling !== undefined && !bytes.equals(sibling.bytes)) sourceUnavailable();
    child.bytes = bytes;
    return bytes;
  })();
  child.flight = flight;
  try {return await flight;} catch (cause) {sourceFailure(entry, cause);throw cause;}
  finally {if (child.flight === flight) child.flight = undefined;}
}
function prepareSourceRead(original, held, derived, declaration) {
  const entry = sourceCurrent(original, held);
  assertSourceRequest(entry, derived);
  const ordinal = entry.bundle.sources.findIndex(value => value.declaration === declaration);
  if (ordinal < 0 || entry.children.some(value => value.ordinal === ordinal)) sourceUnavailable();
  const originalSource = freeze(Object.create(null));
  const child = {entry, ordinal, derived, originalSource, portsTaken: false,
    admitted: false, stopped: false, released: false, readAttempted: false,
    flight: undefined, bytes: undefined, usage: undefined};
  entry.children.push(child);
  sourceChildren.set(originalSource, child);
  return freeze({originalSource,
    readOriginalBytes() {return readSourceBytes(entry, child);},
    close() {child.released = true;return freeze({pending: child.flight !== undefined});},
    status() {return freeze({pending: !child.stopped || !child.released || child.flight !== undefined,
      fdPending: entry.file !== undefined, physicalBackingReleased: false});}});
}
function prepareOriginalSourceChildPorts(original) {
  // A missing original is refused without inspecting a caller reference.
  const child = sourceChildren.get(original);
  if (child === undefined || child.portsTaken) return null;
  assertSourceRequest(child.entry, child.derived);
  child.portsTaken = true;
  const envelope = state.sourceEnvelope, partition = envelope.occurrencePartitions[child.ordinal];
  const quotas = [BigInt(Math.floor(envelope.limits.sourceWork / envelope.limits.sourceOccurrences)),
    BigInt(partition.responses), BigInt(partition.responses), BigInt(partition.responseBackingBytes),
    BigInt(partition.responseBackingBytes), 0n];
  const current = () => {
    if (child.stopped || child.entry.closing || child.entry.receipt?.finished) return 1;
    try {assertSourceRequest(child.entry, child.derived);return 0;}
    catch {return 1;}
  };
  return freeze({
    status(operation) {
      if (operation === 2) {
        if (!child.admitted || child.stopped || child.usage === undefined || child.flight !== undefined) return -42;
        child.stopped = true;
        return 0;
      }
      if (current() !== 0) return -42;
      if (operation === 0) {
        if (child.admitted) return -42;
        child.admitted = true;
      } else if (operation !== 1) return -42;
      return 0;
    },
    limit(ordinal) {return Number.isInteger(ordinal) && ordinal >= 0 && ordinal < quotas.length ? quotas[ordinal] : -42n;},
    report(planning, attempts, holdings, transferred, uncertain, reservedTransfer,
      heldBytes, reservedRetention, reservedExecution, peakRetention) {
      // Core supplies this usage; these counters never acknowledge the FD or
      // return the actual process-lived response ArrayBuffers to a sibling.
      if (!child.admitted || child.stopped || ![planning, attempts, holdings].every(Number.isSafeInteger) ||
          planning < 0 || attempts < 0 || holdings < 0 || BigInt(planning) > quotas[0] ||
          BigInt(attempts) > quotas[1] || BigInt(holdings) > quotas[2] ||
          ![transferred, uncertain, reservedTransfer, heldBytes, reservedRetention, reservedExecution, peakRetention]
            .every(value => typeof value === 'bigint' && value >= 0n) ||
          transferred + uncertain + reservedTransfer > quotas[3] ||
          heldBytes + reservedRetention > quotas[4] || peakRetention > quotas[4] || reservedExecution > quotas[5]) return -42;
      child.usage = freeze({planning, attempts, holdings, transferred, uncertain, reservedTransfer,
        heldBytes, reservedRetention, reservedExecution, peakRetention});
      return 0;
    },
  });
}
const inputLimits = freeze({maxProperties:40,maxNodes:40,maxDepth:4,
  maxStringCodeUnits:4096,maxTotalStringCodeUnits:8192,maxArrayItems:0,maxOpaqueAliases:0,maxWork:65536});
// Capture actual prefix-time descriptors without evaluating a global accessor
// (Node's standard lazy Buffer binding is an accessor). They stay original
// observations, not evidence that arbitrary prior application code was covered.
const prefixIntrinsics = [];
const intrinsicSource = Function.prototype.toString;
for (const [receiver,names] of [[Object,['getOwnPropertyDescriptor','hasOwn','freeze','create']],
  [Reflect,['apply','ownKeys']],[Array,['isArray']],[globalThis,['Object','Reflect','Array','Promise','Buffer']]]) {
  for (const name of names) prefixIntrinsics.push(freeze({receiver,name,property:descriptor(receiver,name)}));
}
freeze(prefixIntrinsics);
function assertSupportedIntrinsics() {
  if (isProxy(intrinsicSource) || apply(intrinsicSource,intrinsicSource,[]) !==
      'function toString() { [native code] }') unavailable();
  for (const held of prefixIntrinsics) {
    const value=held.property?.value;
    if (typeof value !== 'function') continue;
    if (isProxy(value) || apply(intrinsicSource,value,[]) !==
        `function ${held.name}() { [native code] }`) unavailable();
  }
  // This exact Node 22.22 global lazy accessor is implementation input, not a
  // caller getter protocol. Refuse substitutions before invoking it, then
  // require its original value to be the selected node:buffer constructor.
  const buffer=descriptor(globalThis,'Buffer');
  if (typeof buffer?.get !== 'function' || typeof buffer?.set !== 'function' ||
      isProxy(buffer.get) || isProxy(buffer.set) ||
      apply(intrinsicSource,buffer.get,[]) !== 'get() {\n      return _Buffer;\n    }' ||
      apply(intrinsicSource,buffer.set,[]) !== 'set(value) {\n      _Buffer = value;\n    }' ||
      apply(buffer.get,globalThis,[]) !== require('node:buffer').Buffer) unavailable();
}
function assertIntrinsicsCurrent() {
  for (const held of prefixIntrinsics) {
    const current=descriptor(held.receiver,held.name), original=held.property;
    if (current === undefined || original === undefined || current.value !== original.value ||
        current.get !== original.get || current.set !== original.set ||
        current.writable !== original.writable || current.enumerable !== original.enumerable ||
        current.configurable !== original.configurable) unavailable();
  }
}

function sameOriginals(left,right) {
  return left.host === right.host && left.installation === right.installation &&
    left.generation === right.generation && left.supplier === right.supplier &&
    left.moduleLifetime === right.moduleLifetime;
}
function assertPrefixCurrent() {
  if (firstFailure !== undefined) throw firstFailure.cause;
  if (state === undefined) unavailable();
  if (processOriginal !== process || loadingModule !== require.cache[__filename] ||
      loadingModule.exports !== table || delivery !== require.cache[delivery.filename] ||
      processOriginal.execArgv.length !== 0 || processOriginal.env.NODE_OPTIONS !== undefined) unavailable();
  assertIntrinsicsCurrent();
  state.images.assertCurrent();
}
function assertSamePreparation(held) {
  if (preparation === undefined || closed || !sameOriginals(held,preparation.originals)) inputUnavailable();
  assertPrefixCurrent();
  apply(state.validator,state.namespace,[held]);
}
const operational = freeze({
  prepare(held,raw) {
    assertPrefixCurrent();
    if (preparation !== undefined || intake === undefined || intake.raw !== raw || intake.consumed) inputUnavailable();
    apply(state.validator,state.namespace,[held]);
    // Retain original scope/candidate before any subsequent fallible current
    // observation. This process recipe cannot be replenished by Host close.
    preparation = {originals:held,input:intake.snapshot.packet};
    intake.consumed = true;
    intake.raw = undefined;
  },
  assertCurrent: assertSamePreparation,
  readInput(held) {assertSamePreparation(held);return preparation.input;},
  readAsset(held,path) {assertSamePreparation(held);return state.images.readAsset(path);},
  close(held) {
    if (preparation === undefined || !sameOriginals(held,preparation.originals)) inputUnavailable();
    // Called only by the same Owner after child ACKs and preparation alias
    // release. Images, lazy compiled code/native domains and escaped outputs
    // remain process-lived; this observation returns no business capacity.
    preparation.input = undefined;
    intake = undefined;
    closed = true;
    return freeze({pending:false});
  },
});
const owner = createInitialControlInstallationOwner(operational);
function connectInitialControlHostPreparation(kind,raw) {
  // One fixed own-DATA selector belongs to this prefix's finite scaffolding,
  // not complete packet admission. It invokes no getter/Proxy trap and keeps
  // existing unselected routes independent of Local image/preparation failure.
  if (kind === 'connect') {
    if (raw === null || typeof raw !== 'object' || isProxy(raw)) return undefined;
    const mode = descriptor(raw,'mode');
    if (mode === undefined || !own(mode,'value') || mode.value !== 'local') return undefined;
    const endpoint=descriptor(raw,'endpoint');
    if (endpoint !== undefined && own(endpoint,'value') && endpoint.value !== undefined) return undefined;
  } else if (kind !== 'open' || raw !== undefined) inputUnavailable();
  assertPrefixCurrent();
  if (preparation !== undefined || intake !== undefined) inputUnavailable();
  // The actual selected prefix's finite runtime/packet envelope precedes this
  // FIRST enumeration. Reader bounds do not retroactively fund acquisition.
  const snapshot = kind === 'open' ? freeze({packet:freeze(Object.create(null)),originalReferences:freeze([])}) :
    apply(state.reader,state.namespace,[raw,inputLimits]);
  const packet = snapshot.packet;
  if (snapshot.originalReferences.length !== 0) inputUnavailable();
  if (kind === 'connect') {
    const keys = Reflect.ownKeys(packet);
    if (keys.length !== 3 || !keys.includes('mode') || !keys.includes('installation') || !keys.includes('profile') ||
        packet.mode !== 'local' || packet.profile !== 'mock' || packet.installation === null ||
        typeof packet.installation !== 'object') inputUnavailable();
    const names = Reflect.ownKeys(packet.installation);
    if (names.length !== 1 || names[0] !== 'directory' ||
        typeof packet.installation.directory !== 'string' || packet.installation.directory.length === 0) inputUnavailable();
  }
  intake = {raw,snapshot,consumed:false};
  // A synchronous refusal or partial begin retains intake under this same
  // prefix. Never clear/reissue merely because a Promise rejected.
  return apply(state.consumer,state.namespace,[kind,raw]);
}
const table = module.exports = {
  selectedInitialControlHostPreparation:connectInitialControlHostPreparation,
  beginInitialControlInstallation(originals,raw) {return owner.begin(originals,raw);},
  assertInitialControlInstallationCurrent(scope,originals) {return owner.assertCurrent(scope,originals);},
  readInitialControlInstallationInput(scope,originals) {return owner.readInput(scope,originals);},
  readInitialControlInstallationAsset(scope,originals,path) {return owner.readAsset(scope,originals,path);},
  prepareSourceManagedInstallation: prepareSource,
  assertSourceManagedInstallationCurrent(original, originals) {sourceCurrent(original, originals);},
  beforeSourceSnapshot(original, originals, kind, input, options) {
    const entry = sourceCurrent(original, originals);
    if (entry.receipt !== undefined) sourceUnavailable();
    // First ownKeys/clone is covered by the separately declared Source phase,
    // not an initial-control credit or admission of the resulting DATA.
    const snapshot = apply(state.source.input, state.namespace,
      [kind, input, options, state.sourceEnvelope.inputLimits]);
    if (snapshot.originalReferences.length !== 0) sourceUnavailable();
    const receipt = freeze(Object.create(null));
    entry.receipt = {original: receipt, snapshot, body: undefined, request: undefined, finished: false};
    return receipt;
  },
  bindSourceSnapshot(original, originals, receipt, body) {
    const entry = sourceCurrent(original, originals), producer = sourceReceipt(entry, receipt);
    if (producer.body !== undefined || producer.finished || body === null ||
        typeof body !== 'object' || isProxy(body) || !Object.isFrozen(body) ||
        body.kind !== producer.snapshot.packet.kind || body.input !== producer.snapshot.packet.input) sourceUnavailable();
    producer.body = body;
  },
  bindSourceRequest(original, originals, receipt, body, request) {
    const entry = sourceCurrent(original, originals), producer = sourceReceipt(entry, receipt);
    if (producer.body !== body || producer.request !== undefined || producer.finished ||
        request === null || typeof request !== 'object' || isProxy(request)) sourceUnavailable();
    // The receiving Host's fixed transform binding must later recover this
    // same original, rather than identifying a clone by fields or intent CID.
    producer.request = request;
  },
  sourceIntentCid(original, originals, receipt, body) {
    const entry = sourceCurrent(original, originals), producer = sourceReceipt(entry, receipt);
    if (producer.body !== body || producer.finished) sourceUnavailable();
    const identity = apply(state.source.intent, state.namespace, [originals, original, body]);
    sourceCurrent(original, originals);
    return identity;
  },
  finishSourceProducer(original, originals, receipt, terminal) {
    const entry = sourceOriginal(original, originals, true), producer = sourceReceipt(entry, receipt);
    if (terminal !== 'returned' && terminal !== 'failed') sourceUnavailable();
    producer.finished = true;
    producer.snapshot = undefined;
    // Children retain their actual request/byte duties; producer settlement is
    // not their logical stop, physical FD close or returned backing credit.
  },
  closeSourceManagedInstallation(original, originals) {
    return closeSource(sourceOriginal(original, originals, true));
  },
  prepareSourceManagedRead: prepareSourceRead,
  prepareOriginalSourceChildPorts,
};
Object.setPrototypeOf(table,null);
// Same synchronous receiver handoff for the Host namespace while it loads;
// no callable table can pass assertPrefixCurrent until initialization closes.
freeze(table);
try {
  if (module.isPreloading !== false || processOriginal.execArgv.length !== 0 ||
      isMainThread !== true || threadId !== 0 ||
      processOriginal.env.NODE_OPTIONS !== undefined || processOriginal.version !== 'v22.22.0' ||
      processOriginal.platform !== 'darwin' || processOriginal.arch !== 'arm64' ||
      processOriginal.versions.openssl !== '3.5.4' || delivery === undefined ||
      delivery.filename !== join(dirname(delivery.filename),'initial-control-public-dispatch.cjs') ||
      require.cache[delivery.filename] !== delivery) unavailable();
  assertSupportedIntrinsics();
  // The actual prefix owns its fixed initialization and ordinary compiler
  // disposition before loading the generated inventory or covered images.
  const declaration = declareOrdinaryInitialControlPhaseEnvelope(getHeapStatistics().heap_size_limit);
  // Adopt the separate joint Source recipe before namespace, managed Source
  // metadata or raw SDK acquisition. This is not a second whole VM allowance.
  const sourceEnvelope = declareSourceManagedPhaseEnvelope(declaration);
  const runtime = freeze({node:processOriginal.versions.node,v8:processOriginal.versions.v8,
    openssl:processOriginal.versions.openssl,platform:processOriginal.platform,arch:processOriginal.arch,
    eager:false,libraries:freeze({...processOriginal.versions})});
  const inventory = require('./initial-control-package-original.cjs').imageInventory;
  if (inventory === undefined) unavailable();
  const envelope = inspectOrdinaryInitialControlPhaseEnvelope(inventory,declaration,runtime);
  const consumerRequire = createRequire(processOriginal.argv[1]);
  // Actual installed consumer resolution must select this physical Local
  // package, not a source tree, copied helper or an equal foreign installation.
  if (dirname(consumerRequire.resolve('@actql/local-node')) !== localRoot) unavailable();
  let publicDeliveryEntry;
  if (delivery.filename !== join(localRoot,'initial-control-public-dispatch.cjs')) {
    const nodeRoot=dirname(consumerRequire.resolve('@actql/node'));
    if (delivery.filename !== join(nodeRoot,'initial-control-public-dispatch.cjs')) unavailable();
    publicDeliveryEntry=delivery.filename;
  } else if (delivery.parent?.filename !== undefined &&
      delivery.parent.filename.endsWith('/initial-control-public-dispatch.cjs')) {
    const nodeRoot=dirname(consumerRequire.resolve('@actql/node'));
    if (delivery.parent.filename !== join(nodeRoot,'initial-control-public-dispatch.cjs') ||
        require.cache[delivery.parent.filename] !== delivery.parent) unavailable();
    publicDeliveryEntry=delivery.parent.filename;
  }
  const images = require('./initial-control-package-custody.cjs')
    .captureOrdinaryInitialControlPackageCustody(inventory,localRoot,processOriginal.argv[1],publicDeliveryEntry);
  const namespace = images.initializeHostNamespace();
  const consumer = field(namespace,'connectInitialControlHostPreparation');
  const validator = field(namespace,'assertInitialControlHostPreparation');
  const reader = field(namespace,'readInitialControlHostInput');
  if ([consumer,validator,reader].some(value=>typeof value !== 'function')) unavailable();
  assertIntrinsicsCurrent();
  const source = {};
  for (const [name, exported] of Object.entries({prepare: 'prepareInstalledMockSourcePreparation',
    read: 'readInstalledMockPreparation', validator: 'assertSourceManagedHostPreparation',
    request: 'originalSourceManagedHostRequest', intent: 'sourceManagedSubmittedIntentCid',
    input: 'readSourceManagedOriginalInput'})) {
    const entry = descriptor(namespace, exported);
    source[name] = entry !== undefined && own(entry, 'value') ? entry.value : undefined;
  }
  freeze(source);
  state = {declaration,runtime,envelope,sourceEnvelope,inventory,images,namespace,consumer,validator,reader,source,prefixIntrinsics};
} catch(cause) {
  // Keep original FD/namespace/compile failure and its close-only duty. A
  // failed prefix never becomes a second factory or a retrying image read.
  firstFailure = freeze({cause});
}
