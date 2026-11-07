// Private normal-installation assembly over the existing typed constructors.
// Core owns the checked member/row inventory, tariff, Plan and admission.
// The original Site still owns grants, currentness, physical children and ACK.
import {types as nodeTypes} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureInstalledEffectPlanRecipe, effectRecoveryPreviewBounds} from '../../../host-node/installed-effect-plan.mjs';
import {sourceJsonWireGeometry} from '../../../host-node/installed-source-construction-geometry.mjs';
import {localOutputLimits} from '../../../host-node/local-values-plan.mjs';
import {effectLedgerImplementationBounds} from '../../../host-node/effect-ledger-implementation-bounds.mjs';
import {httpsCredentialAuthorizationPrefix, httpsCredentialDefaultRequestBytes,
  httpsCredentialResponseHeaderByteLimit, httpsCredentialResponseReadQuantum,
  httpsCredentialResponseWindowBytes} from '../../../site-node/https-credential-resource.mjs';
import {salesforceWriteOperations, salesforceTargetReadOperation} from './salesforce-write-driver.mjs';
import {salesforceDescribeOperation} from '../site/salesforce-named-describe.mjs';

const fail = () => {throw Object.assign(new Error('InstalledSalesforceEffectRecipeUnavailable'),
  {code: 'InstalledSalesforceEffectRecipeUnavailable'});};
const integer = value => Number.isSafeInteger(value) && value > 0 && value <= 2_147_483_647;
function originalMethod(receiver, name) {
  if (receiver === null || !['object', 'function'].includes(typeof receiver) || nodeTypes.isProxy(receiver)) fail();
  const field = Object.getOwnPropertyDescriptor(receiver, name);
  if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
      nodeTypes.isProxy(field.value) || nodeTypes.isAsyncFunction(field.value)) fail();
  return (...args) => Reflect.apply(field.value, receiver, args);
}

