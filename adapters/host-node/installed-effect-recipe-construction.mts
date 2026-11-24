import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {httpsCredentialResponseWindowBytes, httpsCredentialResponseHeaderByteLimit,
  httpsCredentialResponseReadQuantum, httpsCredentialAuthorizationPrefix} from '../site-node/https-credential-resource.mjs';
import {exchangeLimits} from '../host-common/http-exchange.mjs';
import {effectLedgerImplementationBounds} from './effect-ledger-implementation-bounds.mjs';
import {captureInstalledEffectPlanRecipe, rejectInstalledEffectPlan as fail, installedEffectPlanText as text}
  from './installed-effect-recipe.mjs';
import type {InstalledEffectPlanRecipe} from './installed-effect-recipe.mjs';

type PreviewLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type BodyLimits = Readonly<{maxBytes: number; maxNodes: number; maxDepth: number}>;
type InputLimits = Readonly<{body: BodyLimits; preview: PreviewLimits}>;
type TransportLimits = Readonly<{maxRequestBytes: number; maxResponseBytes: number; maxTargetBytes: number}>;
type HttpOccurrence = Pick<TransportLimits, 'maxRequestBytes' | 'maxResponseBytes'> & Readonly<{operation: string}>;
type CredentialSite = Readonly<{
  construction: Readonly<{
    scope: object;
    issuer: object;
    limits: Readonly<{maxSecretBytes: number}>;
  }>;
}>;
type CreateOptions = Readonly<{
  moon: object;
  providerMoon: object;
  construction: Readonly<{
    write: HttpOccurrence;
    check?: (HttpOccurrence & Readonly<{beforeSend?: boolean}>) | null;
    confirmation?: HttpOccurrence;
    finalization?: unknown;
    metadataTextUnits: number;
  }>;
  credentialSite: CredentialSite;
  limits: PreviewLimits;
  resourceTextUnits: number;
  requestInput?: PreviewLimits;
}>;
type UpdateOptions = Readonly<{
  moon: object;
  providerMoon: object;
  write: unknown;
  credentialSite: CredentialSite;
  limits: InputLimits;
  resourceTextUnits: number;
  connectorRegistration: string;
}>;
type PhysicalLimits = Readonly<{
  maxRequestBytes: number; maxRecoveryBytes: number; maxResponseBytes: number;
  maxOutcomeBytes: number; maxTransferBytes: number;
}>;
type CapacityFields = [retainedNodes: bigint, retainedText: bigint, retainedWire: bigint,
  workspaceNodes: bigint, workspaceText: bigint, workspaceWire: bigint];
type PhysicalQuote = [bodyBytes: number, bodyNodes: number, bodyDepth: number, previewBytes: number,
  previewNodes: number, previewDepth: number, requestBytes: number, recoveryBytes: number,
  responseBytes: number, storedBytes: number, storedNodes: number, storedDepth: number,
  physical: unknown, controlWireBytes: number];
type CoreResult = Extract<SynchronousRuntimeData, object>;
type PhysicalRuntime = Readonly<{
  clientProgramInstalledSourceConstructionCapacity(...values: CapacityFields): CoreResult;
  clientProgramComposeInstalledSourceConstructionCapacity?(original: unknown, providers: readonly unknown[]): CoreResult;
  clientProgramInstalledEffectControlWireBound(outcomeBytes: number, maximumBytes: number): CoreResult;
  clientProgramInstalledPhysicalWriteRecipeCapacities(...values: PhysicalQuote): CoreResult;
  clientProgramInstalledPhysicalWriteRecipeCapacitiesWithRequest?(...values: [...PhysicalQuote, request: unknown]): CoreResult;
  clientProgramInstalledEffectCaptureRecipeExtentPrepare(operation: string, quantities: unknown): CoreResult;
  clientProgramInstalledEffectOperationStagedExtentPrepare(initial: unknown, maximum: unknown): CoreResult;
  clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation: string, capacity: unknown,
    transferBytes: bigint, physical: boolean): CoreResult;
}>;
type PhysicalOptions = Readonly<{
  moon: PhysicalRuntime;
  operation: string;
  inputLimits: InputLimits;
  limits: PhysicalLimits;
  construction: object | undefined;
  requestConstruction?: unknown;
  physicalConstruction?: unknown;
  targetReadOperation?: string;
  footprintCapacity?: unknown;
}>;
type CredentialSlot = Pick<HttpOccurrence, 'maxRequestBytes' | 'maxResponseBytes'> & Readonly<{
  phase: string; operationIndex: number; maxTargetBytes?: number; slot?: string;
}>;

