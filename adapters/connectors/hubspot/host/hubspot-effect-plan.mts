// Same Common constructor/Grant/HTTP quantities and checked managed Plan.
// This assembly supplies immutable limits and actual installed text counts;
// it creates no Account decision, permission, operation use or cleanup ACK.
import {types as nodeTypes} from 'node:util';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeTupleFromFields, runtimeUnboxedReferenceOption} from '../../../host-common/compiler-binding.generated.mjs';
import {captureDeclaredUpdateTargetCapacity, measureInstalledEffectRecoveryInput}
  from '../../../host-node/installed-effect-plan.mjs';
import type {TargetMutationRecipe} from '../../../host-node/installed-effect-recipe-construction.mjs';
import {effectLedgerImplementationBounds} from '../../../host-node/effect-ledger-implementation-bounds.mjs';
import {httpsCredentialAuthorizationPrefix, httpsCredentialDefaultRequestBytes,
  httpsCredentialResponseHeaderByteLimit, httpsCredentialResponseReadQuantum} from '../../../site-node/https-credential-resource.mjs';
import {HUBSPOT_ACCOUNT_DETAILS_OPERATION} from '../site/hubspot-account-read.mjs';
import {HUBSPOT_PROPERTIES_READ_OPERATION} from '../site/hubspot-object-read.mjs';
import {HUBSPOT_OBJECT_BATCH_READ_OPERATION} from '../site/hubspot-target-read.mjs';
import {HUBSPOT_INSTALLED_UPDATE_OPERATION, hubspotUpdatePathFixedBytes} from './hubspot-update-driver.mjs';

type Native = Readonly<{
  clientProgramHubSpotEffectConstructorCapacity(kind: number, input: readonly number[], output: readonly number[],
    counts: readonly number[]): unknown;
  clientProgramHubSpotEffectRecipeCapacities(original: readonly unknown[], finalization: unknown,
    limits: readonly number[], metadataUnits: bigint, responseReadQuantum: number,
    controlWireBytes: number, hostInputBytes: number): unknown;
  clientProgramInstalledEffectControlWireBound(outcomeBytes: number, maximumBytes: number): unknown;
  clientProgramInstalledOpaqueBoundaryFootprintCapacity(origin: string, portalId: string, objectTypeUnits: number): unknown;
  clientProgramInstalledEffectOperationStagedExtentPrepare(initial: unknown, maximum: unknown): unknown;
  clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation: string, capacity: unknown,
    transfer: bigint, physical: boolean): unknown;
  clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare(operation: string, recipe: readonly unknown[],
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramInstalledEffectOperationDiscardedProjectionExtentPrepare(extent: unknown, projection: unknown): unknown;
  clientProgramInstalledEffectOperationEmptyResponseHeadersExtentPrepare(extent: unknown, headerBytes: number): unknown;
  clientProgramInstalledEffectOperationResponseHeadersRequire(extent: unknown, selectedNames: readonly string[], maxHeaderBytes: number): unknown;
}>;
type Options = Readonly<{mappings: unknown; origin: string; portalId: string; objectTypeUnits: number;
  metadataResources: unknown; credentialSite: unknown; limits: unknown; inputLimits: unknown; maxRecoveryBytes: number}>;
type ReadField = 'maxResponseBytes' | 'maxRequestBytes' | 'maxNodes' | 'maxDepth' | 'maxProperties' |
  'maxNameUnits' | 'maxRows' | 'maxColumns' | 'maxCursorUnits' | 'maxValueNodes' | 'maxValueTextBytes' |
  'maxOutputBytes' | 'maxOutputNodes' | 'maxOutputDepth' | 'maxRequestNodes' | 'maxRequestDepth';
type WriteField = 'maxRequestBytes' | 'maxResponseBytes' | 'maxNodes' | 'maxDepth' | 'maxRows';
type NumericRecord<Key extends string> = Readonly<Record<Key, number>>;

