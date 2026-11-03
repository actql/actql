// Private normal-installation assembly over the existing typed constructors.
// Core owns the checked member/row inventory, tariff, Plan and admission.
// The original Site still owns grants, currentness, physical children and ACK.
import {types as nodeTypes} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';
import {captureInstalledEffectPlanRecipe} from '../../../host-node/installed-effect-plan.mjs';
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
  const captureFor = originalMethod(salesforceMoon, 'salesforceEffectCaptureConstructionProfile');
  const compose = originalMethod(moon, 'clientProgramInstalledDescribedEffectRecipeCapacities');
  const extentFor = originalMethod(moon, 'clientProgramInstalledEffectOperationExtentFromCapacityPrepare');
  const captureExtentFor = originalMethod(moon, 'clientProgramInstalledEffectCaptureRecipeExtentPrepare');
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
    const capture = captureFor(profile, limits.preview.maxWireBytes, limits.preview.maxNodes, limits.preview.maxDepth,
      list.maxBytes, list.maxNodes, list.maxDepth, list.maxResources, list.maxSelected, list.maxNameUnits,
      describe.maxBytes, describe.maxNodes, describe.maxDepth, describe.maxFields, describe.maxNameUnits,
      catalogLimits.maxObservationBytes, limits.maxRetainedBytes, localOutputLimits.maxWireBytes,
      bindingUnits, fields, fieldUnits, site.apiVersion.length, resourceUnits);
    const recipes = {};
    for (const [kind, operation] of Object.entries(salesforceWriteOperations)) {
      const targeted = kind !== 'create';
      const capacities = checked(compose(profile, capture,
        limits.preview.maxWireBytes, limits.preview.maxNodes, limits.preview.maxDepth,
        limits.preview.maxWireBytes, limits.preview.maxNodes, limits.preview.maxDepth,
        limits.write.maxRequestBytes, limits.write.maxResponseBytes, targeted,
        httpsCredentialDefaultRequestBytes, limits.target.maxResponseBytes,
        httpsCredentialDefaultRequestBytes, describe.maxBytes,
        secret.limits.maxSecretBytes, httpsCredentialAuthorizationPrefix.length,
        httpsCredentialResponseHeaderByteLimit,
        Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
        Math.max(effectLedgerImplementationBounds.maxNodes, effectLedgerImplementationBounds.maxOutcomeNodes),
        Math.max(effectLedgerImplementationBounds.maxDepth, effectLedgerImplementationBounds.maxOutcomeDepth),
        metadataUnits, httpsCredentialResponseReadQuantum));
      if (!Array.isArray(capacities) || capacities.length !== 8) fail();
      const memberOperations = [Object.freeze({operation,
        extent: checked(captureExtentFor(operation, capacities.slice(0, 6)))})];
      const rowOperations = [Object.freeze({operation,
        extent: checked(extentFor(operation, capacities[2], 0n, false))})];
      const credentialOperations = [];
      const physical = (phase, perRow, selectedOperation, capacity, requestBytes, responseBytes) => {
        const selected = perRow ? rowOperations : memberOperations;
        const operationIndex = selected.length;
        selected.push(Object.freeze({operation: selectedOperation,
          extent: checked(extentFor(selectedOperation, capacity,
            BigInt(requestBytes) + httpsCredentialResponseWindowBytes(responseBytes), true))}));
        credentialOperations.push(Object.freeze({phase, perRow, operationIndex,
          maxRequestBytes: requestBytes, maxResponseBytes: responseBytes}));
      };
      for (const phase of ['capture-describe', 'apply-describe', 'resume-describe']) {
        physical(phase, false, salesforceDescribeOperation, capacities[7],
          httpsCredentialDefaultRequestBytes, describe.maxBytes);
      }
      if (targeted) for (const phase of ['capture-target', 'apply-target', 'resume-target']) {
        physical(phase, true, salesforceTargetReadOperation, capacities[6],
          httpsCredentialDefaultRequestBytes, limits.target.maxResponseBytes);
      }
      physical('write', true, operation, capacities[3],
        limits.write.maxRequestBytes, limits.write.maxResponseBytes);
      recipes[kind] = captureInstalledEffectPlanRecipe(Object.freeze({
        memberOperations: Object.freeze(memberOperations), rowOperations: Object.freeze(rowOperations),
        controlsPerRow: capacities[4], captureConstruction: Object.freeze({operationIndex: 0}),
        requestConstruction: Object.freeze({operationIndex: 0}),
        credentialOperations: Object.freeze(credentialOperations),
      }), memberOperations.length + rowOperations.length);
    }
    return Object.freeze(recipes);
  };
}
