// Pure Local writer/request construction DATA for the existing common Effect
// Plan. The selected actual Native image and existing Host/Store limits supply
// every variable bound; no permission, Resource admission or send is issued.
import {checked} from '../../../host-common/runtime-result.mjs';
import {types as nodeTypes} from 'node:util';
import {runtimeUnboxedReferenceOption} from '../../../host-common/compiler-binding.generated.mjs';
import {sourceJsonWireGeometry} from '../../../host-node/installed-source-construction-geometry.mjs';
import {captureInstalledEffectPlanRecipe} from '../../../host-node/installed-effect-plan.mjs';
import {effectLedgerImplementationBounds} from '../../../host-node/effect-ledger-implementation-bounds.mjs';
import {physicalContentReadWindowBytes} from '../../../store-local/publication-store.mjs';
import {localFileWriteMaxComponents} from '../site/root-file-writer.mjs';

export function prepareLocalFileStorePlanRecipe({moon, inputLimits, limits, writerProfile, requestHeaderUnits, grantIssuer, responseProjector}) {
  // recoveryEntry can retain the accepted prefix and the next already-admitted
  // record before its aggregate guard. The joined frame exists only after
  // that guard succeeds. Both peaks use this SAME original member extent.
  const recoveryConstructionBytes = inputLimits.preview.maxWireBytes + limits.maxRequestBytes;
  if (!Number.isSafeInteger(recoveryConstructionBytes) || recoveryConstructionBytes > 2147483647) {
    throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
  }
  const controlEntryBytes = moon.clientProgramInstalledLocalFileStoreControlWireBound();
  const quote = (controlWireBytes, controlResponseBytes) => checked(moon.clientProgramInstalledLocalFileStoreRecipeCapacities(
    inputLimits.body.maxBytes, inputLimits.body.maxNodes, inputLimits.body.maxDepth,
    inputLimits.preview.maxWireBytes, inputLimits.preview.maxNodes, inputLimits.preview.maxDepth,
    limits.maxRequestBytes, inputLimits.preview.maxWireBytes + limits.maxRequestBytes, limits.maxResponseBytes,
    Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
    effectLedgerImplementationBounds.maxOutcomeNodes, effectLedgerImplementationBounds.maxOutcomeDepth,
    BigInt(writerProfile.nativeOriginalBytes), writerProfile.maxRootBytes, writerProfile.maxNameBytes,
    localFileWriteMaxComponents, writerProfile.maxDepth, physicalContentReadWindowBytes, controlWireBytes, controlResponseBytes));
  const quantities = quote(controlEntryBytes, limits.maxResponseBytes), fallback = quote(undefined, undefined);
  if (!Array.isArray(quantities) || ![6, 7, 8].includes(quantities.length)) {
    throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
  }
  const capture = checked(moon.clientProgramInstalledEffectCaptureRecipeExtentPrepare('files.write.capture',
    quantities.length === 6 ? quantities : quantities.slice(0, 6)));
  let grantConstruction;
  if (quantities.length >= 7 && grantIssuer !== undefined) {
    if (grantIssuer === null || typeof grantIssuer !== 'object' ||
        nodeTypes.isProxy(grantIssuer) || !Object.isFrozen(grantIssuer)) {
      throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
    }
    const method = Object.getOwnPropertyDescriptor(grantIssuer, 'issueEffectGrant');
    if (!method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function' ||
        nodeTypes.isProxy(method.value) || nodeTypes.isAsyncFunction(method.value)) {
      throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
    }
    grantConstruction = Object.freeze({receiver: grantIssuer, method: method.value, capacity: quantities[6]});
  }
  let projectConstruction;
  if (quantities.length === 8 && responseProjector !== undefined) {
    if (responseProjector === null || typeof responseProjector !== 'object' ||
        nodeTypes.isProxy(responseProjector) || !Object.isFrozen(responseProjector)) {
      throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
    }
    const method = Object.getOwnPropertyDescriptor(responseProjector, 'project');
    if (!method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function' ||
        nodeTypes.isProxy(method.value) || nodeTypes.isAsyncFunction(method.value)) {
      throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
    }
    projectConstruction = Object.freeze({receiver: responseProjector, method: method.value, capacity: quantities[7]});
  }
  const request = checked(moon.clientProgramInstalledEffectOperationExtentFromCapacityPrepare(
    'files.write.request', quantities[2], 0n, false));
  const physical = checked(moon.clientProgramInstalledEffectOperationExtentFromCapacityPrepare(
    'files.write', quantities[3], BigInt(limits.maxFileBytes), true));
  // Each original path component has at most1024 UTF8 bytes, hence at most
  // 1024 UTF16 units. The existing fixed opaque-boundary constructor covers
  // the basename slice/lowercase, canonical {basename} text, UTF8 hash input,
  // and fixed Array/Set headers. Variable target CIDs, growing slots and Set
  // entries are separately retained by quantities[4] per actual checked row.
  const footprintCapacity = runtimeUnboxedReferenceOption(
    moon.clientProgramInstalledOpaqueBoundaryFootprintCapacity('local', 'file_collection', 1024));
  if (footprintCapacity === undefined || footprintCapacity === null) {
    throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
  }
  const footprint = checked(moon.clientProgramInstalledEffectOperationExtentFromCapacityPrepare(
    'files.write.footprint', footprintCapacity, 0n, false));
  let warmCapture = capture, coldCapture = capture, warmRequest = request, captureInput, requestInput, recoveryInput;
  if (requestHeaderUnits !== undefined) {
    if (!Number.isSafeInteger(requestHeaderUnits) || requestHeaderUnits < 1) {
      throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
    }
    const initial = moon.clientProgramInstalledLocalFileStoreInitialConstructorCapacities();
    if (!Array.isArray(initial) || initial.length !== 3) throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
    const captureInitial = checked(moon.clientProgramInstalledEffectCaptureRecipeExtentPrepare(
      'files.write.capture', [initial[0], initial[1], quantities[2], quantities[3], quantities[4], quantities[5]]));
    warmCapture = checked(moon.clientProgramInstalledEffectOperationStagedExtentPrepare(captureInitial, capture));
    coldCapture = checked(moon.clientProgramInstalledEffectOperationStagedExtentPrepare(captureInitial, capture));
    const requestInitial = checked(moon.clientProgramInstalledEffectOperationExtentFromCapacityPrepare(
      'files.write.request', initial[2], 0n, false));
    warmRequest = checked(moon.clientProgramInstalledEffectOperationStagedExtentPrepare(requestInitial, request));
    const observe = proposals => {
      if (!Array.isArray(proposals)) throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
      let units = 0, nodes = 0, requestNodes = 0, requestBytes = 0,
        recoveryBytes = 3 * (requestHeaderUnits + 2);
      for (const proposal of proposals) {
        const field = Object.getOwnPropertyDescriptor(proposal, 'changesWire');
        if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'string') {
          throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
        }
        const selector = Object.getOwnPropertyDescriptor(proposal, 'selectorWire');
        if (selector && (!Object.hasOwn(selector, 'value') || typeof selector.value !== 'string')) {
          throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
        }
        const count = field.value.length + (selector?.value.length ?? 0);
        if (count < 1 || count > inputLimits.body.maxBytes) throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
        units = Math.max(units, count);
        // These checked original Strings are parsed once into Host values;
        // CID/path text is not one value node per code unit. The existing
        // syntax observer neither parses nor copies either original wire.
        const rowNodes = Number(sourceJsonWireGeometry(field.value).retained.nodes +
          (selector === undefined ? 0n : sourceJsonWireGeometry(selector.value).retained.nodes));
        nodes = Math.max(nodes, rowNodes);
        // The request adds the closed binding/command/target/value object.
        // Its four fields, root and values need at most ten syntax credits;
        // retaining both complete original subtrees is conservative.
        requestNodes = Math.max(requestNodes, rowNodes + 10);
        // JSON escaping emits at most six ASCII BYTES per input UTF16 unit;
        // unescaped Unicode needs at most three. These maxima do not multiply.
        // Original proposal/selector subtrees are inserted as values, never
        // quoted whole-wire Strings. The same bound covers finite canonical
        // number spelling and the original binding/Command/target envelope.
        const bytes = 6 * (count + requestHeaderUnits);
        requestBytes = Math.max(requestBytes, bytes);
        recoveryBytes = Math.min(inputLimits.preview.maxWireBytes + limits.maxRequestBytes, recoveryBytes + bytes + 1);
        if (![rowNodes, requestNodes, requestBytes, recoveryBytes].every(value => Number.isSafeInteger(value) && value <= 2147483647)) {
          throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
        }
      }
      return checked(moon.clientProgramInstalledLocalFileStoreObservedConstructorCapacities(
        Math.min(3 * units, inputLimits.body.maxBytes), Math.min(nodes, inputLimits.body.maxNodes),
        inputLimits.body.maxDepth, requestBytes, requestNodes, recoveryBytes));
    };
    captureInput = proposals => {
      const actual = observe(proposals);
      return checked(moon.clientProgramInstalledEffectCaptureRecipeExtentPrepare('files.write.capture',
        [actual[0], actual[1], quantities[2], quantities[3], quantities[4], quantities[5]]));
    };
    requestInput = proposal => checked(moon.clientProgramInstalledEffectOperationExtentFromCapacityPrepare(
      'files.write.request', observe([proposal])[2], 0n, false));
    recoveryInput = (_previewWire, recovery, memberIndex) => {
      if (!Array.isArray(recovery) || !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
        throw new TypeError('InvalidLocalFileStoreRecoveryGeometry');
      }
      // SAME original control frame backs this scalar scan. Do not parse or
      // copy the already-admitted whole Preview or another member's wire.
      let wire;
      for (const entry of recovery) {
        const index = Object.getOwnPropertyDescriptor(entry, 'memberIndex');
        if (!index || !Object.hasOwn(index, 'value')) throw new TypeError('InvalidLocalFileStoreRecoveryGeometry');
        if (index.value !== memberIndex) continue;
        const body = Object.getOwnPropertyDescriptor(entry, 'wire');
        if (wire !== undefined || !body || !Object.hasOwn(body, 'value') || typeof body.value !== 'string') {
          throw new TypeError('InvalidLocalFileStoreRecoveryGeometry');
        }
        wire = body.value;
      }
      if (wire === undefined || wire.length < 1 || Buffer.byteLength(wire) > inputLimits.preview.maxWireBytes) {
        throw new TypeError('InvalidLocalFileStoreRecoveryGeometry');
      }
      // Existing recover checks this same aggregate byte policy before parse.
      // One saved envelope and the whole cloned request forest coexist; the
      // structural observer does not parse or copy either original body.
      const bytes = Buffer.byteLength(wire);
      const nodes = Number(sourceJsonWireGeometry(wire).retained.nodes);
      const actual = checked(moon.clientProgramInstalledLocalFileStoreObservedRecoveryCapacities(
        bytes, nodes, inputLimits.preview.maxDepth));
      return checked(moon.clientProgramInstalledEffectCaptureRecipeExtentPrepare('files.write.capture',
        [actual[0], actual[1], quantities[2], quantities[3], quantities[4], quantities[5]]));
    };
  }
  return captureInstalledEffectPlanRecipe(Object.freeze({
    memberOperations: Object.freeze([Object.freeze({operation: 'files.write.capture', extent: warmCapture}),
      Object.freeze({operation: 'files.write.capture', extent: coldCapture}),
      Object.freeze({operation: 'files.write.footprint', extent: footprint})]),
    rowOperations: Object.freeze([Object.freeze({operation: 'files.write.request', extent: warmRequest}),
      Object.freeze({operation: 'files.write', extent: physical})]),
    savedControlCodec: Object.freeze({maxEntryBytes: controlEntryBytes,
      maxResponseBytes: limits.maxResponseBytes, fallbackCapacity: fallback[4]}),
    controlsPerRow: quantities[4], captureConstruction: Object.freeze({operationIndex: 0,
      ...(captureInput === undefined ? {} : {inputExtent: captureInput})}),
    recoveryConstruction: Object.freeze({operationIndex: 1,
      ...(recoveryInput === undefined ? {} : {inputExtent: recoveryInput})}),
    footprintConstruction: Object.freeze({operationIndex: 2}),
    requestConstruction: Object.freeze({operationIndex: 0,
      ...(requestInput === undefined ? {} : {inputExtent: requestInput})}),
    physicalWrite: Object.freeze({operationIndex: 1, transferBytes: BigInt(limits.maxFileBytes)}),
    ...(grantConstruction === undefined ? {} : {grantConstruction}),
    ...(projectConstruction === undefined ? {} : {projectConstruction}),
  }), 5);
}