// Allocation bounds for the SAME already-owned Preview. A larger Catalog or
// request-recovery wire does not enlarge this independent parser input. The
// original decoder still receives its complete configured limits unchanged.
export function effectRecoveryPreviewBounds(bytes: number, limits: PreviewLimits) {
  const extent = Math.max(1, bytes);
  return Object.freeze([Math.min(extent, limits.maxWireBytes),
    Math.min(extent, limits.maxNodes), Math.min(extent, limits.maxDepth)] as const);
}

// Fixed installed implementation metadata, not caller tuning or a Resource
// allowance. Capture the native method/receiver once; no fallback numeric table
// can silently disagree with the mapper/projector's original implementation.
export function captureInstalledStandardCreateLimits(providerMoon: unknown) {
  if (providerMoon === null || !['object', 'function'].includes(typeof providerMoon) ||
      nodeTypes.isProxy(providerMoon)) fail('InstalledStandardCreateRuntimeUnavailable');
  const method = Object.getOwnPropertyDescriptor(providerMoon, 'installedStandardCreateHttpLimits');
  if (!method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function' ||
      nodeTypes.isProxy(method.value) || nodeTypes.isAsyncFunction(method.value)) {
    fail('InstalledStandardCreateRuntimeUnavailable');
  }
  const values = Reflect.apply(method.value, providerMoon, []);
  if (!Array.isArray(values) || nodeTypes.isProxy(values)) fail('InvalidInstalledStandardCreateLimits');
  const fields = Object.getOwnPropertyDescriptors(values as object);
  if (Reflect.ownKeys(fields).length !== 5 || fields.length?.value !== 4) {
    fail('InvalidInstalledStandardCreateLimits');
  }
  const names = ['maxRequestBytes', 'maxResponseBytes', 'maxNodes', 'maxDepth'] as const;
  const limits = {} as Record<typeof names[number], number>;
  for (let index = 0; index < names.length; index++) {
    const field = fields[index];
    if (!field || !Object.hasOwn(field, 'value') || !Number.isSafeInteger(field.value) ||
        field.value < 1 || field.value > 2147483647) fail('InvalidInstalledStandardCreateLimits');
    limits[names[index]] = field.value;
  }
  return Object.freeze(limits);
}

