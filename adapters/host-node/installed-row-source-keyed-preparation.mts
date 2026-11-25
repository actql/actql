import {authorizationRuntimeCode} from '../host-common/authorization-gate.mjs';
import {runtimeField, runtimeIsOk} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';

import type {createInstalledRowSourceReadAuthority} from './installed-row-source-read-authority.mjs';

type ReadAuthority = ReturnType<typeof createInstalledRowSourceReadAuthority>;
type Prepared = Parameters<ReadAuthority['decideRead']>[0];
type SourceAccess = Parameters<ReadAuthority['decideRead']>[1];
type KeyedPrepared = Prepared & Readonly<{checkedSource: Readonly<{selectionCid: string}>}>;
type KeyedOwner = Readonly<{
  preparedProgram?: unknown;
  preparedEffect?: unknown;
  keyedAcquisition: unknown;
  access: SourceAccess;
  physicalBindingCid: string;
}>;
type PrepareKeyedOptions = Readonly<{
  preparedProgram?: unknown;
  preparedEffect?: unknown;
  keyedAcquisition: unknown;
  requestIdentity: unknown;
  sourceAccess?: SourceAccess;
}>;
type VerifyKeyedReadOptions = Readonly<{
  preparedProgram: unknown;
  keyedAcquisition: unknown;
  preparedKeyed: KeyedPrepared;
  sourceAccess?: SourceAccess;
  signal?: AbortSignal;
}>;
type Target = readonly [resource: string, ...fields: string[]];
type KeyedRuntime = Readonly<{
  clientProgramMatchesRequestIdentity(preparedProgram: unknown, requestIdentity: unknown): boolean;
  clientProgramKeyedAcquisitionMatchesProgram(acquisition: unknown, preparedProgram: unknown): boolean;
  clientProgramEffectRequestScope(preparedEffect: unknown, requestIdentity: unknown): unknown;
  clientProgramKeyedAcquisitionMatchesEffectProgram(acquisition: unknown, preparedEffect: unknown): boolean;
  clientProgramKeyedRowPrepareCapacity(acquisition: unknown, declaration: unknown,
    maxPageBytes: number, maxTextBytes: number, maxWork: number): unknown;
  clientProgramKeyedAcquisitionSourceEvidenceFacts(acquisition: unknown): unknown;
  clientProgramKeyedAcquisitionInputCoordinates(acquisition: unknown): unknown;
  clientProgramKeyedRowCapacityTarget(capacity: unknown, declaration: unknown): unknown;
  clientRequestProgramCid(requestIdentity: unknown): string;
  clientRequestParametersCid(requestIdentity: unknown): string;
}>;

