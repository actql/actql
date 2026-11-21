// Checked correspondence of the original Request/Run records retained by this Journal.
import {createHash} from 'node:crypto';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {valuesExecutionContextCid, validValuesHostPolicyRows} from './local-values-capacity.mjs';
import {BOUND_SOURCE_INVENTORY, validBoundSourceOccurrence} from './ordinary-source-binding.mjs';
import {fail, type JournalSqlConnection} from './client-request-journal-sql.mjs';
import type {SQLOutputValue} from 'node:sqlite';
import type {WireRunRef} from '../../packages/client-wire/index.js';
import {checked, type SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {prepareInstalledRunStateObservation, issueInstalledRunControlObservation}
  from '../host-common/run-state-observation.mjs';
import {retainedBudgetFailureMessage} from './client-dispatch-diagnostic.mjs';
import type {clientSourceOperationStorage} from './client-source-operation.mjs';
import type {createJournalAttempts} from './client-request-journal-attempts.mjs';
import type {assertJournalCancellationCustody, assertJournalSubmissionCustody, readJournalExplanationOriginal,
  snapshotJournalConfiguration, validLocalExecutionOwnerReceipt} from './client-request-journal-format.mjs';
import type {createJournalSubmissionRows} from './client-request-journal-submission-originals.mjs';

type RawRecord = Readonly<Record<string, unknown>>;
type RequestIdentityRow = Readonly<{
  authority_scope_cid: string; caller_request_id: string; program_definition_cid: string;
  parameter_values_cid: string; caller_input_intent_cid: string; logical_request_scope_cid: string;
  intent_fingerprint_cid: string;
}>;
type RequestIdentityAdmission<Original> = Readonly<{
  clientRequestAdmitRecord(scope: string, requestId: string, program: string,
    parameters: string, input: string, logicalScope: string, intent: string): Original | undefined;
}>;
type RequestIdentityRead = RequestIdentityAdmission<unknown> & Readonly<{
  clientRequestAuthorityScopeCid(handle: unknown): unknown;
  clientRequestCallerId(handle: unknown): unknown;
  clientRequestScopeCid(handle: unknown): unknown;
  clientRequestIntentCid(handle: unknown): unknown;
  clientRequestProgramCid(handle: unknown): unknown;
  clientRequestParametersCid(handle: unknown): unknown;
  clientRequestInputCid(handle: unknown): unknown;
}>;
type RequestFields = Readonly<{
  authorityScopeCid: string; requestId: string; logicalRequestScopeCid: string;
  intentFingerprintCid: string; programDefinitionCid: string; parameterValuesCid: string;
  callerInputIntentCid: string;
}>;
type AdmissionRow = Readonly<{
  namespace_id: unknown; authority_scope_cid: unknown; run_definition_cid: unknown;
  revision: unknown; lookup_expires_at: unknown;
}>;
type RunDefinition = Readonly<{name: 'run_definition'; identity: string; wire: string}>;
type RunDefinitionRow = Readonly<{run_definition_cid: unknown; run_definition_wire: unknown}>;
type DefinitionControl = Readonly<{
  admit(name: 'run_definition', wire: string, options: Readonly<{
    maxWireBytes: number; maxNodes: number; maxDepth: number;
  }>): unknown;
}>;
type SourceOccurrence = RawRecord & Readonly<{
  checkedSource?: RawRecord; installationBinding?: RawRecord; readTuple?: RawRecord;
}>;
type CandidateInventory = Readonly<{version?: unknown; environmentCid?: unknown; acquisitions?: SourceOccurrence[]}>;
type LogicalPlanOriginal = Readonly<{compiledPlanWire: string; planViewWire: string}>;
type ResultPolicyOriginal = Readonly<{kind: 'data_policy'; cid: string; wire: string}>;
type ValuesPolicyOriginal = Readonly<{cid: string; wire: string}>;
type AdmissionEvidence = Readonly<{
  authorization: string; prepared: string; submittedIntentCid?: string; effectOriginalRunWire?: string;
  sourceInventory?: string; updateTargetRunOriginal?: Readonly<{installations: readonly object[]}>;
  logicalPlanOriginal?: LogicalPlanOriginal; valuesHostPolicyOriginal?: ValuesPolicyOriginal;
  resultPolicyOriginal?: ResultPolicyOriginal; modelOriginalRunWire?: string;
  inferRunOriginal?: Readonly<{materialsWire: string; resultPolicyOriginal: ResultPolicyOriginal}>;
}>;
type UpdateOriginalControl = Readonly<{run(original: unknown, captured: RawRecord): unknown}>;
type CapturedEvidence = Readonly<{wire: string; value: AdmissionEvidence; modelRunDefinitionWire?: string}>;
type EvidenceRow = Readonly<{
  run_admission_evidence_json: string | null; program_definition_cid: string; parameter_values_cid: string;
}>;
type ResultNamesRow = Readonly<{result_names_json: string | null}>;
type RetainedRunRow = EvidenceRow & ResultNamesRow & RunDefinitionRow & Readonly<{
  authority_scope_cid: string;
  dispatch_reserved: number; pre_dispatch_failure_confirmed: number;
  physical_start_reserved: number | null; cancellation_requested: number; physical_close_confirmed: number;
  observed_terminal_outcome: string | null;
}>;

export const cid = (value: unknown): value is string => typeof value === 'string' &&
  /^sha256:[0-9a-f]{64}$/u.test(value);
export const text = (value: unknown): value is string => typeof value === 'string' &&
  value.length > 0 && value.length <= 256 &&
  !/[\u0000-\u001f\u007f]/u.test(value);
export const instant = (value: unknown): value is string => typeof value === 'string' &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/u.test(value) &&
  Number.isFinite(Date.parse(value)) &&
  new Date(value).toISOString() === value;

export function checkedIdentity(handle: unknown, control: RequestIdentityRead): RequestFields {
  const fields = {
    authorityScopeCid: control.clientRequestAuthorityScopeCid(handle),
    requestId: control.clientRequestCallerId(handle),
    logicalRequestScopeCid: control.clientRequestScopeCid(handle),
    intentFingerprintCid: control.clientRequestIntentCid(handle),
    programDefinitionCid: control.clientRequestProgramCid(handle),
    parameterValuesCid: control.clientRequestParametersCid(handle),
    callerInputIntentCid: control.clientRequestInputCid(handle),
  };
  if (!text(fields.requestId) ||
      ![fields.authorityScopeCid, fields.logicalRequestScopeCid,
        fields.intentFingerprintCid, fields.programDefinitionCid,
        fields.parameterValuesCid, fields.callerInputIntentCid].every(cid) ||
      control.clientRequestAdmitRecord(
        fields.authorityScopeCid as string, fields.requestId as string,
        fields.programDefinitionCid as string, fields.parameterValuesCid as string,
        fields.callerInputIntentCid as string, fields.logicalRequestScopeCid as string,
        fields.intentFingerprintCid as string) === undefined) {
    fail('InvalidClientRequestIdentity');
  }
  return Object.freeze(fields) as RequestFields;
}

export function retainedIdentity<Original>(row: RequestIdentityRow, control: RequestIdentityAdmission<Original>) {
  const value = control.clientRequestAdmitRecord(
    row.authority_scope_cid, row.caller_request_id,
    row.program_definition_cid, row.parameter_values_cid,
    row.caller_input_intent_cid, row.logical_request_scope_cid,
    row.intent_fingerprint_cid,
  );
  if (value === undefined) fail('ClientRequestJournalCorrupt');
  return value;
}

export function admission(row: AdmissionRow) {
  if (!text(row.namespace_id) || !cid(row.authority_scope_cid) ||
      !cid(row.run_definition_cid) ||
      !Number.isSafeInteger(row.revision) || (row.revision as number) < 0 ||
      !instant(row.lookup_expires_at)) {
    fail('ClientRequestJournalCorrupt');
  }
  return Object.freeze({
    ref: Object.freeze({
      namespaceId: row.namespace_id,
      authorityScopeCid: row.authority_scope_cid,
      runDefinitionCid: row.run_definition_cid,
    }),
    durability: 'durable',
    revision: Number(row.revision),
    lookupExpiresAt: row.lookup_expires_at,
  });
}

export function checkedRunDefinition(value: unknown, control: DefinitionControl, maxBytes: number): RunDefinition {
  if (value === null || typeof value !== 'object' ||
      (value as RawRecord).name !== 'run_definition' || !cid((value as RawRecord).identity) ||
      typeof (value as RawRecord).wire !== 'string' ||
      Buffer.byteLength((value as RawRecord).wire as string, 'utf8') > maxBytes ||
      control === null || typeof control !== 'object' ||
      typeof control.admit !== 'function') {
    fail('InvalidClientRunDefinition');
  }
  let admitted: RawRecord | undefined;
  try {
    admitted = control.admit('run_definition', (value as RawRecord).wire as string, {
      maxWireBytes: maxBytes, maxNodes: 4096, maxDepth: 64,
    }) as RawRecord | undefined;
  } catch (cause) { fail('InvalidClientRunDefinition', cause); }
  if (admitted?.name !== 'run_definition' ||
      admitted.identity !== (value as RawRecord).identity ||
      admitted.wire !== (value as RawRecord).wire) {
    fail('InvalidClientRunDefinition');
  }
  return admitted as RunDefinition;
}

export function retainedRunDefinition(row: RunDefinitionRow, control: DefinitionControl, maxBytes: number) {
  if (typeof row.run_definition_wire !== 'string') {
    fail('ClientRequestDefinitionMissing');
  }
  let admitted;
  try {
    admitted = checkedRunDefinition({
      name: 'run_definition',
      identity: row.run_definition_cid,
      wire: row.run_definition_wire,
    }, control, maxBytes);
  } catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
  return admitted;
}

// A bounded Host-private physical inventory. Its immutable canonical string
// stays in the existing Run admission row; it is not caller input identity,
// a permission token, or a second execution journal.
export function validateSourceInventory(wire: unknown): string {
  if (typeof wire !== 'string' || Buffer.byteLength(wire) > 256 * 1024) {
    fail('InvalidClientSourceInventory');
  }
  let value: CandidateInventory | null;
  try { value = JSON.parse(wire); } catch (cause) { fail('InvalidClientSourceInventory', cause); }
  const keys = (object: unknown, expected: string): object is RawRecord => object !== null && typeof object === 'object' &&
    !Array.isArray(object) && Object.keys(object).sort().join(',') === expected.split(',').sort().join(',');
  if (value?.version === BOUND_SOURCE_INVENTORY) {
    let canonical;
    try { canonical = canonicalValueJson(value, {dataKeys: true}); }
    catch (cause) { fail('InvalidClientSourceInventory', cause); }
    if (!keys(value, 'version,environmentCid,acquisitions') || !cid(value.environmentCid) ||
        canonical !== wire ||
        !Array.isArray(value.acquisitions) || value.acquisitions.length !== 2 ||
        !value.acquisitions.every(validBoundSourceOccurrence) ||
        (value.acquisitions.every(item => item.checkedSource!.requirementCid !== undefined)
          ? value.acquisitions[0].checkedSource!.requirementCid === value.acquisitions[1].checkedSource!.requirementCid
          : value.acquisitions[0].stage === value.acquisitions[1].stage &&
            value.acquisitions[0].input === value.acquisitions[1].input)) fail('InvalidClientSourceInventory');
    return wire;
  }
  if (value?.version === 'actql-client-keyed-source-inventory/0.1') {
    // The installed Connector owns the target's physical schema. The journal
    // retains its exact data plus immutable installation binding, not another
    // provider-name dispatcher. Semantic preparation and replay still match
    // the original checked selections before physical start.
    if (!keys(value, 'version,environmentCid,acquisitions') || !cid(value.environmentCid) ||
        canonicalValueJson(value, {dataKeys: true}) !== wire ||
        !Array.isArray(value.acquisitions) || value.acquisitions.length !== 2) {
      fail('InvalidClientSourceInventory');
    }
    const commonKeys = 'sourceRef,sourceContractCid,carrierSchemaContractCid,sourceDataPolicyCid,dataClassification,sourceViewContractCid';
    // Source occurrence order is not physical task identity: a Content
    // component can consume both original reads inside task 0. The selection
    // CID below still binds the exact checked task, port and JOIN step.
    for (const [index, occurrence] of value.acquisitions.entries()) {
      const source = occurrence?.checkedSource, binding = occurrence?.installationBinding;
      if (!keys(occurrence, 'stage,input,task,checkedSource,readTuple,physicalBinding,installationBinding') ||
          !Number.isSafeInteger(occurrence.stage) || (occurrence.stage as number) < 0 ||
          !Number.isSafeInteger(occurrence.input) || (occurrence.input as number) < 0 ||
          (index === 0 ? occurrence.task !== 0 : occurrence.task !== 0 && occurrence.task !== 1) ||
          !keys(source, commonKeys + (index === 0 ? ',requirementCid,inputContractCid,outputContractCid'
            : ',selectionCid,programCid,parametersCid,step')) ||
          ![source.sourceContractCid, source.carrierSchemaContractCid, source.sourceDataPolicyCid,
            source.sourceViewContractCid, ...(index === 0
              ? [source.requirementCid, source.inputContractCid, source.outputContractCid]
              : [source.selectionCid, source.programCid, source.parametersCid])].every(cid) ||
          !text(source.sourceRef) || !['public', 'internal', 'confidential', 'restricted', 'unknown']
            .includes(source.dataClassification as string) ||
          !keys(binding, 'connectorId,connectorRegistration,connectorRevision,bindingCid') ||
          ![binding.connectorId, binding.connectorRegistration, binding.connectorRevision].every(text) ||
          !cid(binding.bindingCid) || !keys(occurrence.readTuple, 'connection,resource,operation') ||
          ![occurrence.readTuple.connection, occurrence.readTuple.resource].every(text) ||
          occurrence.readTuple.operation !== 'read' || occurrence.physicalBinding === null ||
          typeof occurrence.physicalBinding !== 'object' || Array.isArray(occurrence.physicalBinding) ||
          Object.keys(occurrence.physicalBinding).length === 0) fail('InvalidClientSourceInventory');
      if (index === 1) {
        if (!Number.isSafeInteger(source.step) || (source.step as number) < 0) fail('InvalidClientSourceInventory');
        const selection = {version: 'actql-installed-keyed-selection/0.1',
          programCid: source.programCid, parametersCid: source.parametersCid,
          coordinates: [occurrence.stage, occurrence.input, occurrence.task, source.step],
          sourceFacts: [source.sourceRef, source.sourceContractCid, source.carrierSchemaContractCid,
            source.sourceDataPolicyCid, source.dataClassification, source.sourceViewContractCid]};
        if (`sha256:${createHash('sha256').update(canonicalValueJson(selection, {dataKeys: true})).digest('hex')}` !==
            source.selectionCid) fail('InvalidClientSourceInventory');
      }
    }
    if (value.acquisitions[0].stage !== value.acquisitions[1].stage ||
        value.acquisitions[0].input === value.acquisitions[1].input) fail('InvalidClientSourceInventory');
    return wire;
  }
  if (!keys(value, 'version,environmentCid,acquisitions') ||
      value.version !== 'actql-client-source-inventory/0.1' || !cid(value.environmentCid) ||
      !Array.isArray(value.acquisitions) || value.acquisitions.length !== 2 ||
      canonicalJson(value) !== wire) fail('InvalidClientSourceInventory');
  const requirements = new Set<unknown>();
  const validPhysicalBinding = (binding: unknown): binding is RawRecord => {
    if (keys(binding, 'version,database,schema,table,utf8_hex') &&
        binding.version === 'actql-installed-duckdb-target/0.1') {
      return keys(binding.utf8_hex, 'database,schema,table') &&
        !['database','schema','table'].some(key => typeof binding[key] !== 'string' ||
          !binding[key] || typeof (binding.utf8_hex as RawRecord)[key] !== 'string' ||
          !/^(?:[0-9a-f]{2})+$/u.test((binding.utf8_hex as RawRecord)[key] as string) ||
          Buffer.from(Buffer.from((binding.utf8_hex as RawRecord)[key] as string, 'hex').toString('utf8'), 'utf8').toString('hex') !== (binding.utf8_hex as RawRecord)[key] ||
          Buffer.from((binding.utf8_hex as RawRecord)[key] as string, 'hex').toString('utf8').normalize('NFC') !== binding[key]);
    }
    if (keys(binding, 'version,org_id,instance_origin,site_key,site_generation,connection_revision,catalog_cid,resource,fields') &&
        binding.version === 'actql-installed-salesforce-target/0.1') {
      let origin;
      try { origin = new URL(binding.instance_origin as string); } catch { return false; }
      return origin.protocol === 'https:' && origin.origin === binding.instance_origin &&
        [binding.org_id, binding.site_key, binding.connection_revision,
          binding.resource].every(value => typeof value === 'string' && value !== '') &&
        Number.isSafeInteger(binding.site_generation) && (binding.site_generation as number) >= 0 &&
        cid(binding.catalog_cid) && Array.isArray(binding.fields) &&
        binding.fields.length > 0 && binding.fields.length <= 100 &&
        binding.fields.every(value => typeof value === 'string' && value !== '') &&
        new Set(binding.fields).size === binding.fields.length;
    }
    // This is a Host-private physical target, not a new common Engine
    // identity. The installed Site checks it again against its publication.
    let origin;
    try { origin = new URL((binding as RawRecord | null | undefined)?.api_origin as string); } catch { return false; }
    return keys(binding, 'version,api_origin,repository_id,repository_node_id,owner,repo,catalog_cid,resource,fields') &&
      binding.version === 'actql-installed-github-target/0.1' &&
      origin.protocol === 'https:' && origin.origin === binding.api_origin &&
      Number.isSafeInteger(binding.repository_id) && (binding.repository_id as number) > 0 &&
      [binding.repository_node_id, binding.owner, binding.repo,
        binding.resource].every(value => typeof value === 'string' && value !== '') &&
      cid(binding.catalog_cid) && Array.isArray(binding.fields) &&
      binding.fields.length > 0 && binding.fields.length <= 100 &&
      binding.fields.every(value => typeof value === 'string' && value !== '') &&
      new Set(binding.fields).size === binding.fields.length;
  };
  for (const [index, occurrence] of value.acquisitions.entries()) {
    if (!keys(occurrence, 'stage,input,task,checkedSource,readTuple,physicalBinding') ||
        occurrence.stage !== index || occurrence.input !== 0 || occurrence.task !== index ||
        !keys(occurrence.checkedSource, 'requirementCid,sourceRef,sourceContractCid,carrierSchemaContractCid,sourceDataPolicyCid,dataClassification,sourceViewContractCid,inputContractCid,outputContractCid') ||
        !keys(occurrence.readTuple, 'connection,resource,operation') ||
        !validPhysicalBinding(occurrence.physicalBinding)) {
      fail('InvalidClientSourceInventory');
    }
    const source = occurrence.checkedSource, binding = occurrence.physicalBinding;
    if (![source.requirementCid, source.sourceContractCid, source.carrierSchemaContractCid,
      source.sourceDataPolicyCid, source.sourceViewContractCid, source.inputContractCid,
      source.outputContractCid].every(cid) || typeof source.sourceRef !== 'string' ||
      !source.sourceRef || !['public', 'internal', 'confidential', 'restricted', 'unknown']
        .includes(source.dataClassification as string) || requirements.has(source.requirementCid) ||
      occurrence.readTuple.operation !== 'read' ||
      typeof occurrence.readTuple.connection !== 'string' || !occurrence.readTuple.connection ||
      typeof occurrence.readTuple.resource !== 'string' || !occurrence.readTuple.resource ||
      !validPhysicalBinding(binding) ||
      (binding.version === 'actql-installed-github-target/0.1' &&
        (binding.resource !== occurrence.readTuple.resource ||
         occurrence.readTuple.connection !==
           `github:${new URL(binding.api_origin as string).host}/${binding.owner}/${binding.repo}`)) ||
      (binding.version === 'actql-installed-salesforce-target/0.1' &&
        (binding.resource !== occurrence.readTuple.resource ||
         occurrence.readTuple.connection !== `salesforce:${binding.org_id}`))) {
      fail('InvalidClientSourceInventory');
    }
    requirements.add(source.requirementCid);
  }
  return wire;
}

export function logicalPlanOriginalShape(value: unknown): value is LogicalPlanOriginal {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).sort().join(',') === 'compiledPlanWire,planViewWire' &&
    typeof (value as RawRecord).compiledPlanWire === 'string' && (value as RawRecord).compiledPlanWire !== '' &&
    typeof (value as RawRecord).planViewWire === 'string' && (value as RawRecord).planViewWire !== '';
}