// One selected standard implementation recipe from original Native/Host/Site
// constructor facts. This is a private installing-code path, not user tuning,
// a new Provider framework, a Run admission or a replacement cleanup owner.
export function prepareInstalledStandardCreatePlanRecipe({moon, providerMoon, construction, credentialSite, limits,
  resourceTextUnits, requestInput = limits}: CreateOptions): InstalledEffectPlanRecipe {
  if (construction === undefined || construction.check === null ||
      credentialSite?.construction === undefined ||
      !Number.isSafeInteger(resourceTextUnits) || resourceTextUnits < 0) {
    fail('InstalledStandardCreateConstructionUnavailable');
  }
  const originalMethod = (receiver: object, name: string) => {
    if (receiver === null || !['object','function'].includes(typeof receiver) || nodeTypes.isProxy(receiver)) {
      fail('InstalledStandardCreateRuntimeUnavailable');
    }
    const field = Object.getOwnPropertyDescriptor(receiver, name);
    if (!field || !Object.hasOwn(field,'value') || typeof field.value !== 'function' ||
        nodeTypes.isProxy(field.value) || nodeTypes.isAsyncFunction(field.value)) {
      fail('InstalledStandardCreateRuntimeUnavailable');
    }
    return (...args: unknown[]) => Reflect.apply(field.value, receiver, args);
  };
  const confirmed = construction.confirmation !== undefined;
  if (confirmed !== (construction.finalization !== undefined)) {
    fail('InstalledStandardCreateConstructionUnavailable');
  }
  const profile = originalMethod(providerMoon, confirmed
    ? 'installedStandardCreateConfirmedConstructionProfile' : 'installedStandardCreateConstructionProfile');
  const captureField = Object.getOwnPropertyDescriptor(providerMoon, 'installedStandardDriverCaptureConstructionCapacity');
  const captureProfile = captureField === undefined ? undefined
    : originalMethod(providerMoon, 'installedStandardDriverCaptureConstructionCapacity');
  if (confirmed && captureProfile !== undefined) fail('InstalledStandardCreateConstructionUnavailable');
  const capacitiesFor = originalMethod(moon, captureProfile === undefined
    ? 'clientProgramInstalledStandardCreateRequestRecipeCapacities' : 'clientProgramInstalledStandardDriverRecipeCapacities');
  const extentFor = originalMethod(moon, 'clientProgramInstalledEffectOperationExtentFromCapacityPrepare');
  const captureFor = originalMethod(moon, captureProfile === undefined
    ? 'clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare' : 'clientProgramInstalledEffectCaptureRecipeExtentPrepare');
  const {write, check} = construction;
  const confirmation = construction.confirmation;
  if (confirmed && (check === undefined || confirmation!.maxRequestBytes !== check.maxRequestBytes ||
      confirmation!.maxResponseBytes !== check.maxResponseBytes)) {
    fail('InstalledStandardCreateConstructionUnavailable');
  }
  const secret = credentialSite.construction;
  if (![write.maxRequestBytes,write.maxResponseBytes,limits.maxWireBytes,limits.maxNodes,limits.maxDepth,
    requestInput?.maxWireBytes,requestInput?.maxNodes,requestInput?.maxDepth,
    secret.limits?.maxSecretBytes,httpsCredentialResponseHeaderByteLimit,
    ...(check === undefined ? [] : [check.maxRequestBytes,check.maxResponseBytes])]
    .every(value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647)) {
    fail('InstalledStandardCreateConstructionUnavailable');
  }
  // Immutable original metadata only. The issuer itself retains and consumes
  // these same scope/issuer fields; do not query policy or sample grant time.
  let units = BigInt(construction.metadataTextUnits) + BigInt(resourceTextUnits);
  for (const value of Object.values(secret.scope)) if (typeof value === 'string') units += BigInt(value.length);
  for (const value of Object.values(secret.issuer)) units += BigInt(value.length);
  const capacities = checked(capacitiesFor(profile(requestInput.maxWireBytes, requestInput.maxNodes, requestInput.maxDepth),
    ...(captureProfile === undefined ? [] : [captureProfile(limits.maxWireBytes,limits.maxNodes,limits.maxDepth,
      requestInput.maxWireBytes,requestInput.maxNodes,requestInput.maxDepth)]), limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
    requestInput.maxWireBytes,requestInput.maxNodes,requestInput.maxDepth,
    write.maxRequestBytes, write.maxResponseBytes, check?.maxRequestBytes ?? 0, check?.maxResponseBytes ?? 0,
    check?.beforeSend === true, secret.limits.maxSecretBytes, httpsCredentialAuthorizationPrefix.length,
    httpsCredentialResponseHeaderByteLimit,
    Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
    Math.max(effectLedgerImplementationBounds.maxNodes, effectLedgerImplementationBounds.maxOutcomeNodes),
    Math.max(effectLedgerImplementationBounds.maxDepth, effectLedgerImplementationBounds.maxOutcomeDepth),
    units, httpsCredentialResponseReadQuantum));
  if (!Array.isArray(capacities) || capacities.length !== (confirmed ? 8
    : (check === undefined ? 5 : 6) + (captureProfile === undefined ? 0 : 1))) {
    fail('InstalledStandardCreateConstructionUnavailable');
  }
  const memberOperations = [Object.freeze({operation:write.operation,
    extent:checked(captureProfile === undefined ? captureFor(write.operation,[capacities[0],capacities[1]],
      limits.maxWireBytes,limits.maxNodes,limits.maxDepth) : captureFor(write.operation,capacities))})];
  const rowOperations = [Object.freeze({operation:write.operation,
    extent:checked(extentFor(write.operation,capacities[2],0n,false))})];
  const requestFinalization = confirmed ? Object.freeze({operationIndex: rowOperations.length}) : undefined;
  if (confirmed) rowOperations.push(Object.freeze({operation: write.operation,
    extent: checked(extentFor(write.operation, capacities[6], 0n, false))}));
  const credentialOperations: CredentialSlot[] = [];
  const physical = (phase: string, selected: HttpOccurrence, capacity: unknown) => {
    const operationIndex = rowOperations.length;
    const transfer = BigInt(selected.maxRequestBytes) + httpsCredentialResponseWindowBytes(selected.maxResponseBytes);
    rowOperations.push(Object.freeze({operation:selected.operation,
      extent:checked(extentFor(selected.operation,capacity,transfer,true))}));
    credentialOperations.push(Object.freeze({phase,operationIndex,
      maxRequestBytes:selected.maxRequestBytes,maxResponseBytes:selected.maxResponseBytes}));
  };
  if (check !== undefined) {
    for (const phase of ['capture-check','apply-check','resume-check']) physical(phase,check,capacities[5]);
    if (check.beforeSend) physical('write-check',check,capacities[5]);
  }
  physical('write',write,capacities[3]);
  if (confirmed) {
    for (const phase of ['apply-confirm', 'resume-confirm']) physical(phase, confirmation!, capacities[7]);
  }
  // Recovery rebuilds requests after capture aliases retire. It is a distinct
  // pure occurrence of the SAME typed extent, never a replay of a spent slot.
  const recoveryConstruction = Object.freeze({operationIndex: memberOperations.length});
  memberOperations.push(memberOperations[0]);
  return captureInstalledEffectPlanRecipe(Object.freeze({
    memberOperations:Object.freeze(memberOperations),rowOperations:Object.freeze(rowOperations),
    controlsPerRow:capacities[4],captureConstruction:Object.freeze({operationIndex:0}),recoveryConstruction,
    requestConstruction:Object.freeze({operationIndex:0}),credentialOperations:Object.freeze(credentialOperations),
    ...(requestFinalization === undefined ? {} : {requestFinalization}),
  }), rowOperations.length + memberOperations.length);
}

