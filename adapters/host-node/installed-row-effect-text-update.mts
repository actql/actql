import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {rejectInstalledEffectPlan as fail} from './installed-effect-recipe.mjs';

const cid = /^sha256:[0-9a-f]{64}$/u;
const fieldName = /^[A-Za-z_][A-Za-z0-9_]*$/u;
const asciiIdentity = /^[a-z0-9-]+$/u;
const invalid: () => never = () => fail('InvalidInstalledRowTextUpdate');
const foreign: () => never = () => fail('ForeignInstalledRowEffectRequest');
const recoveryMismatch: () => never = () => fail('InstalledEffectContinuationMismatch');

type JsonTextRow = Readonly<Record<string, string | null>>;
export type InstalledTextUpdateMapping = Readonly<{
  primary_identity?: unknown;
  target_schema?: Readonly<{fields?: Readonly<Record<string, Readonly<{type?: unknown; nullable?: unknown}>>>}>;
  row_mapping?: Readonly<Record<string, Readonly<{null_behavior?: unknown}>>>;
}>;
type Member = Readonly<{kind: string; resource: string; effectId: string; memberIndex: number;
  mapping: Readonly<{primaryIdentity: string; mappingCid: string; standardTextAcceptsNull?: true}>}>;
type Request = Readonly<Record<string, string | null> & {body: string}>;
type RequestOriginal = Readonly<{member: Member; value: JsonTextRow; target: string; requestCid: string}>;
type Selection = Readonly<{member: Member; value: unknown; selector: unknown}>;
type Row = Readonly<{target_row_identity: unknown; after?: Readonly<{value?: unknown}>}>;
type Recovery = Readonly<{members: readonly Member[];
  body: Readonly<{effects: readonly Readonly<{effect_id: string; changes: readonly Row[]}>[]}>;
  durable: Readonly<{connectorRecovery?: readonly Readonly<{
    memberIndex: number; kind: string; wire: string; observationCid: string;
  }>[]}>}>;
type Layout = Readonly<{
  resource: string; identityField: string; field: string; domain: string; boundaryCid: string;
  maxIdentityUnits: number; maxTextUnits: number; maxRecoveryBytes: number;
}>;
export type InstalledTextUpdateBounds = Readonly<{
  body: number; request: number; preimage: number; recovery: number;
}>;

const integer = (value: unknown): value is number => typeof value === 'number' &&
  Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const plain = (value: unknown): value is Record<string, unknown> => value !== null &&
  typeof value === 'object' && !nodeTypes.isProxy(value) && Object.getPrototypeOf(value) === Object.prototype;

function data(object: object, name: PropertyKey): unknown {
  const descriptor = Object.getOwnPropertyDescriptor(object, name);
  if (descriptor === undefined || !Object.hasOwn(descriptor, 'value')) invalid();
  return descriptor.value;
}

