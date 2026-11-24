// Original Checkpoint connection input validation and the immutable identity
// projections retained by the installed Host. No operation here grants access.
import {createHash, createPublicKey} from 'node:crypto';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {BOUND_SOURCE_SUBMISSION, validBoundSourceOccurrence} from './ordinary-source-binding.mjs';
import {MAX_INSTALLED_EFFECT_PROFILES} from './installed-effect-limits.mjs';

import type {BinaryLike, KeyObject} from 'node:crypto';
import type {createLocalAuthorizationGate} from './local-account-config.mjs';

type GateOptions = NonNullable<Parameters<typeof createLocalAuthorizationGate>[0]>;
type TargetAuthorization = Pick<GateOptions, 'accountConfiguration' | 'accountConstruction'> &
  Readonly<{context: NonNullable<GateOptions['context']>}>;
type TargetSelector = Readonly<{kind: string; target: string; mappingRef: string; mappingCid: string; effectId?: string}>;
type EffectTarget = Readonly<{selectors: readonly TargetSelector[]; authorization: TargetAuthorization}>;
type Mapping = Readonly<{mappingRef: string; mappingCid: string}>;
type MappingOwner = Mapping & Readonly<{authorization: TargetAuthorization; target: string}>;
type InstalledEffectTarget = {
  readonly authority: TargetAuthorization;
  readonly mappings: readonly Mapping[];
  readonly configuration: Readonly<TargetAuthorization>;
  gate?: Awaited<ReturnType<typeof createLocalAuthorizationGate>>;
};
type ReviewerInput = Readonly<{
  keyId: string; reviewerId: string; principalId: string; publicKey: Parameters<typeof createPublicKey>[0];
}>;
type TrustedReviewer = Omit<ReviewerInput, 'publicKey'> & Readonly<{publicKey: KeyObject}>;
type CheckedSource = Readonly<{
  sourceRef: string; requirementCid?: string; selectionCid?: string; programCid?: string;
  parametersCid?: string; step?: number;
}>;
export type CapturedOccurrence = Readonly<{
  stage?: number; input?: number; task?: number; physicalBinding?: unknown; installationBinding?: unknown;
  readTuple: Readonly<{operation: string; connection: string; resource: string}>;
  checkedSource: CheckedSource;
}>;
export type SourceCapture = Readonly<{
  version: string; acquisition?: CapturedOccurrence; acquisitions?: readonly CapturedOccurrence[];
}>;

export const IDENTIFIER = /^[A-Za-z0-9._:-]{1,128}$/u;
const MULTI_SOURCE_SUBMISSION = 'actql-remote-multi-source-submission/0.1';
const KEYED_SOURCE_SUBMISSION = 'actql-remote-keyed-source-submission/0.1';
export const pluralCapture = (captured: SourceCapture) => [MULTI_SOURCE_SUBMISSION, KEYED_SOURCE_SUBMISSION, BOUND_SOURCE_SUBMISSION]
  .includes(captured.version);
// The existing read-scope CID binds the full checked occurrence. Include the
// original Run separately and keep the identifier bounded even for a maximal
// Run ID; neither a Source slot nor a Unit index is a global Checkpoint ID.
export function computationSourceCheckpointId(runId: string, scopeCid: string) {
  return `source-${contentCid({run_id: runId, read_scope_cid: scopeCid}).slice(7)}`;
}

export function coded(code: string, detail?: unknown) {
  return Object.assign(new Error(code, detail === undefined ? undefined
    : {cause: detail}), {code});
}
export const fail: (code: string, detail?: unknown) => never = (code, detail) => { throw coded(code, detail); };
export const without = (value: object, ...keys: string[]) => Object.fromEntries(
  Object.entries(value).filter(([key]) => !keys.includes(key)));
export const hex = (value: BinaryLike) => createHash('sha256').update(value).digest('hex');
// Captured caller input is opaque data, not an installation identity.
export const capturedValueWire = (value: unknown) => canonicalValueJson(value, {dataKeys: true});
export const capturedValueCid = (value: unknown) => `sha256:${hex(capturedValueWire(value))}`;
// This is an installed Host-private bounded capture, not a new Run schema.
// A plural capture is never inferred by reinterpreting the singular field.
export function acquisitionsOf(captured: SourceCapture): readonly CapturedOccurrence[] {
  if (!pluralCapture(captured)) {
    if (captured.acquisitions !== undefined) fail('HeldAcquisitionChanged');
    return captured.acquisition === undefined ? [] : [captured.acquisition];
  }
  // A keyed Source can share task 0 with its Direct prefix (Content) or
  // occupy task 1. Retain that checked coordinate, never derive it from the
  // acquisition's position in this two-Source inventory.
  if (captured.acquisition !== undefined ||
      !Array.isArray(captured.acquisitions) ||
      captured.acquisitions.length !== 2 ||
      captured.acquisitions.some((item: CapturedOccurrence, index: number) =>
        !(captured.version === BOUND_SOURCE_SUBMISSION ? validBoundSourceOccurrence(item, index)
          : captured.version === KEYED_SOURCE_SUBMISSION
          ? Number.isSafeInteger(item?.stage) && item.stage! >= 0 &&
            Number.isSafeInteger(item.input) && item.input! >= 0 &&
            (index === 0 ? item.task === 0 : item.task === 0 || item.task === 1) &&
            (index === 0 ? typeof item.checkedSource?.requirementCid === 'string' &&
              item.checkedSource.selectionCid === undefined
              : typeof item.checkedSource?.selectionCid === 'string' &&
                item.checkedSource.requirementCid === undefined &&
                typeof item.checkedSource.programCid === 'string' &&
                typeof item.checkedSource.parametersCid === 'string' &&
                Number.isSafeInteger(item.checkedSource.step) && item.checkedSource.step! >= 0)
          : item?.stage === index && item.input === 0 && item.task === index &&
            typeof item.checkedSource?.requirementCid === 'string') ||
        typeof item.checkedSource?.sourceRef !== 'string' ||
        item.readTuple?.operation !== 'read' ||
        item.physicalBinding === undefined)) {
    fail('HeldAcquisitionChanged');
  }
  if (captured.version === KEYED_SOURCE_SUBMISSION &&
      (captured.acquisitions![0].stage !== captured.acquisitions![1].stage ||
       captured.acquisitions![0].input === captured.acquisitions![1].input)) {
    fail('HeldAcquisitionChanged');
  }
  return captured.acquisitions!;
}
export const occurrenceIdentity = (occurrence: CapturedOccurrence) => ({stage: occurrence.stage,
  input: occurrence.input, task: occurrence.task,
  ...(occurrence.checkedSource.selectionCid === undefined
    ? {requirement_cid: occurrence.checkedSource.requirementCid}
    : {selection_cid: occurrence.checkedSource.selectionCid})});
