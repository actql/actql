import {buildControlRegistry} from './interactive-run-control-contract.mjs';
import {resolveControlSchema} from './interactive-run-control-schema.mjs';
import {generateCheckReasonCatalog} from './generate-check-reason-catalog.mjs';
import {readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join, resolve} from 'node:path';
import {project, structuralValidatorSource, typeOf} from
  './generate-client-publication-wire.mjs';

import {nativeClientWire, responseRules, jsResponseRules,
  requestResponseRules, jsRequestResponseRules} from './generate-native-client-wire.mjs';
import {checkReportRules, jsCheckReportRules} from './client-check-report-rules.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const source = 'spec/contracts/actql-client-host.json';
const runStateSource = 'spec/contracts/actql-protocol-schemas.json';
const names = ['submission_epoch', 'submission_ref', 'submission_outcome', 'submission_lookup', 'submission_restart', 'submission_attempt',
  'submission_name', 'named_submission_attempt',
  'run_ref', 'connection', 'profile', 'admission',
  'lookup_found', 'lookup_not_found', 'lookup_unknown', 'held',
  'checkpoint_summary', 'checkpoint_review', 'resolve_item',
  'resolve_result', 'submit_preparation_error', 'cancellation',
  'cancellation_ref', 'cancellation_lookup', 'operation_attempt_ref', 'cancellation_attempt',
  'request_cancellation', 'resource_listing', 'resource_inspection',
  'resource_peek', 'result_description', 'owner_ref', 'owner_cursor', 'owner_observations'];
const exports = ['SubmissionEpoch', 'SubmissionRef', 'SubmissionOutcome', 'SubmissionLookup', 'SubmissionRestart', 'SubmissionAttempt',
  'SubmissionName', 'NamedSubmissionAttempt',
  'RunRef', 'Connection', 'Profile', 'Admission',
  'LookupFound', 'LookupNotFound', 'LookupUnknown', 'Held',
  'CheckpointSummary', 'CheckpointReview', 'ResolveItem', 'ResolveResult',
  'SubmitPreparationError', 'Cancellation', 'CancellationRef',
  'CancellationLookup', 'OperationAttemptRef', 'CancellationAttempt', 'RequestCancellation',
  'ResourceListing', 'ResourceInspection', 'ResourcePeek', 'ResultDescription', 'OwnerRef', 'OwnerCursor', 'OwnerObservations'];

// Public language discovery exports the complete existing Program schema,
// including its metadata and local definitions. The validator projection below
// intentionally discards annotations and cannot serve as the discovery body.
export function nativeProgramSchema(protocol) {
  const original = protocol?.artifact_schemas?.executable_plan?.properties
    ?.execution_material?.properties?.program;
  if (original === null || typeof original !== 'object' || Array.isArray(original)) {
    throw new Error('MissingProgramSchema');
  }
  const body = JSON.stringify(original);
  if (Buffer.byteLength(body, 'utf8') > 1048576) {
    throw new Error('NativeProgramSchemaOutputLimit');
  }
  return '// Generated from the registered Program JSON Schema. Do not edit.\n' +
    '// Run: node scripts/generate-client-host-wire.mjs --write\n' +
    '// DATA for language discovery; this does not admit a Program or issue authority.\n\n' +
    '///|\nfn generated_program_schema() -> String {\n  ' +
    JSON.stringify(body) + '\n}\n';
}

