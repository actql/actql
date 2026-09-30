declare const resultAuthorityBrand: unique symbol;
declare const resultServiceBrand: unique symbol;

export interface ResultAccessAuthority {
  readonly [resultAuthorityBrand]: true;
}

export interface ResultAccessService {
  readonly [resultServiceBrand]: true;
}

export interface ResultAccessKey {
  readonly namespaceId: string;
  readonly authorityScopeCid: string;
  readonly runDefinitionCid: string;
}

export interface ResultAccessRequest {
  readonly indexKey: ResultAccessKey;
  readonly principalId: string;
  readonly purpose: string;
  readonly resultName: string;
  readonly attemptId: string;
  readonly format: 'json' | 'jsonl' | 'csv';
}

export interface ResultDeliverySink {
  write(bytes: Uint8Array, signal?: AbortSignal): Promise<unknown>;
  finish(signal?: AbortSignal): Promise<unknown>;
}

// Both constructors validate every callback and Store method at runtime.
// The physical adapter supplies them; the portable service owns sequencing.
// A Store may provide sampleTrustedClock(clockContractCid, now): Promise<string>
// to sample the installed Host clock after reading its durable lower bound.
// It returns the exact durably accepted sample and must re-sample after a CAS
// conflict. Explicit observeTrustedClock remains the compatibility contract.
export function installResultAccessAuthority(
  configuration: unknown): ResultAccessAuthority;
export function installResultAccessService(
  configuration: unknown): ResultAccessService;
export function deliverAuthorizedResult(service: ResultAccessService,
  request: ResultAccessRequest, sink: ResultDeliverySink,
  signal?: AbortSignal): Promise<unknown>;
export function inspectAuthorizedDeliveryAttempt(
  service: ResultAccessService,
  request: Omit<ResultAccessRequest, 'format'>): Promise<unknown>;
export function describeAuthorizedResult(service: ResultAccessService,
  request: ResultAccessRequest & Readonly<{
    maxWireBytes: number; maxNodes: number; maxDepth: number}>,
  signal?: AbortSignal): Promise<import('@actql/client-wire').WireResultDescription>;
