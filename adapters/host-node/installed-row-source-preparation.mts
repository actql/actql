import {types as nodeTypes} from 'node:util';
import {authorizationRuntimeCode} from '../host-common/authorization-gate.mjs';
import {runtimeField, runtimeOptionalField, runtimeIsBoxedSome} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';
import {prepareOriginalSourceQuery} from './original-query-preparation.mjs';

import type {createInstalledRowSourceReadAuthority} from './installed-row-source-read-authority.mjs';

type ReadAuthority = ReturnType<typeof createInstalledRowSourceReadAuthority>;
type Prepared = Parameters<ReadAuthority['decideRead']>[0];
type SourceAccess = Parameters<ReadAuthority['decideRead']>[1];
type Occurrence = Readonly<{stage: number; input: number; task: number; computeTask?: number}>;
type QueryOptions = Parameters<typeof prepareOriginalSourceQuery>[0];
type ContractInputs = Pick<QueryOptions, 'registry' | 'values' | 'fragment' | 'ordered'>;
type Target = readonly [resource: string, ...fields: string[]];
type PreparedOwner = Readonly<{
  checkedOwner: unknown;
  requestIdentity: unknown;
  effectful: boolean;
  occurrence: Occurrence;
  requirement: unknown;
  resource: string;
  access: SourceAccess;
  physicalBindingCid: string;
  physicalBindingOriginal?: unknown;
  physicalTargetGeneration?: object;
  retainedOnly?: true;
  acquisition?: unknown;
  wholeInput?: boolean;
  providerCaptureCapacity?: unknown;
  originalRead?: unknown;
  managedRun?: unknown;
}>;
type RetainedPreparationOptions = ContractInputs & Readonly<{
  preparedProgram: unknown;
  requestIdentity: unknown;
  occurrence: Occurrence;
  sourceAccess?: SourceAccess;
}>;
type PrepareOptions = ContractInputs & Readonly<{
  preparedProgram?: unknown;
  preparedEffect?: unknown;
  sourceAccess?: SourceAccess;
  queryTimePreparation?: unknown;
  requestIdentity?: unknown;
  managedRun?: unknown;
  preparedSource?: Prepared;
  occurrence?: Occurrence;
}>;
type SourceReadInput = Readonly<{
  checkedOwner: unknown;
  effectful: boolean;
  declaration: unknown;
  requirement: unknown;
  occurrence: Occurrence;
  managedRun?: unknown;
  originalRead?: unknown;
  requestIdentity?: unknown;
}>;
type AtOccurrence = (run: unknown, owner: unknown, request: unknown, task: number) => unknown;
type ReadAtOccurrence = (run: unknown, owner: unknown, request: unknown, declaration: unknown, task: number) => unknown;
type PreparationRuntime = QueryOptions['moon'] & Readonly<{
  clientProgramWholeSourceFacts(acquisition: unknown): unknown;
  clientProgramQueryRequirementSourceEvidenceFacts(requirement: unknown): unknown;
  clientProgramWholeSourceTarget(acquisition: unknown): Target;
  clientProgramRowSourceTarget(declaration: unknown, requirement: unknown): unknown;
  clientProgramEffectWholeSourceInputIdentity(owner: unknown, requirement: unknown): unknown;
  clientProgramWholeSourceInputIdentity(owner: unknown, requirement: unknown): unknown;
  clientProgramQueryRequirementCid(requirement: unknown): string;
  clientProgramQueryRequirementInputContractCid(requirement: unknown): string;
  clientProgramQueryRequirementOutputContractCid(requirement: unknown): string;
  clientProgramMatchesRequestIdentity(preparedProgram: unknown, requestIdentity: unknown): boolean;
  clientProgramPrepareLocalQueryRequirement: NonNullable<QueryOptions['moon']['clientProgramPrepareLocalQueryRequirement']>;
  clientProgramInstalledSourceReadCheckCurrent(read: unknown): unknown;
  clientProgramInstalledEffectManagedSourceRead?(run: unknown, declaration: unknown, task: number): unknown;
  clientProgramInstalledEffectManagedSourceInputKind?: AtOccurrence;
  clientProgramInstalledEffectManagedSourceOccurrence?: AtOccurrence;
  clientProgramInstalledEffectManagedRunCheck(run: unknown, owner: unknown, request: unknown): unknown;
  clientProgramInstalledEffectManagedWholeSourceRead?: ReadAtOccurrence;
  clientProgramInstalledManagedSourceOccurrence?: AtOccurrence;
  clientProgramInstalledManagedCaptureSourceRead?: ReadAtOccurrence;
  clientProgramInstalledManagedSourceInputKind?(run: unknown, owner: unknown, request: unknown): unknown;
  clientProgramInstalledManagedWholeSourceReadAt?: ReadAtOccurrence;
  clientProgramInstalledSourceReadBindEffectProgram(read: unknown, owner: unknown): unknown;
  clientProgramInstalledSourceReadBindProgram(read: unknown, owner: unknown): unknown;
  clientProgramInstalledSourceReadAttachAcquisition(read: unknown, declaration: unknown, requirement: unknown,
    acquisition: unknown, stage: number, input: number): unknown;
  clientProgramInstalledProviderRowCaptureCapacity(acquisition: unknown, capacity: unknown): unknown;
  clientProgramInstalledSourceReadRetire(read: unknown): unknown;
}>;