export function structuralExplanationOriginalShape(value: unknown): value is Readonly<{factsWire: string}> {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).join(',') === 'factsWire' &&
    typeof (value as RawRecord).factsWire === 'string' && (value as RawRecord).factsWire !== '';
}

export function assertKeyedInventoryRequest(wire: string | undefined, fields: Pick<RequestFields, 'programDefinitionCid' | 'parameterValuesCid'>) {
  if (wire === undefined) return;
  const inventory: CandidateInventory = JSON.parse(wire);
  if (inventory.version !== 'actql-client-keyed-source-inventory/0.1') return;
  const selection = inventory.acquisitions![1].checkedSource!;
  if (selection.programCid !== fields.programDefinitionCid ||
      selection.parametersCid !== fields.parameterValuesCid) {
    fail('ClientRequestSourceInventoryMismatch');
  }
}

const admissionEvidenceFields = Object.freeze(['authorization', 'prepared',
  'sourceInventory', 'resultPolicyOriginal', 'modelOriginalRunWire',
  'valuesHostPolicyOriginal', 'logicalPlanOriginal', 'updateTargetRunOriginal',
  'submittedIntentCid', 'effectOriginalRunWire', 'inferRunOriginal']);

export function admissionEvidenceShape(value: RawRecord | null | undefined, updateOriginalControl?: UpdateOriginalControl,
  captured?: {modelRunDefinitionWire?: string}): value is AdmissionEvidence {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  if (Object.keys(value).some(key => !admissionEvidenceFields.includes(key)) ||
      !Object.hasOwn(value, 'prepared') || !Object.hasOwn(value, 'authorization') ||
      typeof value.prepared !== 'string' || typeof value.authorization !== 'string') return false;
  if (value.submittedIntentCid !== undefined && !cid(value.submittedIntentCid)) return false;
  // Bounded original-codec DATA only. Its Common material reader must still
  // admit the full Run/request/evidence pair before a restored use. Presence
  // in this private record is neither that admission nor a resume permission.
  if (value.effectOriginalRunWire !== undefined &&
      (typeof value.effectOriginalRunWire !== 'string' || value.effectOriginalRunWire.length === 0)) return false;
  if (value.inferRunOriginal !== undefined) {
    const original = value.inferRunOriginal as RawRecord | null;
    if (original === null || typeof original !== 'object' || Array.isArray(original)) return false;
    const keys = Object.keys(original);
    if (keys.length !== 2 || !keys.includes('materialsWire') || !keys.includes('resultPolicyOriginal') ||
        typeof original.materialsWire !== 'string' || original.materialsWire.length === 0) return false;
    const policy = original.resultPolicyOriginal as RawRecord | null;
    if (policy === null || typeof policy !== 'object' || Array.isArray(policy)) return false;
    const policyKeys = Object.keys(policy);
    if (policyKeys.length !== 3 || !['kind', 'cid', 'wire'].every(key => policyKeys.includes(key)) ||
        policy.kind !== 'data_policy' || !cid(policy.cid) || typeof policy.wire !== 'string') return false;
  }
  if (value.sourceInventory !== undefined) validateSourceInventory(value.sourceInventory);
  if (value.updateTargetRunOriginal !== undefined &&
      updateOriginalControl?.run(value.updateTargetRunOriginal, value) !== true) return false;
  if (value.logicalPlanOriginal !== undefined &&
      !logicalPlanOriginalShape(value.logicalPlanOriginal)) return false;
  if (value.valuesHostPolicyOriginal !== undefined) {
    const original = value.valuesHostPolicyOriginal as RawRecord | null;
    if (original === null || typeof original !== 'object' || Array.isArray(original) ||
        Object.keys(original).sort().join(',') !== 'cid,wire' ||
        !cid(original.cid) || typeof original.wire !== 'string') return false;
    let body: RawRecord | null, prepared: RawRecord | null, authorization: RawRecord | null;
    try {
      body = JSON.parse(original.wire);
      prepared = JSON.parse(value.prepared as string);
      authorization = JSON.parse(value.authorization as string);
    } catch { return false; }
    if (body === null || typeof body !== 'object' || Array.isArray(body) ||
        Object.keys(body).sort().join(',') !== 'max_rows,name,version' ||
        body.version !== 'actql-installed-local-policy/0.1' ||
        body.name !== 'source-free-values' ||
        !validValuesHostPolicyRows(body.max_rows) ||
        canonicalJson(body) !== original.wire ||
        `sha256:${createHash('sha256').update(original.wire).digest('hex')}` !== original.cid ||
        prepared?.host_policy_cid !== original.cid ||
        authorization?.host_policy_cid !== original.cid) return false;
  }
  if (value.resultPolicyOriginal !== undefined &&
      (value.resultPolicyOriginal === null ||
       typeof value.resultPolicyOriginal !== 'object' ||
       Array.isArray(value.resultPolicyOriginal) ||
       Object.keys(value.resultPolicyOriginal).sort().join(',') !== 'cid,kind,wire' ||
       (value.resultPolicyOriginal as RawRecord).kind !== 'data_policy' ||
       typeof (value.resultPolicyOriginal as RawRecord).cid !== 'string' ||
       typeof (value.resultPolicyOriginal as RawRecord).wire !== 'string')) return false;
  if (value.modelOriginalRunWire !== undefined) {
    if (typeof value.modelOriginalRunWire !== 'string') return false;
    let original: RawRecord | null;
    try { original = JSON.parse(value.modelOriginalRunWire as string); } catch { return false; }
    if (original === null || typeof original !== 'object' || Array.isArray(original) ||
        Object.keys(original).sort().join(',') !==
          'boundInvocationTemplateWire,compiledPlanWire,preparedInvocationWire,runAuthorizationWire,runDefinitionWire' ||
        Object.values(original).some(wire => typeof wire !== 'string' || wire === '') ||
        canonicalValueJson(original) !== value.modelOriginalRunWire ||
        original.preparedInvocationWire !== value.prepared ||
        original.runAuthorizationWire !== value.authorization) return false;
    if (captured !== undefined) captured.modelRunDefinitionWire = original.runDefinitionWire as string;
  }
  return true;
}

