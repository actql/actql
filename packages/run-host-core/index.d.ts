declare const environmentBrand: unique symbol;
declare const preparedBrand: unique symbol;
declare const compilationBrand: unique symbol;
declare const requestBrand: unique symbol;
declare const admissionBrand: unique symbol;
declare const definitionBrand: unique symbol;
declare const publicationBrand: unique symbol;
declare const resultOccurrenceBrand: unique symbol;

export interface CheckEnvironment {
  readonly [environmentBrand]: true;
}

export interface PreparedProgram {
  readonly [preparedBrand]: true;
}

export interface ValuesCompilation {
  readonly [compilationBrand]: true;
}

export interface RequestIdentity {
  readonly [requestBrand]: true;
}

export interface RunAdmission {
  readonly [admissionBrand]: true;
}

export interface RunDefinition {
  readonly [definitionBrand]: true;
}

export interface PublicationContract {
  readonly token: {readonly [publicationBrand]: true};
  readonly cid: string;
  readonly wire: string;
}

export interface PublicationLimits {
  readonly maxWireBytes: number;
  readonly maxNodes: number;
  readonly maxDepth: number;
}

export interface ResultOccurrenceEvidence {
  readonly token: {readonly [resultOccurrenceBrand]: true};
  readonly derivation: PublicationContract;
  readonly ordering: PublicationContract;
}

export interface RequestFields {
  readonly authorityScopeCid: string;
  readonly requestId: string;
  readonly logicalRequestScopeCid: string;
  readonly intentFingerprintCid: string;
  readonly programDefinitionCid: string;
  readonly parameterValuesCid: string;
  readonly callerInputIntentCid: string;
}

export interface ProfileSelection {
  readonly textTime?: boolean;
  readonly veca?: boolean;
  readonly rela?: boolean;
  readonly sga?: boolean;
  readonly tea?: boolean;
  readonly calendar?: boolean;
  readonly textRank?: boolean;
}

export interface PrivateCompilationWires {
  readonly executablePlan: string;
  readonly factManifest: string;
  readonly boundTemplate: string;
  readonly compiledPlan: string;
}

export function admitEnvironment(body: string, evidenceBundleCid: string,
  profiles: ProfileSelection): CheckEnvironment;
export function prepare(document: string, format: 'json' | 'yaml',
  environment: CheckEnvironment, parametersWire?: string): PreparedProgram;
export function compileValues(prepared: PreparedProgram): ValuesCompilation;
export function privateCompilationWires(
  compilation: ValuesCompilation): PrivateCompilationWires;
export function executionShape(compilation: ValuesCompilation): Readonly<{
  planNodeId: string;
  outputContractCid: string;
  resultNames: readonly string[];
}>;
/** Complete checked inventory; these identities are not read grants. */
export function resultDefinitions(prepared: PreparedProgram,
  compilation: ValuesCompilation): readonly Readonly<{
  name: string;
  cid: string;
  wire: string;
}>[];
/** Checked output schema for this Values compilation, not a read grant. */
export function resultSchema(prepared: PreparedProgram,
  compilation: ValuesCompilation): Readonly<{
    cid: string;
    wire: string;
    fields: readonly string[];
  }>;
// The Host establishes authority scope and admitted input intent. An identity
// handle or its fields do not grant Run access or permission to dispatch.
export function prepareRequest(prepared: PreparedProgram,
  authorityScopeCid: string, requestId: string,
  admittedInputIntentCid: string): RequestIdentity;
export function prepareSourceFreeRequest(prepared: PreparedProgram,
  compilation: ValuesCompilation, authorityScopeCid: string,
  requestId: string): RequestIdentity;
export function requestFields(request: RequestIdentity): RequestFields;
export function admitRequestFields(fields: RequestFields): RequestIdentity;
export function admitSourceFreeRequestFields(prepared: PreparedProgram,
  compilation: ValuesCompilation, fields: RequestFields): RequestIdentity;
export function requestRelation(requested: RequestIdentity,
  retained: RequestIdentity): 'different_request' | 'same_request' |
    'changed_intent';
// Current Host policy and authorization evidence must be issued by the Host.
// This operation only checks their binding to the compiled Program.
export function admitRun(prepared: PreparedProgram,
  compilation: ValuesCompilation, preparedInvocationWire: string,
  authorizationWire: string): RunAdmission;
