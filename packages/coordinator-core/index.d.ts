declare const ownerHandle: unique symbol;

export type Journal = {readonly [ownerHandle]: 'journal'};
export type DispatchRequest = {readonly [ownerHandle]: 'dispatch-request'};
export type IntentAdmission = {readonly [ownerHandle]: 'intent-admission'};
export type IntentRecord = {readonly [ownerHandle]: 'intent-record'};
export type DurableRecord = {readonly [ownerHandle]: 'durable-record'};
export type Transition = {readonly [ownerHandle]: 'transition'};
export type DispatchResponse = {readonly [ownerHandle]: 'dispatch-response'};
export type CheckedOutputPlan = {readonly [ownerHandle]: 'checked-output-plan'};
export type OutputIntentAdmission = {
  readonly [ownerHandle]: 'output-intent-admission'
};
export type OutputRecord = {readonly [ownerHandle]: 'output-record'};
export type DurableOutputRecord = {
  readonly [ownerHandle]: 'durable-output-record'
};
export type OutputTransition = {readonly [ownerHandle]: 'output-transition'};

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
export function admitDispatchJson(body: string,
  claimedCid: string): DispatchRequest;
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
/** Accepted physical Site evidence, never publication or read authority. */
export interface AcceptedSiteOutput {
  evidenceCid: string;
  measurementCid: string;
  dispatchRequestCid: string;
  materialGeneration: string;
  holdingEvidenceCid: string;
  managedProfileCid: string;
  resultSchemaCid: string;
  logicalViewCid: string;
  representationCodecCid: string;
  physicalManifestCid: string;
  measurementEvidenceCid: string;
  rowCount: string;
  retainedBytes: string;
  subjectCid: string;
}
export function acceptedSiteOutput(durable: DurableRecord):
  Readonly<AcceptedSiteOutput> | undefined;
export interface OutputIntentInput {
  storeAuthorityCid: string;
  publicationAttemptCid: string;
  resultDefinitionCid: string;
  orderingEvidenceCid: string;
  coordinatorAuthority: string;
  transferAttempt: string;
  transferRoute: 'direct' | 'store';
  destinationSiteKey: string;
  destinationSiteGeneration: number;
  transferMaxBytes: number | bigint;
  transferExpiresUnixMs: number | bigint;
  sourceGrantCid: string;
  destinationGrantCid: string;
  routeCapabilityCid: string;
  transferOrigin: string;
}
/** Caller must independently authorize every publication and movement field. */
export function issueOutputPlanPollJson(durable: DurableRecord,
  input: Readonly<OutputIntentInput>): string;
export function admitCheckedOutputPlan(durable: DurableRecord,
  pollBody: string, planBody: string, expectedResultDefinitionCid: string,
  limits: Readonly<{maxChunks: number; maxManifestBytes: number;
    maxReferencedBytes: number | bigint}>): CheckedOutputPlan;
export function checkedOutputPlanCid(plan: CheckedOutputPlan): string;
export function checkedOutputIntentCid(plan: CheckedOutputPlan): string;
/** Admitted Site claims, not verified publication or a read grant. */
export function checkedOutputPublicationFacts(plan: CheckedOutputPlan):
  Readonly<{
    resultDefinitionCid: string;
    logicalRelationCid: string;
    resultSchemaCid: string;
    orderingEvidenceCid: string;
    codecContractCid: string;
    rowCount: bigint;
    materialGenerationCid: string;
  }>;
export function prepareOutputIntent(journal: Journal,
  plan: CheckedOutputPlan): OutputIntentAdmission;
export function outputIntentIsNew(admission: OutputIntentAdmission): boolean;
/** Call only after the matching output intent and plan were persisted. */
export function commitOutputIntent(admission: OutputIntentAdmission): OutputRecord;
export function outputRecordStatus(record: OutputRecord): string[];
/** Available only before the first durably recorded physical send. */
export function outputInitialPollJson(record: OutputRecord): string;
export function outputAdmissionDurableJson(plan: CheckedOutputPlan): string;
export function admitDurableOutputJson(body: string, dispatch: DurableRecord,
  expectedResultDefinitionCid: string,
  limits: Readonly<{maxChunks: number; maxManifestBytes: number;
    maxReferencedBytes: number | bigint}>): DurableOutputRecord;
export function restoreDurableOutput(journal: Journal,
  durable: DurableOutputRecord): OutputRecord;
export function durableOutputRevision(durable: DurableOutputRecord): number;
export function durableOutputJson(durable: DurableOutputRecord): string;
export function durableOutputPollJson(durable: DurableOutputRecord): string;
/** Binds a destination-committed reply to the retained Transfer request. */
export function admitOutputTransferReplyJson(durable: DurableOutputRecord,
  reply: string): string;
/** Identity for recovery only; current authority and bytes must be checked. */
export function outputTransferRequestCid(durable: DurableOutputRecord): string;
/** The caller must independently verify local payload custody and digest. */
export function prepareOutputResultJson(durable: DurableOutputRecord,
  reply: string, payloadPhysicalDigest: string): string;
export function prepareOutputUnknown(record: OutputRecord): OutputTransition;
export function prepareOutputSuccessJson(record: OutputRecord,
  body: string): OutputTransition;
export function outputTransitionExpectedRevision(
  transition: OutputTransition): number;
export function outputTransitionDurableJson(durable: DurableOutputRecord,
  transition: OutputTransition): string;
/** Call only after the exact next output body was atomically persisted. */
export function commitOutputTransition(
  transition: OutputTransition): OutputRecord;
export function outputResultJson(record: OutputRecord): string;
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
export function exactRetransmissionEligible(record: IntentRecord,
  request: DispatchRequest): boolean;
