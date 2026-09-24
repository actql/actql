declare const ownerHandle: unique symbol;

export type Journal = {readonly [ownerHandle]: 'journal'};
export type DispatchRequest = {readonly [ownerHandle]: 'dispatch-request'};
export type IntentAdmission = {readonly [ownerHandle]: 'intent-admission'};
export type IntentRecord = {readonly [ownerHandle]: 'intent-record'};
export type DurableRecord = {readonly [ownerHandle]: 'durable-record'};
export type Transition = {readonly [ownerHandle]: 'transition'};
export type DispatchResponse = {readonly [ownerHandle]: 'dispatch-response'};

export interface DispatchInput {
  coordinatorAuthority: string;
  runDefinitionCid: string;
  taskKey: string;
  taskAttempt: number;
  dispatchId: string;
  siteKey: string;
  siteGeneration: number;
  runtimeBundleCid: string;
  connectorRegistration: string;
  connectorRevision: string;
  strategyRevision: string;
  inputBindingCid: string;
  obligationsCid: string;
  budgetCid: string;
  evidenceIssuerCapabilityCid: string;
  grantCid: string;
}

export function createJournal(authority: string): Journal;
export function prepareDispatch(input: DispatchInput): DispatchRequest;
export function dispatchCid(request: DispatchRequest): string;
export function dispatchJson(request: DispatchRequest): string;
export function dispatchRoute(request: DispatchRequest): string[];
export function pollDispatchJson(request: DispatchRequest,
  inputBindingBody: string, maxBindingBytes: number): string;
export function pollQueryJson(request: DispatchRequest): string;
export function prepareIntent(journal: Journal,
  request: DispatchRequest): IntentAdmission;
export function intentIsNew(admission: IntentAdmission): boolean;
export function admissionDurableJson(admission: IntentAdmission): string;
/** Call only after the exact admission body was durably persisted. */
export function commitIntent(admission: IntentAdmission): IntentRecord;
export function admitDurableJson(body: string): DurableRecord;
export function restoreDurable(journal: Journal,
  durable: DurableRecord): IntentRecord;
export function durableRevision(durable: DurableRecord): number;
export function durableDispatchCid(durable: DurableRecord): string;
export function durableRequest(durable: DurableRecord): DispatchRequest;
export function prepareUnknown(record: IntentRecord): Transition;
export function admitResponseJson(body: string, request: DispatchRequest,
  statusReply: boolean): DispatchResponse;
export function prepareResponseObservation(record: IntentRecord,
  response: DispatchResponse): Transition;
export function transitionExpectedRevision(transition: Transition): number;
export function transitionDurableJson(durable: DurableRecord,
  transition: Transition): string;
export function responseDurableJson(durable: DurableRecord,
  transition: Transition, response: DispatchResponse): string;
/** Call only after the exact next durable body was atomically persisted. */
export function commitTransition(transition: Transition): void;
export function recordStateCodes(record: IntentRecord): string[];
