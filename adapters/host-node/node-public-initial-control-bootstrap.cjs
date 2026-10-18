'use strict';

// Actual installed public-package prefix. This instance is constructed by its
// fixed delivery module, not by a caller's factory, receipt or options. It is
// deliberately separate from the preload recipe: no eager bytecode, preload
// ancestor, frozen-intrinsic history or earlier application work is claimed.
const {createRequire} = require('node:module');
const {join, dirname} = require('node:path');
const {getHeapStatistics} = require('node:v8');
const {isProxy} = require('node:util').types;
const processOriginal = require('node:process');
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const own = Object.hasOwn, freeze = Object.freeze;
const {createInitialControlInstallationOwner} = require('./initial-control-installation-owner.cjs');
const {declareOrdinaryInitialControlPhaseEnvelope, inspectOrdinaryInitialControlPhaseEnvelope}
  = require('./initial-control-phase-envelope.cjs');
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
const inputLimits = freeze({maxProperties:40,maxNodes:40,maxDepth:4,
  maxStringCodeUnits:4096,maxTotalStringCodeUnits:8192,maxArrayItems:0,maxOpaqueAliases:0,maxWork:65536});
// Capture actual prefix-time descriptors without evaluating a global accessor
// (Node's standard lazy Buffer binding is an accessor). They stay original
// observations, not evidence that arbitrary prior application code was covered.
const prefixIntrinsics = [];
for (const [receiver,names] of [[Object,['getOwnPropertyDescriptor','hasOwn','freeze','create']],
  [Reflect,['apply','ownKeys']],[Array,['isArray']],[globalThis,['Object','Reflect','Array','Promise','Buffer']]]) {
  for (const name of names) prefixIntrinsics.push(freeze({receiver,name,property:descriptor(receiver,name)}));
}
freeze(prefixIntrinsics);
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
const table = Object.setPrototypeOf({
  selectedInitialControlHostPreparation:connectInitialControlHostPreparation,
  beginInitialControlInstallation(originals,raw) {return owner.begin(originals,raw);},
  assertInitialControlInstallationCurrent(scope,originals) {return owner.assertCurrent(scope,originals);},
  readInitialControlInstallationInput(scope,originals) {return owner.readInput(scope,originals);},
  readInitialControlInstallationAsset(scope,originals,path) {return owner.readAsset(scope,originals,path);},
},null);
// Same synchronous receiver handoff for the Host namespace while it loads;
// no callable table can pass assertPrefixCurrent until initialization closes.
module.exports = freeze(table);
try {
  if (module.isPreloading !== false || processOriginal.execArgv.length !== 0 ||
      processOriginal.env.NODE_OPTIONS !== undefined || processOriginal.version !== 'v22.22.0' ||
      processOriginal.platform !== 'darwin' || processOriginal.arch !== 'arm64' ||
      processOriginal.versions.openssl !== '3.5.4' || delivery === undefined ||
      delivery.filename !== join(dirname(delivery.filename),'initial-control-public-dispatch.cjs') ||
      require.cache[delivery.filename] !== delivery) unavailable();
  // The actual prefix owns its fixed initialization and ordinary compiler
  // disposition before loading the generated inventory or covered images.
  const declaration = declareOrdinaryInitialControlPhaseEnvelope(getHeapStatistics().heap_size_limit);
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
  }
  const images = require('./initial-control-package-custody.cjs')
    .captureOrdinaryInitialControlPackageCustody(inventory,localRoot,processOriginal.argv[1],publicDeliveryEntry);
  const namespace = images.initializeHostNamespace();
  const consumer = field(namespace,'connectInitialControlHostPreparation');
  const validator = field(namespace,'assertInitialControlHostPreparation');
  const reader = field(namespace,'readInitialControlHostInput');
  if ([consumer,validator,reader].some(value=>typeof value !== 'function')) unavailable();
  assertIntrinsicsCurrent();
  state = {declaration,runtime,envelope,inventory,images,namespace,consumer,validator,reader,prefixIntrinsics};
} catch(cause) {
  // Keep original FD/namespace/compile failure and its close-only duty. A
  // failed prefix never becomes a second factory or a retrying image read.
  firstFailure = freeze({cause});
}