export function projectClientHostOptionalFields(registry) {
  const fieldsByOperation = registry.request_optional_fields;
  if (fieldsByOperation === null || typeof fieldsByOperation !== 'object' ||
      Array.isArray(fieldsByOperation) || Object.entries(fieldsByOperation).some(([name, fields]) =>
        !Object.hasOwn(registry.operations, name) || fields === null ||
        typeof fields !== 'object' || Array.isArray(fields) ||
        Object.keys(fields).length === 0 || Object.keys(fields).some(key =>
          !/^[a-zA-Z][a-zA-Z]*$/u.test(key) || registry.operations[name].includes(key)))) {
    throw new Error('InvalidClientHostOptionalFields');
  }
  // The exact-ID selection is the existing Checkpoint identity, not a new
  // permissive identifier spelling maintained by a transport consumer.
  const lookup = fieldsByOperation.checkpoints;
  if (lookup !== undefined) {
    const canonical = value => value !== null && typeof value === 'object' && !Array.isArray(value)
      ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
    const expected = registry.schemas?.checkpoint_summary?.oneOf?.map(branch => branch.properties?.checkpointId);
    if (Object.keys(lookup).join() !== 'checkpointId' || !expected?.length || expected.some(rule =>
      JSON.stringify(canonical(rule)) !== JSON.stringify(canonical(lookup.checkpointId)))) {
      throw new Error('InvalidCheckpointLookupIdentity');
    }
  }
  return Object.fromEntries(Object.entries(fieldsByOperation).map(([name, fields]) =>
    [name, Object.fromEntries(Object.entries(fields).map(([field, schema]) => [field, project(schema)]))]));
}