export function createInstalledRowSourceKeyedPreparation({keyedPreparations, originalReader, moon, declaration, limits,
  sourceRefs, cidPattern, valueCid, site, physicalTarget, sourceAccess, decideRead, currentRead,
  connectorRegistration, connectorRevision, bindingCid}: Pick<ReadAuthority, 'decideRead' | 'currentRead'> & {
  keyedPreparations: Pick<WeakMap<KeyedPrepared, KeyedOwner>, 'get' | 'set'>;
  originalReader: object | undefined;
  moon: KeyedRuntime;
  declaration: unknown;
  limits: Readonly<{maxPageBytes: number}>;
  sourceRefs: ReadonlySet<string>;
  cidPattern: RegExp;
  valueCid(value: unknown): string;
  site: Readonly<{connection: string}>;
  physicalTarget(resource: string, fields: readonly string[]): unknown;
  sourceAccess: SourceAccess;
  connectorRegistration: string;
  connectorRevision: string;
  bindingCid: string;
}) {
  // A declared keyed response port is selected before observing any left
  // rows. It is not a fabricated Direct requirement or an individual GET.
  async function prepareKeyed({preparedProgram, preparedEffect, keyedAcquisition, requestIdentity,
    sourceAccess: access = sourceAccess}: PrepareKeyedOptions) {
    // This selected declaration covers the Direct reader only, not a keyed
    // child or listing report. Other original profiles retain their behavior.
    if (originalReader !== undefined) fail('InstalledProviderSourceUnavailable');
    if ((preparedProgram === undefined) === (preparedEffect === undefined) || requestIdentity === undefined ||
        (preparedEffect === undefined
          ? moon.clientProgramMatchesRequestIdentity(preparedProgram, requestIdentity) !== true ||
            moon.clientProgramKeyedAcquisitionMatchesProgram(keyedAcquisition, preparedProgram) !== true
          : moon.clientProgramEffectRequestScope(preparedEffect, requestIdentity) === undefined ||
            moon.clientProgramKeyedAcquisitionMatchesEffectProgram(keyedAcquisition, preparedEffect) !== true)) {
      fail('InstalledSourceProgramMismatch');
    }
    const capacity = checked(moon.clientProgramKeyedRowPrepareCapacity(keyedAcquisition,
      declaration, limits.maxPageBytes, limits.maxPageBytes, 1000000));
    const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
    if (!Array.isArray(facts) || facts.length !== 6 || !sourceRefs.has(facts[0])) {
      fail('InstalledSourceEvidenceFactsUnavailable');
    }
    const selectedCoordinates = moon.clientProgramKeyedAcquisitionInputCoordinates(keyedAcquisition);
    const coordinates = runtimeIsOk(selectedCoordinates) ? runtimeField(selectedCoordinates, 0) as readonly number[] : undefined;
    if (coordinates === undefined || coordinates.length !== 4 ||
        !coordinates.every(value => Number.isSafeInteger(value) && value >= 0)) {
      fail('InvalidAcquisitionOccurrence');
    }
    const [stage, input, task, step] = coordinates;
    const [resource, ...fields] = checked(
      moon.clientProgramKeyedRowCapacityTarget(capacity, declaration)) as Target;
    const [sourceRef, sourceContractCid, carrierSchemaContractCid,
      sourceDataPolicyCid, dataClassification, sourceViewContractCid] = facts;
    const programCid = moon.clientRequestProgramCid(requestIdentity);
    const parametersCid = moon.clientRequestParametersCid(requestIdentity);
    if (![programCid, parametersCid].every(value => cidPattern.test(value))) {
      fail('InstalledKeyedRequestIdentityUnavailable');
    }
    const selectionCid = valueCid({version: 'actql-installed-keyed-selection/0.1',
      programCid, parametersCid, coordinates, sourceFacts: facts});
    const prepared = Object.freeze({
      checkedSource: Object.freeze({selectionCid, programCid, parametersCid, step,
        sourceRef, sourceContractCid, carrierSchemaContractCid, sourceDataPolicyCid,
        dataClassification, sourceViewContractCid}),
      readTuple: Object.freeze({connection: site.connection, resource, operation: 'read' as const}),
      physicalBinding: physicalTarget(resource, fields),
    });
    const decision = await decideRead(prepared, access);
    if (decision?.action === 'deny') fail(authorizationRuntimeCode(decision)!, decision);
    keyedPreparations.set(prepared, {preparedProgram, preparedEffect, keyedAcquisition, access,
      physicalBindingCid: valueCid(prepared.physicalBinding)});
    return Object.freeze({prepared, occurrence: Object.freeze({stage, input, task})});
  }

  // Reopening retained bytes needs the same checked keyed selection's current
  // read authority, not a new RowRun or a grant inferred from saved metadata.
  // This checks the original preparation and installed target without I/O.
  async function verifyKeyedRead({preparedProgram, keyedAcquisition, preparedKeyed,
    sourceAccess: access = sourceAccess, signal}: VerifyKeyedReadOptions) {
    const owner = keyedPreparations.get(preparedKeyed);
    if (owner === undefined || owner.preparedProgram !== preparedProgram ||
        owner.keyedAcquisition !== keyedAcquisition || owner.access !== access) {
      fail('InstalledSourcePreparationMismatch');
    }
    const recheck = () => {
      signal?.throwIfAborted();
      if (moon.clientProgramKeyedAcquisitionMatchesProgram(keyedAcquisition, preparedProgram) !== true) {
        fail('InstalledSourceProgramMismatch');
      }
      const capacity = checked(moon.clientProgramKeyedRowPrepareCapacity(keyedAcquisition,
        declaration, limits.maxPageBytes, limits.maxPageBytes, 1000000));
      const [resource, ...fields] = checked(moon.clientProgramKeyedRowCapacityTarget(capacity, declaration)) as Target;
      if (valueCid(preparedKeyed.physicalBinding) !== owner.physicalBindingCid ||
          valueCid(physicalTarget(resource, fields)) !== owner.physicalBindingCid) {
        fail('InstalledSourcePreparationMismatch');
      }
    };
    recheck();
    const decision = await currentRead(preparedKeyed, access, signal);
    recheck();
    return decision;
  }
  function keyedRecoveryBinding(prepared: KeyedPrepared) {
    const owner = keyedPreparations.get(prepared);
    if (owner === undefined || valueCid(prepared.physicalBinding) !== owner.physicalBindingCid) {
      fail('InstalledSourcePreparationMismatch');
    }
    return Object.freeze({version: 'actql-installed-keyed-read-binding/0.1',
      selectionCid: prepared.checkedSource.selectionCid,
      physicalBindingCid: owner.physicalBindingCid,
      connectorRegistration, connectorRevision, bindingCid, connection: site.connection});
  }

  return {prepareKeyed, verifyKeyedRead, keyedRecoveryBinding};
}