export function createInstalledRowSourcePreparation({moon, declaration, sourceRefs, site, physicalTarget, cidPattern,
  immutableTargets, currentPhysicalTargetGeneration, sourceAccess, preparations, preparingSourceReads,
  reauthorizingPreparations, valueCid, ordinaryRecoveryBinding, directReadIdentity, currentRead, originalReader,
  prepareSourceRead, decideRead, prepareOriginalAcquisition}: Pick<ReadAuthority, 'decideRead' | 'currentRead' | 'ordinaryRecoveryBinding'> & {
  moon: PreparationRuntime;
  declaration: unknown;
  sourceRefs: ReadonlySet<string>;
  site: Readonly<{connection: string}>;
  physicalTarget(resource: string, fields: readonly string[]): unknown;
  cidPattern: RegExp;
  immutableTargets: object | undefined;
  currentPhysicalTargetGeneration(): object | undefined;
  sourceAccess: SourceAccess;
  preparations: Pick<WeakMap<Prepared, PreparedOwner>, 'get' | 'set'>;
  preparingSourceReads: Pick<Set<unknown>, 'add' | 'has' | 'delete'>;
  reauthorizingPreparations: Pick<WeakSet<Prepared>, 'add' | 'has' | 'delete'>;
  valueCid(value: unknown): string;
  directReadIdentity?: Readonly<{input: number}>;
  originalReader?: Readonly<{capacity: unknown}>;
  prepareSourceRead?: (input: SourceReadInput) => unknown;
  prepareOriginalAcquisition(requirement: unknown): unknown;
}) {
  function describePreparedSource(requirement: unknown, occurrence: Occurrence, checkedOwner: unknown,
    wholeInput = false, plannedAcquisition?: unknown, effectful = false) {
    const facts = wholeInput ? moon.clientProgramWholeSourceFacts(plannedAcquisition)
      : checked(moon.clientProgramQueryRequirementSourceEvidenceFacts(requirement));
    if (!Array.isArray(facts) || facts.length !== 6 ||
        !facts.every(value => typeof value === 'string')) {
      fail('InstalledSourceEvidenceFactsUnavailable');
    }
    const [sourceRef, sourceContractCid, carrierSchemaContractCid,
      sourceDataPolicyCid, dataClassification, sourceViewContractCid] = facts;
    if (!sourceRefs.has(sourceRef)) fail('InstalledSourceProgramMismatch');
    const [resource, ...fields] = wholeInput ? moon.clientProgramWholeSourceTarget(plannedAcquisition)
      : checked(moon.clientProgramRowSourceTarget(declaration, requirement)) as Target;
    const sourceInputOption = !wholeInput ? undefined : effectful
      ? moon.clientProgramEffectWholeSourceInputIdentity(checkedOwner, requirement)
      : moon.clientProgramWholeSourceInputIdentity(checkedOwner, requirement);
    const sourceInput = wholeInput && runtimeIsBoxedSome(sourceInputOption)
      ? runtimeField(sourceInputOption, 0) : undefined;
    if (wholeInput && (!Array.isArray(sourceInput) || sourceInput.length !== 2 ||
        sourceInput.some(value => typeof value !== 'string' || !cidPattern.test(value)))) {
      fail('InstalledSourceProgramMismatch');
    }
    const prepared = Object.freeze({
      checkedSource: Object.freeze({
        ...(wholeInput ? {sourceInput: Object.freeze([...(sourceInput as readonly string[])])}
          : {requirementCid: moon.clientProgramQueryRequirementCid(requirement)}),
        sourceRef, sourceContractCid, carrierSchemaContractCid,
        sourceDataPolicyCid, dataClassification, sourceViewContractCid,
        ...(wholeInput ? {} : {
          inputContractCid: moon.clientProgramQueryRequirementInputContractCid(requirement),
          outputContractCid: moon.clientProgramQueryRequirementOutputContractCid(requirement)}),
      }),
      readTuple: Object.freeze({connection: site.connection, resource,
        operation: 'read' as const}),
      physicalBinding: physicalTarget(resource, fields),
      occurrence,
    });
    return {prepared, resource};
  }

  // Metadata for consuming already retained Model input. This entry creates
  // no Source read, acquisition, capture capacity or authorization decision.
  // The recovery Request backs the constructor before calling this Owner.
  function prepareRetained({preparedProgram, requestIdentity, occurrence,
    registry, values, fragment, ordered, sourceAccess: access = sourceAccess}: RetainedPreparationOptions) {
    if (immutableTargets !== undefined && currentPhysicalTargetGeneration() === undefined) {
      fail('InstalledSourceInitializationClosed');
    }
    if (preparedProgram === undefined || requestIdentity === undefined ||
        moon.clientProgramMatchesRequestIdentity(preparedProgram, requestIdentity) !== true ||
        occurrence === undefined || !(['stage', 'input', 'task'] as const).every(name =>
          Number.isSafeInteger(occurrence[name]) && occurrence[name] >= 0)) {
      fail('InstalledSourcePreparationMismatch');
    }
    const requirement = checked(moon.clientProgramPrepareLocalQueryRequirement(
      preparedProgram, occurrence.stage, occurrence.input, registry, values, fragment, ordered));
    const {prepared, resource} = describePreparedSource(requirement, Object.freeze({...occurrence}), preparedProgram);
    preparations.set(prepared, Object.freeze({checkedOwner: preparedProgram, effectful: false,
      retainedOnly: true, requirement, resource, access, requestIdentity, occurrence: prepared.occurrence,
      physicalBindingCid: valueCid(prepared.physicalBinding),
      ...(immutableTargets === undefined ? {} : {physicalBindingOriginal: prepared.physicalBinding,
        physicalTargetGeneration: currentPhysicalTargetGeneration()})}));
    ordinaryRecoveryBinding(prepared);
    return prepared;
  }

  async function prepare({preparedProgram, preparedEffect, registry, values,
    fragment, ordered, sourceAccess: access = sourceAccess,
    queryTimePreparation, requestIdentity, managedRun, preparedSource,
    occurrence = {stage: 0, input: 0, task: 0}}: PrepareOptions) {
    if (immutableTargets !== undefined && currentPhysicalTargetGeneration() === undefined) {
      fail('InstalledSourceInitializationClosed');
    }
    if ((preparedProgram === undefined) === (preparedEffect === undefined)) {
      fail('InvalidInstalledSourcePreparation');
    }
    const effectful = preparedEffect !== undefined;
    if (![occurrence.stage, occurrence.input, occurrence.task].every(Number.isSafeInteger) ||
        occurrence.stage < 0 || occurrence.input < 0 || occurrence.task < 0 ||
        (directReadIdentity !== undefined && occurrence.input !== directReadIdentity.input)) {
      fail('InvalidAcquisitionOccurrence');
    }
    occurrence = Object.freeze({...occurrence});
    const checkedOwner = preparedEffect ?? preparedProgram;
    if (preparedSource !== undefined) {
      const original = preparations.get(preparedSource);
      const recheck = () => {
        if (original === undefined || preparations.get(preparedSource) !== original ||
            original.checkedOwner !== checkedOwner || original.effectful !== effectful ||
            original.managedRun === undefined || original.managedRun !== managedRun ||
            original.requestIdentity !== requestIdentity ||
            original.occurrence.stage !== occurrence.stage ||
            original.occurrence.input !== occurrence.input ||
            original.occurrence.task !== occurrence.task ||
            !preparingSourceReads.has(original.originalRead)) {
          fail('InstalledSourcePreparationMismatch');
        }
        ordinaryRecoveryBinding(preparedSource);
        checked(moon.clientProgramInstalledSourceReadCheckCurrent(original.originalRead));
      };
      recheck();
      if (reauthorizingPreparations.has(preparedSource)) fail('InstalledSourcePreparationMismatch');
      reauthorizingPreparations.add(preparedSource);
      try {
        // Approval changes read authority, not the admitted Plan's original
        // acquisition. Revalidate that same unentered read instead of issuing
        // another one under an equal requirement.
        await currentRead(preparedSource, access);
        recheck();
        preparations.set(preparedSource, Object.freeze({...original!, access}));
        return preparedSource;
      } finally {
        reauthorizingPreparations.delete(preparedSource);
      }
    }
    let planned;
    let wholeInput = false;
    if (effectful) {
      if (managedRun === undefined || originalReader === undefined && prepareSourceRead === undefined ||
          typeof moon.clientProgramInstalledEffectManagedSourceRead !== 'function' ||
          typeof moon.clientProgramInstalledEffectManagedSourceInputKind !== 'function' ||
          typeof moon.clientProgramInstalledEffectManagedSourceOccurrence !== 'function') {
        fail('InstalledEffectPlanUnavailable');
      }
      const selected = checked(moon.clientProgramInstalledEffectManagedSourceOccurrence(
        managedRun, checkedOwner, requestIdentity, occurrence.task));
      if (runtimeOptionalField(selected, 0) !== occurrence.stage ||
          runtimeOptionalField(selected, 1) !== occurrence.input ||
          runtimeOptionalField(selected, 2) !== (occurrence.computeTask ?? occurrence.task)) {
        fail('InstalledSourcePreparationMismatch');
      }
      // The admitted parent already owns this acquisition/capacity. Do not
      // prepare another equal requirement or attach a replacement acquisition.
      checked(moon.clientProgramInstalledEffectManagedRunCheck(managedRun, checkedOwner, requestIdentity));
      const kind = checked(moon.clientProgramInstalledEffectManagedSourceInputKind(
        managedRun, checkedOwner, requestIdentity, occurrence.task));
      if (kind !== 'query' && kind !== 'whole-input') fail('InstalledEffectPlanUnavailable');
      wholeInput = kind === 'whole-input';
      if (wholeInput && typeof moon.clientProgramInstalledEffectManagedWholeSourceRead !== 'function') {
        fail('InstalledEffectPlanUnavailable');
      }
      planned = wholeInput
        ? checked(moon.clientProgramInstalledEffectManagedWholeSourceRead!(
          managedRun, checkedOwner, requestIdentity, declaration, occurrence.task))
        : checked(moon.clientProgramInstalledEffectManagedSourceRead(managedRun, declaration, occurrence.task));
    } else if (managedRun !== undefined && (originalReader !== undefined || prepareSourceRead !== undefined)) {
      if (typeof moon.clientProgramInstalledManagedSourceOccurrence !== 'function') fail('InstalledSourcePlanUnavailable');
      const selected = checked(moon.clientProgramInstalledManagedSourceOccurrence(
        managedRun, checkedOwner, requestIdentity, occurrence.task));
      if (runtimeOptionalField(selected, 0) !== occurrence.stage ||
          runtimeOptionalField(selected, 1) !== occurrence.input ||
          runtimeOptionalField(selected, 2) !== (occurrence.computeTask ?? occurrence.task)) {
        fail('InstalledSourcePreparationMismatch');
      }
      if (typeof moon.clientProgramInstalledManagedCaptureSourceRead !== 'function') {
        fail('InstalledSourcePlanUnavailable');
      }
      // Pure provider and Host reads consume the SAME original Plan acquisition.
      // Missing retained-plan support cannot fall back to another equal query.
      if (typeof moon.clientProgramInstalledManagedSourceInputKind !== 'function') {
        fail('InstalledSourcePlanUnavailable');
      }
      const kind = checked(moon.clientProgramInstalledManagedSourceInputKind(managedRun, checkedOwner, requestIdentity));
      if (kind !== 'query' && kind !== 'whole-input') fail('InstalledSourcePlanUnavailable');
      wholeInput = kind === 'whole-input';
      if (wholeInput && typeof moon.clientProgramInstalledManagedWholeSourceReadAt !== 'function') {
        fail('InstalledSourcePlanUnavailable');
      }
      planned = wholeInput
        ? checked(moon.clientProgramInstalledManagedWholeSourceReadAt!(
          managedRun, checkedOwner, requestIdentity, declaration, occurrence.task))
        : checked(moon.clientProgramInstalledManagedCaptureSourceRead(
          managedRun, checkedOwner, requestIdentity, declaration, occurrence.task));
    }
    const plannedRead = planned === undefined ? undefined : runtimeField(planned, 0);
    if (plannedRead !== undefined) preparingSourceReads.add(plannedRead);
    try {
      const requirement = planned === undefined ? prepareOriginalSourceQuery({moon,
        preparedProgram, preparedEffect, stage: occurrence.stage, input: occurrence.input,
        registry, values, fragment, ordered, queryTimePreparation, requestIdentity}).requirement
        : runtimeField(planned, 1);
      const plannedAcquisition = wholeInput ? runtimeField(planned, 2) : undefined;
      const {prepared, resource} = describePreparedSource(requirement, occurrence, checkedOwner, wholeInput, plannedAcquisition, effectful);
      const physicalBindingCid = valueCid(prepared.physicalBinding);
      const authorizePreparation = async () => {
        const decision = await decideRead(prepared, access);
        const refused = decision?.action === 'deny'
          ? authorizationRuntimeCode(decision) : undefined;
        if (refused !== undefined) {
          throw Object.assign(new Error(refused), {code: refused,
            authorization: decision});
        }
      };
      // Original provider compatibility authorizes before its pure acquisition
      // preparation. The ordinary path keeps its original opposite order.
      if (directReadIdentity !== undefined) await authorizePreparation();
      // The actual installation retains the imported child before returning
      // this same opaque read. A failure below remains with that original
      // supplier; no local scalar/fallback Ledger or cleanup ACK is created.
      const originalRead = planned !== undefined ? plannedRead
        : prepareSourceRead === undefined ? undefined :
          prepareSourceRead(Object.freeze({checkedOwner, effectful, declaration, requirement, occurrence}));
      if (planned !== undefined && prepareSourceRead !== undefined &&
          prepareSourceRead(Object.freeze({checkedOwner, effectful, declaration, requirement,
            occurrence, managedRun, originalRead, requestIdentity})) !== originalRead) fail('InstalledSourceReadUnavailable');
      if (originalRead !== undefined) {
        if (originalRead === undefined || nodeTypes.isPromise(originalRead)) fail('InstalledSourceReadUnavailable');
        // Bind includes the same current check. No external operation occurs
        // between a separate check and this original-owner binding.
        checked(effectful
          ? moon.clientProgramInstalledSourceReadBindEffectProgram(originalRead, checkedOwner)
          : moon.clientProgramInstalledSourceReadBindProgram(originalRead, checkedOwner));
      }
      // An installed provider may select its existing pure typed preparer. It
      // must return this exact requirement/declaration's original acquisition;
      // this is neither an I/O callback nor permission to replace a checked Run.
      const acquisition = planned !== undefined ? runtimeField(planned, 2)
        : prepareOriginalAcquisition(requirement);
      if (planned === undefined && originalRead !== undefined) checked(moon.clientProgramInstalledSourceReadAttachAcquisition(
        originalRead, declaration, requirement, acquisition, occurrence.stage, occurrence.input));
      const providerCaptureCapacity = planned !== undefined ? runtimeField(planned, 3)
        : originalReader === undefined ? undefined :
          moon.clientProgramInstalledProviderRowCaptureCapacity(acquisition, originalReader.capacity);
      if (originalReader !== undefined && providerCaptureCapacity === undefined) {
        fail('InstalledSourceCapacityUnavailable');
      }
      if (directReadIdentity === undefined) await authorizePreparation();
      if (plannedRead !== undefined && !preparingSourceReads.has(plannedRead)) {
        fail('InstalledSourceReadUnavailable');
      }
      preparations.set(prepared, Object.freeze({checkedOwner, effectful,
        requirement, resource, access, acquisition, wholeInput,
        occurrence, physicalBindingCid, providerCaptureCapacity, originalRead, managedRun, requestIdentity,
        ...(immutableTargets === undefined ? {} : {physicalBindingOriginal: prepared.physicalBinding,
          physicalTargetGeneration: currentPhysicalTargetGeneration()})}));
      ordinaryRecoveryBinding(prepared);
      return prepared;
    } catch (error) {
      if (plannedRead !== undefined && preparingSourceReads.has(plannedRead)) {
        try {
          checked(moon.clientProgramInstalledSourceReadRetire(plannedRead));
          preparingSourceReads.delete(plannedRead);
        } catch { /* SAME Source close retains the original retirement retry. */ }
      }
      throw error;
    }
  }

  return {prepare, prepareRetained};
}