export function assertSourceInventory(retained: Readonly<{physicalStartReserved?: boolean;
  runAdmissionEvidence?: AdmissionEvidence}>, proposed: unknown) {
  if (proposed !== undefined) validateSourceInventory(proposed);
  // A physical start can only be reconciled through its retained owner; a
// later configuration never becomes authority to restart its sources.
  if (retained.physicalStartReserved === true) return;
  if (retained.runAdmissionEvidence?.sourceInventory !== proposed) {
    fail('ClientRequestSourceInventoryMismatch');
  }
}

// Private replay evidence is stored atomically with acceptance. Its semantic
// admission remains with the common MoonBit owner before any physical start.
export function evidenceJson(value: unknown, maxBytes: number, updateOriginalControl?: UpdateOriginalControl): CapturedEvidence | null {
  if (value === undefined) return null;
  // Capture mutable input once, then admit the exact bytes that can be stored.
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).some(key => !admissionEvidenceFields.includes(key)) ||
      !Object.hasOwn(value, 'prepared') || !Object.hasOwn(value, 'authorization')) {
    fail('InvalidClientRunAdmissionEvidence');
  }
  const wire = JSON.stringify(value);
  if (typeof wire !== 'string' || Buffer.byteLength(wire) > maxBytes) {
    fail('InvalidClientRunAdmissionEvidence');
  }
  const captured: {wire: string; value: RawRecord | null; modelRunDefinitionWire?: string} = {wire, value: JSON.parse(wire)};
  if (!admissionEvidenceShape(captured.value, updateOriginalControl, captured)) {
    fail('InvalidClientRunAdmissionEvidence');
  }
  freezeAdmissionEvidence(captured.value);
  return Object.freeze(captured) as CapturedEvidence;
}

export function retainedEvidence(row: EvidenceRow, updateOriginalControl?: UpdateOriginalControl, original?: CapturedEvidence | null) {
  if (row.run_admission_evidence_json === null) return undefined;
  if (original != null && row.run_admission_evidence_json === original.wire) return original.value;
  let value: RawRecord | null;
  try { value = JSON.parse(row.run_admission_evidence_json); }
  catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
  // This acceptance already admitted every unchanged material. A saved intent
  // CID is the only permitted addition, and it still receives its own check.
  if (original != null && original.value.submittedIntentCid === undefined &&
      cid(value?.submittedIntentCid) && JSON.stringify({...original.value,
        submittedIntentCid: value.submittedIntentCid}) === row.run_admission_evidence_json) {
    return freezeAdmissionEvidence(value as AdmissionEvidence);
  }
  try {
    if (!admissionEvidenceShape(value, updateOriginalControl)) fail('ClientRequestJournalCorrupt');
    assertKeyedInventoryRequest(value.sourceInventory, {
      programDefinitionCid: row.program_definition_cid,
      parameterValuesCid: row.parameter_values_cid});
  } catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
  return freezeAdmissionEvidence(value as AdmissionEvidence);
}

export function freezeAdmissionEvidence(value: AdmissionEvidence) {
  if (value.logicalPlanOriginal !== undefined) Object.freeze(value.logicalPlanOriginal);
  if (value.inferRunOriginal !== undefined) {
    Object.freeze(value.inferRunOriginal.resultPolicyOriginal);
    Object.freeze(value.inferRunOriginal);
  }
  if (value.updateTargetRunOriginal !== undefined) {
    value.updateTargetRunOriginal.installations.forEach(Object.freeze);
    Object.freeze(value.updateTargetRunOriginal.installations);
    Object.freeze(value.updateTargetRunOriginal);
  }
  return Object.freeze(value);
}

export function retainedResultNames(row: ResultNamesRow, maxWireBytes: number): string[] | undefined {
  if (row.result_names_json === null) return undefined;
  // Reuse the installed per-metadata-object wire allowance before JSON
  // expansion. This is not an aggregate database or whole-record grant;
  // Result cardinality comes from the retained original inventory.
  if (Buffer.byteLength(row.result_names_json, 'utf8') > maxWireBytes) {
    fail('ClientRequestJournalCorrupt');
  }
  let names: unknown;
  try { names = JSON.parse(row.result_names_json); }
  catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
  if (!Array.isArray(names) ||
      names.some(name => typeof name !== 'string' || !name) ||
      new Set(names).size !== names.length) {
    fail('ClientRequestJournalCorrupt');
  }
  return names as string[];
}

export function retainedRunFacts(row: RetainedRunRow, publicationControl: DefinitionControl, maxWireBytes: number,
  updateOriginalControl?: UpdateOriginalControl) {
  if (![0, 1].includes(row.dispatch_reserved) ||
      ![0, 1].includes(row.pre_dispatch_failure_confirmed) ||
      ![null, 0, 1].includes(row.physical_start_reserved) ||
      ![0, 1].includes(row.cancellation_requested) ||
      ![0, 1].includes(row.physical_close_confirmed) ||
      ![null, 'failed', 'cancelled'].includes(
        row.observed_terminal_outcome)) {
    fail('ClientRequestJournalCorrupt');
  }
  const runAdmissionEvidence = retainedEvidence(row, updateOriginalControl);
  const runDefinition = retainedRunDefinition(row, publicationControl,
    maxWireBytes);
  if (runAdmissionEvidence?.valuesHostPolicyOriginal !== undefined &&
      (JSON.parse(row.run_definition_wire as string) as RawRecord).authorization_context_cid !==
        valuesExecutionContextCid(row.authority_scope_cid,
          runAdmissionEvidence.valuesHostPolicyOriginal)) {
    fail('ClientRequestJournalCorrupt');
  }
  if (runAdmissionEvidence?.modelOriginalRunWire !== undefined &&
      (JSON.parse(runAdmissionEvidence.modelOriginalRunWire) as RawRecord).runDefinitionWire !== row.run_definition_wire) {
    fail('ClientRequestJournalCorrupt');
  }
  // Metadata/status/control consumes the admitted Run and current row flags,
  // not its logical map. Keep the bounded original bytes here; the existing
  // plan reader checks their semantic binding only when that map is used.
  const savedPlan = runAdmissionEvidence?.logicalPlanOriginal;
  if (savedPlan !== undefined &&
      (Buffer.byteLength(savedPlan.compiledPlanWire) > maxWireBytes ||
       Buffer.byteLength(savedPlan.planViewWire) > maxWireBytes)) {
    fail('ClientRequestJournalCorrupt');
  }
  return Object.freeze({
    runDefinition,
    programDefinitionCid: row.program_definition_cid,
    resultNames: retainedResultNames(row, maxWireBytes),
    runAdmissionEvidence,
    cancellationRequested: row.cancellation_requested === 1,
    physicalCloseConfirmed: row.physical_close_confirmed === 1,
    dispatchReserved: row.dispatch_reserved === 1,
    preDispatchFailureConfirmed:
      row.pre_dispatch_failure_confirmed === 1,
    physicalStartReserved: row.physical_start_reserved === null
      ? undefined : row.physical_start_reserved === 1,
    observedTerminalOutcome: row.observed_terminal_outcome,
  });
}

// Native SQLite rows stay DATA. Frame membership belongs to the map that
// the actual open Journal creates and never returns to its callers.
type JournalRow = Readonly<Record<string, SQLOutputValue>>;
type JournalRunFrames = WeakMap<object, Readonly<{
  row: JournalRow;
  requestControl: RequestIdentityRead;
  publicationControl: DefinitionControl;
}>>;

export function readJournalRunDefinitionRow(ref: WireRunRef | null | undefined,
  requestControl: RequestIdentityAdmission<unknown>, ensureOpen: () => void,
  selectRef: Pick<ReturnType<JournalSqlConnection['prepare']>, 'get'>) {
  ensureOpen();
  if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
      !cid(ref?.runDefinitionCid) ||
      typeof requestControl?.clientRequestAdmitRecord !== 'function') {
    fail('InvalidClientRunLookup');
  }
  try {
    return selectRef.get(ref.namespaceId, ref.authorityScopeCid,
      ref.runDefinitionCid);
  } catch (error) { fail('ClientRequestLookupUnknown', error); }
}

export function retainJournalRunStateFrame(runStateFrames: JournalRunFrames, frame: object,
  selected: WireRunRef | null | undefined) {
  const original = runStateFrames.get(frame);
  if (original === undefined || original.row.namespace_id !== selected?.namespaceId ||
      original.row.authority_scope_cid !== selected?.authorityScopeCid ||
      original.row.run_definition_cid !== selected?.runDefinitionCid) {
    fail('ForeignRunStateObservation');
  }
  return original;
}

