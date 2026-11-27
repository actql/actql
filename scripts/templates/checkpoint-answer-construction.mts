// This source is materialized and strictly compiled by the Checkpoint generator.
// Candidate DATA only; signature verification and admission belong to the Host.
import type {WireCheckpointSummary, WireResolveItem} from '@actql/client-wire';
import type {CheckpointAnswerContract, CheckpointAnswerFieldRule} from '../checkpoint-answer-wire.mjs';

/* @wire-bindings */

// These names brand only the opaque objects held by the two private WeakMaps.
declare const candidateStage: unique symbol;
declare const resolutionStage: unique symbol;
export type AnswerCandidate = Readonly<{[candidateStage]: true}>;
export type AnswerResolution = Readonly<{[resolutionStage]: true}>;
export interface AnswerLimits {
  readonly maxWireBytes: number;
  readonly maxNodes: number;
  readonly maxDepth: number;
}
export interface AnswerPrimitives {
  canonicalJson(value: unknown, options?: {dataKeys?: boolean}): string;
  bytesCid(bytes: Uint8Array<ArrayBuffer>): string | PromiseLike<string>;
}

type Data = Readonly<Record<string, unknown>>;
interface CapturedObject { readonly [key: string]: Captured }
type Captured = string | number | boolean | null | readonly Captured[] | CapturedObject;
type Profile = CheckpointAnswerContract['candidates'][number];
type ApprovalKind = Profile['approval'] | 'resolution';
type Context = Readonly<{
  summary: WireCheckpointSummary;
  actor: Readonly<{keyId: string; reviewerId: string; authorityScopeCid: unknown}>;
  decision: AnswerDecision;
  decidedAt: string;
  selectedProfile: Readonly<{preparedInvocationCid: string | undefined}>;
}>;
type Preparation = Readonly<{context: Context; profile: Profile;
  approval: CapturedObject | undefined; preimage: string | undefined; limits: AnswerLimits}>;
type Resolution = Readonly<{body: CapturedObject; preimage: string;
  approvalEvidenceWire: string; context: Context; limits: AnswerLimits}>;