// A published UPDATE supplies implementation limits and the compiled
// constructor profile, just as CREATE does. The Host selects the slots and
// builds the Plan recipe against its own Common and installed Credential Site.
export function prepareInstalledDeclaredUpdatePlanRecipe({moon, providerMoon, write, credentialSite,
  limits, resourceTextUnits, connectorRegistration}: UpdateOptions): InstalledEffectPlanRecipe {
  const invalid: () => never = () => fail('InstalledDeclaredUpdateConstructionUnavailable');
  const data = (object: unknown, name: string): unknown => {
    if (object === null || typeof object !== 'object' || nodeTypes.isProxy(object)) invalid();
    const field = Object.getOwnPropertyDescriptor(object, name);
    if (!Object.hasOwn(field ?? {}, 'value')) invalid();
    return field!.value;
  };
  const method = (object: unknown, name: string) => {
    const original = data(object, name);
    if (typeof original !== 'function' || nodeTypes.isProxy(original) || nodeTypes.isAsyncFunction(original)) invalid();
    return (...args: unknown[]) => Reflect.apply(original, object, args);
  };
  const bounds = (value: unknown): TransportLimits => {
    const maxRequestBytes = data(value, 'maxRequestBytes') as number;
    const maxResponseBytes = data(value, 'maxResponseBytes') as number;
    const maxTargetBytes = data(value, 'maxTargetBytes') as number;
    if (![maxRequestBytes, maxResponseBytes, maxTargetBytes].every(value =>
      Number.isSafeInteger(value) && value > 0 && value <= 2147483647)) invalid();
    return {maxRequestBytes, maxResponseBytes, maxTargetBytes};
  };
  const mutation = bounds(data(write, 'transport'));
  const target = bounds(data(data(write, 'targetRead'), 'transport'));
  const operation = data(write, 'operation');
  const targetOperation = data(data(write, 'targetRead'), 'operation');
  if (!text(operation) || !text(targetOperation) || operation === targetOperation ||
      !operation.isWellFormed() || !targetOperation.isWellFormed()) invalid();
  const secret = credentialSite.construction;
  let units = BigInt(resourceTextUnits) + BigInt(operation.length + targetOperation.length + connectorRegistration.length);
  for (const record of [secret.scope, secret.issuer]) {
    for (const value of Object.values(record)) if (typeof value === 'string') units += BigInt(value.length);
  }
  const {preview, body} = limits;
  const input = [preview.maxWireBytes, preview.maxNodes, preview.maxDepth, body.maxBytes, body.maxNodes, body.maxDepth];
  const native = method(providerMoon, 'installedDeclaredUpdateConstructionProfile')(...input);
  const capture = method(providerMoon, 'installedDeclaredUpdateCaptureConstructionProfile')(...input);
  // This Common composer already supports a synchronous projector running
  // on the physical child's reservation. Its projected-response slot includes
  // HTTP backing, secret and the complete typed decoder. Select it for each
  // of the three target reads. The simpler target slot splits the decoder's
  // workspace onto Run controls, so it is not selected here.
  const capacities = checked(method(moon, 'clientProgramInstalledDescribedEffectInputRecipeCapacities')(
    native, capture, ...input, mutation.maxRequestBytes, mutation.maxResponseBytes,
    false, target.maxRequestBytes, target.maxResponseBytes, target.maxRequestBytes, target.maxResponseBytes,
    secret.limits.maxSecretBytes, httpsCredentialAuthorizationPrefix.length, httpsCredentialResponseHeaderByteLimit,
    Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
    Math.max(effectLedgerImplementationBounds.maxNodes, effectLedgerImplementationBounds.maxOutcomeNodes),
    Math.max(effectLedgerImplementationBounds.maxDepth, effectLedgerImplementationBounds.maxOutcomeDepth),
    units, httpsCredentialResponseReadQuantum, 0, -1));
  if (!Array.isArray(capacities) || capacities.length !== 8) invalid();
  const prepareCapture = method(moon, 'clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare');
  const extent = method(moon, 'clientProgramInstalledEffectOperationExtentFromCapacityPrepare');
  const requestCapacity = method(moon, 'clientProgramInstalledSourceConstructionCapacity');
  const compose = method(moon, 'clientProgramComposeInstalledSourceConstructionCapacity');
  const requestEnvelope = ({maxTargetBytes, maxRequestBytes}: TransportLimits, responseHeaders: boolean) => {
    const target = BigInt(maxTargetBytes);
    const query = BigInt(Math.min(maxTargetBytes, exchangeLimits.maxQueryBytes));
    const pairs = BigInt(exchangeLimits.maxQueryPairs);
    const headers = BigInt(exchangeLimits.maxRequestHeaders);
    const observed = responseHeaders ? BigInt(exchangeLimits.maxObservedHeaders) : 0n;
    const headerName = BigInt(exchangeLimits.maxHeaderNameBytes);
    const headerValue = BigInt(exchangeLimits.maxHeaderValueBytes);
    const body = BigInt(maxRequestBytes);
    // The canonical request and Credential Resource each keep header pairs;
    // the Site also makes a header dictionary and its physical copy. Include
    // the encoding vector and output pair Strings while the full target lives.
    const headerPairs = 1n + 4n * headers;
    const headerDictionaries = 2n * (1n + 2n * headers);
    const responseNames = 2n * (1n + observed);
    const retained = 6n + 2n * headerPairs + headerDictionaries + responseNames;
    const workspace = retained + (1n + 4n * pairs) + (5n + 4n * headers) + 12n;
    // Bound both encoding passes, joined query and full target, plus one
    // request body and header lines. Secret/response backing is already on
    // the selected Common physical capacity. This is logical Host backing.
    const headerText = headers * (headerName + headerValue + 4n) + observed * headerName;
    return checked(requestCapacity(retained, 2n * target, 0n,
      workspace, 2n * (4n * query + 2n * target + headerText + body),
      target + headerText + body));
  };
  const member = Object.freeze({operation, extent: checked(prepareCapture(operation, capacities.slice(0, 6), ...input.slice(0, 3)))});
  const rowOperations = [Object.freeze({operation, extent: checked(extent(operation, capacities[2], 0n, false))})];
  const credentialOperations: CredentialSlot[] = [];
  const physical = (phase: string, name: string, bound: TransportLimits, quantity: unknown, slot?: string) => {
    const operationIndex = rowOperations.length;
    const transfer = BigInt(bound.maxRequestBytes) + httpsCredentialResponseWindowBytes(bound.maxResponseBytes);
    rowOperations.push(Object.freeze({operation: name,
      extent: checked(extent(name, quantity, transfer, true))}));
    credentialOperations.push(Object.freeze({phase, operationIndex, ...bound, ...(slot === undefined ? {} : {slot})}));
  };
  const targetCapacity = checked(compose(capacities[7], [requestEnvelope(target, false)]));
  for (const phase of ['capture-target', 'apply-target', 'resume-target']) {
    physical(phase, targetOperation, target, targetCapacity, 'target');
  }
  // The mutation's pure transport builder can run while its original row
  // request is still retained. Fund the declared constructor envelope in
  // this physical child before invoking it, independently of the row slot.
  const mutationCapacity = checked(compose(capacities[3],
    [capacities[2], requestEnvelope(mutation, true)]));
  physical('write', operation, mutation, mutationCapacity);
  return captureInstalledEffectPlanRecipe(Object.freeze({
    memberOperations: Object.freeze([member, member]), rowOperations: Object.freeze(rowOperations),
    controlsPerRow: capacities[4], captureConstruction: Object.freeze({operationIndex: 0}),
    recoveryConstruction: Object.freeze({operationIndex: 1}), requestConstruction: Object.freeze({operationIndex: 0}),
    credentialOperations: Object.freeze(credentialOperations),
  }), rowOperations.length + 2);
}