export const sameRunStateRow = (row: JournalRow | undefined, original: JournalRow) => row !== undefined &&
  Object.keys(row).length === Object.keys(original).length &&
  Object.keys(row).every(key => row[key] === original[key]);
const statePublicationAdvanced = (old: JournalRow, next: JournalRow) =>
  Number.isSafeInteger(old.state_revision) && (old.state_revision as number) >= 0 &&
  Number.isSafeInteger(next.state_revision) &&
    ((next.state_revision as number) > (old.state_revision as number) || old.state_observation_key === null &&
      old.state_revision === 0 && next.state_revision === 0) &&
  (old.state_observation_key === null || typeof old.state_observation_key === 'string' && old.state_observation_key.length > 0) &&
  typeof next.state_observation_key === 'string' && next.state_observation_key.length > 0 &&
  next.state_observation_key !== old.state_observation_key;
const physicalCloseAdvanced = (old: JournalRow, next: JournalRow) =>
  Number.isSafeInteger(old.revision) && (old.revision as number) >= 0 &&
  Number.isSafeInteger(next.revision) && next.revision === (old.revision as number) + 1 &&
  old.physical_start_reserved === 1 && old.physical_close_confirmed === 0 &&
  next.physical_close_confirmed === 1 && old.cancellation_requested === 0 &&
  old.observed_terminal_outcome === null;
export function admitJournalRunDefinitionRow(runStateFrames: JournalRunFrames,
  row: JournalRow, requestControl: RequestIdentityRead, publicationControl: DefinitionControl,
  maxRunDefinitionWireBytes: number, updateOriginalControl: UpdateOriginalControl | undefined) {
  const retained = retainedIdentity(row as RequestIdentityRow, requestControl);
  if (requestControl.clientRequestScopeCid(retained) !== row.logical_request_scope_cid) {
    fail('ClientRequestJournalCorrupt');
  }
  const accepted = admission(row as AdmissionRow);
  const facts = Object.freeze({
    ref: accepted.ref, durability: accepted.durability,
    revision: accepted.revision, requestId: (row as RequestIdentityRow).caller_request_id,
    ...retainedRunFacts(row as RetainedRunRow, publicationControl, maxRunDefinitionWireBytes, updateOriginalControl),
  });
  runStateFrames.set(facts, Object.freeze({row: Object.freeze({...row}),
    requestControl, publicationControl}));
  return facts;
}

// Only public observation metadata may explain this particular frame
// change. Both frames already belong to this Journal's full admission;
// every immutable/control column and selected key must remain exact.
export function reinspectJournalRunStopAfterStatePublication(runStateFrames: JournalRunFrames,
  beforeFrame: object, afterFrame: object) {
  const before = runStateFrames.get(beforeFrame), after = runStateFrames.get(afterFrame);
  if (before === undefined || after === undefined || beforeFrame === afterFrame ||
      before.requestControl !== after.requestControl || before.publicationControl !== after.publicationControl) return false;
  const old = before.row, next = after.row;
  return statePublicationAdvanced(old, next) &&
    Object.keys(old).length === Object.keys(next).length &&
    Object.keys(old).every(key => key === 'state_revision' || key === 'state_observation_key' || old[key] === next[key]);
}

// Signing may overlap this Journal owner's completed physical-stop write.
// This is reobservation of the SAME admitted Run, never stop authority or
// permission to accept another control, publication or identity change.
export function reinspectJournalRunAfterPhysicalClose(runStateFrames: JournalRunFrames,
  beforeFrame: object, afterFrame: object) {
  const before = runStateFrames.get(beforeFrame), after = runStateFrames.get(afterFrame);
  if (before === undefined || after === undefined || beforeFrame === afterFrame ||
      before.requestControl !== after.requestControl || before.publicationControl !== after.publicationControl) return false;
  const old = before.row, next = after.row;
  return physicalCloseAdvanced(old, next) &&
    Object.keys(old).length === Object.keys(next).length &&
    Object.keys(old).every(key => key === 'revision' || key === 'physical_close_confirmed' || old[key] === next[key]);
}

// A signing recovery can span both the original physical close and its
// public status publication. Compose those same one-way progressions;
// every other complete admitted column remains exact. No copied frame or
// changed cancellation, terminal, authority or retained body is accepted.
export function reinspectJournalRunForSigning(runStateFrames: JournalRunFrames,
  beforeFrame: object, afterFrame: object) {
  const before = runStateFrames.get(beforeFrame), after = runStateFrames.get(afterFrame);
  if (before === undefined || after === undefined || beforeFrame === afterFrame ||
      before.requestControl !== after.requestControl || before.publicationControl !== after.publicationControl) return false;
  const old = before.row, next = after.row;
  const samePhysical = old.revision === next.revision &&
    old.physical_close_confirmed === next.physical_close_confirmed;
  const samePublication = old.state_revision === next.state_revision &&
    old.state_observation_key === next.state_observation_key;
  return old.cancellation_requested === 0 && old.observed_terminal_outcome === null &&
    (samePhysical || physicalCloseAdvanced(old, next)) &&
    (samePublication || statePublicationAdvanced(old, next)) &&
    Object.keys(old).length === Object.keys(next).length &&
    Object.keys(old).every(key => key === 'revision' || key === 'physical_close_confirmed' ||
      key === 'state_revision' || key === 'state_observation_key' || old[key] === next[key]);
}

type JournalStatement = ReturnType<JournalSqlConnection['prepare']>;
type SubmissionRows = ReturnType<typeof createJournalSubmissionRows>;
type RunRecordStatements = Readonly<{
  select: Pick<JournalStatement, 'get'>; selectRun: Pick<JournalStatement, 'get'>;
  requestUsage: JournalStatement; submissionIssued: JournalStatement;
  cancellationUsage: JournalStatement; cancellationIssued: JournalStatement;
  intentSelect: Pick<JournalStatement, 'get'>;
  insert: Pick<JournalStatement, 'run'>; advanceSubmissionCustody: Pick<JournalStatement, 'run'>;
}>;
type ExplanationOriginal = Readonly<{factsWire: string}>;
type RunRecordOwners = Readonly<{
  ensureOpen: () => void; transact: ReturnType<typeof createJournalAttempts>['transact'];
  checkSubmissionBinding: SubmissionRows['checkSubmissionBinding']; refuseEpoch: SubmissionRows['refuseEpoch'];
  retainedIntent: SubmissionRows['retainedIntent'];
  assertJournalSubmissionCustody: typeof assertJournalSubmissionCustody;
  assertJournalCancellationCustody: typeof assertJournalCancellationCustody;
  readExplanationOriginal: (ref: WireRunRef) => ReturnType<typeof readJournalExplanationOriginal>;
  insertExplanationOriginal: (ref: WireRunRef, original: ExplanationOriginal) => void;
}>;
type RequestRelation = Readonly<{clientRequestRelation(original: unknown, retained: unknown): number}>;
type LookupControl = RequestIdentityAdmission<unknown> & Pick<RequestIdentityRead, 'clientRequestScopeCid'>;
type AcceptanceControl = RequestIdentityRead & RequestRelation & Parameters<SubmissionRows['checkSubmissionBinding']>[2];
type RequestKey = Readonly<{namespaceId: unknown; authorityScopeCid: unknown; requestId: unknown}>;
type RunLookupRow = RetainedRunRow & RequestIdentityRow & AdmissionRow & Readonly<{
  run_definition_cid: string; run_definition_wire: string | null;
}>;
type RunAdmissionInput = Readonly<{
  namespaceId: unknown; runDefinitionCid: unknown; runDefinitionWire?: unknown; resultNames?: unknown;
  runAdmissionEvidence?: unknown; revision?: number; lookupExpiresAt: unknown;
  submission?: Parameters<SubmissionRows['checkSubmissionBinding']>[1];
}>;
type AcceptedRun = ReturnType<typeof admission> & Readonly<{
  inserted: boolean; runAdmissionEvidence: AdmissionEvidence | undefined;
  runDefinitionWire?: string | null; resultNames: string[] | undefined;
  epochRejected?: never;
}>;
type AcceptanceOutcome = AcceptedRun | Readonly<{epochRejected: string}>;
type ObservedFailure = Readonly<{code?: string}> | null | undefined;