export function buildClientHostWire(registry, protocol) {
  if (registry.version !== 'actql-client-host/0.1' ||
      registry.operations === null ||
      typeof registry.operations !== 'object' ||
      Array.isArray(registry.operations)) {
    throw new Error('InvalidClientHostRegistry');
  }
  const rules = responseRules(registry);
  const reportRules = checkReportRules(registry);
  const operations = Object.entries(registry.operations);
  if (operations.length === 0 || operations.some(([name, keys]) =>
    !/^[a-z][a-z-]*$/u.test(name) || !Array.isArray(keys) ||
    keys.length === 0 || new Set(keys).size !== keys.length ||
    keys.some(key => !/^[a-zA-Z][a-zA-Z]*$/u.test(key)))) {
    throw new Error('InvalidClientHostOperations');
  }
  const optionalSchemas = projectClientHostOptionalFields(registry);
  const schemas = Object.fromEntries(names.map(name => {
    if (!registry.schemas?.[name]) throw new Error(`MissingClientHostSchema:${name}`);
    return [name, project(registry.schemas[name])];
  }));
  if (protocol?.artifact_schemas?.run_state === undefined) {
    throw new Error('MissingRunStateSchema');
  }
  schemas.run_state = project(protocol.artifact_schemas.run_state);
  const runVersion = schemas.run_state.properties?.version?.const;
  const runStatuses = schemas.run_state.properties?.status?.enum;
  if (typeof runVersion !== 'string' || !Array.isArray(runStatuses) ||
      !runStatuses.length || runStatuses.some(value => typeof value !== 'string') ||
      new Set(runStatuses).size !== runStatuses.length) {
    throw new Error('InvalidRunStateDiscriminants');
  }
  if (protocol?.artifact_schemas?.check_outcome === undefined) {
    throw new Error('MissingCheckOutcomeSchema');
  }
  schemas.check_outcome = project(protocol.artifact_schemas.check_outcome);
  // Presentation may distinguish an unknown discriminant only after the single
  // registered validator rejects the reply. Derive its vocabulary from that
  // same schema instead of maintaining a second acceptance table in the SDK.
  const checkBranches = schemas.check_outcome.oneOf;
  const checkVersion = checkBranches?.[0]?.properties?.version?.const;
  const checkVariants = checkBranches?.map(branch => branch.properties?.outcome?.const);
  if (typeof checkVersion !== 'string' || !checkVariants?.length ||
      checkVariants.some(value => typeof value !== 'string') ||
      new Set(checkVariants).size !== checkVariants.length ||
      checkBranches.some(branch => branch.properties?.version?.const !== checkVersion)) {
    throw new Error('InvalidCheckOutcomeDiscriminants');
  }
  schemas.value_contract = project(
    protocol.schemas.canonical_value_contract.$defs.value_contract);
  const interactive = buildControlRegistry();
  // The existing Native generator admits null literals. Preserve the exact
  // null-only branches of the resolved interactive schema as const:null.
  const nullLiterals = value => Array.isArray(value) ? value.map(nullLiterals) :
    value !== null && typeof value === 'object' ?
      value.type === 'null' && Object.keys(value).length === 1 ? {const: null} :
        Object.fromEntries(Object.entries(value).map(([key, child]) => [key, nullLiterals(child)])) : value;
  schemas.run_plan_view = project(nullLiterals(resolveControlSchema(
    interactive.schemas.run_plan_view, interactive)));
  const module = `// Generated from the registered Client–Host machine contract.\n` +
    `// Run: node scripts/generate-client-host-wire.mjs --write\n` +
    `const schemas = ${JSON.stringify(schemas, null, 2)};\n` +
    `const operationKeys = ${JSON.stringify(registry.operations, null, 2)};\n\n` +
    `const optionalRequestFields = ${JSON.stringify(optionalSchemas, null, 2)};\n\n` +
    `export const checkReasonSchemaCid = ${JSON.stringify(protocol.artifact_schema_cids.check_reason)};\n` +
    `export const checkOutcomeSchemaCid = ${JSON.stringify(protocol.artifact_schema_cids.check_outcome)};\n` +
    `export const checkOutcomeProtocol = Object.freeze({version: ${JSON.stringify(checkVersion)}, ` +
    `reasonSchemaCid: checkReasonSchemaCid, outcomeSchemaCid: checkOutcomeSchemaCid, ` +
    `outcomes: Object.freeze(${JSON.stringify(checkVariants)})});\n` +
    `export const runStateProtocol = Object.freeze({version: ${JSON.stringify(runVersion)}, ` +
    `statuses: Object.freeze(${JSON.stringify(runStatuses)})});\n` +
    structuralValidatorSource() +
    `export const clientHostOperations = Object.freeze(` +
    `Object.keys(operationKeys));\n` +
    `export const clientHostRequestKeys = (operation, body = {}) => ` +
    `(Object.hasOwn(operationKeys, operation) ? [...operationKeys[operation], ` +
    `...Object.keys(optionalRequestFields[operation] ?? {}).filter(key => ` +
    `body !== null && typeof body === 'object' && Object.hasOwn(body, key))] : undefined);\n` +
    `export const validClientRequestOptionalFields = (operation, body) => ` +
    `Object.entries(optionalRequestFields[operation] ?? {}).every(([key, schema]) => ` +
    `!Object.hasOwn(body, key) || valid(body[key], schema));\n` +
    names.map((name, index) =>
      `export const valid${exports[index]}Shape = value => ` +
      `valid(value, schemas.${name});\n`).join('') +
    `export const validRunStateShape = value => ` +
    `valid(value, schemas.run_state);\n` +
    `export const validCheckOutcomeShape = value => ` +
    `valid(value, schemas.check_outcome) && value.outcome_schema_cid === checkOutcomeSchemaCid;\n`;
  const requestRules = requestResponseRules(registry, schemas);
  const {native, nativeTests, nativeCheckOutcome} = nativeClientWire(schemas, rules, requestRules, {reason: protocol.artifact_schema_cids.check_reason,
    outcome: protocol.artifact_schema_cids.check_outcome}, reportRules);
  const types = `// Generated from the registered Client–Host machine contract.\n` +
    `export declare const checkOutcomeProtocol: Readonly<{version: ${JSON.stringify(checkVersion)}; ` +
    `reasonSchemaCid: string; outcomeSchemaCid: string; ` +
    `outcomes: readonly (${checkVariants.map(value => JSON.stringify(value)).join(' | ')})[]}>;\n` +
    `export declare const runStateProtocol: Readonly<{version: ${JSON.stringify(runVersion)}; ` +
    `statuses: readonly (${runStatuses.map(value => JSON.stringify(value)).join(' | ')})[]}>;\n` +
    `export type ClientHostOperation = ${operations.map(([name]) =>
      JSON.stringify(name)).join(' | ')};\n` +
    `export type WireValueContractShape = ${typeOf(schemas.value_contract)};\n` +
    names.map((name, index) =>
      `export type Wire${exports[index]}Shape = ${typeOf(schemas[name])};\n`
    ).join('\n') +
    `\nexport type WireRunStateShape = ${typeOf(schemas.run_state)};\n` +
    `export type WireCheckOutcomeShape = ${typeOf(schemas.check_outcome)};\n` +
    `export type WireCheckLocationShape = ${typeOf(project(protocol.artifact_schemas.check_reason.properties.location))};\n` +
    `export type WireCheckFixShape = ${typeOf(project(protocol.artifact_schemas.check_reason.properties.fixes.items))};\n`;
  // SDK action correspondence uses the existing artifact contracts, not a
  // second handwritten Resolution/Evidence grammar. This is structural DATA
  // admission only; the actual Host still owns authentication and authority.
  const answerSchemas = {
    resolution: project(protocol.artifact_schemas.checkpoint_resolution, {extended: true}),
    evidence: project(protocol.artifact_schemas.verified_checkpoint_resolution.properties.approval_evidence,
      {extended: true}),
  };
  const checkpointAnswers = '// Generated by scripts/generate-client-host-wire.mjs.\n' +
    '// Existing Checkpoint artifact shapes only; not a signature, grant or current authority.\n' +
    `const schemas = ${JSON.stringify(answerSchemas, null, 2)};\n` +
    structuralValidatorSource({extended: true, compositeConstants: true}) +
    'export const validAnswerResolution = value => valid(value, schemas.resolution);\n' +
    'export const validAnswerEvidence = value => valid(value, schemas.evidence);\n';
  const wait = requestRules.run_wait;
  const runWait = '// Generated from the existing Client–Host Run wait correlation rule.\n' +
    '// Run: node scripts/generate-client-host-wire.mjs --write\n\n' +
    '///|\nfn generated_run_wait_stable(status : String) -> Bool {\n  ' +
    wait.stableStatuses.map(status => `status == ${JSON.stringify(status)}`).join(' ||\n  ') + '\n}\n';
  return {runWait, checkpointAnswers, module: module + jsResponseRules(rules) +
    jsRequestResponseRules(schemas, requestRules) + jsCheckReportRules(reportRules), types, native, nativeTests, nativeCheckOutcome};
}

