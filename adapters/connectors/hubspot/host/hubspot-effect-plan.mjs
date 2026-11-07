// Same Common constructor/Grant/HTTP quantities and checked managed Plan.
// This assembly supplies immutable limits and actual installed text counts;
// it creates no Account decision, permission, operation use or cleanup ACK.
import {types as nodeTypes} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeTupleFromFields, runtimeUnboxedReferenceOption} from '../../../host-common/compiler-binding.generated.mjs';
import {captureInstalledEffectPlanRecipe} from '../../../host-node/installed-effect-plan.mjs';
import {effectLedgerImplementationBounds} from '../../../host-node/effect-ledger-implementation-bounds.mjs';
import {httpsCredentialAuthorizationPrefix, httpsCredentialDefaultRequestBytes,
  httpsCredentialResponseHeaderByteLimit, httpsCredentialResponseReadQuantum,
  httpsCredentialResponseWindowBytes} from '../../../site-node/https-credential-resource.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';
import {HUBSPOT_PROPERTIES_READ_OPERATION} from '../site/hubspot-object-read.mjs';
import {HUBSPOT_OBJECT_BATCH_READ_OPERATION} from '../site/hubspot-target-read.mjs';
import {HUBSPOT_INSTALLED_UPDATE_OPERATION} from './hubspot-update-driver.mjs';