export function createJournalRunRecords({select, selectRun, requestUsage, submissionIssued, cancellationUsage,
  cancellationIssued, intentSelect, insert, advanceSubmissionCustody}: RunRecordStatements,
  {ensureOpen, transact, checkSubmissionBinding, refuseEpoch, retainedIntent,
    assertJournalSubmissionCustody, assertJournalCancellationCustody,
    readExplanationOriginal, insertExplanationOriginal}: RunRecordOwners,
  {maxRecords, maxRunDefinitionWireBytes, updateOriginalControl}: Pick<ReturnType<typeof snapshotJournalConfiguration>,
    'maxRecords' | 'maxRunDefinitionWireBytes'> & Readonly<{updateOriginalControl?: UpdateOriginalControl}>) {
  const acceptRecord = (identity: unknown, {namespaceId, runDefinitionCid,
    runDefinitionWire, resultNames, runAdmissionEvidence, revision = 0, lookupExpiresAt,
    submission}: RunAdmissionInput, control: AcceptanceControl, originalExplanation?: ExplanationOriginal) => {
    ensureOpen();
    if (!control || typeof control.clientRequestAdmitRecord !== 'function' ||
        typeof control.clientRequestRelation !== 'function') {
      fail('InvalidClientRequestJournalControl');
    }
    const fields = checkedIdentity(identity, control);
    if (!text(namespaceId) || !cid(runDefinitionCid) ||
        runDefinitionWire !== undefined &&
          (typeof runDefinitionWire !== 'string' ||
            Buffer.byteLength(runDefinitionWire, 'utf8') >
              maxRunDefinitionWireBytes) ||
        !Number.isSafeInteger(revision) || revision < 0 ||
        resultNames !== undefined && (!Array.isArray(resultNames) ||
          resultNames.some(name => typeof name !== 'string' || !name) ||
          new Set(resultNames).size !== resultNames.length ||
          Buffer.byteLength(JSON.stringify(resultNames), 'utf8') > maxRunDefinitionWireBytes) ||
        !instant(lookupExpiresAt) ||
        Date.parse(lookupExpiresAt) <= Date.now()) {
      fail('InvalidClientRequestAdmission');
    }
    const capturedAdmissionEvidence = evidenceJson(runAdmissionEvidence,
      maxRunDefinitionWireBytes, updateOriginalControl);
    const admissionEvidence = capturedAdmissionEvidence?.wire ?? null;
    const admittedEvidence = capturedAdmissionEvidence?.value;
    assertKeyedInventoryRequest(admittedEvidence?.sourceInventory, fields);
    if (admittedEvidence?.valuesHostPolicyOriginal !== undefined &&
        (typeof runDefinitionWire !== 'string' ||
         JSON.parse(runDefinitionWire).authorization_context_cid !==
           valuesExecutionContextCid(fields.authorityScopeCid,
             admittedEvidence.valuesHostPolicyOriginal))) {
      fail('InvalidClientRunAdmissionEvidence');
    }
    if (admittedEvidence?.modelOriginalRunWire !== undefined &&
        capturedAdmissionEvidence!.modelRunDefinitionWire !== runDefinitionWire) {
      fail('InvalidClientRunAdmissionEvidence');
    }
    // Retain observed expiry even if another admission fact later conflicts
    // and rolls its transaction back. The atomic check below still decides
    // whether this particular Run may be inserted.
    checkSubmissionBinding(fields, submission, control);
    const outcome = transact<AcceptanceOutcome>('accept', 'ClientRequestAcceptanceUnknown',
      error => typeof (error as ObservedFailure)?.code === 'string' &&
        ((error as NonNullable<ObservedFailure>).code!.startsWith('ClientRequest') ||
          (error as NonNullable<ObservedFailure>).code!.startsWith('ClientSubmission')), () => {
      const retainedCount = assertJournalSubmissionCustody(requestUsage, submissionIssued);
      const existing = select.get(fields.authorityScopeCid,
        fields.requestId) as RunLookupRow | undefined;
      if (existing !== undefined) {
        // An expired identity may still identify its retained outcome. This
        // path performs no new issuance; authenticate the original binding.
        checkSubmissionBinding(fields, submission, control, true);
        if (existing.namespace_id !== namespaceId) {
          fail('ClientRequestOwnerMismatch');
        }
        const relation = control.clientRequestRelation(identity,
          retainedIdentity(existing, control));
        if (relation !== 1) {
          fail(relation === 2 ? 'ClientRequestIntentConflict' :
            'ClientRequestJournalCorrupt');
        }
        if (runDefinitionWire !== undefined &&
            existing.run_definition_wire === null) {
          fail('ClientRequestDefinitionMissing');
        }
        if (resultNames !== undefined &&
            existing.result_names_json !== null &&
            existing.result_names_json !== JSON.stringify(resultNames)) {
          fail('ClientRequestResultInventoryMismatch');
        }
        const existingEvidence = retainedEvidence(existing, updateOriginalControl, capturedAdmissionEvidence);
        assertSourceInventory({physicalStartReserved: existing.physical_start_reserved === 1,
          runAdmissionEvidence: existingEvidence}, admittedEvidence?.sourceInventory);
        const proposedPlan = admittedEvidence?.logicalPlanOriginal;
        if (proposedPlan !== undefined) {
          const originalPlan = existingEvidence?.logicalPlanOriginal;
          if (originalPlan === undefined) fail('ClientRequestPlanEvidenceMissing');
          if (originalPlan.compiledPlanWire !== proposedPlan.compiledPlanWire ||
              originalPlan.planViewWire !== proposedPlan.planViewWire) {
            fail('ClientRequestPlanEvidenceMismatch');
          }
        }
        if (originalExplanation !== undefined) {
          const original = readExplanationOriginal({namespaceId,
            authorityScopeCid: fields.authorityScopeCid, runDefinitionCid: existing.run_definition_cid});
          if (original === undefined) fail('ClientRequestExplanationEvidenceMissing');
          if (original.factsWire !== originalExplanation.factsWire) fail('ClientRequestExplanationEvidenceMismatch');
        }
        const proposedInfer = admittedEvidence?.inferRunOriginal;
        if (proposedInfer !== undefined) {
          const original = existingEvidence?.inferRunOriginal;
          if (original === undefined) fail('ClientRequestInferEvidenceMissing');
          if (canonicalValueJson(original) !== canonicalValueJson(proposedInfer)) {
            fail('ClientRequestInferEvidenceMismatch');
          }
        }
        return Object.freeze({inserted: false, ...admission(existing),
          runAdmissionEvidence: existingEvidence,
          ...(runDefinitionWire === undefined ? {} :
            {runDefinitionWire: existing.run_definition_wire}),
          resultNames: retainedResultNames(existing, maxRunDefinitionWireBytes)});
      }
      const epochValidity = checkSubmissionBinding(fields, submission, control, true);
      if (epochValidity !== 'admissible') {
        // Commit the expiry watermark without admitting a Run. Throwing inside
        // this transaction would roll the watermark back and let a backwards
        // clock revive the identity after an awaited issuance.
        return {epochRejected: epochValidity};
      }
      if (retainedCount + assertJournalCancellationCustody(cancellationUsage, cancellationIssued) >= maxRecords) {
        fail('ClientRequestJournalCapacity');
      }
      if (selectRun.get(runDefinitionCid) !== undefined) {
        fail('ClientRequestRunAlreadyAssigned');
      }
      // Only this original acceptance transaction may associate submitted
      // content with a new Run. Equal caller CIDs or later configuration are
      // not a way to attach a restriction to an already issued Run.
      let originalAdmissionEvidence = admissionEvidence;
      if (submission?.intentCid !== undefined && admittedEvidence !== undefined) {
        const original = retainedIntent(intentSelect.get(fields.requestId) as Parameters<typeof retainedIntent>[0],
          control, submission.epoch);
        if (admittedEvidence.submittedIntentCid !== undefined &&
            admittedEvidence.submittedIntentCid !== original.intentCid) {
          fail('ClientRequestSubmittedIntentMismatch');
        }
        if (!cid(original.intentCid)) fail('InvalidClientRunAdmissionEvidence');
        originalAdmissionEvidence = JSON.stringify({...admittedEvidence,
          submittedIntentCid: original.intentCid});
        if (Buffer.byteLength(originalAdmissionEvidence) > maxRunDefinitionWireBytes) {
          fail('InvalidClientRunAdmissionEvidence');
        }
      } else if (admittedEvidence?.submittedIntentCid !== undefined) {
        fail('ClientRequestSubmittedIntentMismatch');
      }
      insert.run(fields.authorityScopeCid, fields.requestId,
        fields.logicalRequestScopeCid, fields.intentFingerprintCid,
        fields.programDefinitionCid, fields.parameterValuesCid,
        fields.callerInputIntentCid, namespaceId, runDefinitionCid,
        runDefinitionWire ?? null, revision, lookupExpiresAt,
        resultNames === undefined ? null : JSON.stringify(resultNames),
        originalAdmissionEvidence);
      if (originalExplanation !== undefined) insertExplanationOriginal({namespaceId,
        authorityScopeCid: fields.authorityScopeCid, runDefinitionCid}, originalExplanation);
      if (Number(advanceSubmissionCustody.run(retainedCount).changes) !== 1) {
        fail('ClientRequestSubmissionCustodyLost');
      }
      return Object.freeze({inserted: true, ref: Object.freeze({
        namespaceId, authorityScopeCid: fields.authorityScopeCid,
        runDefinitionCid,
      }), durability: 'durable', revision, lookupExpiresAt,
      ...(runDefinitionWire === undefined ? {} : {runDefinitionWire}),
      resultNames, runAdmissionEvidence: originalAdmissionEvidence === null ? undefined :
        freezeAdmissionEvidence(JSON.parse(originalAdmissionEvidence))});
    });
    if (outcome.epochRejected !== undefined) refuseEpoch(outcome.epochRejected);
    // The original refusal owner throws for every non-admissible epoch.
    return outcome as AcceptedRun;
  };

  const lookupRecord = ({namespaceId, authorityScopeCid, requestId}: RequestKey,
    control: LookupControl, original?: Readonly<{identity: unknown; fields: RequestFields}>) => {
    ensureOpen();
    if (!text(namespaceId) || !cid(authorityScopeCid) || !text(requestId) ||
        !control || typeof control.clientRequestAdmitRecord !== 'function') {
      fail('InvalidClientRequestLookup');
    }
    let row: RunLookupRow | undefined;
    try { row = select.get(authorityScopeCid, requestId) as RunLookupRow | undefined; }
    catch (error) { fail('ClientRequestLookupUnknown', error); }
    if (row === undefined || row.namespace_id !== namespaceId) return undefined;
    const identity = original !== undefined &&
        row.authority_scope_cid === original.fields.authorityScopeCid &&
        row.caller_request_id === original.fields.requestId &&
        row.logical_request_scope_cid === original.fields.logicalRequestScopeCid &&
        row.intent_fingerprint_cid === original.fields.intentFingerprintCid &&
        row.program_definition_cid === original.fields.programDefinitionCid &&
        row.parameter_values_cid === original.fields.parameterValuesCid &&
        row.caller_input_intent_cid === original.fields.callerInputIntentCid
      ? original.identity : retainedIdentity(row, control);
    if (control.clientRequestScopeCid(identity) !==
        row.logical_request_scope_cid) {
      fail('ClientRequestJournalCorrupt');
    }
    return Object.freeze({row, identity, found: Object.freeze({
      requestId: row.caller_request_id,
      ...admission(row),
    })});
  };

  const resolveOriginalDefinition = (identity: unknown, fields: RequestFields, namespaceId: string,
    requestControl: LookupControl & RequestRelation, publicationControl: DefinitionControl) => {
    if (typeof requestControl.clientRequestRelation !== 'function') {
      fail('InvalidClientRequestLookup');
    }
    const retained = lookupRecord({namespaceId,
      authorityScopeCid: fields.authorityScopeCid,
      requestId: fields.requestId}, requestControl, {identity, fields});
    if (retained === undefined) return undefined;
    // Exact saved identity fields reuse this entry's already admitted request.
    // A distinct saved identity still follows lookupRecord's full admission.
    const relation = requestControl.clientRequestRelation(identity, retained.identity);
    if (relation !== 1) {
      fail(relation === 2 ? 'ClientRequestIntentConflict' :
        'ClientRequestJournalCorrupt');
    }
    return Object.freeze({...retained.found,
      ...retainedRunFacts(retained.row, publicationControl,
        maxRunDefinitionWireBytes, updateOriginalControl),
    });
  };

  return {acceptRecord, lookupRecord, resolveOriginalDefinition};
}

type KeyedRunDefinition = Pick<RunDefinition, 'identity' | 'wire'>;
type KeyedLookupSelection = Readonly<{
  identity: unknown; preparedEffect: unknown; compilation: unknown; compiled: unknown;
  runDefinition: KeyedRunDefinition; graph: unknown; limits: unknown; sourceOriginal?: unknown;
}>;
type KeyedLookupCoordinates = Readonly<{wire: string; batchCid: string; slotCid: string; batchIndex: number}>;
type KeyedActivationRecord = KeyedLookupCoordinates & Readonly<{batchCount: number}>;
type KeyedPageRecord = KeyedLookupCoordinates & Readonly<{activationCid: string}>;
type KeyedActivationSelection = KeyedLookupSelection & Readonly<{activation: unknown}>;
type KeyedPageSelection = KeyedLookupSelection & Readonly<{
  page: unknown; keyedRequest: unknown; activationRecord: KeyedActivationRecord;
}>;
type KeyedRequestControl = RequestIdentityAdmission<unknown> & RequestRelation;
type KeyedLookupBinding = [identity: unknown, compiled: unknown, runDefinition: KeyedRunDefinition, graph: unknown];
type KeyedLookupChecks = Readonly<{
  checkClientCompiledEffectRunOwner(compiled: unknown, preparedEffect: unknown, compilation: unknown): SynchronousRuntimeData;
  checkClientCompiledRunDefinition(compiled: unknown, definition: KeyedRunDefinition): SynchronousRuntimeData;
}>;
type KeyedActivationControl = KeyedLookupChecks & Readonly<{
  keyedLookupActivationJournalRecord(activation: unknown,
    ...binding: [...KeyedLookupBinding, limits: unknown, sourceOriginal: unknown]): KeyedActivationRecord | undefined;
  keyedLookupActivationJournalCurrent(activation: unknown,
    ...binding: [...KeyedLookupBinding, sourceOriginal: unknown]): unknown;
}>;
type KeyedPageControl = KeyedLookupChecks & Readonly<{
  keyedLookupPageJournalRecord(page: unknown, keyedRequest: unknown,
    ...binding: [...KeyedLookupBinding, limits: unknown, sourceOriginal: unknown]): KeyedPageRecord | undefined;
  keyedLookupPageJournalCurrent(page: unknown, keyedRequest: unknown,
    ...binding: [...KeyedLookupBinding, sourceOriginal: unknown]): unknown;
}>;