export const occurrenceKey = (occurrence: CapturedOccurrence) => occurrence.stage === undefined
  ? 'singular' : canonicalJson(occurrenceIdentity(occurrence));

export function trustedReviewers(reviewers: readonly ReviewerInput[] | undefined) {
  if (!Array.isArray(reviewers) || reviewers.length === 0) {
    fail('InvalidCheckpointReviewers');
  }
  const byKey = new Map<string, TrustedReviewer>();
  for (const reviewer of reviewers) {
    if (!IDENTIFIER.test(reviewer?.keyId ?? '') ||
        !IDENTIFIER.test(reviewer?.reviewerId ?? '') ||
        typeof reviewer.principalId !== 'string' || !reviewer.principalId ||
        byKey.has(reviewer.keyId)) {
      fail('InvalidCheckpointReviewers');
    }
    byKey.set(reviewer.keyId, Object.freeze({
      keyId: reviewer.keyId,
      reviewerId: reviewer.reviewerId,
      principalId: reviewer.principalId,
      publicKey: createPublicKey(reviewer.publicKey),
    }));
  }
  return byKey;
}

export function principals(values: readonly string[] | undefined, code: string): Set<string> {
  if (values === undefined) return new Set();
  if (!Array.isArray(values) || values.some(value =>
    typeof value !== 'string' || !value)) fail(code);
  return new Set(values);
}

// The installed adapter's authorization object is an opaque in-process
// selector. Retained identity uses only the checked Mapping and account
// bindings; caller-created lookalikes cannot select an authority.
export function captureEffectTargets(effectTargets: readonly EffectTarget[]): InstalledEffectTarget[] {
  const invalid: () => never = () => fail('InvalidRemoteHostEffectTargets');
  const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
  if (!Array.isArray(effectTargets) ||
      effectTargets.length > MAX_INSTALLED_EFFECT_PROFILES) invalid();
  const authorities = new Set<TargetAuthorization>();
  const byRef = new Map<string, MappingOwner>();
  const byCid = new Map<string, MappingOwner>();
  return Array.from(effectTargets, (item: EffectTarget): InstalledEffectTarget => {
    if (item === null || typeof item !== 'object' || Array.isArray(item)) invalid();
    const {selectors, authorization} = item;
    if (authorization === null || typeof authorization !== 'object' ||
        Array.isArray(authorization) || authorities.has(authorization) ||
        !Array.isArray(selectors) || selectors.length === 0) invalid();
    authorities.add(authorization);
    const mappings = new Map<string, Mapping>();
    for (const selector of selectors) {
      if (!text(selector?.kind) || !text(selector.target) ||
          !text(selector.mappingRef) ||
          !/^sha256:[0-9a-f]{64}$/u.test(selector.mappingCid ?? '') ||
          selector.effectId !== undefined && !text(selector.effectId)) invalid();
      const {mappingRef, mappingCid, target} = selector;
      const previous = byRef.get(mappingRef) ?? byCid.get(mappingCid);
      if (previous !== undefined && (previous.authorization !== authorization ||
          previous.mappingRef !== mappingRef || previous.mappingCid !== mappingCid ||
          previous.target !== target)) invalid();
      const mapping = {authorization, mappingRef, mappingCid, target};
      byRef.set(mappingRef, mapping);
      byCid.set(mappingCid, mapping);
      mappings.set(mappingRef, Object.freeze({mappingRef, mappingCid}));
    }
    // A profile has at least one uniquely owned Mapping, so the common
    // CheckEnvironment member bound also bounds this authority inventory.
    if (byRef.size > MAX_INSTALLED_EFFECT_PROFILES) invalid();
    const context = authorization.context;
    return {authority: authorization,
      mappings: Object.freeze([...mappings.values()]),
      configuration: Object.freeze({
        accountConfiguration: authorization.accountConfiguration,
        accountConstruction: authorization.accountConstruction,
        context: Object.freeze({...context}),
      })};
  });
}