// Capture original methods/receivers BEFORE Source reserve/current can reenter.
// The returned builder runs only inside the funded driver projection. Names
// and field counts come from the SAME restored immutable Mappings; native
// Options and tuples pass unchanged to their original Core consumer.
export function captureSalesforceEffectPlanRecipeBuilder({moon, salesforceMoon}) {
  const profileFor = originalMethod(salesforceMoon, 'salesforceEffectConstructionProfile');
  const captureFor = originalMethod(salesforceMoon, 'salesforceEffectInputCaptureConstructionProfile');
  const recoveryFor = originalMethod(salesforceMoon, 'salesforceEffectRecoveryInputConstructionProfile');
  const targetFor = originalMethod(salesforceMoon, 'salesforceEffectTargetInputConstructionProfile');
  const controlBoundFor = originalMethod(moon, 'clientProgramInstalledEffectControlWireBound');
  const metadataFor = originalMethod(salesforceMoon, 'salesforceEffectMetadataInputConstructionProfile');
  const currentMetadataFor = originalMethod(salesforceMoon, 'salesforceEffectCurrentMetadataConstructionProfile');
  const stageFor = originalMethod(moon, 'clientProgramInstalledEffectOperationStagedExtentPrepare');
  const compose = originalMethod(moon, 'clientProgramInstalledDescribedEffectInputRecipeCapacities');
  const extentFor = originalMethod(moon, 'clientProgramInstalledEffectOperationExtentFromCapacityPrepare');
  const captureExtentFor = originalMethod(moon, 'clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare');
  return function prepareSalesforceEffectPlanRecipes({installed,
    site, credentialConstruction, catalogLimits, limits}) {
    const secret = credentialConstruction;
    if (!Object.isFrozen(installed) || !Array.isArray(installed.mappings) ||
        installed.mappings.length === 0 || !secret || !Object.isFrozen(secret) ||
        !Object.isFrozen(secret.scope) || !Object.isFrozen(secret.issuer) ||
        !integer(secret.limits?.maxSecretBytes)) fail();
    let fields = 0, fieldUnits = 0, resourceUnits = 0;
    for (const mapping of installed.mappings) {
      const names = mapping.write.fields ?? mapping.write.sources?.map(source => source.target);
      if (!Array.isArray(names) || names.length === 0 ||
          names.some(name => typeof name !== 'string' || name.length === 0) ||
          typeof mapping.write.resource !== 'string' || mapping.write.resource.length === 0) fail();
      fields = Math.max(fields, names.length);
      fieldUnits = Math.max(fieldUnits, names.reduce((sum, name) => sum + name.length, 0));
      resourceUnits = Math.max(resourceUnits, mapping.write.resource.length);
    }
    // The emitted Catalog binding includes original Site/scope strings, two
    // Run/dispatch CIDs and the fixed index/time/counter occurrence spelling.
    // IDs themselves remain with Core; no row count or byte price is selected.
    let bindingUnits = 4 * 71 + 128;
    for (const record of [site, secret.scope, secret.issuer]) {
      for (const value of Object.values(record)) if (typeof value === 'string') bindingUnits += value.length;
    }
    const metadataUnits = BigInt(bindingUnits) + BigInt(fieldUnits) + BigInt(resourceUnits);
    const describe = catalogLimits.describe, list = catalogLimits.list;
    if (![fields, fieldUnits, resourceUnits, bindingUnits, site.apiVersion?.length,
      limits.preview.maxWireBytes, limits.preview.maxNodes, limits.preview.maxDepth,
      limits.body.maxBytes, limits.body.maxNodes, limits.body.maxDepth,
      limits.request.maxPathBytes, limits.request.maxTargetBytes, limits.request.maxBodyBytes,
      limits.target.maxResponseBytes, limits.target.maxNodes, limits.target.maxDepth,
      limits.maxIdentityBytes, limits.write.maxResponseBytes, limits.write.maxNodes, limits.write.maxDepth,
      describe.maxBytes, describe.maxNodes, describe.maxDepth, describe.maxFields, describe.maxNameUnits,
      list.maxBytes, list.maxNodes, list.maxDepth, list.maxResources, list.maxSelected, list.maxNameUnits,
      catalogLimits.maxObservationBytes, limits.maxRetainedBytes, localOutputLimits.maxWireBytes]
      .every(integer) || metadataUnits > 2_147_483_647n) fail();
    const profile = profileFor(limits.body.maxBytes, limits.body.maxNodes, limits.body.maxDepth,
      limits.request.maxPathBytes, limits.request.maxTargetBytes, limits.request.maxBodyBytes,
      limits.target.maxResponseBytes, limits.target.maxNodes, limits.target.maxDepth,
      limits.maxIdentityBytes, limits.write.maxResponseBytes, limits.write.maxNodes, limits.write.maxDepth,
      describe.maxBytes, describe.maxNodes, describe.maxDepth, describe.maxFields, describe.maxNameUnits,
      catalogLimits.maxObservationBytes, bindingUnits, fields, fieldUnits, site.apiVersion.length, resourceUnits);
    // The standard Node Store's maxObjectBytes is this SAME output-policy
    // field. The authenticated decoded capture and its inner wire are smaller
    // than that object; raw metadata keeps its independent original limit.
    const captureArguments = Object.freeze([ limits.preview.maxWireBytes, limits.preview.maxNodes, limits.preview.maxDepth,
      list.maxBytes, list.maxNodes, list.maxDepth, list.maxResources, list.maxSelected, list.maxNameUnits,
      describe.maxBytes, describe.maxNodes, describe.maxDepth, describe.maxFields, describe.maxNameUnits,
      catalogLimits.maxObservationBytes, limits.maxRetainedBytes, localOutputLimits.maxWireBytes,
      bindingUnits, fields, fieldUnits, site.apiVersion.length, resourceUnits]);
    const metadataArguments = Object.freeze([describe.maxBytes, describe.maxNodes, describe.maxDepth,
      describe.maxFields, describe.maxNameUnits, catalogLimits.maxObservationBytes, bindingUnits, resourceUnits]);
    const targetArguments = Object.freeze([limits.target.maxResponseBytes,limits.target.maxNodes,
      limits.target.maxDepth,limits.maxIdentityBytes,fields]);
    const initialProfile = targetFor(metadataFor(profile, ...metadataArguments, 0), ...targetArguments, 0);
    // The selected native outcome writer already refuses larger output before
    // the existing receipt envelope. Keep its complete rejection prefix and
    // use the original full-codec fallback for wider composed implementations.
    const controlEntryBytes = checked(controlBoundFor(limits.write.maxResponseBytes,effectLedgerImplementationBounds.maxEntryBytes));
    const warmCapture = captureFor(profile, ...captureArguments, 0);
    const maximumCapture = captureFor(profile, ...captureArguments, -1);
    const recipes = {};
    for (const [kind, operation] of Object.entries(salesforceWriteOperations)) {
      const targeted = kind !== 'create';
      const composeArguments = Object.freeze([
        limits.preview.maxWireBytes, limits.preview.maxNodes, limits.preview.maxDepth,
        // The SAME source exporter already uses body limits per proposal row.
        // Whole-Preview bounds still own the fixed member input above.
        limits.body.maxBytes, limits.body.maxNodes, limits.body.maxDepth,
        limits.write.maxRequestBytes, limits.write.maxResponseBytes, targeted,
        httpsCredentialDefaultRequestBytes, limits.target.maxResponseBytes,
        httpsCredentialDefaultRequestBytes, describe.maxBytes,
        secret.limits.maxSecretBytes, httpsCredentialAuthorizationPrefix.length,
        httpsCredentialResponseHeaderByteLimit,
        Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
        Math.max(effectLedgerImplementationBounds.maxNodes, effectLedgerImplementationBounds.maxOutcomeNodes),
        Math.max(effectLedgerImplementationBounds.maxDepth, effectLedgerImplementationBounds.maxOutcomeDepth),
        metadataUnits, httpsCredentialResponseReadQuantum]);
      const quantities = (inputProfile, capture, controlBytes = controlEntryBytes, hostInputBytes = 0) =>
        checked(compose(inputProfile, capture, ...composeArguments, controlBytes, hostInputBytes));
      const capacities = quantities(initialProfile, warmCapture);
      const maximum = quantities(profile, maximumCapture, controlEntryBytes, -1);
      const fallback = quantities(initialProfile,warmCapture,0);
      const responseExtent = (bytes, originalBody) => {
        if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > metadataArguments[0]) fail();
        if (!(originalBody instanceof Uint8Array) || originalBody.byteLength !== bytes) fail();
        const selected = quantities(targetFor(currentMetadataFor(profile, ...metadataArguments, originalBody), ...targetArguments, 0), warmCapture);
        return checked(extentFor(salesforceDescribeOperation, selected[7],
          BigInt(httpsCredentialDefaultRequestBytes) + httpsCredentialResponseWindowBytes(metadataArguments[0]), true));
      };
      const targetResponseExtent = bytes => {
        if(!Number.isSafeInteger(bytes)||bytes<0||bytes>targetArguments[0])fail();
        const selected=quantities(targetFor(initialProfile,...targetArguments,bytes),warmCapture);
        return checked(extentFor(salesforceTargetReadOperation,selected[6],
          BigInt(httpsCredentialDefaultRequestBytes)+httpsCredentialResponseWindowBytes(targetArguments[0]),true));
      };
      const inputExtent = (previewWire, recovery, memberIndex, metadata) => {
        if (typeof previewWire !== 'string' || !Array.isArray(recovery)) fail();
        const previewBytes = Buffer.byteLength(previewWire);
        let bytes = previewBytes;
        for (const entry of recovery) {
          if (typeof entry?.wire !== 'string') fail();
          bytes = Math.max(bytes, Buffer.byteLength(entry.wire));
        }
        // Same authenticated Store input bound. This quantities only a native
        // constructor; the original decoder still validates every old limit.
        if (!integer(bytes) || bytes > localOutputLimits.maxWireBytes) fail();
        const originalPreviewBounds = effectRecoveryPreviewBounds(previewBytes, limits.preview);
        const entry = Number.isSafeInteger(memberIndex)
          ? recovery.find(value => value.memberIndex === memberIndex) : undefined;
        const staged = entry?.kind === 'salesforce-named-catalog' &&
          typeof entry.wire === 'string';
        let capture;
        if (staged && metadata === undefined) {
          // This actual immutable wire bounds the outer/nested JSON forests.
          // It funds binary/Source preflight before the original body is read.
          const nodes = sourceJsonWireGeometry(entry.wire).nodes;
          if (nodes > 2_147_483_647n) fail();
          capture = recoveryFor(profile, ...originalPreviewBounds,
            ...captureArguments.slice(3), bytes, Number(nodes), new Uint8Array(0));
        } else if (staged && metadata?.bodies?.length === 1 &&
            metadata.bodies[0] instanceof Uint8Array &&
            metadata.evidence?.names?.length === 1 &&
            metadata.evidence.maxObservationBytes === catalogLimits.maxObservationBytes &&
            ['maxBytes', 'maxNodes', 'maxDepth', 'maxFields', 'maxNameUnits']
              .every(key => metadata.evidence.describeLimits?.[key] === describe[key])) {
          const nodes = sourceJsonWireGeometry(entry.wire).nodes;
          if (nodes > 2_147_483_647n) fail();
          capture = recoveryFor(profile, ...originalPreviewBounds,
            ...captureArguments.slice(3), bytes, Number(nodes), metadata.bodies[0]);
        } else {
          // Whole Catalog, foreign/changed limits and unavailable/wider named
          // inputs retain the complete original constructor and refusal path.
          capture = captureFor(profile, ...originalPreviewBounds,
            ...captureArguments.slice(3), bytes);
        }
        const selected = quantities(initialProfile, capture, controlEntryBytes, previewBytes);
        return checked(captureExtentFor(operation, selected.slice(0, 6),
          limits.preview.maxWireBytes, limits.preview.maxNodes, limits.preview.maxDepth));
      };
      if (!Array.isArray(capacities) || capacities.length !== 8) fail();
      const memberOperations = [Object.freeze({operation,
        extent: checked(stageFor(checked(captureExtentFor(operation, capacities.slice(0, 6),
          limits.preview.maxWireBytes, limits.preview.maxNodes, limits.preview.maxDepth)),
          checked(captureExtentFor(operation, maximum.slice(0, 6),
            limits.preview.maxWireBytes, limits.preview.maxNodes, limits.preview.maxDepth))))})];
      const rowOperations = [Object.freeze({operation,
        extent: checked(extentFor(operation, capacities[2], 0n, false))})];
      const credentialOperations = [];
      const physical = (phase, perRow, selectedOperation, capacity, requestBytes, responseBytes, maximumCapacity, originalResponseExtent) => {
        const selected = perRow ? rowOperations : memberOperations;
        const operationIndex = selected.length;
        const extent = value => checked(extentFor(selectedOperation, value,
          BigInt(requestBytes) + httpsCredentialResponseWindowBytes(responseBytes), true));
        selected.push(Object.freeze({operation: selectedOperation,
          extent: maximumCapacity === undefined ? extent(capacity) : checked(stageFor(extent(capacity), extent(maximumCapacity)))}));
        credentialOperations.push(Object.freeze({phase, perRow, operationIndex,
          maxRequestBytes: requestBytes, maxResponseBytes: responseBytes,
          ...(maximumCapacity === undefined ? {} : {responseExtent: originalResponseExtent})}));
      };
      for (const phase of ['capture-describe', 'apply-describe', 'resume-describe']) {
        physical(phase, false, salesforceDescribeOperation, capacities[7],
          httpsCredentialDefaultRequestBytes, describe.maxBytes, maximum[7], responseExtent);
      }
      if (targeted) for (const phase of ['capture-target', 'apply-target', 'resume-target']) {
        physical(phase, true, salesforceTargetReadOperation, capacities[6],
          httpsCredentialDefaultRequestBytes, limits.target.maxResponseBytes, maximum[6], targetResponseExtent);
      }
      physical('write', true, operation, capacities[3],
        limits.write.maxRequestBytes, limits.write.maxResponseBytes);
      const recoveryConstruction = Object.freeze({operationIndex: memberOperations.length, inputExtent});
      memberOperations.push(memberOperations[0]);
      recipes[kind] = captureInstalledEffectPlanRecipe(Object.freeze({
        memberOperations: Object.freeze(memberOperations), rowOperations: Object.freeze(rowOperations),
        savedControlCodec: Object.freeze({maxEntryBytes: controlEntryBytes, fallbackCapacity: fallback[4]}),
        controlsPerRow: capacities[4], captureConstruction: Object.freeze({operationIndex: 0, inputExtent}), recoveryConstruction,
        requestConstruction: Object.freeze({operationIndex: 0}),
        credentialOperations: Object.freeze(credentialOperations),
      }), memberOperations.length + rowOperations.length);
    }
    return Object.freeze(recipes);
  };
}