const fail: () => never = () => {throw Object.assign(new Error('HubSpotEffectRecipeUnavailable'), {code: 'HubSpotEffectRecipeUnavailable'});};
const positive = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) > 0 && (value as number) <= 2147483647;
const data = <Key extends string,>(object: unknown, names: readonly Key[]) => {
  if (!object || nodeTypes.isProxy(object)) fail();
  return Object.freeze(Object.fromEntries(names.map(name => {
    const field = Object.getOwnPropertyDescriptor(object, name);
    if (!field || !Object.hasOwn(field, 'value')) fail();
    return [name, field.value];
  }))) as Readonly<Record<Key, unknown>>;
};
const numbers = <const Names extends readonly string[],>(object: unknown, names: Names) => {
  const record = data(object, names);
  if (!Object.values(record).every(positive)) fail();
  return Object.freeze(Object.values(record)) as unknown as Readonly<{[Index in keyof Names]: number}>;
};
const method = <Name extends keyof Native,>(receiver: unknown, name: Name): Native[Name] => {
  const selected = data(receiver, [name])[name];
  if (typeof selected !== 'function' || nodeTypes.isProxy(selected) || nodeTypes.isAsyncFunction(selected)) fail();
  return ((...args: unknown[]) => Reflect.apply(selected, receiver, args)) as Native[Name];
};