// Call only after the Host has made its current authorization decision.
export function issueAllowedRun(prepared: PreparedProgram,
  compilation: ValuesCompilation, policy: Readonly<{
    executionContextCid: string;
    hostPolicyCid: string;
    expiresAt: string;
  }>): Readonly<{
    admission: RunAdmission;
    preparedInvocationWire: string;
    authorizationWire: string;
  }>;
export function issueRunDefinition(admission: RunAdmission, scopeId: string,
  runId: string, inputArtifactSetCid: string, createdAt: string,
  validUntil: string): RunDefinition;
export function privateRunDefinition(definition: RunDefinition): Readonly<{
  wire: string;
  cid: string;
}>;
export function admitRunDefinition(wire: string): RunDefinition;
export function prepareRunStart(requested: RequestIdentity,
  retained: RequestIdentity, definition: RunDefinition,
  retainedRunDefinitionCid: string, dispatchReserved: boolean,
  currentAuthorization: boolean): 'reserve_dispatch' |
  'reconcile_reserved_dispatch';
export function checkRunBinding(prepared: PreparedProgram,
  admission: RunAdmission, definition: RunDefinition): void;
export interface ValuesSiteSelection {
  readonly taskAttempt: number;
  readonly dispatchId: string;
  readonly siteKey: string;
  readonly siteGeneration: number;
  readonly runtimeBundleCid: string;
  readonly connectorRegistration: string;
  readonly connectorRevision: string;
  readonly strategyRevision: string;
  readonly obligationsCid: string;
  readonly budgetCid: string;
  readonly evidenceIssuerCapabilityCid: string;
  readonly grantCid: string;
}
/** Call only after current Host authorization and Site selection. */
export function issueSourceFreeDispatch(prepared: PreparedProgram,
  compilation: ValuesCompilation, admission: RunAdmission,
  definition: RunDefinition, request: RequestIdentity,
  selection: ValuesSiteSelection): Readonly<{cid: string; wire: string}>;
/** Canonical contract admission is not publication or read authorization. */
export function admitPublicationContract(name: string, wire: string,
  limits: PublicationLimits): PublicationContract;
export function issueResultManifest(runDefinition: PublicationContract,
  invocation: PublicationContract,
  definitions: readonly PublicationContract[],
  artifacts: readonly PublicationContract[],
  limits: PublicationLimits): PublicationContract;
/** Facts must come from the exact completed, checked Result export. */
export function issueResultOccurrenceEvidence(
  definition: PublicationContract, facts: Readonly<{
    logicalValueCid: string;
    resultSchemaCid: string;
    computationContractCid: string;
    inputRelationCids: readonly string[];
    scopeCid: string;
    effectiveDataPolicyCid: string;
    issuerId: string;
    authorityScopeCid: string;
  }>, limits: PublicationLimits): ResultOccurrenceEvidence;
export function issueCompleteResultArtifact(definition: PublicationContract,
  invocation: PublicationContract, evidence: ResultOccurrenceEvidence,
  retention: PublicationContract, actualRowCount: number,
  limits: PublicationLimits): PublicationContract;
/** Physical facts must come from an independently held Store object. */
export function issueDurableResultBinding(
  runDefinition: PublicationContract, definition: PublicationContract,
  invocation: PublicationContract, artifact: PublicationContract,
  ordering: PublicationContract, retention: PublicationContract,
  physical: Readonly<{
    codecContractCid: string;
    resultFields: readonly string[];
    resultSchemaWire: string;
    materialGenerationCid: string;
    storeAuthorityCid: string;
    rowCount: number;
    byteCount: number;
    physicalSha256: string;
  }>, limits: PublicationLimits): PublicationContract;
/** Establish logical identity from bounded bytes at the physical holder. */
export function inspectCanonicalResultRows(rowsWire: string,
  fields: readonly string[], limits: PublicationLimits):
  Readonly<{logicalRelationCid: string; rowCount: number}>;
export function validatePublicationChain(runDefinition: PublicationContract,
  invocation: PublicationContract,
  definitions: readonly PublicationContract[],
  artifacts: readonly PublicationContract[], manifest: PublicationContract,
  limits: PublicationLimits): void;
/** Physical CAS and durable persistence remain Store effects. */
export function validatePublicationRecordTransition(
  previous: PublicationContract | undefined, next: PublicationContract,
  uncommittedConfirmed: boolean): void;
