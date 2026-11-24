// Installed Host authority for exact committed Manifest inspection.
// MoonBit owns grant meaning; this adapter performs current authorization and
// delegates durable use-count and trusted-clock effects to the Store.
import type {WireRunRef} from '../../packages/client-wire/index.js';

type Awaitable<T> = T | PromiseLike<T>;
type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Entry = Readonly<{public_index_entry_cid: string; result_manifest_cid: string}>;
type Contract = Readonly<{identity: string; wire: string}>;
type ContractName = 'public_index_entry' | 'result_manifest';
type ManifestRequest = Readonly<{
  indexKey: WireRunRef;
  principalId: string;
  purpose: string;
  attemptId: string;
}>;
type Admission = Readonly<{
  authorizationContextCid: string;
  clockContractCid: string;
  dataCeilingCid: string;
  expiresAt: string;
  maxBytes: number;
  maxUses: number;
}>;
type GrantRequest = Pick<ManifestRequest, 'principalId' | 'purpose'> & Omit<Admission, 'clockContractCid'>;
type ManifestResponse = Readonly<{
  manifestCid: string;
  manifest: unknown;
  grantCid: string;
  idempotent: boolean;
}>;
type RequestFacts = ManifestRequest & Readonly<{stage: 'request'}>;
type Resolved = ManifestRequest & Readonly<{entry: Entry; index: Contract; manifest: Contract}>;
type GrantFacts = Resolved & Readonly<{grant: Contract; at: string}>;
type ReadFacts = GrantFacts & Readonly<{stage: 'read'}>;
type ResponseFacts = GrantFacts & Readonly<{stage: 'response'; response: ManifestResponse}>;
type AuthorityConfiguration = Readonly<{
  admitManifestRead(facts: Resolved & Readonly<{stage: 'request'}>): Awaitable<Admission>;
  authorizeManifestRead(facts: RequestFacts | ReadFacts | ResponseFacts): Awaitable<boolean>;
}>;
type Store = Readonly<{
  confirmCommittedIndex(indexKey: WireRunRef): Awaitable<Entry | undefined>;
  readPublicationContract(cid: string, name: ContractName): Awaitable<Contract>;
  observeTrustedClock(clockContractCid: string, at: string): Awaitable<unknown>;
  consumeManifestReadGrant(wire: string, attemptId: string): Awaitable<Readonly<{idempotent: boolean}>>;
}>;
type Control = Readonly<{
  issueManifestReadGrant(index: Contract, manifest: Contract, grant: GrantRequest, limits: Limits): Contract;
  manifestReadGrantAllowsBytes(grant: Contract, byteCount: number): boolean;
  manifestReadGrantValidAt(grant: Contract, at: string): boolean;
}>;
declare const authorityBrand: unique symbol;
declare const serviceBrand: unique symbol;
type Authority = Readonly<{[authorityBrand]: true}>;
type ManifestService = Readonly<{[serviceBrand]: true}>;
type ServiceConfiguration = Readonly<{
  store: Store;
  control: Control;
  authority: Authority;
  now: () => unknown;
  limits: Limits;
}>;
type InstalledService = Omit<ServiceConfiguration, 'authority'> &
  Readonly<{authority: AuthorityConfiguration}>;

const authorities = new WeakMap<Authority, AuthorityConfiguration>();
const services = new WeakMap<ManifestService, InstalledService>();
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const exactKeys = (value: unknown, keys: readonly string[]) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const positive = (value: number) => Number.isSafeInteger(value) && value > 0;

export class ManifestAccessError extends Error {
  declare readonly code: string;
  declare readonly primaryFailure: unknown;

  constructor(code: string, cause?: unknown) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const fail: (code: string, cause?: unknown) => never = (code, cause) => { throw new ManifestAccessError(code, cause); };

export function installManifestAccessAuthority(configuration: AuthorityConfiguration): Authority {
  if (!exactKeys(configuration, [
    'admitManifestRead', 'authorizeManifestRead',
  ]) || typeof configuration.admitManifestRead !== 'function' ||
      typeof configuration.authorizeManifestRead !== 'function') {
    fail('InvalidManifestAccessAuthority');
  }
  const authority = Object.freeze({}) as Authority;
  authorities.set(authority, Object.freeze({...configuration}));
  return authority;
}

export function installManifestAccessService(configuration: ServiceConfiguration): ManifestService {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'limits',
  ]) || configuration.store === null ||
      typeof configuration.store !== 'object' ||
      typeof configuration.store.confirmCommittedIndex !== 'function' ||
      typeof configuration.store.readPublicationContract !== 'function' ||
      typeof configuration.store.consumeManifestReadGrant !== 'function' ||
      typeof configuration.store.observeTrustedClock !== 'function' ||
      configuration.control === null ||
      typeof configuration.control !== 'object' ||
      typeof configuration.control.issueManifestReadGrant !== 'function' ||
      typeof configuration.control.manifestReadGrantAllowsBytes !==
        'function' ||
      typeof configuration.control.manifestReadGrantValidAt !== 'function' ||
      !authorities.has(configuration.authority) ||
      typeof configuration.now !== 'function' ||
      !exactKeys(configuration.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(configuration.limits).every(positive)) {
    fail('InvalidManifestAccessService');
  }
  const service = Object.freeze({}) as ManifestService;
  services.set(service, Object.freeze({
    store: configuration.store,
    control: configuration.control,
    authority: authorities.get(configuration.authority)!,
    now: configuration.now,
    limits: Object.freeze({...configuration.limits}),
  }));
  return service;
}

