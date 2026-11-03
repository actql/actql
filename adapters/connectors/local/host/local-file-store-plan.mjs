// Pure Local writer/request construction DATA for the existing common Effect
// Plan. The selected actual Native image and existing Host/Store limits supply
// every variable bound; no permission, Resource admission or send is issued.
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureInstalledEffectPlanRecipe} from '../../../host-node/installed-effect-plan.mjs';
import {effectLedgerImplementationBounds} from '../../../host-node/effect-ledger-implementation-bounds.mjs';
import {physicalContentReadWindowBytes} from '../../../store-local/publication-store.mjs';
import {localFileWriteMaxComponents} from '../site/root-file-writer.mjs';

export function prepareLocalFileStorePlanRecipe({moon, inputLimits, limits, writerProfile}) {
  const quantities = checked(moon.clientProgramInstalledLocalFileStoreRecipeCapacities(
    inputLimits.body.maxBytes, inputLimits.body.maxNodes, inputLimits.body.maxDepth,
    inputLimits.preview.maxWireBytes, inputLimits.preview.maxNodes, inputLimits.preview.maxDepth,
    limits.maxRequestBytes, limits.maxRequestBytes, limits.maxResponseBytes,
    Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
    effectLedgerImplementationBounds.maxOutcomeNodes, effectLedgerImplementationBounds.maxOutcomeDepth,
    BigInt(writerProfile.nativeOriginalBytes), writerProfile.maxRootBytes, writerProfile.maxNameBytes,
    localFileWriteMaxComponents, writerProfile.maxDepth, physicalContentReadWindowBytes));
  const capture = checked(moon.clientProgramInstalledEffectCaptureRecipeExtentPrepare('files.write.capture', quantities));
  const request = checked(moon.clientProgramInstalledEffectOperationExtentFromCapacityPrepare(
    'files.write.request', quantities[2], 0n, false));
  const physical = checked(moon.clientProgramInstalledEffectOperationExtentFromCapacityPrepare(
    'files.write', quantities[3], BigInt(limits.maxFileBytes), true));
  return captureInstalledEffectPlanRecipe(Object.freeze({
    memberOperations: Object.freeze([Object.freeze({operation: 'files.write.capture', extent: capture})]),
    rowOperations: Object.freeze([Object.freeze({operation: 'files.write.request', extent: request}),
      Object.freeze({operation: 'files.write', extent: physical})]),
    controlsPerRow: quantities[4], captureConstruction: Object.freeze({operationIndex: 0}),
    requestConstruction: Object.freeze({operationIndex: 0}),
    physicalWrite: Object.freeze({operationIndex: 1, transferBytes: BigInt(limits.maxFileBytes)}),
  }), 3);
}