// Non-HTTP providers retain their actual pure constructor metadata. These six
// extents describe returned/workspace DATA, never policy, grants or a Plan.
// Common alone composes the native quantities, control codec and operation slots.
export function prepareInstalledPhysicalWritePlanRecipe({moon, operation, inputLimits, limits, construction,
  requestConstruction, physicalConstruction, targetReadOperation, footprintCapacity}: PhysicalOptions): InstalledEffectPlanRecipe {
  if (typeof operation !== 'string' || !operation || !operation.isWellFormed() ||
      !construction || nodeTypes.isProxy(construction) || !Object.isFrozen(construction)) {
    fail('InstalledPhysicalWriteConstructionUnavailable');
  }
  const dimensions = ['nodes', 'text', 'wire'];
  const selected = ['retained', 'workspace'].flatMap(name => {
    const field = Object.getOwnPropertyDescriptor(construction, name);
    const value = field?.value;
    if (!field || !Object.hasOwn(field, 'value') || !value || nodeTypes.isProxy(value) ||
        !Object.isFrozen(value) || Reflect.ownKeys(value).length !== dimensions.length) {
      fail('InstalledPhysicalWriteConstructionUnavailable');
    }
    return dimensions.map(key => {
      const field = Object.getOwnPropertyDescriptor(value, key);
      if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'bigint' ||
          field.value < 0n) fail('InstalledPhysicalWriteConstructionUnavailable');
      return field.value;
    });
  });
  const names = ['maxRequestBytes', 'maxRecoveryBytes', 'maxResponseBytes', 'maxOutcomeBytes', 'maxTransferBytes'] as const;
  if (Reflect.ownKeys(construction).length !== 2 || !limits || names.some(name =>
      !Number.isSafeInteger(limits[name]) || limits[name] < 1 || limits[name] > 2147483647)) {
    fail('InstalledPhysicalWriteConstructionUnavailable');
  }
  const provider = checked(moon.clientProgramInstalledSourceConstructionCapacity(...selected as CapacityFields));
  const physical = physicalConstruction === undefined ? provider : checked(
    moon.clientProgramComposeInstalledSourceConstructionCapacity!(provider, [physicalConstruction]));
  const controlEntryBytes = checked(moon.clientProgramInstalledEffectControlWireBound(
    limits.maxOutcomeBytes, effectLedgerImplementationBounds.maxEntryBytes)) as number;
  const quote = (controlWireBytes: number, previewBytes = inputLimits.preview.maxWireBytes,
    previewNodes = inputLimits.preview.maxNodes, previewDepth = inputLimits.preview.maxDepth,
    recoveryBytes = limits.maxRecoveryBytes) => checked(Reflect.apply(requestConstruction === undefined
    ? moon.clientProgramInstalledPhysicalWriteRecipeCapacities
    : moon.clientProgramInstalledPhysicalWriteRecipeCapacitiesWithRequest!, moon, [
    inputLimits.body.maxBytes, inputLimits.body.maxNodes, inputLimits.body.maxDepth,
    previewBytes, previewNodes, previewDepth,
    limits.maxRequestBytes, recoveryBytes, limits.maxResponseBytes,
    Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
    effectLedgerImplementationBounds.maxOutcomeNodes, effectLedgerImplementationBounds.maxOutcomeDepth,
    physical, controlWireBytes, ...(requestConstruction === undefined ? [] : [requestConstruction])]));
  const quantities = quote(controlEntryBytes), fallback = quote(0);
  if (!Array.isArray(quantities) || quantities.length !== 6 || !Array.isArray(fallback) || fallback.length !== 6) {
    fail('InstalledPhysicalWriteConstructionUnavailable');
  }
  const captureOperation = operation + '.capture', requestOperation = operation + '.request';
  const capture = checked(moon.clientProgramInstalledEffectCaptureRecipeExtentPrepare(captureOperation, quantities));
  // Cold reconstruction already owns these authenticated immutable inputs.
  // Select their actual wire envelope on the SAME staged constructor before
  // the provider rebuilds requests; retain the original full maximum as a bound.
  const recoveryInitial = checked(moon.clientProgramInstalledEffectCaptureRecipeExtentPrepare(
    captureOperation, quote(controlEntryBytes, 1, 1, 1, 1)));
  const recoveryExtent = checked(moon.clientProgramInstalledEffectOperationStagedExtentPrepare(
    recoveryInitial, capture));
  const recoveryInputExtent = (previewWire: unknown, recovery: unknown, memberIndex: number) => {
    if (typeof previewWire !== 'string' || !previewWire.isWellFormed() ||
        !Array.isArray(recovery) || !Number.isSafeInteger(memberIndex) || memberIndex < 0) {
      fail('InstalledPhysicalWriteConstructionUnavailable');
    }
    const previewBytes = Buffer.byteLength(previewWire);
    if (previewBytes < 1 || previewBytes > inputLimits.preview.maxWireBytes) {
      fail('InstalledPhysicalWriteConstructionUnavailable');
    }
    let recoveryBytes = 1;
    for (const entry of recovery) {
      if (entry?.memberIndex !== memberIndex) continue;
      if (typeof entry.wire !== 'string' || !entry.wire.isWellFormed()) {
        fail('InstalledPhysicalWriteConstructionUnavailable');
      }
      const bytes = Buffer.byteLength(entry.wire);
      if (bytes < 1 || bytes > limits.maxRecoveryBytes) fail('InstalledPhysicalWriteConstructionUnavailable');
      recoveryBytes = Math.max(recoveryBytes, bytes);
    }
    // Every JSON node/nesting level occupies an original UTF-8 byte. The
    // saved decoder's existing node/depth limits remain additional bounds;
    // no second parse or serialization is needed to quantify this constructor.
    return checked(moon.clientProgramInstalledEffectCaptureRecipeExtentPrepare(captureOperation,
      quote(controlEntryBytes, ...effectRecoveryPreviewBounds(previewBytes, inputLimits.preview), recoveryBytes)));
  };

  const extent = (name: string, capacity: unknown, transfer: bigint, physical: boolean) => checked(
    moon.clientProgramInstalledEffectOperationExtentFromCapacityPrepare(name, capacity, transfer, physical));
  const rowOperations = [
    Object.freeze({operation: requestOperation, extent: extent(requestOperation, quantities[2], 0n, false)}),
    Object.freeze({operation, extent: extent(operation, quantities[3], BigInt(limits.maxTransferBytes), true)}),
  ];
  let ownedReadOperations;
  if (targetReadOperation !== undefined) {
    if (requestConstruction === undefined || !text(targetReadOperation) || !targetReadOperation.isWellFormed()) {
      fail('InstalledPhysicalWriteConstructionUnavailable');
    }
    ownedReadOperations = Object.freeze(['capture-target', 'apply-target', 'resume-target'].map(phase => {
      const name = targetReadOperation + '.' + phase, operationIndex = rowOperations.length;
      rowOperations.push(Object.freeze({operation: name, extent: extent(name, quantities[2], 0n, false)}));
      return Object.freeze({phase, operationIndex});
    }));
  }
  const memberOperations = [Object.freeze({operation: captureOperation, extent: capture}),
    Object.freeze({operation: captureOperation, extent: recoveryExtent})];
  let footprintConstruction;
  if (footprintCapacity !== undefined) {
    const name = operation + '.footprint';
    footprintConstruction = Object.freeze({operationIndex: memberOperations.length});
    memberOperations.push(Object.freeze({operation: name, extent: extent(name, footprintCapacity, 0n, false)}));
  }
  return captureInstalledEffectPlanRecipe(Object.freeze({
    memberOperations: Object.freeze(memberOperations),
    rowOperations: Object.freeze(rowOperations),
    ...(ownedReadOperations === undefined ? {} : {ownedReadOperations}),
    savedControlCodec: Object.freeze({maxEntryBytes: controlEntryBytes, fallbackCapacity: fallback[4]}),
    controlsPerRow: quantities[4], captureConstruction: Object.freeze({operationIndex: 0}),
    recoveryConstruction: Object.freeze({operationIndex: 1, inputExtent: recoveryInputExtent}),
    ...(footprintConstruction === undefined ? {} : {footprintConstruction}),
    requestConstruction: Object.freeze({operationIndex: 0}),
    physicalWrite: Object.freeze({operationIndex: 1, transferBytes: BigInt(limits.maxTransferBytes)}),
  }), rowOperations.length + memberOperations.length);
}