const encoder = new TextEncoder();
const own = (value: unknown, key: PropertyKey) => Object.hasOwn(value as object, key);
const cidPattern = /^sha256:[0-9a-f]{64}$(?![\s\S])/u;
function refuse(code: string, field?: string): never {
  const cause = new TypeError('CheckpointCandidate:' + code);
  Object.defineProperties(cause, {code: {value: code}, field: {value: field}});
  throw cause;
}
function shape(value: unknown, required: readonly string[], optional: readonly string[] = []): asserts value is Data {
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      required.some(key => !own(value, key)) ||
      Object.keys(value).some(key => !required.includes(key) && !optional.includes(key))) refuse('InvalidShape');
}
function limitsOf(value: unknown): AnswerLimits {
  shape(value, ['maxWireBytes', 'maxNodes', 'maxDepth']);
  const result = {maxWireBytes: value.maxWireBytes as number, maxNodes: value.maxNodes as number, maxDepth: value.maxDepth as number};
  const minima = contract.recipe.limits;
  if (!Number.isSafeInteger(result.maxWireBytes) || result.maxWireBytes < minima.max_wire_bytes.minimum ||
      !Number.isSafeInteger(result.maxNodes) || result.maxNodes < minima.max_nodes.minimum ||
      !Number.isSafeInteger(result.maxDepth) || result.maxDepth < minima.max_depth.minimum) refuse('InvalidLimits');
  return Object.freeze(result);
}
function quotedBytes(text: string): number {
  let count = 2;
  for (let index = 0; index < text.length; index++) {
    const unit = text.charCodeAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = text.charCodeAt(++index);
      if (!(next >= 0xdc00 && next <= 0xdfff)) refuse('InvalidWire');
      count += 4;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) refuse('InvalidWire');
    else if (unit === 34 || unit === 92 || [8, 9, 10, 12, 13].includes(unit)) count += 2;
    else if (unit < 32) count += 6;
    else count += unit < 128 ? 1 : unit < 2048 ? 2 : 3;
  }
  return count;
}
function capture(value: Data, limits: AnswerLimits): CapturedObject;
function capture(value: unknown, limits: AnswerLimits): Captured;
function capture(value: unknown, limits: AnswerLimits): Captured {
  let nodes = 0, bytes = 0;
  const active = new Set<object>();
  const add = (count: number) => { bytes += count; if (bytes > limits.maxWireBytes) refuse('Encoding'); };
  const string = (value: string) => {
    if (value.length > limits.maxWireBytes) refuse('Encoding');
    add(quotedBytes(value));
    return value;
  };
  function visit(value: unknown, depth: number): Captured {
    if (++nodes > limits.maxNodes) refuse('Encoding');
    if (typeof value === 'string') return string(value);
    if (value === null || typeof value === 'boolean') { add(value === null ? 4 : value ? 4 : 5); return value; }
    if (typeof value === 'number') {
      if (!Number.isFinite(value) || Object.is(value, -0)) refuse('InvalidWire');
      add(JSON.stringify(value).length); return value;
    }
    if (typeof value !== 'object' || value === null || active.has(value) || depth >= limits.maxDepth) refuse('InvalidWire');
    if (!Array.isArray(value) && Object.getPrototypeOf(value) !== Object.prototype) refuse('InvalidWire');
    active.add(value);
    try {
      add(2);
      if (Array.isArray(value)) {
        const length = value.length;
        if (length > limits.maxNodes - nodes) refuse('Encoding');
        const result: Captured[] = [];
        for (let index = 0; index < length; index++) {
          if (index) add(1);
          result.push(visit(value[index], depth + 1));
        }
        return Object.freeze(result);
      }
      const result: Record<string, Captured> = {};
      let fields = 0;
      for (const key of Object.keys(value)) {
        if (fields++) add(1);
        string(key); add(1);
        Object.defineProperty(result, key, {value: visit((value as Data)[key], depth + 1), enumerable: true});
      }
      return Object.freeze(result);
    } finally { active.delete(value); }
  }
  return visit(value, 0);
}
function canonicalText(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.length === 0 ||
      value.normalize('NFC').replace(/\r\n?/gu, '\n') !== value) refuse('InvalidField', field);
  return value;
}
function validCid(value: unknown, field: string): string {
  if (typeof value !== 'string' || !cidPattern.test(value)) refuse('InvalidField', field);
  return value;
}
function present(value: unknown, path: readonly string[]): unknown {
  for (const key of path) {
    if (value === null || typeof value !== 'object' || !own(value, key)) return undefined;
    value = (value as Data)[key];
  }
  return value;
}
function timestamp(value: unknown): value is string {
  if (typeof value !== 'string' || value.length !== contract.recipe.time.width ||
      !/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$(?![\s\S])/u.test(value)) return false;
  const year = +value.slice(0, 4), month = +value.slice(5, 7), day = +value.slice(8, 10);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = month === 2 ? leap ? 29 : 28 : [4, 6, 9, 11].includes(month) ? 30 : 31;
  return month >= 1 && month <= 12 && day >= 1 && day <= days &&
    +value.slice(11, 13) <= 23 && +value.slice(14, 16) <= 59 && +value.slice(17, 19) <= 59;
}
function source(context: object, path: string): unknown {
  let value: unknown = context;
  for (const key of path.split('.')) {
    if (value === undefined || value === null || !own(value, key)) refuse('InvalidField', path);
    value = (value as Data)[key];
  }
  if (value === undefined) refuse('InvalidField', path);
  return value;
}
function document(fields: Readonly<Record<string, CheckpointAnswerFieldRule>>, context: Context & Data): Data {
  return Object.fromEntries(Object.entries(fields).filter(([, rule]) =>
    rule.omitOn !== context.decision).map(([key, rule]) => [key,
    own(rule, 'constant') ? rule.constant : own(rule, 'source') ? source(context, rule.source!) :
      rule.concatenate!.map(part => part === 'decision' || part.startsWith('summary.') ? source(context, part) : part).join('')]));
}
const {byteLength: signatureBytes, pattern: signaturePattern} = contract.signatureEncoding;
const signatureTextLength = 4 * Math.ceil(signatureBytes / 3);
const signaturePatternExact = new RegExp('^' + signaturePattern + '$', 'u');
const typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype);
const typedArrayByteLength = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteLength')!.get!;
const typedArrayTag = Object.getOwnPropertyDescriptor(typedArrayPrototype, Symbol.toStringTag)!.get!;

const {token_min_length: signerTokenMin, token_max_length: signerTokenMax} = contract.recipe.signer;
function validSignerToken(value: unknown): value is string {
  return typeof value === 'string' && value.length >= signerTokenMin &&
    value.length <= signerTokenMax && /^[A-Za-z0-9._:-]+$(?![\s\S])/u.test(value);
}

function validSignerIds(keyId: unknown, reviewerId: unknown): boolean {
  return validSignerToken(keyId) && validSignerToken(reviewerId);
}

function signature(value: unknown): string {
  if (typeof value !== 'string' || value.length !== signatureTextLength ||
      !signaturePatternExact.test(value)) refuse('InvalidField', 'proof.signature');
  return value;
}

