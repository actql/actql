import {checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {validInstallationBinding} from './ordinary-source-binding.mjs';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';

import type {installRowSourceAuthorization} from './installed-row-source-authorization.mjs';

type Scope = Parameters<Awaited<ReturnType<typeof installRowSourceAuthorization>>['authorize']>[1];
type SourceAccess = Readonly<{authorization: Pick<Awaited<ReturnType<typeof installRowSourceAuthorization>>, 'authorize'>}>;
type Prepared = Readonly<{
  checkedSource: Readonly<{sourceInput?: unknown; requirementCid?: string; selectionCid?: string}>;
  readSubjectCid?: string;
  readTuple: Scope;
  physicalBinding: unknown;
}>;
type Occurrence = Readonly<{stage: number; input: number; task: number; computeTask?: number}>;
type PriorPreparation = Readonly<{checkedOwner: unknown; requestIdentity: unknown; occurrence?: Occurrence}>;
type OriginalPreparation = PriorPreparation & Readonly<{
  wholeInput?: boolean;
  requirement: unknown;
  acquisition?: unknown;
  resource: string;
  physicalBindingCid: string;
  physicalBindingOriginal?: Readonly<{fields: readonly string[]}>;
  physicalTargetGeneration?: object;
}>;
type Target = readonly [resource: string, ...fields: string[]];

export function createInstalledRowSourceReadAuthority({preparations, installationBinding, immutableTargets,
  currentPhysicalTargetGeneration, moon, declaration, site, physicalTarget, directReadIdentity, valueCid, cid, cidPattern}: {
  preparations: Pick<WeakMap<Prepared, OriginalPreparation>, 'get'>;
  installationBinding: unknown;
  immutableTargets: object | undefined;
  currentPhysicalTargetGeneration(): object | undefined;
  moon: Readonly<{
    clientProgramWholeSourceTarget(acquisition: unknown): Target;
    clientProgramRowSourceTarget(declaration: unknown, requirement: unknown): unknown;
  }>;
  declaration: unknown;
  site: Readonly<{connection: string}>;
  physicalTarget(resource: string, fields: readonly string[]): unknown;
  directReadIdentity?: Readonly<{subject(prepared: Prepared): unknown}>;
  valueCid(value: unknown): string;
  cid(value: unknown): string;
  cidPattern: RegExp;
}) {
  function ordinaryRecoveryBinding(prepared: Prepared, expected?: PriorPreparation) {
    const owner = preparations.get(prepared);
    if (owner === undefined || !validInstallationBinding(installationBinding) ||
        expected !== undefined && (owner.checkedOwner !== expected.checkedOwner ||
          owner.requestIdentity !== expected.requestIdentity ||
          (['stage', 'input', 'task', 'computeTask'] as const).some(name =>
            owner.occurrence?.[name] !== expected.occurrence?.[name]))) {
      fail('InstalledSourcePreparationMismatch');
    }
    if (immutableTargets === undefined
      ? valueCid(prepared.physicalBinding) !== owner.physicalBindingCid
      : currentPhysicalTargetGeneration() === undefined || owner.physicalTargetGeneration !== currentPhysicalTargetGeneration() ||
        prepared.physicalBinding !== owner.physicalBindingOriginal) {
      fail('InstalledSourcePreparationMismatch');
    }
    const [resource, ...fields] = owner.wholeInput
      ? moon.clientProgramWholeSourceTarget(owner.acquisition)
      : checked(moon.clientProgramRowSourceTarget(declaration, owner.requirement)) as Target;
    if (resource !== owner.resource || prepared.readTuple.connection !== site.connection ||
        prepared.readTuple.resource !== resource || prepared.readTuple.operation !== 'read') {
      fail('InstalledSourcePreparationMismatch');
    }
    // The same immutable target was fully constructed and hashed at prepare.
    // Still obtain the exact Core target and compare all ordered field names;
    // this is not an Account decision or a substitute for its current checks.
    if (immutableTargets === undefined
      ? valueCid(physicalTarget(resource, fields)) !== owner.physicalBindingCid
      : fields.length !== owner.physicalBindingOriginal!.fields.length ||
        fields.some((field, index) => field !== owner.physicalBindingOriginal!.fields[index])) {
      fail('InstalledSourcePreparationMismatch');
    }
    return installationBinding;
  }

  // Read disclosure and held-Run authority are per declared view. The
  // acquisition access stays installation-scoped; its checked preparation
  // supplies the one exact view and read tuple before provider I/O.
  const ordinarySubject = (prepared: Prepared) => {
    const subject = directReadIdentity === undefined
      ? cid({version: 'actql-row-source-acquisition-read/0.1',
        ...(prepared.checkedSource.sourceInput === undefined
          ? {requirementCid: prepared.checkedSource.requirementCid}
          : {sourceInput: prepared.checkedSource.sourceInput}), physicalBinding: prepared.physicalBinding})
      : directReadIdentity.subject(prepared);
    if (typeof subject !== 'string' || !cidPattern.test(subject)) {
      fail('InvalidInstalledSourceReadIdentity');
    }
    return subject;
  };
  const decideRead = (prepared: Prepared, access: SourceAccess, signal?: AbortSignal) =>
    access.authorization.authorize('acquisition', prepared.readTuple, {
      subjectCid: prepared.readSubjectCid ?? (prepared.checkedSource.selectionCid === undefined
        ? ordinarySubject(prepared)
        : valueCid({version: 'actql-keyed-source-selection-read/0.1',
          selectionCid: prepared.checkedSource.selectionCid, physicalBinding: prepared.physicalBinding})), signal});
  const currentRead = async (prepared: Prepared, access: SourceAccess, signal?: AbortSignal) => {
    if (prepared.checkedSource?.selectionCid === undefined) ordinaryRecoveryBinding(prepared);
    const decision = await decideRead(prepared, access, signal);
    if (prepared.checkedSource?.selectionCid === undefined) ordinaryRecoveryBinding(prepared);
    if (decision?.action !== 'dispatch') {
      throw Object.assign(new Error('ExecutionAuthorizationDenied'),
        {code: 'ExecutionAuthorizationDenied', decision});
    }
    if (prepared.checkedSource?.selectionCid !== undefined &&
        decision.basis === 'resumed_approval') {
      const facts = checkpointApprovalFacts(decision);
      if (facts === undefined || (facts.checkedSource as Prepared['checkedSource'] | undefined)?.selectionCid !== prepared.checkedSource.selectionCid ||
          valueCid(facts.checkedSource) !== valueCid(prepared.checkedSource) ||
          valueCid(facts.physicalBinding) !== valueCid(prepared.physicalBinding) ||
          valueCid(facts.readTuple) !== valueCid(prepared.readTuple)) {
        fail('InstalledKeyedReadApprovalMismatch');
      }
    }
    if (prepared.checkedSource?.selectionCid === undefined && decision.basis === 'resumed_approval') {
      const facts = checkpointApprovalFacts(decision);
      if (facts === undefined || valueCid(facts.checkedSource) !== valueCid(prepared.checkedSource) ||
          valueCid(facts.readTuple) !== valueCid(prepared.readTuple) ||
          valueCid(facts.physicalBinding) !== valueCid(prepared.physicalBinding) ||
          (facts.installationBinding !== undefined &&
            valueCid(facts.installationBinding) !== valueCid(installationBinding))) {
        fail('InstalledSourceReadApprovalMismatch');
      }
    }
    return decision;
  };

  return {ordinaryRecoveryBinding, decideRead, currentRead};
}