// The selected Host supplies original typed extents from its actual implementation
// recipe. Names/limits alone cannot select a Plan. Preserve those same opaque
// Core values; this view creates no capacity, admission or permission.
export function captureDeclaredUpdateTargetCapacity(moon: object) {
  const method = (name: string) => {
    const field = Object.getOwnPropertyDescriptor(moon, name);
    if (typeof field?.value !== 'function' || nodeTypes.isProxy(field.value) ||
        nodeTypes.isAsyncFunction(field.value)) fail('InvalidInstalledEffectPlanRecipe');
    return field.value;
  };
  const quantity = method('clientProgramInstalledSourceConstructionCapacity');
  const compose = method('clientProgramComposeInstalledSourceConstructionCapacity');
  return (original: unknown, maxTargetBytes: number) => {
    if (!Number.isSafeInteger(maxTargetBytes) || maxTargetBytes < 1 || maxTargetBytes > 2147483647) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    const targetBytes = BigInt(maxTargetBytes);
    // Original path/query text, encoded pieces, joined query and complete
    // target can coexist. Keep each worst-case UTF-16 backing and the encoded
    // wire in the existing physical operation until that child retires.
    const target = checked(Reflect.apply(quantity, moon, [0n, 0n, 0n, 0n, 8n * targetBytes, targetBytes]));
    return checked(Reflect.apply(compose, moon, [original, [target]]));
  };
}