export function captureHubSpotUpdateConstruction({moon}: Readonly<{moon: object}>) {
  const composeUpdateTarget = captureDeclaredUpdateTargetCapacity(moon);
  const constructor = method(moon, 'clientProgramHubSpotEffectConstructorCapacity');
  const compose = method(moon, 'clientProgramHubSpotEffectRecipeCapacities');
  const controlBound = method(moon, 'clientProgramInstalledEffectControlWireBound');
  const footprintCapacity = method(moon, 'clientProgramInstalledOpaqueBoundaryFootprintCapacity');
  const stage = method(moon, 'clientProgramInstalledEffectOperationStagedExtentPrepare');
  const extent = method(moon, 'clientProgramInstalledEffectOperationExtentFromCapacityPrepare');
  const capture = method(moon, 'clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare');
  const discardProjection = method(moon, 'clientProgramInstalledEffectOperationDiscardedProjectionExtentPrepare');
  const emptyResponseHeaders = method(moon, 'clientProgramInstalledEffectOperationEmptyResponseHeadersExtentPrepare');
  // Matching Common must enforce this exact selection before the request.
  method(moon, 'clientProgramInstalledEffectOperationResponseHeadersRequire');
  return function prepareHubSpotEffectConstruction({mappings, origin, portalId, objectTypeUnits,
    metadataResources, credentialSite, limits, inputLimits, maxRecoveryBytes}: Options): TargetMutationRecipe {
    if (!Array.isArray(mappings) || nodeTypes.isProxy(mappings) || !Object.isFrozen(mappings) ||
        mappings.length < 1 || typeof origin !== 'string' || !origin || typeof portalId !== 'string' || !positive(portalId.length) ||
        !positive(objectTypeUnits) || !positive(maxRecoveryBytes)) fail();
    const resources = data(metadataResources, ['account', 'properties']) as Readonly<Record<'account' | 'properties', string>>;
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
      'maxOutputBytes', 'maxOutputNodes', 'maxOutputDepth', 'maxRequestNodes', 'maxRequestDepth']) as NumericRecord<ReadField>;
    const write = data(fixed.write, ['maxRequestBytes', 'maxResponseBytes', 'maxNodes', 'maxDepth', 'maxRows']) as NumericRecord<WriteField>;
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
      mappingUnits = Math.max(mappingUnits, (selected.resource as string).length + (selected.mappingRef as string).length + (selected.mappingCid as string).length + units);
    }
    let bindingUnits = 12 * 71 + 1024 + objectTypeUnits + portalId.length + mappingUnits;
    for (const record of [secretLimits.scope, secretLimits.issuer]) {
      if (!record || nodeTypes.isProxy(record)) fail();
      for (const field of Object.values(Object.getOwnPropertyDescriptors(record as object))) {
        if (!Object.hasOwn(field, 'value')) fail();
        if (typeof field.value === 'string') bindingUnits += field.value.length;
      }
    }
    if (![fields, fieldUnits, bindingUnits].every(positive)) fail();
    const counts = Object.freeze([fields, fieldUnits, bindingUnits]);
    const requestInput = Object.freeze([...body, ...request, 1, read.maxProperties, read.maxColumns,
      read.maxRequestBytes, read.maxRequestNodes, read.maxRequestDepth]);
    const quote = (kind: number, input: readonly number[], output: readonly number[] = [], sizes: readonly number[] = []) => {
      const value = runtimeUnboxedReferenceOption(constructor(kind, input, output, sizes));
      if (value === undefined || value === null) fail();
      return value;
    };
    const requestCapacity = quote(0, requestInput, [], counts), finalization = quote(6, requestInput, [], counts);
    const responseCapacity = quote(2, [write.maxResponseBytes, write.maxNodes, write.maxDepth]);
    const targetOutput = Object.freeze([read.maxOutputBytes, read.maxOutputNodes, read.maxOutputDepth]);
    const profile = (targetBytes: number, metadataBytes: number, metadataKind = 5, geometry: readonly number[] = []) => {
      const bytes = Math.max(1, targetBytes);
      const target = quote(1, [bytes, Math.min(read.maxNodes, bytes), Math.min(read.maxDepth, bytes), 1,
        read.maxColumns, read.maxCursorUnits, read.maxValueNodes, read.maxValueTextBytes], targetOutput, counts);
      const metadata = quote(metadataKind, metadataKind === 9 ? [] : metadataKind === 3
        ? [metadataBytes, portalId.length, read.maxResponseBytes, read.maxNodes, read.maxDepth]
        : metadataKind === 4
        ? [metadataBytes, objectTypeUnits, read.maxResponseBytes, read.maxNodes, read.maxDepth, read.maxProperties, read.maxNameUnits]
        : [metadataBytes, portalId.length, objectTypeUnits, read.maxResponseBytes, read.maxNodes, read.maxDepth, read.maxProperties, read.maxNameUnits],
        [], metadataKind === 4 ? geometry : []);
      // The binding enumerates the original tuple's numeric array keys.
      return [requestCapacity, target, responseCapacity, metadata].map(value =>
        runtimeTupleFromFields([value, undefined, undefined] as unknown as Parameters<typeof runtimeTupleFromFields>[0]));
    };
    const maximumWire = Math.max(preview[0], maxRecoveryBytes);
    const parameters = Object.freeze([maximumWire, preview[1], preview[2], ...row,
      write.maxRequestBytes, write.maxResponseBytes, read.maxRequestBytes, read.maxResponseBytes,
      httpsCredentialDefaultRequestBytes, read.maxResponseBytes, secretBytes,
      httpsCredentialAuthorizationPrefix.length, httpsCredentialResponseHeaderByteLimit,
      Math.max(effectLedgerImplementationBounds.maxEntryBytes, effectLedgerImplementationBounds.maxResponseBytes),
      Math.max(effectLedgerImplementationBounds.maxNodes, effectLedgerImplementationBounds.maxOutcomeNodes),
      Math.max(effectLedgerImplementationBounds.maxDepth, effectLedgerImplementationBounds.maxOutcomeDepth)]);
    const controlBytes = checked(controlBound(write.maxResponseBytes, effectLedgerImplementationBounds.maxEntryBytes)) as number;
    const quantities = (original: readonly unknown[], hostBytes = 0, control = controlBytes) => {
      // Policy wire/text storage is already retained on the original child.
      // Core stages the actual parser forest through hostBytes separately;
      // replacing its policy ceiling here would shrink that live retention.
      return checked(compose(original, finalization, parameters, BigInt(bindingUnits),
        httpsCredentialResponseReadQuantum, control, hostBytes)) as readonly unknown[];
    };
    const initialProfile = profile(0, 0), maximumProfile = profile(read.maxResponseBytes, read.maxResponseBytes);
    const initial = quantities(initialProfile), maximum = quantities(maximumProfile, -1), fallback = quantities(initialProfile, 0, 0);
    if ([initial, maximum, fallback].some(value => !Array.isArray(value) || value.length !== 8)) fail();
    const captureName = HUBSPOT_INSTALLED_UPDATE_OPERATION + '.capture';
    const capturedExtent = (values: readonly unknown[]) => checked(capture(captureName, values.slice(0, 6), ...preview));
    const inputExtent = (previewWire: unknown, recovery: unknown, memberIndex: number) => {
      const {previewBytes, recoveryBytes} = measureInstalledEffectRecoveryInput(previewWire, recovery,
        memberIndex, preview[0], maxRecoveryBytes, fail);
      return capturedExtent(quantities(initialProfile, Math.max(previewBytes, recoveryBytes), controlBytes));
    };
    const operationExtent = (operation: string, capacity: unknown, transfer = 0n, physical = false) =>
      checked(extent(operation, capacity, transfer, physical));
    const captureOperation = {operation: captureName,
      extent: checked(stage(capturedExtent(initial), capturedExtent(maximum)))};
    const footprint = runtimeUnboxedReferenceOption(footprintCapacity(origin, portalId, objectTypeUnits));
    if (footprint === undefined || footprint === null) fail();
    const footprintName = HUBSPOT_INSTALLED_UPDATE_OPERATION + '.footprint';
    const footprintOperation = {operation: footprintName, extent: operationExtent(footprintName, footprint)};
    const readOccurrence = (slot: string, resource: string | undefined, operation: string, kind: number) => ({
      operation, slot, resource,
      maxRequestBytes: kind === 1 ? read.maxRequestBytes : httpsCredentialDefaultRequestBytes,
      maxResponseBytes: read.maxResponseBytes,
      prepare(transfer: bigint) {
        const position = kind === 1 ? 6 : 7;
        const discardedProjection = slot === 'schema-after'
          ? quantities(profile(0, 0, 9))[position] : undefined;
        const extentOf = (values: readonly unknown[]) => {
          const original = operationExtent(operation, values[position], transfer, true);
          const output = discardedProjection === undefined ? original : checked(
            discardProjection(original, discardedProjection));
          // This original HubSpot read declares no observed response headers.
          // Keep the full receive/parse peak; Common owns the success-only cut.
          return checked(emptyResponseHeaders(output, httpsCredentialResponseHeaderByteLimit));
        };
        // The original physical backing and its received-input growth must use
        // the SAME constructor. A generic Account/schema maximum is appropriate
        // for the shared capture, but its retained schema output cannot become
        // an Account operation's initial backing and then shrink at InputBegin.
        const physicalProfile = (bytes: number, geometry?: readonly number[]) => kind === 1 ? profile(bytes, 0) : profile(0, bytes, kind, geometry);
        const responseExtent = (bytes: number, body: Uint8Array, geometry?: readonly number[]) => {
          if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > read.maxResponseBytes ||
              !(body instanceof Uint8Array) || body.byteLength !== bytes) fail();
          return extentOf(quantities(physicalProfile(bytes, geometry)));
        };
        return {extent: checked(stage(extentOf(quantities(physicalProfile(0))),
          extentOf(quantities(physicalProfile(read.maxResponseBytes))))), responseExtent,
          ...(discardedProjection === undefined ? {} : {discardResponseProjection: true as const})};
      },
    });
    const operation = HUBSPOT_INSTALLED_UPDATE_OPERATION;
    return {
      capture: captureOperation, footprint: footprintOperation, recoveryInputExtent: inputExtent,
      request: {operation: operation + '.request', extent: operationExtent(operation + '.request', initial[2])},
      finalization: {operation: operation + '.finalize', extent: operationExtent(operation + '.finalize', finalization)},
      describe: [
        readOccurrence('account', resources.account, HUBSPOT_ACCOUNT_DETAILS_OPERATION, 3),
        readOccurrence('schema', resources.properties, HUBSPOT_PROPERTIES_READ_OPERATION, 4),
      ],
      targets: [
        readOccurrence('account', resources.account, HUBSPOT_ACCOUNT_DETAILS_OPERATION, 3),
        readOccurrence('schema-before', resources.properties, HUBSPOT_PROPERTIES_READ_OPERATION, 4),
        readOccurrence('target', undefined, HUBSPOT_OBJECT_BATCH_READ_OPERATION, 1),
        readOccurrence('schema-after', resources.properties, HUBSPOT_PROPERTIES_READ_OPERATION, 4),
      ],
      writes() {
        // A BMP unit can encode to three UTF-8 bytes with three ASCII bytes each.
        // A supplementary code point uses two units and fits the same bound.
        const maxTargetBytes = hubspotUpdatePathFixedBytes + 9 * objectTypeUnits;
        const writeCapacity = composeUpdateTarget(initial[3], maxTargetBytes);
        return [{operation, maxRequestBytes: write.maxRequestBytes, maxResponseBytes: write.maxResponseBytes,
          maxTargetBytes, prepare: transfer => ({extent: operationExtent(operation, writeCapacity, transfer, true)})}];
      },
      controlsPerRow: initial[4],
      savedControlCodec: Object.freeze({maxEntryBytes: controlBytes, fallbackCapacity: fallback[4]}),
    };
  };
}