const fail = () => {throw Object.assign(new Error('HubSpotEffectRecipeUnavailable'), {code: 'HubSpotEffectRecipeUnavailable'});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const data = (object, names) => {
  if (!object || nodeTypes.isProxy(object)) fail();
  return Object.freeze(Object.fromEntries(names.map(name => {
    const field = Object.getOwnPropertyDescriptor(object, name);
    if (!field || !Object.hasOwn(field, 'value')) fail();
    return [name, field.value];
  })));
};
const numbers = (object, names) => {
  const record = data(object, names);
  if (!Object.values(record).every(positive)) fail();
  return Object.freeze(Object.values(record));
};
const method = (receiver, name) => {
  const selected = data(receiver, [name])[name];
  if (typeof selected !== 'function' || nodeTypes.isProxy(selected) || nodeTypes.isAsyncFunction(selected)) fail();
  return (...args) => Reflect.apply(selected, receiver, args);
};

export function captureHubSpotEffectPlanRecipeBuilder({moon}) {
  const constructor = method(moon, 'clientProgramHubSpotEffectConstructorCapacity');
  const compose = method(moon, 'clientProgramHubSpotEffectRecipeCapacities');
  const controlBound = method(moon, 'clientProgramInstalledEffectControlWireBound');
  const stage = method(moon, 'clientProgramInstalledEffectOperationStagedExtentPrepare');
  const extent = method(moon, 'clientProgramInstalledEffectOperationExtentFromCapacityPrepare');
  const capture = method(moon, 'clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare');
  return function prepareHubSpotEffectPlanRecipe({mappings, portalId, objectTypeUnits,
    metadataResources, credentialSite, limits, inputLimits, maxRecoveryBytes}) {
    if (!Array.isArray(mappings) || nodeTypes.isProxy(mappings) || !Object.isFrozen(mappings) ||
        mappings.length < 1 || typeof portalId !== 'string' || !positive(portalId.length) ||
        !positive(objectTypeUnits) || !positive(maxRecoveryBytes)) fail();
    const resources = data(metadataResources, ['account', 'properties']);
    if (Object.values(resources).some(value => typeof value !== 'string' || !value) ||
        resources.account === resources.properties) fail();
    const secret = data(credentialSite, ['construction']).construction;
    const secretLimits = data(secret, ['scope', 'issuer', 'limits']);
    const secretBytes = numbers(secretLimits.limits, ['maxSecretBytes'])[0];
    const fixed = data(limits, ['body', 'request', 'read', 'write']);
    const body = numbers(fixed.body, ['maxInputBytes', 'maxNodes', 'maxDepth', 'maxFields', 'maxNameBytes',
      'maxValueNodes', 'maxValueTextBytes', 'maxComparisonWork', 'maxOutputBytes', 'maxOutputNodes', 'maxOutputDepth']);
    const request = numbers(fixed.request, ['maxRows', 'maxProperties', 'maxTraceBytes', 'maxBodyBytes', 'maxBodyNodes', 'maxBodyDepth']);
    const read = data(fixed.read, ['maxResponseBytes', 'maxRequestBytes', 'maxNodes', 'maxDepth', 'maxProperties',
      'maxNameUnits', 'maxRows', 'maxColumns', 'maxCursorUnits', 'maxValueNodes', 'maxValueTextBytes',
      'maxOutputBytes', 'maxOutputNodes', 'maxOutputDepth', 'maxRequestNodes', 'maxRequestDepth']);
    const write = data(fixed.write, ['maxRequestBytes', 'maxResponseBytes', 'maxNodes', 'maxDepth', 'maxRows']);
    if (![...Object.values(read), ...Object.values(write)].every(positive) || write.maxRows !== 1 ||
        request[0] > 100 || read.maxRows > 100) fail();
    const source = data(inputLimits, ['body', 'preview']);
    const row = numbers(source.body, ['maxBytes', 'maxNodes', 'maxDepth']);
    const preview = numbers(source.preview, ['maxWireBytes', 'maxNodes', 'maxDepth']);
    let fields = 0, fieldUnits = 0, mappingUnits = 0;
    for (const mapping of mappings) {
      const selected = data(mapping, ['resource', 'fields', 'mappingRef', 'mappingCid']);
      if (!Array.isArray(selected.fields) || nodeTypes.isProxy(selected.fields) ||
          !Object.isFrozen(selected.fields) || selected.fields.length < 1 ||
          [selected.resource, selected.mappingRef, selected.mappingCid].some(value => typeof value !== 'string')) fail();
      let units = 0;
      for (let index = 0; index < selected.fields.length; index++) {
        const field = Object.getOwnPropertyDescriptor(selected.fields, String(index));
        if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'string') fail();
        units += field.value.length;
      }
      fields = Math.max(fields, selected.fields.length); fieldUnits = Math.max(fieldUnits, units);
      mappingUnits = Math.max(mappingUnits, selected.resource.length + selected.mappingRef.length + selected.mappingCid.length + units);
    }
    let bindingUnits = 12 * 71 + 1024 + objectTypeUnits + portalId.length + mappingUnits;
    for (const record of [secretLimits.scope, secretLimits.issuer]) {
      if (!record || nodeTypes.isProxy(record)) fail();
      for (const field of Object.values(Object.getOwnPropertyDescriptors(record))) {
        if (!Object.hasOwn(field, 'value')) fail();
        if (typeof field.value === 'string') bindingUnits += field.value.length;
      }
    }
    if (![fields, fieldUnits, bindingUnits].every(positive)) fail();
    const counts = Object.freeze([fields, fieldUnits, bindingUnits]);
    const requestInput = Object.freeze([...body, ...request, 1, read.maxProperties, read.maxColumns,
      read.maxRequestBytes, read.maxRequestNodes, read.maxRequestDepth]);
    const quote = (kind, input, output = [], sizes = []) => {
      const value = runtimeUnboxedReferenceOption(constructor(kind, input, output, sizes));
      if (value === undefined || value === null) fail();
      return value;
    };
    const requestCapacity = quote(0, requestInput, [], counts), finalization = quote(6, requestInput, [], counts);
    const responseCapacity = quote(2, [write.maxResponseBytes, write.maxNodes, write.maxDepth]);
    const targetOutput = Object.freeze([read.maxOutputBytes, read.maxOutputNodes, read.maxOutputDepth]);
    const profile = (targetBytes, metadataBytes, metadataKind = 5) => {
      const bytes = Math.max(1, targetBytes);
      const target = quote(1, [bytes, Math.min(read.maxNodes, bytes), Math.min(read.maxDepth, bytes), 1,
        read.maxColumns, read.maxCursorUnits, read.maxValueNodes, read.maxValueTextBytes], targetOutput, counts);
      const metadata = quote(metadataKind, metadataKind === 3
        ? [metadataBytes, portalId.length, read.maxResponseBytes, read.maxNodes, read.maxDepth]
        : metadataKind === 4
        ? [metadataBytes, objectTypeUnits, read.maxResponseBytes, read.maxNodes, read.maxDepth, read.maxProperties, read.maxNameUnits]
        : [metadataBytes, portalId.length, objectTypeUnits, read.maxResponseBytes, read.maxNodes, read.maxDepth, read.maxProperties, read.maxNameUnits]);
      return [requestCapacity, target, responseCapacity, metadata].map(value =>
        runtimeTupleFromFields([value, undefined, undefined]));
    };
    const maximumWire = Math.max(preview[0], maxRecoveryBytes);
    const parameters = Object.freeze([maximumWire, preview[1], preview[2], ...row,
      write.maxRequestBytes, write.maxResponseBytes, read.maxRequestBytes, read.maxResponseBytes,
      httpsCredentialDefaultRequestBytes, read.maxResponseBytes, secretBytes,
      httpsCredentialAuthorizationPrefix.length, httpsCredentialResponseHeaderByteLimit,
      Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
      Math.max(effectLedgerImplementationBounds.maxNodes, effectLedgerImplementationBounds.maxOutcomeNodes),
      Math.max(effectLedgerImplementationBounds.maxDepth, effectLedgerImplementationBounds.maxOutcomeDepth)]);
    const controlBytes = checked(controlBound(write.maxResponseBytes, effectLedgerImplementationBounds.maxEntryBytes));
    const quantities = (original, hostBytes = 0, control = controlBytes) => {
      // Policy wire/text storage is already retained on the original child.
      // Core stages the actual parser forest through hostBytes separately;
      // replacing its policy ceiling here would shrink that live retention.
      return checked(compose(original, finalization, parameters, BigInt(bindingUnits),
        httpsCredentialResponseReadQuantum, control, hostBytes));
    };
    const initialProfile = profile(0, 0), maximumProfile = profile(read.maxResponseBytes, read.maxResponseBytes);
    const initial = quantities(initialProfile), maximum = quantities(maximumProfile, -1), fallback = quantities(initialProfile, 0, 0);
    if ([initial, maximum, fallback].some(value => !Array.isArray(value) || value.length !== 8)) fail();
    const captureName = HUBSPOT_INSTALLED_UPDATE_OPERATION + '.capture';
    const capturedExtent = values => checked(capture(captureName, values.slice(0, 6), ...preview));
    const inputExtent = (previewWire, recovery, memberIndex) => {
      if (typeof previewWire !== 'string' || !previewWire.isWellFormed() || !Array.isArray(recovery) ||
          !Number.isSafeInteger(memberIndex) || memberIndex < 0) fail();
      const previewBytes = Buffer.byteLength(previewWire);
      if (!positive(previewBytes) || previewBytes > preview[0]) fail();
      let bytes = previewBytes;
      for (const entry of recovery) {
        if (entry?.memberIndex !== memberIndex) continue;
        if (typeof entry.wire !== 'string' || !entry.wire.isWellFormed()) fail();
        const size = Buffer.byteLength(entry.wire);
        if (!positive(size) || size > maxRecoveryBytes) fail();
        bytes = Math.max(bytes, size);
      }
      return capturedExtent(quantities(initialProfile, bytes, controlBytes));
    };
    const operationExtent = (operation, capacity, transfer = 0n, physical = false) =>
      checked(extent(operation, capacity, transfer, physical));
    const memberOperations = [{operation: captureName,
      extent: checked(stage(capturedExtent(initial), capturedExtent(maximum)))}];
    const rowOperations = [
      {operation: HUBSPOT_INSTALLED_UPDATE_OPERATION + '.request', extent: operationExtent(HUBSPOT_INSTALLED_UPDATE_OPERATION + '.request', initial[2])},
      {operation: HUBSPOT_INSTALLED_UPDATE_OPERATION + '.finalize', extent: operationExtent(HUBSPOT_INSTALLED_UPDATE_OPERATION + '.finalize', finalization)},
    ];
    const credentialOperations = [];
    const physical = (phase, slot, resource, perRow, operation, position, requestBytes, responseBytes, kind) => {
      const selected = perRow ? rowOperations : memberOperations, operationIndex = selected.length;
      const transfer = BigInt(requestBytes) + httpsCredentialResponseWindowBytes(responseBytes);
      const extentOf = values => operationExtent(operation, values[position], transfer, true);
      // The original physical backing and its received-input growth must use
      // the SAME constructor. A generic Account/schema maximum is appropriate
      // for the shared capture, but its retained schema output cannot become
      // an Account operation's initial backing and then shrink at InputBegin.
      const physicalProfile = bytes => kind === 1 ? profile(bytes, 0) : profile(0, bytes, kind);
      const responseExtent = (bytes, body) => {
        if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > responseBytes ||
            !(body instanceof Uint8Array) || body.byteLength !== bytes) fail();
        return extentOf(quantities(physicalProfile(bytes)));
      };
      selected.push({operation, extent: checked(stage(extentOf(quantities(physicalProfile(0))),
        extentOf(quantities(physicalProfile(responseBytes)))))});
      credentialOperations.push(Object.freeze({phase, slot, ...(resource === undefined ? {} : {resource}), perRow,
        operationIndex, maxRequestBytes: requestBytes, maxResponseBytes: responseBytes, responseExtent}));
    };
    for (const phase of ['capture', 'apply', 'resume']) {
      physical(phase + '-describe', 'account', resources.account, false, HUBSPOT_ACCOUNT_DETAILS_OPERATION,
        7, httpsCredentialDefaultRequestBytes, read.maxResponseBytes, 3);
      physical(phase + '-describe', 'schema', resources.properties, false, HUBSPOT_PROPERTIES_READ_OPERATION,
        7, httpsCredentialDefaultRequestBytes, read.maxResponseBytes, 4);
      for (const [slot, resource, operation, kind] of [
        ['account', resources.account, HUBSPOT_ACCOUNT_DETAILS_OPERATION, 3],
        ['schema-before', resources.properties, HUBSPOT_PROPERTIES_READ_OPERATION, 4],
        ['target', undefined, HUBSPOT_OBJECT_BATCH_READ_OPERATION, 1],
        ['schema-after', resources.properties, HUBSPOT_PROPERTIES_READ_OPERATION, 4],
      ]) physical(phase + '-target', slot, resource, true, operation, kind === 1 ? 6 : 7,
        kind === 1 ? read.maxRequestBytes : httpsCredentialDefaultRequestBytes, read.maxResponseBytes, kind);
    }
    const writeIndex = rowOperations.length;
    rowOperations.push({operation: HUBSPOT_INSTALLED_UPDATE_OPERATION, extent: operationExtent(HUBSPOT_INSTALLED_UPDATE_OPERATION,
      initial[3], BigInt(write.maxRequestBytes) + httpsCredentialResponseWindowBytes(write.maxResponseBytes), true)});
    credentialOperations.push(Object.freeze({phase: 'write', operationIndex: writeIndex,
      maxRequestBytes: write.maxRequestBytes, maxResponseBytes: write.maxResponseBytes}));
    const recoveryIndex = memberOperations.length;
    memberOperations.push(memberOperations[0]);
    return captureInstalledEffectPlanRecipe(Object.freeze({
      memberOperations: Object.freeze(memberOperations.map(Object.freeze)),
      rowOperations: Object.freeze(rowOperations.map(Object.freeze)),
      credentialOperations: Object.freeze(credentialOperations),
      captureConstruction: Object.freeze({operationIndex: 0}),
      recoveryConstruction: Object.freeze({operationIndex: recoveryIndex, inputExtent}),
      requestConstruction: Object.freeze({operationIndex: 0}), requestFinalization: Object.freeze({operationIndex: 1}),
      controlsPerRow: initial[4],
      savedControlCodec: Object.freeze({maxEntryBytes: controlBytes, fallbackCapacity: fallback[4]}),
    }), memberOperations.length + rowOperations.length);
  };
}