function validateRequest(request: ManifestRequest) {
  if (!exactKeys(request, [
    'indexKey', 'principalId', 'purpose', 'attemptId',
  ]) || !exactKeys(request.indexKey, [
    'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof request.indexKey.namespaceId !== 'string' ||
      request.indexKey.namespaceId.length === 0 ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.principalId !== 'string' ||
      request.principalId.length === 0 ||
      typeof request.purpose !== 'string' || request.purpose.length === 0 ||
      typeof request.attemptId !== 'string' || request.attemptId.length === 0) {
    fail('InvalidManifestAccessRequest');
  }
}

function validateAdmission(admission: Admission) {
  if (!exactKeys(admission, [
    'authorizationContextCid', 'clockContractCid', 'dataCeilingCid',
    'expiresAt', 'maxBytes', 'maxUses',
  ]) || !cidPattern.test(admission.authorizationContextCid) ||
      !cidPattern.test(admission.clockContractCid) ||
      !cidPattern.test(admission.dataCeilingCid) ||
      typeof admission.expiresAt !== 'string' ||
      !Number.isSafeInteger(admission.maxBytes) || admission.maxBytes < 0 ||
      !positive(admission.maxUses)) {
    fail('InvalidManifestReadAdmission');
  }
}

function observedAt(now: ServiceConfiguration['now']) {
  const value = now();
  if (typeof value !== 'string' || value.length === 0) {
    fail('InvalidManifestAccessClock');
  }
  return value;
}

function immutableJson(wire: string): unknown {
  let value: unknown;
  try { value = JSON.parse(wire); }
  catch (error) { fail('InvalidManifestControlResult', error); }
  const freeze = (item: unknown) => {
    if (item !== null && typeof item === 'object') {
      for (const child of Object.values(item)) freeze(child);
      Object.freeze(item);
    }
    return item;
  };
  return freeze(value);
}

export async function readAuthorizedManifest(service: ManifestService, request: ManifestRequest): Promise<ManifestResponse> {
  const installed = services.get(service) ?? fail('ForeignManifestService');
  validateRequest(request);
  const indexKey = Object.freeze({...request.indexKey});
  const requestFacts: RequestFacts = Object.freeze({
    stage: 'request',
    indexKey,
    principalId: request.principalId,
    purpose: request.purpose,
    attemptId: request.attemptId,
  });
  if (await installed.authority.authorizeManifestRead(requestFacts) !== true) {
    fail('ManifestAccessDenied');
  }
  const entry = await installed.store.confirmCommittedIndex(indexKey);
  if (entry === undefined) fail('ManifestAccessDenied');
  const index = await installed.store.readPublicationContract(
    entry.public_index_entry_cid, 'public_index_entry',
  );
  const manifest = await installed.store.readPublicationContract(
    entry.result_manifest_cid, 'result_manifest',
  );
  const at = observedAt(installed.now);
  const facts = Object.freeze({...requestFacts, entry, index, manifest});
  const admission = await installed.authority.admitManifestRead(facts);
  validateAdmission(admission);
  await installed.store.observeTrustedClock(admission.clockContractCid, at);
  const grant = installed.control.issueManifestReadGrant(
    index,
    manifest,
    {
      principalId: request.principalId,
      purpose: request.purpose,
      dataCeilingCid: admission.dataCeilingCid,
      maxBytes: admission.maxBytes,
      maxUses: admission.maxUses,
      expiresAt: admission.expiresAt,
      authorizationContextCid: admission.authorizationContextCid,
    },
    installed.limits,
  );
  const byteCount = new TextEncoder().encode(manifest.wire).byteLength;
  if (!installed.control.manifestReadGrantAllowsBytes(grant, byteCount) ||
      !installed.control.manifestReadGrantValidAt(grant, at)) {
    fail('ManifestAccessDenied');
  }
  const authorization: ReadFacts = Object.freeze({...facts, stage: 'read', grant, at});
  if (await installed.authority.authorizeManifestRead(authorization) !== true) {
    fail('ManifestAccessDenied');
  }
  const usage = await installed.store.consumeManifestReadGrant(
    grant.wire, request.attemptId,
  );
  const response = Object.freeze({
    manifestCid: manifest.identity,
    manifest: immutableJson(manifest.wire),
    grantCid: grant.identity,
    idempotent: usage.idempotent,
  });
  if (await installed.authority.authorizeManifestRead(Object.freeze({
    ...authorization, stage: 'response', response,
  })) !== true) {
    fail('ManifestAccessDenied');
  }
  return response;
}
