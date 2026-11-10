// Kintone's existing described row Effect recipe: three fresh Form describe
// slots, nine before/target/after slots and one original PUT. Common owns every
// constructor, grant/transfer child, checked Plan, control codec and cleanup.
import {types as nodeTypes} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeUnboxedReferenceOption} from '../../../host-common/compiler-binding.generated.mjs';
import {captureInstalledEffectPlanRecipe} from '../../../host-node/installed-effect-plan.mjs';
import {effectLedgerImplementationBounds} from '../../../host-node/effect-ledger-implementation-bounds.mjs';
import {httpsCredentialAuthorizationPrefix, httpsCredentialDefaultRequestBytes,
  httpsCredentialResponseHeaderByteLimit, httpsCredentialResponseReadQuantum,
  httpsCredentialResponseWindowBytes} from '../../../site-node/https-credential-resource.mjs';
import {KINTONE_FORM_READ_OPERATION} from '../site/kintone-record-read.mjs';
import {KINTONE_TARGET_READ_OPERATION} from '../site/kintone-record-delete.mjs';
import {KINTONE_RECORD_UPDATE_OPERATION} from '../site/kintone-record-write.mjs';

const fail = () => {throw Object.assign(new Error('KintoneEffectRecipeUnavailable'), {code: 'KintoneEffectRecipeUnavailable'});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const data = (value, names) => {
  if (!value || nodeTypes.isProxy(value)) fail();
  return Object.freeze(Object.fromEntries(names.map(name => {
    const field = Object.getOwnPropertyDescriptor(value, name);
    if (!field || !Object.hasOwn(field, 'value')) fail();
    return [name, field.value];
  })));
};
const method = (receiver, name) => {
  const fn = data(receiver, [name])[name];
  if (typeof fn !== 'function' || nodeTypes.isProxy(fn) || nodeTypes.isAsyncFunction(fn)) fail();
  return (...args) => Reflect.apply(fn, receiver, args);
};
const names = ['maxInputBytes', 'maxRequestBytes', 'maxResponseBytes', 'maxNodes', 'maxDepth',
  'maxFields', 'maxNameUnits', 'maxColumns', 'maxCells', 'maxTableRows', 'maxValueNodes',
  'maxValueDepth', 'maxValueTextBytes', 'maxIdentityBytes', 'maxComparisonWork', 'maxRecoveryBytes'];

export function captureKintoneEffectPlanRecipeBuilder({moon}) {
  const original = Object.freeze(Object.fromEntries(['MutationLimits', 'PageLimits', 'ValueLimits',
    'WriteLimits', 'FormLimits', 'UpdateProposalConstructionCapacity', 'UpdateFormConstructionCapacity',
    'UpdateTargetConstructionCapacity', 'UpdateFinalizationConstructionCapacity',
    'UpdateResponseConstructionCapacity', 'UpdateAddConstructionCapacity', 'UpdateRecipeCapacities']
    .map(name => [name, method(moon, 'clientProgramKintone' + name)])));
  const sourceCapacity = method(moon, 'clientProgramInstalledSourceConstructionCapacity');
  const extent = method(moon, 'clientProgramInstalledEffectOperationExtentFromCapacityPrepare');
  const stage = method(moon, 'clientProgramInstalledEffectOperationStagedExtentPrepare');
  const capture = method(moon, 'clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare');
  const controlBound = method(moon, 'clientProgramInstalledEffectControlWireBound');
  const native = value => {const result = runtimeUnboxedReferenceOption(value); if (!result) fail(); return result;};
  const add = (left, right) => native(original.UpdateAddConstructionCapacity(left, right));
  return function prepareKintoneEffectPlanRecipe({mapping, fields, formResource, bindingUnits,
    credentialSite, limits, inputLimits, maxRecoveryBytes}) {
    const policy = data(limits, names);
    if (!Object.values(policy).every(positive) || policy.maxValueNodes > 2147483645 ||
        policy.maxValueDepth > 2147483645 || !positive(bindingUnits) || !positive(maxRecoveryBytes) ||
        typeof formResource !== 'string' || !formResource || !Array.isArray(fields) ||
        nodeTypes.isProxy(fields) || !Object.isFrozen(fields) || fields.length < 1 || fields.length > policy.maxFields) fail();
    const body = data(inputLimits.body, ['maxBytes', 'maxNodes', 'maxDepth']);
    const preview = data(inputLimits.preview, ['maxWireBytes', 'maxNodes', 'maxDepth']);
    if (![...Object.values(body), ...Object.values(preview)].every(positive)) fail();
    const secret = data(data(credentialSite, ['construction']).construction, ['scope', 'issuer', 'limits']);
    const secretBytes = data(secret.limits, ['maxSecretBytes']).maxSecretBytes;
    if (!positive(secretBytes)) fail();
    for (const record of [secret.scope, secret.issuer]) {
      for (const field of Object.values(Object.getOwnPropertyDescriptors(record))) {
        if (!Object.hasOwn(field, 'value')) fail();
        if (typeof field.value === 'string') bindingUnits += field.value.length;
      }
    }
    if (!positive(bindingUnits)) fail();
    const mutation = maximum => original.MutationLimits(1, policy.maxIdentityBytes, policy.maxComparisonWork,
      maximum, policy.maxNodes, policy.maxDepth);
    const requestLimits = mutation(policy.maxRequestBytes), responseLimits = mutation(policy.maxResponseBytes);
    const writeLimits = original.WriteLimits(policy.maxFields, policy.maxNameUnits, policy.maxValueNodes,
      policy.maxValueDepth, policy.maxValueTextBytes, policy.maxRequestBytes);
    const pageLimits = original.PageLimits(policy.maxResponseBytes, policy.maxNodes, policy.maxDepth,
      1, policy.maxColumns, policy.maxCells, policy.maxTableRows);
    const valueLimits = original.ValueLimits(policy.maxColumns, policy.maxNameUnits,
      policy.maxValueNodes, policy.maxValueDepth, policy.maxValueTextBytes);
    const formLimits = original.FormLimits(policy.maxResponseBytes, policy.maxNodes, policy.maxDepth,
      policy.maxFields, policy.maxNameUnits);
    const parsed = (bytes, nodes = policy.maxValueNodes + 2, depth = policy.maxValueDepth + 2) =>
      [bytes, Math.min(nodes, bytes), Math.min(depth, bytes)];
    // Caller-only DATA: carrier/WeakMap entry views, exact CID preimages,
    // canonical map/join scratch, UTF8 hash input and one Base64 copy. Native
    // data and returned JSON trees are separately priced by their original
    // capacities/Core output ports. A Form Unit has no such returned material.
    const host = (kind, bytes) => {
      const b = BigInt(Math.max(1, bytes)), units = BigInt(bindingUnits), f = BigInt(fields.length);
      const input = kind === 'request' ? BigInt(body.maxBytes) : 0n;
      const base64 = kind === 'target' ? 4n * ((b + 2n) / 3n) : 0n;
      const returnedNodes = kind === 'form' ? 0n : 80n + 4n * f;
      const returnedText = kind === 'form' ? 0n : 2n * (base64 + 3n * 71n);
      // Only the initial mapped value is recursively encoded. Every later
      // identity/recovery preimage nests bounded Strings at depth<=4.
      const recursive = input * BigInt(body.maxDepth + 1);
      const canonical = 6n * (recursive + 4n * (units + b + base64)) + 128n;
      return checked(sourceCapacity(returnedNodes, returnedText, 0n,
        256n + 16n * BigInt(body.maxNodes) + 8n * f, 6n * canonical,
        2n * canonical + input + b));
    };
    const request = add(native(original.UpdateProposalConstructionCapacity(mapping, policy.maxInputBytes,
      writeLimits, requestLimits)), host('request', policy.maxRequestBytes));
    const finalization = add(native(original.UpdateFinalizationConstructionCapacity(mapping, requestLimits)),
      host('finalize', policy.maxRequestBytes));
    const profile = (targetBytes, metadataBytes, responseBytes = policy.maxResponseBytes) => {
      const target = add(native(original.UpdateTargetConstructionCapacity(mapping, targetBytes,
        pageLimits, valueLimits, responseLimits)), host('target', targetBytes));
      const form = native(original.UpdateFormConstructionCapacity(mapping, metadataBytes, formLimits));
      const response = native(original.UpdateResponseConstructionCapacity(mapping, responseBytes, responseLimits));
      const outcomeBytes = Math.min(policy.maxResponseBytes, 6 * Math.min(Math.max(1, responseBytes), policy.maxIdentityBytes) + 128);
      return Object.freeze({capacities: [request, target, response, form],
        output: [...parsed(policy.maxRequestBytes), ...parsed(policy.maxResponseBytes), ...parsed(outcomeBytes, 16, 3)]});
    };
    const controlBytes = checked(controlBound(policy.maxResponseBytes, effectLedgerImplementationBounds.maxEntryBytes));
    const parameters = [Math.max(preview.maxWireBytes, maxRecoveryBytes), preview.maxNodes, preview.maxDepth,
      body.maxBytes, body.maxNodes, body.maxDepth, policy.maxRequestBytes, policy.maxResponseBytes,
      policy.maxRequestBytes, policy.maxResponseBytes, httpsCredentialDefaultRequestBytes, policy.maxResponseBytes,
      secretBytes, httpsCredentialAuthorizationPrefix.length, httpsCredentialResponseHeaderByteLimit,
      Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
      Math.max(effectLedgerImplementationBounds.maxNodes, effectLedgerImplementationBounds.maxOutcomeNodes),
      Math.max(effectLedgerImplementationBounds.maxDepth, effectLedgerImplementationBounds.maxOutcomeDepth)];
    const cold = bytes => {
      const targetBytes = bytes < 0 ? policy.maxResponseBytes : Math.min(policy.maxResponseBytes, bytes);
      const wireBytes = BigInt(bytes < 0 ? maxRecoveryBytes : Math.max(1, bytes));
      // Outer member and inner row JSON parsing precede their closed-shape
      // checks. Even malformed full-wire prefixes need workspace. Successful
      // envelopes retain only their closed records and decoded String bodies;
      // native admitted values/targets and Host before trees are separate.
      const envelopes = checked(sourceCapacity(128n, 2n * wireBytes, 0n,
        512n + 4n * wireBytes, 148n * wireBytes + 16n * BigInt(bindingUnits), 4n * wireBytes));
      return add(envelopes, add(finalization, add(native(original.UpdateTargetConstructionCapacity(mapping,
        targetBytes, pageLimits, valueLimits, responseLimits)), host('target', targetBytes))));
    };
    const quantities = (values, hostBytes = 0, control = controlBytes, recoveryBytes = hostBytes) => checked(original.UpdateRecipeCapacities(
      values.capacities, values.output, cold(recoveryBytes), parameters, BigInt(bindingUnits), httpsCredentialResponseReadQuantum, control, hostBytes));
    const initialProfile = profile(0, 0), initial = quantities(initialProfile);
    const maximum = quantities(profile(policy.maxResponseBytes, policy.maxResponseBytes), -1);
    const fallback = quantities(initialProfile, 0, 0);
    if ([initial, maximum, fallback].some(values => !Array.isArray(values) || values.length !== 8)) fail();
    const captureName = KINTONE_RECORD_UPDATE_OPERATION + '.capture';
    const capturedExtent = values => checked(capture(captureName, values.slice(0, 6),
      preview.maxWireBytes, preview.maxNodes, preview.maxDepth));
    const operationExtent = (operation, capacity, transfer = 0n, physical = false) => checked(extent(operation, capacity, transfer, physical));
    const memberOperations = [{operation: captureName, extent: checked(stage(capturedExtent(initial), capturedExtent(maximum)))}];
    const rowOperations = [
      {operation: KINTONE_RECORD_UPDATE_OPERATION + '.request', extent: operationExtent(KINTONE_RECORD_UPDATE_OPERATION + '.request', initial[2])},
      {operation: KINTONE_RECORD_UPDATE_OPERATION + '.finalize', extent: operationExtent(KINTONE_RECORD_UPDATE_OPERATION + '.finalize', finalization)},
    ];
    const credentialOperations = [];
    const physical = (phase, slot, resource, perRow, target) => {
      const operation = target ? KINTONE_TARGET_READ_OPERATION : KINTONE_FORM_READ_OPERATION;
      const operations = perRow ? rowOperations : memberOperations, operationIndex = operations.length;
      const transfer = BigInt(policy.maxRequestBytes) + httpsCredentialResponseWindowBytes(policy.maxResponseBytes);
      const of = bytes => operationExtent(operation, quantities(target ? profile(bytes, 0) : profile(0, bytes))[target ? 6 : 7], transfer, true);
      operations.push({operation, extent: checked(stage(of(0), of(policy.maxResponseBytes)))});
      credentialOperations.push(Object.freeze({phase, slot, ...(resource === undefined ? {} : {resource}), perRow, operationIndex,
        maxRequestBytes: policy.maxRequestBytes, maxResponseBytes: policy.maxResponseBytes,
        responseExtent(bytes, body) {
          if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > policy.maxResponseBytes ||
              !(body instanceof Uint8Array) || body.byteLength !== bytes) fail();
          return of(bytes);
        }}));
    };
    for (const phase of ['capture', 'apply', 'resume']) {
      physical(phase + '-describe', 'schema', formResource, false, false);
      physical(phase + '-target', 'schema-before', formResource, true, false);
      physical(phase + '-target', 'target', undefined, true, true);
      physical(phase + '-target', 'schema-after', formResource, true, false);
    }
    const writeIndex = rowOperations.length;
    rowOperations.push({operation: KINTONE_RECORD_UPDATE_OPERATION, extent: operationExtent(KINTONE_RECORD_UPDATE_OPERATION,
      initial[3], BigInt(policy.maxRequestBytes) + httpsCredentialResponseWindowBytes(policy.maxResponseBytes), true)});
    credentialOperations.push(Object.freeze({phase: 'write', operationIndex: writeIndex,
      maxRequestBytes: policy.maxRequestBytes, maxResponseBytes: policy.maxResponseBytes}));
    const recoveryIndex = memberOperations.length; memberOperations.push(memberOperations[0]);
    return captureInstalledEffectPlanRecipe(Object.freeze({memberOperations: Object.freeze(memberOperations.map(Object.freeze)),
      rowOperations: Object.freeze(rowOperations.map(Object.freeze)), credentialOperations: Object.freeze(credentialOperations),
      captureConstruction: Object.freeze({operationIndex: 0}), recoveryConstruction: Object.freeze({operationIndex: recoveryIndex,
        inputExtent(previewWire, recovery, memberIndex) {
          if (typeof previewWire !== 'string' || !previewWire.isWellFormed() || !Array.isArray(recovery) ||
              !Number.isSafeInteger(memberIndex) || memberIndex < 0) fail();
          let bytes = Buffer.byteLength(previewWire);
          if (!positive(bytes) || bytes > preview.maxWireBytes) fail();
          let recoveryBytes = 1;
          for (const entry of recovery) if (entry?.memberIndex === memberIndex) {
            if (typeof entry.wire !== 'string' || !entry.wire.isWellFormed()) fail();
            const size = Buffer.byteLength(entry.wire); if (!positive(size) || size > maxRecoveryBytes) fail();
            bytes = Math.max(bytes, size); recoveryBytes = Math.max(recoveryBytes, size);
          }
          return capturedExtent(quantities(initialProfile, bytes, controlBytes, recoveryBytes));
        }}), requestConstruction: Object.freeze({operationIndex: 0}), requestFinalization: Object.freeze({operationIndex: 1}),
      controlsPerRow: initial[4], savedControlCodec: Object.freeze({maxEntryBytes: controlBytes, fallbackCapacity: fallback[4]}),
    }), memberOperations.length + rowOperations.length);
  };
}
