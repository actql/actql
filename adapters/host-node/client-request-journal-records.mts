// Checked correspondence of the original Request/Run records retained by this Journal.
import {createHash} from 'node:crypto';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {valuesExecutionContextCid, validValuesHostPolicyRows} from './local-values-capacity.mjs';
import {BOUND_SOURCE_INVENTORY, validBoundSourceOccurrence} from './ordinary-source-binding.mjs';
import {fail, type JournalSqlConnection} from './client-request-journal-sql.mjs';
import type {SQLOutputValue} from 'node:sqlite';
import type {WireRunRef} from '../../packages/client-wire/index.js';

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
