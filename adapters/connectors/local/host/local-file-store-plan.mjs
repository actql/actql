// Pure Local writer/request construction DATA for the existing common Effect
// Plan. The selected actual Native image and existing Host/Store limits supply
// every variable bound; no permission, Resource admission or send is issued.
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeUnboxedReferenceOption} from '../../../host-common/compiler-binding.generated.mjs';
import {captureInstalledEffectPlanRecipe} from '../../../host-node/installed-effect-plan.mjs';
import {effectLedgerImplementationBounds} from '../../../host-node/effect-ledger-implementation-bounds.mjs';
import {physicalContentReadWindowBytes} from '../../../store-local/publication-store.mjs';
import {localFileWriteMaxComponents} from '../site/root-file-writer.mjs';

export function prepareLocalFileStorePlanRecipe({moon, inputLimits, limits, writerProfile, requestHeaderUnits}) {
  const controlEntryBytes = moon.clientProgramInstalledLocalFileStoreControlWireBound();
  const quote = controlWireBytes => checked(moon.clientProgramInstalledLocalFileStoreRecipeCapacities(
    inputLimits.body.maxBytes, inputLimits.body.maxNodes, inputLimits.body.maxDepth,
    inputLimits.preview.maxWireBytes, inputLimits.preview.maxNodes, inputLimits.preview.maxDepth,
    limits.maxRequestBytes, limits.maxRequestBytes, limits.maxResponseBytes,
    Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
    effectLedgerImplementationBounds.maxOutcomeNodes, effectLedgerImplementationBounds.maxOutcomeDepth,
    BigInt(writerProfile.nativeOriginalBytes), writerProfile.maxRootBytes, writerProfile.maxNameBytes,
    localFileWriteMaxComponents, writerProfile.maxDepth, physicalContentReadWindowBytes, controlWireBytes));
  const quantities = quote(controlEntryBytes), fallback = quote(undefined);
  const capture = checked(moon.clientProgramInstalledEffectCaptureRecipeExtentPrepare('files.write.capture', quantities));
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
      let units = 0, requestBytes = 0, recoveryBytes = 3 * (requestHeaderUnits + 2);
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
        // Every output JSON code unit has at most six escaped units, each
        // requiring at most three UTF8 bytes. Include the original fixed
        // binding/Command/target envelope before requestFrom serializes it.
        const bytes = 18 * (count + requestHeaderUnits);
        requestBytes = Math.max(requestBytes, bytes); recoveryBytes += bytes + 1;
        if (![requestBytes, recoveryBytes].every(value => Number.isSafeInteger(value) && value <= 2147483647)) {
          throw new TypeError('InvalidLocalFileStoreConstructionGeometry');
        }
      }
      return checked(moon.clientProgramInstalledLocalFileStoreObservedConstructorCapacities(
        Math.min(3 * units, inputLimits.body.maxBytes), Math.min(units, inputLimits.body.maxNodes),
        inputLimits.body.maxDepth, requestBytes, proposals.length === 0 ? 0 : units + requestHeaderUnits, recoveryBytes));
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
      if (wire === undefined || wire.length < 1 || wire.length > limits.maxRequestBytes) {
        throw new TypeError('InvalidLocalFileStoreRecoveryGeometry');
      }
      // Existing recover checks the actual byte ceiling before JSON.parse.
      // A tree cannot have more nodes than code units of this original wire.
      const bytes = Math.min(3 * wire.length, limits.maxRequestBytes);
      const actual = checked(moon.clientProgramInstalledLocalFileStoreObservedRecoveryCapacities(
        bytes, wire.length, inputLimits.preview.maxDepth));
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
    savedControlCodec: Object.freeze({maxEntryBytes: controlEntryBytes, fallbackCapacity: fallback[4]}),
    controlsPerRow: quantities[4], captureConstruction: Object.freeze({operationIndex: 0,
      ...(captureInput === undefined ? {} : {inputExtent: captureInput})}),
    recoveryConstruction: Object.freeze({operationIndex: 1,
      ...(recoveryInput === undefined ? {} : {inputExtent: recoveryInput})}),
    footprintConstruction: Object.freeze({operationIndex: 2}),
    requestConstruction: Object.freeze({operationIndex: 0,
      ...(requestInput === undefined ? {} : {inputExtent: requestInput})}),
    physicalWrite: Object.freeze({operationIndex: 1, transferBytes: BigInt(limits.maxFileBytes)}),
  }), 5);
}
