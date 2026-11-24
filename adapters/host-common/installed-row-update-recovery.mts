import {createHash} from 'node:crypto';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';

type MemberRecovery = Readonly<{memberIndex: number}>;
type RestoreContext = Readonly<{
  members: readonly unknown[];
  recorded: Readonly<{members: readonly unknown[]}>;
  durable: Readonly<{connectorRecovery: readonly MemberRecovery[]}>;
  memberIndexes?: readonly number[];
}>;
type RecoveryMember<Context extends RestoreContext> = Context['durable']['connectorRecovery'][number];
type RecoveryInput = Readonly<{kind?: unknown; wire?: unknown; observationCid?: unknown}>;
type Change = Readonly<{after?: Readonly<{value?: unknown}>; target_row_identity?: unknown}>;
type Claim = Readonly<{canonicalRequestCid: string}>;
type RequestEntry<Request> = Readonly<{request: Request; requestCid: string}>;
type RequestCodec<Request> = Readonly<{requestCid(request: Request): string; savedWire(request: Request): string}>;

const encode = (value: unknown) => canonicalJson(value, {dataKeys: true});
const wireCid = (wire: string) => 'sha256:' + createHash('sha256').update(wire).digest('hex');

function fail(code: string): never {
  throw Object.assign(new Error(code), {code});
}

// The admitted Preview and its claims keep their original global member
// indexes. Only a connector's retained request codec can restore a row.
export function restoreInstalledRowUpdateMembers<Context extends RestoreContext, Request>(
  context: Context, maxMembers: number, invalidCode: string,
  restoreMember: (context: Context, index: number, entry: RecoveryMember<Context> | undefined) => Request,
) {
  const {durable, recorded, members, memberIndexes} = context;
  if (!Array.isArray(members) || members.length < 1 || members.length > maxMembers ||
      !Array.isArray(durable?.connectorRecovery) || durable.connectorRecovery.length > members.length ||
      !Array.isArray(recorded?.members) || recorded.members.length !== members.length) fail(invalidCode);
  const indexes = memberIndexes ?? members.map((_, index) => index);
  if (!Array.isArray(indexes) || indexes.length < 1 || indexes.length > members.length ||
      indexes.some((index, offset) => !Number.isSafeInteger(index) || index < 0 || index >= members.length ||
        offset > 0 && index <= indexes[offset - 1])) fail(invalidCode);
  const byIndex = new Map<number, RecoveryMember<Context>>();
  for (const entry of durable.connectorRecovery) {
    if (!Number.isSafeInteger(entry?.memberIndex) || entry.memberIndex < 0 || entry.memberIndex >= members.length ||
        byIndex.has(entry.memberIndex)) fail(invalidCode);
    byIndex.set(entry.memberIndex, entry as RecoveryMember<Context>);
  }
  const requests = new Array<Request | undefined>(indexes.length);
  for (let position = 0; position < indexes.length; position++) {
    if (position in indexes) {
      const index = indexes[position];
      requests[position] = restoreMember(context, index, byIndex.get(index));
    }
  }
  return Object.freeze({requests: Object.freeze(requests)});
}

// Check each reconstructed row against its original claim and approved Preview.
export function assertInstalledRowUpdateClaim(rebuilt: Readonly<{requestCid: string}>,
  facts: Readonly<{value: unknown; target: unknown}>, claims: readonly Claim[], changes: readonly Change[],
  row: number, foreignCode: string): void {
  if (rebuilt.requestCid !== claims[row].canonicalRequestCid ||
      encode(facts.value) !== encode(changes[row].after?.value) ||
      encode(facts.target) !== encode(changes[row].target_row_identity)) fail(foreignCode);
}

// The enclosing capture owns the original members and request codec.
export function installedRowUpdateRequestWires<Request>(entries: readonly RequestEntry<Request>[],
  maxRows: number, requests: RequestCodec<Request>, invalidCode: string, foreignCode: string) {
  if (!Array.isArray(entries) || entries.length > maxRows) fail(invalidCode);
  return entries.map(entry => {
    if (entry.requestCid !== requests.requestCid(entry.request)) fail(foreignCode);
    return requests.savedWire(entry.request);
  });
}

// Retain the bounded canonical wire with its original digest.
export function packInstalledRowUpdateRecovery<Kind extends string>(kind: Kind, recovery: unknown,
  maxRecoveryBytes: number, limitCode: string) {
  const wire = encode(recovery);
  if (Buffer.byteLength(wire) > maxRecoveryBytes) fail(limitCode);
  return Object.freeze({kind, observationCid: wireCid(wire), wire});
}

// Check the common custody envelope before decoding. The caller's original
// codec still validates the provider version, binding and per-row wire.
export function unpackInstalledRowUpdateRecovery(saved: RecoveryInput | null | undefined, kind: string,
  maxRecoveryBytes: number, changes: unknown, claims: unknown, maxRows: number, invalidCode: string): unknown {
  if (saved?.kind !== kind || typeof saved.wire !== 'string' ||
      Buffer.byteLength(saved.wire) > maxRecoveryBytes || wireCid(saved.wire) !== saved.observationCid ||
      !Array.isArray(changes) || changes.length > maxRows || !Array.isArray(claims) ||
      claims.length !== changes.length) fail(invalidCode);
  return JSON.parse(saved.wire);
}