async function main() {
  generateCheckReasonCatalog(process.argv.includes('--write'));
  const registry = JSON.parse(await readFile(join(root, source), 'utf8'));
  const protocol = JSON.parse(await readFile(join(root, runStateSource),
    'utf8'));
  const outputs = buildClientHostWire(registry, protocol);
  const files = [
    ['src/cmd/native_client/program_schema.generated.mbt', nativeProgramSchema(protocol)],
    ['packages/client-wire/client-host.generated.js', outputs.module],
    ['packages/client-wire/client-host.generated.d.ts', outputs.types],
    ['packages/sdk/internal/checkpoint-answer-contract.generated.mjs', outputs.checkpointAnswers],
    ['src/cmd/native_client/wire.generated.mbt', outputs.native],
    ['src/cmd/native_client/wire_owner_observations.generated_wbtest.mbt', outputs.nativeTests],
    ['src/run_publication/run_wait.generated.mbt', outputs.runWait],
  ];
  for (const [path, content] of files) {
    if (process.argv.includes('--write')) {
      await writeFile(join(root, path), content);
    } else if (await readFile(join(root, path), 'utf8') !== content) {
      throw new Error(`StaleClientHostWire:${path}`);
    }
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) ===
    resolve(process.argv[1])) {
  await main();
}