export function createJournalKeyedLookupStorage(database: Pick<JournalSqlConnection, 'prepare'>,
  selectRef: Pick<JournalStatement, 'get'>, ensureOpen: () => void, transact: ReturnType<typeof createJournalAttempts>['transact']) {
  // Prepare each keyed statement only when this Journal first needs it.
  // Retain that same original for its connection lifetime, not per key.
  let keyedLookupPrior: JournalStatement | undefined, keyedLookupBatch: JournalStatement | undefined;
  let keyedLookupInsert: JournalStatement | undefined, keyedLookupAdopt: JournalStatement | undefined;
  return {
    // Persist the original checked activation BEFORE its first physical
    // attempt. An existing/uncertain entry never authorizes another send.
    persistOriginalKeyedLookupActivation(ref: WireRunRef, {activation, identity, preparedEffect,
      compilation, compiled, runDefinition, graph, limits, sourceOriginal}: KeyedActivationSelection,
      requestControl: KeyedRequestControl, publicationControl: KeyedActivationControl) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) || !cid(ref?.runDefinitionCid) ||
          runDefinition?.identity !== ref.runDefinitionCid ||
          typeof publicationControl?.keyedLookupActivationJournalRecord !== 'function' ||
          typeof publicationControl?.keyedLookupActivationJournalCurrent !== 'function') {
        fail('ForeignClientKeyedLookupOriginal');
      }
      publicationControl.checkClientCompiledEffectRunOwner(compiled, preparedEffect, compilation);
      publicationControl.checkClientCompiledRunDefinition(compiled, runDefinition);
      const record = publicationControl.keyedLookupActivationJournalRecord(
        activation, identity, compiled, runDefinition, graph, limits, sourceOriginal);
      if (!cid(record?.batchCid) || !cid(record?.slotCid) ||
          !Number.isSafeInteger(record?.batchIndex) || record.batchIndex < 0 ||
          !Number.isSafeInteger(record?.batchCount) || record.batchCount < 1 ||
          record.batchIndex >= record.batchCount || typeof record.wire !== 'string') {
        fail('ForeignClientKeyedLookupOriginal');
      }
      const current = () => {
        ensureOpen();
        if (publicationControl.keyedLookupActivationJournalCurrent(
          activation, identity, compiled, runDefinition, graph, sourceOriginal) !== true) {
          fail('ForeignClientKeyedLookupOriginal');
        }
      };
      current();
      transact('keyed_lookup_activation', 'ClientKeyedLookupActivationUnknown',
        error => (['ForeignClientKeyedLookupOriginal', 'ClientRunPhysicalStartDenied',
          'ClientKeyedLookupActivationUnresolved', 'ClientRequestJournalCorrupt'] as readonly (string | undefined)[])
          .includes((error as ObservedFailure)?.code), () => {
          const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid) as RunLookupRow | undefined;
          if (row === undefined || requestControl.clientRequestRelation(identity,
                retainedIdentity(row, requestControl)) !== 1 ||
              row.run_definition_wire !== runDefinition.wire ||
              row.dispatch_reserved !== 1 || row.physical_start_reserved !== 1 ||
              row.pre_dispatch_failure_confirmed !== 0 || row.cancellation_requested !== 0) {
            fail('ClientRunPhysicalStartDenied');
          }
          current();
          const prior = (keyedLookupPrior ??= database.prepare(`SELECT 1 AS present FROM client_keyed_lookup_originals
    WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ? AND call_slot_cid = ?`)).get(ref.namespaceId, ref.authorityScopeCid,
            ref.runDefinitionCid, record.slotCid);
          if (prior !== undefined) fail('ClientKeyedLookupActivationUnresolved');
          const batch = (keyedLookupBatch ??= database.prepare(`SELECT COUNT(*) AS n,
    COUNT(CASE WHEN page_wire IS NULL THEN 1 END) AS pending FROM client_keyed_lookup_originals
    WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ? AND batch_plan_cid = ?`)).get(ref.namespaceId, ref.authorityScopeCid,
            ref.runDefinitionCid, record.batchCid)!;
          if (!Number.isSafeInteger(batch.n) || batch.n !== record.batchIndex) {
            fail('ClientRequestJournalCorrupt');
          }
          if (batch.pending !== 0) fail('ClientKeyedLookupActivationUnresolved');
          (keyedLookupInsert ??= database.prepare(`INSERT INTO client_keyed_lookup_originals
    (namespace_id, authority_scope_cid, run_definition_cid, batch_plan_cid,
      call_slot_cid, batch_index, batch_count, activation_wire, page_wire)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)`)).run(ref.namespaceId, ref.authorityScopeCid,
            ref.runDefinitionCid, record.batchCid, record.slotCid,
            record.batchIndex, record.batchCount, record.wire);
          current();
        });
      // A failed post-COMMIT current check still leaves the original durable
      // entry. It cannot turn into permission to retry the physical attempt.
      current();
      return record;
    },
    // A completed captured page replaces only the SAME unresolved activation.
    // Exact original wires and the checked nominal page are both required;
    // neither row absence nor a lost commit permits another physical read.
    persistOriginalKeyedLookupPage(ref: WireRunRef, {page, keyedRequest, identity, preparedEffect,
      compilation, compiled, runDefinition, graph, limits, activationRecord, sourceOriginal}: KeyedPageSelection,
      requestControl: KeyedRequestControl, publicationControl: KeyedPageControl) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) || !cid(ref?.runDefinitionCid) ||
          runDefinition?.identity !== ref.runDefinitionCid ||
          typeof activationRecord?.wire !== 'string' ||
          typeof publicationControl?.keyedLookupPageJournalRecord !== 'function' ||
          typeof publicationControl?.keyedLookupPageJournalCurrent !== 'function') {
        fail('ForeignClientKeyedLookupPage');
      }
      publicationControl.checkClientCompiledEffectRunOwner(compiled, preparedEffect, compilation);
      publicationControl.checkClientCompiledRunDefinition(compiled, runDefinition);
      const record = publicationControl.keyedLookupPageJournalRecord(page, keyedRequest,
        identity, compiled, runDefinition, graph, limits, sourceOriginal);
      if (!cid(record?.batchCid) || !cid(record?.slotCid) || !cid(record?.activationCid) ||
          typeof record.wire !== 'string' || record.batchCid !== activationRecord.batchCid ||
          record.slotCid !== activationRecord.slotCid || record.batchIndex !== activationRecord.batchIndex ||
          !Number.isSafeInteger(activationRecord.batchCount) || activationRecord.batchCount <= record.batchIndex ||
          !Number.isSafeInteger(record.batchIndex) || record.batchIndex < 0) {
        fail('ForeignClientKeyedLookupPage');
      }
      const current = () => {
        ensureOpen();
        if (publicationControl.keyedLookupPageJournalCurrent(page, keyedRequest, identity,
            compiled, runDefinition, graph, sourceOriginal) !== true) fail('ForeignClientKeyedLookupPage');
      };
      current();
      transact('keyed_lookup_page', 'ClientKeyedLookupPageUnknown',
        error => (['ForeignClientKeyedLookupPage', 'ClientRunPhysicalStartDenied',
          'ClientKeyedLookupPageUnresolved'] as readonly (string | undefined)[])
          .includes((error as ObservedFailure)?.code), () => {
          const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid) as RunLookupRow | undefined;
          if (row === undefined || requestControl.clientRequestRelation(identity,
                retainedIdentity(row, requestControl)) !== 1 ||
              row.run_definition_wire !== runDefinition.wire || row.dispatch_reserved !== 1 ||
              row.physical_start_reserved !== 1 || row.pre_dispatch_failure_confirmed !== 0 ||
              row.cancellation_requested !== 0) fail('ClientRunPhysicalStartDenied');
          current();
          if ((keyedLookupAdopt ??= database.prepare(`UPDATE client_keyed_lookup_originals
    SET page_wire = ? WHERE namespace_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ? AND batch_plan_cid = ? AND call_slot_cid = ? AND
      batch_index = ? AND batch_count = ? AND activation_wire = ? AND page_wire IS NULL`)).run(record.wire, ref.namespaceId, ref.authorityScopeCid,
            ref.runDefinitionCid, record.batchCid, record.slotCid, record.batchIndex,
            activationRecord.batchCount, activationRecord.wire).changes !== 1) {
            fail('ClientKeyedLookupPageUnresolved');
          }
          current();
        });
      current();
      return record;
    },
  };
}

type SourceOperationStorage = NonNullable<ReturnType<typeof clientSourceOperationStorage>>;
type SourceRunOriginal = Parameters<SourceOperationStorage['issue']>[0];
type RunStartOptions = Readonly<{namespaceId: unknown; currentAuthorization: unknown}>;
type DispatchStartControl = RequestIdentityRead & Readonly<{
  clientRunStartAction(original: unknown, retained: unknown, definition: RunDefinition, runDefinitionCid: string,
    dispatchReserved: boolean, currentAuthorization: boolean): unknown;
}>;
type CompiledProgram = Readonly<{program: unknown; compiled: unknown}>;
type SourceCapture = CompiledProgram & Readonly<{
  store: SourceRunOriginal['store'] & {privateEvidenceWireLimit?: SourceRunOriginal['checkStore']};
  capture(scope: ReturnType<SourceOperationStorage['issue']>): SynchronousRuntimeData;
}>;
type PhysicalStartOptions = RunStartOptions & Readonly<{
  ref: WireRunRef; captureSourceOperation?: SourceCapture; localExecutionOwner?: CompiledProgram;
}>;
type PhysicalStartControl = RequestIdentityRead & Partial<SourceRunOriginal['requestControl']> & Readonly<{
  clientRunPhysicalStartWithCancellationAction(original: unknown, retained: unknown, definition: RunDefinition,
    runDefinitionCid: string, dispatchReserved: boolean, fresh: boolean, currentAuthorization: boolean,
    cancelled: boolean): unknown;
  clientProgramComposedInferOccurrences?(program: unknown): unknown;
  clientProgramSerializationOccurrences?(program: unknown): unknown;
  clientProgramAcquisitionCount?(program: unknown): unknown;
}>;
type PhysicalStartPublication = DefinitionControl & Partial<SourceRunOriginal['publicationControl']> & Readonly<{
  checkClientCompiledLocalExecutionOwner?(compiled: unknown, definition: RunDefinition): SynchronousRuntimeData;
}>;
type LocalExecutionReceipt = Readonly<{token: string; anchor: Readonly<{identity: string; device: string; inode: string}>}>;
type RunStartStatements = Readonly<{
  select: Pick<JournalStatement, 'get'>; selectRef: Pick<JournalStatement, 'get'>;
  reserve: Pick<JournalStatement, 'run'>; reservePhysicalStart: Pick<JournalStatement, 'run'>;
  localExecutionOwnerInsert?: Pick<JournalStatement, 'run'>;
}>;
type RunStartOwners = Readonly<{
  ensureOpen: () => void; transact: ReturnType<typeof createJournalAttempts>['transact'];
  getDeliveredJournal: () => object; sourceOperations?: SourceOperationStorage;
  ownedOriginal?: object;
  captureOriginalLocalExecutionOwner: (original: object) => LocalExecutionReceipt | undefined;
  validLocalExecutionOwnerReceipt: typeof validLocalExecutionOwnerReceipt;
}>;