// Issuance and recovery run only in the existing paid row/member construction
// slots. This holder retains the exact checked member and cell value for each
// returned request, with no authority or Provider transport of its own.
export function deriveInstalledRowTextUpdate(moon: object, write: unknown) {
  if (!plain(write) || !Object.hasOwn(write, 'standardText')) return undefined;
  const selected = data(write, 'standardText');
  if (!plain(selected) || !Object.isFrozen(selected) || !Object.isFrozen(write) ||
      data(write, 'kind') !== 'update' || Reflect.ownKeys(write).some(key => {
        const descriptor = Object.getOwnPropertyDescriptor(write, key);
        return !descriptor?.enumerable || !Object.hasOwn(descriptor, 'value');
      }) ||
      ['prepareRequest', 'requestFacts', 'requestCid', 'recoveryEntry', 'recoverRequests',
        'recoverMemberRequests'].some(name => Object.hasOwn(write, name))) invalid();
  const names = ['resource', 'identityField', 'field', 'domain', 'boundaryCid',
    'maxIdentityUnits', 'maxTextUnits', 'maxRecoveryBytes'] as const;
  if (Reflect.ownKeys(selected).length !== names.length) invalid();
  for (const name of names) data(selected, name);
  const original = selected as Layout;
  const {resource, identityField, field, domain, boundaryCid, maxIdentityUnits, maxTextUnits, maxRecoveryBytes} = original;
  if (typeof resource !== 'string' || resource.length === 0 ||
      typeof identityField !== 'string' || typeof field !== 'string' || !fieldName.test(identityField) ||
      !fieldName.test(field) || field === identityField || ['body', 'version', 'boundaryCid'].some(key => key === field || key === identityField) ||
      typeof domain !== 'string' || domain.length === 0 || !domain.isWellFormed() ||
      typeof boundaryCid !== 'string' || !cid.test(boundaryCid) ||
      ![maxIdentityUnits, maxTextUnits, maxRecoveryBytes].every(integer)) invalid();
  const transport = data(write, 'transport');
  if (!plain(transport) || !Object.isFrozen(transport)) invalid();
  const maxBodyBytes = data(transport, 'maxRequestBytes');
  if (!integer(maxBodyBytes)) invalid();
  const method = (name: string) => {
    const callable = data(moon, name);
    if (typeof callable !== 'function' || nodeTypes.isProxy(callable) || nodeTypes.isAsyncFunction(callable)) invalid();
    return (...args: readonly (string | number | boolean)[]) => checked(Reflect.apply(callable, moon, args));
  };
  const measure = method('clientProgramInstalledUpdateTextRequestBounds');
  const requestWire = method('clientProgramConstructInstalledUpdateTextRequest');
  const recoveryWire = method('clientProgramConstructInstalledUpdateTextRecovery');
  const limits = measure(identityField, field, domain, boundaryCid, maxIdentityUnits, maxTextUnits);
  if (!Array.isArray(limits) || limits.length !== 3 || !limits.every(integer)) invalid();
  const [body, request, preimage] = limits as [number, number, number];
  const bounds: InstalledTextUpdateBounds = Object.freeze({body: Math.min(body, maxBodyBytes),
    request, preimage, recovery: maxRecoveryBytes});
  const requests = new WeakMap<object, RequestOriginal>();
  const requestOriginal = (request: object) => requests.get(request) ?? foreign();

  // The existing installer projects this fact once from the selected Mapping.
  // An author layout cannot turn omission or a nonnullable column into a write.
  function admitsNull(selectedResource: string, mapping: InstalledTextUpdateMapping): boolean {
    const fields = mapping.target_schema?.fields;
    const sources = mapping.row_mapping;
    if (selectedResource !== resource || mapping.primary_identity !== identityField ||
        fields === undefined || sources === undefined ||
        !Object.hasOwn(fields, field) || !Object.hasOwn(sources, field)) return false;
    const column = fields[field];
    return column?.type === 'string' && column.nullable === true &&
      sources[field]?.null_behavior === 'write_null';
  }

  function checkedCell(member: Member, target: unknown, value: unknown): asserts value is JsonTextRow {
    if (member?.kind !== 'update' || member.resource !== resource || member.mapping?.primaryIdentity !== identityField ||
        typeof member.mapping.mappingCid !== 'string' || !cid.test(member.mapping.mappingCid) ||
        typeof member.effectId !== 'string' || member.effectId.length === 0 || !member.effectId.isWellFormed() ||
        !Number.isSafeInteger(member.memberIndex) || member.memberIndex < 0 || member.memberIndex > 2147483647 ||
        typeof target !== 'string' || target.length > maxIdentityUnits || !asciiIdentity.test(target) ||
        !plain(value) || Reflect.ownKeys(value).length !== 1 || !Object.hasOwn(value, field)) foreign();
    const text = data(value, field);
    if (text === null ? member.mapping.standardTextAcceptsNull !== true
      : typeof text !== 'string' || text.length > maxTextUnits || !text.isWellFormed()) foreign();
  }

  function prepareRequest({member, value, selector}: Selection) {
    checkedCell(member, selector, value);
    const target = selector as string;
    const text = value[field];
    const output = requestWire(identityField, field, target, text ?? '', domain, boundaryCid,
      bounds.body, bounds.request, bounds.preimage, text === null);
    if (!Array.isArray(output) || output.length !== 2 || typeof output[0] !== 'string' ||
        Buffer.byteLength(output[0]) > bounds.body || typeof output[1] !== 'string' || !cid.test(output[1])) invalid();
    const [body, requestCid] = output as [string, string];
    const request: Request = Object.freeze({[identityField]: target, [field]: value[field], body});
    requests.set(request, Object.freeze({member, target, value: Object.freeze(value), requestCid}));
    return Object.freeze({request, requestCid});
  }

  function witness(member: Member, target: string, value: JsonTextRow) {
    const text = value[field];
    const output = recoveryWire(boundaryCid, member.effectId, member.memberIndex, member.mapping.mappingCid,
      target, text ?? '', bounds.recovery, text === null);
    if (!Array.isArray(output) || output.length !== 2 || typeof output[0] !== 'string' ||
        Buffer.byteLength(output[0]) > bounds.recovery || typeof output[1] !== 'string' || !cid.test(output[1])) recoveryMismatch();
    const [wire, observationCid] = output as [string, string];
    return Object.freeze({kind: domain, wire, observationCid});
  }

  function exactWitness(member: Member, target: string, value: JsonTextRow,
      saved: {wire: string; observationCid: string}) {
    const original = witness(member, target, value);
    return original.wire === saved.wire && original.observationCid === saved.observationCid;
  }

  const owned = Object.freeze({...write, prepareRequest,
    requestFacts(request: object) {
      const {target, value} = requestOriginal(request);
      return {target, value};
    },
    requestCid(request: object) { return requestOriginal(request).requestCid; },
    recoveryEntry({member, entries}: Readonly<{member: Member;
      entries: readonly Readonly<{request: object; requestCid: string; target: unknown; value: unknown}>[]}>) {
      if (entries.length !== 1) recoveryMismatch();
      const [entry] = entries, held = requestOriginal(entry.request);
      if (held.member !== member || held.requestCid !== entry.requestCid || held.value !== entry.value ||
          held.target !== entry.target) recoveryMismatch();
      return witness(member, held.target, held.value);
    },
    recoverRequests({members, body, durable}: Recovery) {
      if (members.length !== 1 || body.effects.length !== 1 ||
          durable.connectorRecovery?.length !== 1) recoveryMismatch();
      const [member] = members, [effect] = body.effects, [saved] = durable.connectorRecovery;
      if (effect.effect_id !== member.effectId || effect.changes.length !== 1 || saved.memberIndex !== member.memberIndex ||
          saved.kind !== domain || typeof saved.wire !== 'string' || Buffer.byteLength(saved.wire) > bounds.recovery ||
          !cid.test(saved.observationCid)) recoveryMismatch();
      const [row] = effect.changes;
      const {target_row_identity: selector, after} = row, value = after?.value;
      checkedCell(member, selector, value);
      if (!exactWitness(member, selector as string, value, saved)) recoveryMismatch();
      // The parent still compares the rebuilt request CID with the exact
      // durable claim and its value/target with this original approved Preview.
      return {requests: [[prepareRequest({member, selector, value}).request]]};
    },
  });
  return {owned, bounds, admitsNull};
}
