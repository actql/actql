declare const environmentBrand: unique symbol;
declare const preparedBrand: unique symbol;
declare const compilationBrand: unique symbol;
declare const requestBrand: unique symbol;
declare const admissionBrand: unique symbol;
declare const definitionBrand: unique symbol;

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