export function createJournalRunStart({select, selectRef, reserve, reservePhysicalStart, localExecutionOwnerInsert}: RunStartStatements,
  {ensureOpen, transact, getDeliveredJournal, sourceOperations, ownedOriginal,
    captureOriginalLocalExecutionOwner, validLocalExecutionOwnerReceipt}: RunStartOwners, maxRunDefinitionWireBytes: number) {
  return {
    // One physical transaction applies the common MoonBit start decision.
    // A committed reservation records possible dispatch before any work. A
    // later caller must reconcile that Run rather than run Compute again.
    reserveDispatch(identity: unknown, {namespaceId, currentAuthorization}: RunStartOptions,
      requestControl: DispatchStartControl, publicationControl: DefinitionControl) {
      ensureOpen();
      if (!text(namespaceId) || typeof currentAuthorization !== 'boolean' ||
          typeof requestControl?.clientRunStartAction !== 'function') {
        fail('InvalidClientRunStart');
      }
      const fields = checkedIdentity(identity, requestControl);
      return transact('start', 'ClientRunStartUnknown',
        error => typeof (error as ObservedFailure)?.code === 'string' &&
          ((error as NonNullable<ObservedFailure>).code!.startsWith('ClientRequest') ||
            (error as NonNullable<ObservedFailure>).code!.startsWith('ClientRun')), () => {
        const row = select.get(fields.authorityScopeCid, fields.requestId) as RunLookupRow | undefined;
        if (row === undefined || row.namespace_id !== namespaceId) {
          fail('ClientRunStartDenied');
        }
        const retained = retainedIdentity(row, requestControl);
        const definition = retainedRunDefinition(row, publicationControl,
          maxRunDefinitionWireBytes);
        const action = requestControl.clientRunStartAction(identity, retained,
          definition, row.run_definition_cid, row.dispatch_reserved === 1,
          currentAuthorization);
        if (action === 0) {
          if (reserve.run(fields.authorityScopeCid, fields.requestId)
            .changes !== 1) {
            fail('ClientRequestJournalCorrupt');
          }
          return Object.freeze({kind: 'reserved',
            ...admission({...row, revision: Number(row.revision) + 1})});
        }
        if (action === 1) {
          return Object.freeze({kind: 'reconcile', ...admission(row)});
        }
        fail(action === 3 ? 'ClientRequestIntentConflict' :
          action === 5 ? 'ClientRunStartDenied' :
          'ClientRequestJournalCorrupt');
      });
    },
    // The exact durable claim precedes the call that can start physical
    // Compute. A missing claim is safe to resume; a claim or legacy unknown
    // is never evidence that Compute did not run.
    reservePhysicalStart(identity: unknown, {namespaceId, ref, currentAuthorization,
      captureSourceOperation, localExecutionOwner}: PhysicalStartOptions,
      requestControl: PhysicalStartControl, publicationControl: PhysicalStartPublication) {
      ensureOpen();
      if (!text(namespaceId) || !text(ref?.namespaceId) ||
          !cid(ref?.authorityScopeCid) || !cid(ref?.runDefinitionCid) ||
          typeof currentAuthorization !== 'boolean' ||
          typeof requestControl?.clientRunPhysicalStartWithCancellationAction !==
            'function') {
        fail('InvalidClientRunPhysicalStart');
      }
      const fields = checkedIdentity(identity, requestControl);
      let sourceOriginal: SourceRunOriginal | undefined;
      let captureOriginal: SourceCapture['capture'] | undefined, captureReceiver: SourceCapture | undefined;
      if (captureSourceOperation !== undefined) {
        if (sourceOperations === undefined) fail('ClientSourceOperationUnavailable');
        const {program, compiled, capture, store} = captureSourceOperation;
        const checkStore = store?.privateEvidenceWireLimit;
        if (typeof capture !== 'function' ||
            typeof checkStore !== 'function' ||
            typeof requestControl.clientProgramMatchesRequestIdentity !== 'function' ||
            requestControl.clientProgramMatchesRequestIdentity!(program, identity) !== true) {
          fail('ForeignClientSourceOperation');
        }
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid) as RunDefinitionRow | undefined;
        if (row === undefined) fail('ForeignClientSourceOperation');
        const definition = retainedRunDefinition(row, publicationControl, maxRunDefinitionWireBytes);
        publicationControl.checkClientCompiledRunOwner!(compiled, program);
        publicationControl.checkClientCompiledRunDefinition!(compiled, definition);
        // Existing same-Store active guard only; its numeric result is neither
        // the Source operation's capacity nor a private-evidence permission.
        Reflect.apply(checkStore, store, []);
        sourceOriginal = Object.freeze({ref: Object.freeze({...ref}), program, compiled,
          definition, identity, requestControl: requestControl as SourceRunOriginal['requestControl'],
          publicationControl: publicationControl as SourceRunOriginal['publicationControl'],
          // The same Owner may deliver its bounded method facade. Retain
          // that exact original, which dispatch receives, not the inaccessible
          // inner method table. Copies still fail the nominal Source check.
          journal: getDeliveredJournal(), store, checkStore,
          requestId: fields.requestId, requestScopeCid: fields.logicalRequestScopeCid,
          intentCid: fields.intentFingerprintCid});
        captureOriginal = capture;
        captureReceiver = captureSourceOperation;
      }
      // Only the actual compiled effect-free Prepared original can qualify;
      // source text, a caller boolean or an empty local worker map cannot.
      let localOwnerProgram: unknown, localOwnerCompiled: unknown;
      if (localExecutionOwner !== undefined && ownedOriginal !== undefined) {
        const {program, compiled} = localExecutionOwner;
        try {
          if (requestControl.clientProgramMatchesRequestIdentity!(program, identity) !== true) {
            fail('ForeignClientLocalExecutionOwner');
          }
          publicationControl.checkClientCompiledRunOwner!(compiled, program);
          const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid) as RunDefinitionRow | undefined;
          if (row === undefined) fail('ForeignClientLocalExecutionOwner');
          const definition = retainedRunDefinition(row, publicationControl, maxRunDefinitionWireBytes);
          publicationControl.checkClientCompiledRunDefinition!(compiled, definition);
          publicationControl.checkClientCompiledLocalExecutionOwner!(compiled, definition);
          const inferred = checked(requestControl.clientProgramComposedInferOccurrences!(program));
          const serialized = requestControl.clientProgramSerializationOccurrences!(program);
          if (requestControl.clientProgramAcquisitionCount!(program) !== 0 ||
              !Array.isArray(inferred) || inferred.length !== 0 ||
              !Array.isArray(serialized) || serialized.length !== 0) {
            fail('ForeignClientLocalExecutionOwner');
          }
          localOwnerProgram = program; localOwnerCompiled = compiled;
        } catch (cause) {fail('ForeignClientLocalExecutionOwner', cause);}
      }
      const started = transact('physical_start', 'ClientRunPhysicalStartUnknown',
        error => typeof (error as ObservedFailure)?.code === 'string' &&
          ((error as NonNullable<ObservedFailure>).code!.startsWith('ClientRun') ||
            (error as NonNullable<ObservedFailure>).code!.startsWith('ClientRequest')), () => {
        const row = select.get(fields.authorityScopeCid, fields.requestId) as RunLookupRow | undefined;
        if (row === undefined || row.namespace_id !== namespaceId ||
            ref.namespaceId !== namespaceId ||
            ref.authorityScopeCid !== fields.authorityScopeCid ||
            ref.runDefinitionCid !== row.run_definition_cid) {
          fail('ClientRunPhysicalStartDenied');
        }
        const retained = retainedIdentity(row, requestControl);
        const definition = retainedRunDefinition(row, publicationControl,
          maxRunDefinitionWireBytes);
        const action = requestControl.clientRunPhysicalStartWithCancellationAction(
          identity, retained, definition, row.run_definition_cid,
          row.dispatch_reserved === 1,
          row.pre_dispatch_failure_confirmed === 0 &&
            row.physical_start_reserved === 0,
          currentAuthorization, row.cancellation_requested === 1);
        if (action === 0) {
          return false;
        }
        if (action !== 1) {
          fail(action === 3 ? 'ClientRequestIntentConflict' :
            action === 5 ? 'ClientRunPhysicalStartDenied' :
            'ClientRequestJournalCorrupt');
        }
        if (localOwnerProgram !== undefined) {
          publicationControl.checkClientCompiledRunOwner!(localOwnerCompiled, localOwnerProgram);
          publicationControl.checkClientCompiledRunDefinition!(localOwnerCompiled, definition);
          publicationControl.checkClientCompiledLocalExecutionOwner!(localOwnerCompiled, definition);
          const receipt = captureOriginalLocalExecutionOwner(ownedOriginal!);
          // Unsupported native ownership proof preserves ordinary execution;
          // its absent receipt cannot later be promoted into a stop witness.
          if (receipt !== undefined) {
            if (!validLocalExecutionOwnerReceipt(receipt)) fail('ForeignClientLocalExecutionOwner');
            localExecutionOwnerInsert!.run(ref.namespaceId, ref.authorityScopeCid,
              ref.runDefinitionCid, receipt.token, receipt.anchor.identity,
              receipt.anchor.device, receipt.anchor.inode);
          }
        }
        if (reservePhysicalStart.run(ref.namespaceId,
          ref.authorityScopeCid, ref.runDefinitionCid).changes !== 1) {
          fail('ClientRequestJournalCorrupt');
        }
        return true;
      });
      // No lookup/recovery API exposes this issuer. In particular a lost COMMIT
      // response throws before a scope can reach physical Source dispatch.
      if (started && sourceOriginal !== undefined) {
        Reflect.apply(captureOriginal!, captureReceiver, [sourceOperations!.issue(sourceOriginal)]);
      }
      return started;
    },
  };
}

type AdmittedRunFrame = ReturnType<typeof admitJournalRunDefinitionRow>;
type RunStateRequestControl = RequestIdentityRead &
  Parameters<typeof prepareInstalledRunStateObservation>[0] & Parameters<typeof issueInstalledRunControlObservation>[0];
type RunStatePublicationControl = DefinitionControl & Readonly<{
  runDefinitionRunId(definition: RunDefinition): string;
  executionFailureExplanation?: Parameters<typeof retainedBudgetFailureMessage>[4];
}>;
type StatePublicationRow = JournalRow & Readonly<{
  namespace_id: string; authority_scope_cid: string; run_definition_cid: string;
  state_revision: number; state_observation_key: string | null;
}>;
type ReconciliationState = Readonly<{status?: unknown; next_action?: Readonly<{kind?: unknown}> | null}>;
type RunObservationStatements = Readonly<{
  selectRef: Pick<JournalStatement, 'get'>;
  selectedRequestStatement(statement: JournalStatement, selection: 'run-definition', completeRef: true): Pick<JournalStatement, 'get'>;
  confirmPreDispatchFailure: Pick<JournalStatement, 'run'>;
  localExecutionOwnerLookup?: Pick<JournalStatement, 'get'>;
}>;
type RunObservationOwners = Readonly<{
  ensureOpen: () => void;
  transact: ReturnType<typeof createJournalAttempts>['transact'];
  runStateFrames: JournalRunFrames;
  retainRunStateFrame(frame: object, ref: WireRunRef): ReturnType<typeof retainJournalRunStateFrame>;
  readRunDefinitionRow(ref: WireRunRef, requestControl: RequestIdentityAdmission<unknown>): ReturnType<typeof readJournalRunDefinitionRow>;
  admitRunDefinitionRow(row: JournalRow, requestControl: RequestIdentityRead, publicationControl: DefinitionControl): AdmittedRunFrame;
  ownedOriginal?: object;
  validLocalExecutionOwnerReceipt: typeof validLocalExecutionOwnerReceipt;
  originalLocalExecutionOwnerStopped(original: object, receipt: LocalExecutionReceipt): unknown;
}>;