// Application signer output is either exact proof text or a bounded byte view.
// The wire constructor below still accepts only canonical proof text.
function encodeSignerSignature(value: unknown): string {
  if (typedArrayTag.call(value) !== 'Uint8Array') return signature(value);
  if (typedArrayByteLength.call(value) !== signatureBytes) refuse('InvalidField', 'proof.signature');
  let binary = '';
  for (let index = 0; index < signatureBytes; index++) binary += String.fromCharCode((value as Uint8Array)[index]);
  return btoa(binary);
}

// The review envelope already checks the alphabet, length and padding shape.
// Only its final quartet can spell the same bytes with nonzero padding bits.
export function hasCanonicalReviewContentPadding(value: string): boolean {
  const tail = value.slice(-4);
  try { return btoa(atob(tail)) === tail; }
  catch { return false; }
}

export function createCheckpointAnswerCodec(primitives: AnswerPrimitives) {
  shape(primitives, ['canonicalJson', 'bytesCid']);
  const canonicalJson = primitives.canonicalJson, bytesCid = primitives.bytesCid;
  if (typeof canonicalJson !== 'function' || typeof bytesCid !== 'function') refuse('Encoding');
  const preparations = new WeakMap<AnswerCandidate, Preparation>(), resolutions = new WeakMap<AnswerResolution, Resolution>();
  function frame(value: unknown, limits: AnswerLimits): string {
    const captured = capture(value, limits);
    const wire = canonicalJson.call(primitives, captured);
    if (typeof wire !== 'string' || wire.length > limits.maxWireBytes ||
        encoder.encode(wire).byteLength > limits.maxWireBytes) refuse('Encoding');
    return wire;
  }
  async function identity(value: unknown, limits: AnswerLimits): Promise<string> {
    const wire = frame(value, limits);
    return validCid(await bytesCid.call(primitives, encoder.encode(wire)), 'identity');
  }
  async function withProof(body: CapturedObject, keyId: string, proof: unknown, kind: ApprovalKind, limits: AnswerLimits) {
    const signed = {...body, proof: {scheme: contract.recipe.proof.scheme, key_id: keyId, signature: signature(proof)}};
    const cid = await identity(signed, limits);
    return Object.freeze({...signed, [contract.recipe.identities[kind].selfField]: cid});
  }
  const original = <Stage extends object, Value>(map: WeakMap<Stage, Value>, stage: Stage): Value => {
    const value = map.get(stage);
    if (value === undefined) refuse('InvalidShape');
    return value;
  };
  async function prepareAnswerCandidate(inputSummary: unknown, decision: unknown, actor: unknown,
    decidedAt: unknown, selectedLimits: AnswerLimits): Promise<AnswerCandidate> {
    const limits = limitsOf(selectedLimits);
    if (!contract.recipe.decisions.includes(decision as AnswerDecision)) refuse('InvalidField', 'decision');
    shape(actor, ['keyId', 'reviewerId'], ['authorityScopeCid']);
    const capturedActor = {keyId: actor.keyId, reviewerId: actor.reviewerId, authorityScopeCid: actor.authorityScopeCid};
    if (!validSignerIds(capturedActor.keyId, capturedActor.reviewerId)) refuse('InvalidField', 'signer');
    const summary = capture(inputSummary, limits) as WireCheckpointSummary;
    if (!valid(summary, contract.summary)) refuse('InvalidShape');
    for (const path of contract.recipe.canonical.identity_text_paths) {
      const value = present(summary, path);
      if (value !== undefined) canonicalText(value, path.join('.'));
    }
    for (const path of contract.cidPaths) {
      const value = present(summary, path);
      if (value !== undefined) validCid(value, path.join('.'));
    }
    const profile = contract.candidates.find(value => value.kind === summary.kind &&
      value.subject === summary.subject.kind && value.phase === summary.phase);
    if (profile === undefined || profile.artifactType !== summary.requiredArtifact.type) refuse('UnsupportedProfile');
    if (!profile.requirements.some(items => items.length === summary.requirements.length &&
        items.every((item, index) => item === summary.requirements[index]))) refuse('InvalidRequirements');
    const separatePrepared = profile.preparedInvocationCid === 'summary.preparedInvocationCid';
    if (!separatePrepared && own(summary, 'preparedInvocationCid')) refuse('UnsupportedProfile');
    const preparedCid = profile.preparedInvocationCid === null ? undefined : validCid(
      source({summary}, profile.preparedInvocationCid), 'preparedInvocationCid');
    if (!timestamp(summary.createdAt) || !timestamp(summary.expiresAt) || !timestamp(decidedAt)) refuse('InvalidField', 'time');
    if (summary.createdAt >= summary.expiresAt || decidedAt < summary.createdAt || decidedAt >= summary.expiresAt) refuse('OutsideWindow');
    if (decision === 'approved' && contract.recipe.documents[profile.approval].authority_scope_cid?.requiredOn === 'approved effect')
      validCid(capturedActor.authorityScopeCid, 'authority_scope_cid');
    const context = Object.freeze({summary, actor: Object.freeze(capturedActor) as Context['actor'],
      decision: decision as AnswerDecision, decidedAt,
      selectedProfile: Object.freeze({preparedInvocationCid: preparedCid})});
    const approval = decision === 'approved' ? capture(document(contract.recipe.documents[profile.approval], context), limits) : undefined;
    const preimage = approval === undefined ? undefined : await identity(approval, limits);
    const stage = Object.freeze({}) as AnswerCandidate;
    preparations.set(stage, {context, profile, approval, preimage, limits});
    return stage;
  }
  function answerCandidateApprovalPreimage(stage: AnswerCandidate): string | undefined { return original(preparations, stage).preimage; }
  async function prepareAnswerResolution(stage: AnswerCandidate, approvalSignature?: unknown): Promise<AnswerResolution> {
    const {context, profile, approval, limits} = original(preparations, stage);
    let approvalEvidenceWire = '', evidenceCid;
    if (approval === undefined) {
      if (approvalSignature !== undefined) refuse('InvalidField', 'approval_signature');
    } else {
      const signedApprovalWithSelfCid = await withProof(approval, context.actor.keyId, approvalSignature, profile.approval, limits);
      const evidence = document(contract.recipe.documents.evidence, {...context, signedApprovalWithSelfCid});
      approvalEvidenceWire = frame(evidence, limits);
      evidenceCid = await identity(evidence, limits);
    }
    const body = capture({...document(contract.recipe.documents.resolution, {...context, evidenceCid}),
      ...document(contract.recipe.resolution_subject_fields[profile.resolutionSubject], context)}, limits);
    const preimage = await identity(body, limits);
    const result = Object.freeze({}) as AnswerResolution;
    resolutions.set(result, {body, preimage, approvalEvidenceWire, context, limits});
    return result;
  }
  function answerResolutionPreimage(stage: AnswerResolution): string { return original(resolutions, stage).preimage; }
  async function finishAnswerCandidate(stage: AnswerResolution, resolutionSignature: unknown): Promise<WireResolveItem> {
    const value = original(resolutions, stage);
    const signed = await withProof(value.body, value.context.actor.keyId, resolutionSignature, 'resolution', value.limits);
    return Object.freeze({checkpointCid: value.context.summary.checkpointCid,
      resolutionWire: frame(signed, value.limits), approvalEvidenceWire: value.approvalEvidenceWire});
  }
  async function reviewBytesMatchCid(raw: unknown, expected: unknown, selectedLimits: AnswerLimits): Promise<boolean> {
    try {
      const limits = limitsOf(selectedLimits);
      const view = ArrayBuffer.isView(raw) ? new Uint8Array(raw.buffer, raw.byteOffset, raw.byteLength)
        : raw instanceof ArrayBuffer ? new Uint8Array(raw) : undefined;
      if (view === undefined || view.byteLength > limits.maxWireBytes ||
          typeof expected !== 'string' || !cidPattern.test(expected)) return false;
      // Preserve the bounded original before the first asynchronous digest.
      const bytes = Uint8Array.prototype.slice.call(view) as Uint8Array<ArrayBuffer>;
      if (await bytesCid.call(primitives, bytes) === expected) return true;
      const wire = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(bytes);
      const value = capture(JSON.parse(wire) as unknown, limits) as CapturedObject | undefined;
      const profile = contract.reviews.find(item => item.version === value?.version);
      if (profile === undefined || value![profile.selfField] !== expected ||
          canonicalJson.call(primitives, value, {dataKeys: profile.dataKeys}) !== wire) return false;
      const body = Object.fromEntries(Object.entries(value!).filter(([key]) => key !== profile.selfField));
      return await bytesCid.call(primitives, encoder.encode(
        canonicalJson.call(primitives, body, {dataKeys: profile.dataKeys}))) === expected;
    } catch { return false; }
  }
  return Object.freeze({prepareAnswerCandidate, answerCandidateApprovalPreimage,
    prepareAnswerResolution, answerResolutionPreimage, finishAnswerCandidate,
    reviewBytesMatchCid, encodeSignerSignature, validSignerIds});
}