export function createJournalRunObservations(database: Pick<JournalSqlConnection, 'prepare'>,
  {selectRef, selectedRequestStatement, localExecutionOwnerLookup, confirmPreDispatchFailure}: RunObservationStatements,
  {ensureOpen, transact, runStateFrames, retainRunStateFrame, readRunDefinitionRow, admitRunDefinitionRow,
    ownedOriginal, validLocalExecutionOwnerReceipt, originalLocalExecutionOwnerStopped}: RunObservationOwners,
  maxRunDefinitionWireBytes: number) {
  return {
    // Advance only published logical/control/availability facts. The same
    // original accepted row, complete observation fence and confirmed COMMIT
    // own this counter. Neither reading nor wall-clock time increments it.
    publishRunState(frame: AdmittedRunFrame, state: Parameters<typeof retainedBudgetFailureMessage>[1],
      requestControl: RunStateRequestControl, publicationControl: RunStatePublicationControl) {
      ensureOpen();
      const retained = runStateFrames.get(frame);
      if (retained === undefined || retained.requestControl !== requestControl ||
          retained.publicationControl !== publicationControl) fail('ForeignRunStateObservation');
      const expected = retained.row;
      if (!Number.isSafeInteger(expected.state_revision) || (expected.state_revision as number) < 0 ||
          expected.state_observation_key !== null &&
            (typeof expected.state_observation_key !== 'string' || expected.state_observation_key.length === 0)) {
        fail('ClientRequestJournalCorrupt');
      }
      // The frame already admitted this complete original row. Reuse its
      // typed Run/control facts, not a decode/encode/hash of identical bytes.
      const control = issueInstalledRunControlObservation(requestControl, {
          revision: frame.revision,
          cancellationRequested: frame.cancellationRequested,
          physicallyUnstarted: frame.physicalStartReserved === false,
          preDispatchFailureConfirmed: frame.preDispatchFailureConfirmed,
          physicalCloseConfirmed: frame.physicalCloseConfirmed,
        });
      const runId = publicationControl.runDefinitionRunId(frame.runDefinition);
      const originalMessage = retainedBudgetFailureMessage(expected.state_observation_key,
        state, runId, control as Parameters<typeof retainedBudgetFailureMessage>[3], publicationControl.executionFailureExplanation);
      const projection = prepareInstalledRunStateObservation(requestControl, {
        state: {...state, ...(originalMessage === undefined ? {} : {
          terminal_error: {...state.terminal_error, message: originalMessage},
        }), control}, runId,
        revision: expected.state_revision as number, priorKey: expected.state_observation_key,
      });
      const currentRow = () => {
        const row = readRunDefinitionRow(frame.ref, requestControl);
        if (row === undefined || Object.keys(row).length !== Object.keys(expected).length ||
            Object.keys(expected).some(key => row[key] !== expected[key])) {
          fail('RunStateObservationChanged');
        }
        return row as StatePublicationRow;
      };
      // This read follows projection/callback work and is the unchanged
      // observation's linearization point. No mutation means no write TX or
      // COMMIT. Changed observations still use the original atomic CAS below.
      const observed = currentRow();
      if (projection.key === observed.state_observation_key) return projection.wire;
      return transact('run_state_observation', 'ClientRunStateObservationUnknown',
        error => (['RunStateObservationChanged', 'ClientRequestJournalCorrupt',
          'ForeignRunStateObservation', 'MoonBitHostFailure'] as readonly (string | undefined)[])
          .includes((error as ObservedFailure)?.code), () => {
          const row = currentRow();
          if (projection.key !== row.state_observation_key) {
            const result = database.prepare(`UPDATE client_requests SET
              state_revision = ?, state_observation_key = ?
              WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?
                AND state_revision = ? AND state_observation_key IS ?`).run(
              projection.revision, projection.key, row.namespace_id, row.authority_scope_cid,
              row.run_definition_cid, row.state_revision, row.state_observation_key);
            if (Number(result.changes) !== 1) fail('RunStateObservationChanged');
          }
          // transaction.run exposes this value only after confirmed COMMIT.
          return projection.wire;
        });
    },
    // One observation frame for an already selected Run, not an authority
    // cache. Every call reads committed storage and checks connection health.
    // Reuse admission only for an exactly unchanged complete row, including
    // cancellation and payload bytes; revision alone is not sufficient.
    observeRunCancellation(ref: WireRunRef, requestControl: RequestIdentityRead,
      publicationControl: DefinitionControl, originalFrame?: AdmittedRunFrame) {
      const selected = Object.freeze({namespaceId: ref?.namespaceId,
        authorityScopeCid: ref?.authorityScopeCid, runDefinitionCid: ref?.runDefinitionCid});
      let previousRow: JournalRow | undefined;
      let previousFacts: Pick<AdmittedRunFrame, 'revision' | 'cancellationRequested'> | undefined;
      if (originalFrame !== undefined) {
        ensureOpen();
        const retained = retainRunStateFrame(originalFrame,selected);
        if (retained.requestControl !== requestControl ||
            retained.publicationControl !== publicationControl) {
          fail('ForeignRunStateObservation');
        }
        // The same observation already admitted this complete original row.
        // The first probe still reads and compares every current scalar field.
        previousRow = retained.row;
        previousFacts = Object.freeze({revision: originalFrame.revision,
          cancellationRequested: originalFrame.cancellationRequested});
      }
      return () => {
        try {
          const row = readRunDefinitionRow(selected, requestControl);
          if (row === undefined) {
            previousRow = previousFacts = undefined;
            return undefined;
          }
          if (previousRow !== undefined && sameRunStateRow(row,previousRow)) {
            return previousFacts;
          }
          const facts = admitRunDefinitionRow(row, requestControl, publicationControl);
          previousRow = row;
          // Do not expose cached mutable nested evidence or a Definition as
          // permission. The caller receives only the current cancellation fact.
          previousFacts = Object.freeze({revision: facts.revision,
            cancellationRequested: facts.cancellationRequested});
          return previousFacts;
        } catch (error) {
          previousRow = previousFacts = undefined;
          throw error;
        }
      };
    },
    // This observation is only available to the SAME original Store owner
    // holding its stable lease. It never starts work, marks a stop or claims
    // cleanup. The caller must still inspect publication and revalidate this
    // nominal frame before recording the existing terminal observation.
    observeStoppedLocalExecutionOwner(ref: WireRunRef, originalFrame: object) {
      ensureOpen();
      const original = retainRunStateFrame(originalFrame, ref);
      if (localExecutionOwnerLookup === undefined) return false;
      const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
      if (!sameRunStateRow(row, original.row)) fail('ClientRunStopObservationChanged');
      if (row!.physical_start_reserved !== 1 || row!.physical_close_confirmed !== 0 ||
          row!.observed_terminal_outcome !== null) return false;
      const stored = localExecutionOwnerLookup.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
      if (stored === undefined) return false;
      const receipt = {token: stored.owner_token, anchor: {identity: stored.anchor_identity,
        device: stored.anchor_device, inode: stored.anchor_inode}};
      if (!validLocalExecutionOwnerReceipt(receipt)) return false;
      const stopped = originalLocalExecutionOwnerStopped(ownedOriginal!, receipt as LocalExecutionReceipt);
      // The native owner observation must not make a stale frame current.
      if (!sameRunStateRow(selectRef.get(ref.namespaceId, ref.authorityScopeCid,
        ref.runDefinitionCid), original.row)) fail('ClientRunStopObservationChanged');
      return stopped === true;
    },
    // Only original execution custody may report a completed physical close.
    // A successor needs the retained native lease, publication and cleanup
    // observations; an empty worker map never establishes any of them.
    markPhysicalClose(ref: WireRunRef, terminalOutcome: string | null = null, originalFrame?: object) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) ||
          terminalOutcome !== null &&
            !['failed', 'cancelled'].includes(terminalOutcome)) {
        fail('InvalidClientRunStopObservation');
      }
      const original = originalFrame === undefined ? undefined : retainRunStateFrame(originalFrame, ref);
      return transact('stop_observation', 'ClientRunStopObservationUnknown',
        error => (['ClientRunStopObservationDenied', 'ClientRunStopObservationChanged'] as readonly (string | undefined)[])
          .includes((error as ObservedFailure)?.code), () => {
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (original !== undefined && !sameRunStateRow(row, original.row)) {
          fail('ClientRunStopObservationChanged');
        }
        if (row === undefined || row.physical_start_reserved !== 1 ||
            row.physical_close_confirmed === 1 &&
              row.observed_terminal_outcome !== terminalOutcome) {
          fail('ClientRunStopObservationDenied');
        }
        if (row.physical_close_confirmed === 0) {
          const changed = database.prepare(`UPDATE client_requests SET
            physical_close_confirmed = 1, observed_terminal_outcome = ?,
            revision = revision + 1
            WHERE namespace_id = ? AND authority_scope_cid = ? AND
              run_definition_cid = ? AND physical_start_reserved = 1 AND
              physical_close_confirmed = 0`).run(terminalOutcome,
            ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
          if (Number(changed.changes) !== 1) fail('ClientRunStopObservationChanged');
        }
      });
    },
    // Physical Host evidence only: a failure before invoking Site execution
    // is confirmed. A lost reply or absent worker cannot call this method.
    markPreDispatchFailure(ref: WireRunRef) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid)) {
        fail('InvalidClientRunFailureObservation');
      }
      return transact('failure_observation',
        'ClientRunFailureObservationUnknown',
        error => typeof (error as ObservedFailure)?.code === 'string' &&
          ((error as NonNullable<ObservedFailure>).code!.startsWith('ClientRun') ||
            (error as NonNullable<ObservedFailure>).code!.startsWith('ClientRequest')), () => {
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined || row.dispatch_reserved !== 1 ||
            row.pre_dispatch_failure_confirmed === 0 &&
            row.physical_start_reserved !== 0) {
          fail('ClientRunFailureObservationDenied');
        }
        if (row.pre_dispatch_failure_confirmed === 0 &&
            confirmPreDispatchFailure.run(ref.namespaceId,
              ref.authorityScopeCid, ref.runDefinitionCid).changes !== 1) {
          fail('ClientRequestJournalCorrupt');
        }
      });
    },
    // Keep the owner-issued `needs_reconciliation` state of a started Run
    // whose Effect outcomes are unknown. It is recorded once and never
    // replaced: a different state for the same Run is a conflict.
    recordReconciliationState(ref: WireRunRef, wire: unknown) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) || typeof wire !== 'string' ||
          Buffer.byteLength(wire, 'utf8') > maxRunDefinitionWireBytes) {
        fail('InvalidClientRunReconciliation');
      }
      let state: ReconciliationState | null;
      try { state = JSON.parse(wire); }
      catch { fail('InvalidClientRunReconciliation'); }
      if (state?.status !== 'needs_reconciliation' ||
          state?.next_action?.kind !== 'reconcile') {
        fail('InvalidClientRunReconciliation');
      }
      return transact('reconciliation', 'ClientRunReconciliationUnknown',
        error => typeof (error as ObservedFailure)?.code === 'string' &&
          (error as NonNullable<ObservedFailure>).code!.startsWith('ClientRun'), () => {
        const row = selectedRequestStatement(database.prepare(`SELECT physical_start_reserved,
          reconciliation_state_wire FROM client_requests
          WHERE namespace_id = ? AND authority_scope_cid = ? AND
            run_definition_cid = ?`), 'run-definition', true).get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined || row.physical_start_reserved !== 1) {
          fail('ClientRunReconciliationDenied');
        }
        if (row.reconciliation_state_wire !== null &&
            row.reconciliation_state_wire !== wire) {
          fail('ClientRunReconciliationConflict');
        }
        if (row.reconciliation_state_wire === null) {
          database.prepare(`UPDATE client_requests SET
            reconciliation_state_wire = ?, revision = revision + 1
            WHERE namespace_id = ? AND authority_scope_cid = ? AND
              run_definition_cid = ?`).run(wire, ref.namespaceId,
            ref.authorityScopeCid, ref.runDefinitionCid);
        }
      });
    },
    lookupReconciliationState(ref: WireRunRef) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid)) {
        fail('InvalidClientRunLookup');
      }
      const row = selectedRequestStatement(database.prepare(`SELECT reconciliation_state_wire
        FROM client_requests WHERE namespace_id = ? AND
          authority_scope_cid = ? AND run_definition_cid = ?`), 'run-definition', true).get(
        ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
      return row?.reconciliation_state_wire ?? undefined;
    },
  };
}
