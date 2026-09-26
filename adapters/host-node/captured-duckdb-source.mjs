// Physical acquisition for a Host-authorized DuckDB source. The checked
// Program and MoonBit acquisition planner own the source request and query;
// this adapter supplies only the approved database grant and bounded I/O.
import {readFile} from 'node:fs/promises';
import {checked} from '../host-common/runtime-result.mjs';
import {authorizeLocalDatabase} from
  '../connectors/duckdb/node/session.mjs';
import {runNativeHostQuery, nativeSourceIdentityMatches, issueNativeSourceEvidence} from
  '../connectors/duckdb/node/host.mjs';

const contractRoot = new URL('../../spec/contracts/', import.meta.url);
const contractFiles = [
  'actql-query-acquisition.json',
  'actql-query-process-evidence.json',
  'actql-query-two-receipt.json',
];
const preparations = new WeakMap();

// Checked preparation for the Host's acquisition Checkpoint. It does not
// open the database or infer authority from the source CID. The returned
// handle can only be consumed with the same checked Program and Host profile.
export async function prepareCapturedDuckDBSource({moon, preparedProgram,
  registry, values, fragment, ordered, database, schema, table,
  sourceAccess}) {
  if (typeof database !== 'string' || typeof schema !== 'string' ||
      typeof table !== 'string' || typeof registry !== 'string' ||
      typeof values !== 'string' || typeof fragment !== 'string' ||
      typeof ordered !== 'string') {
    throw new TypeError('InvalidInstalledSourceConfiguration');
  }
  // This installed profile has one captured source at the first task. The
  // owner rejects a different checked source rather than using file settings
  // as a substitute for the Program's source declaration.
  checked(moon.clientProgramPrepareQueryAcquisition(preparedProgram, 0, 0));
  const requirement = checked(
    moon.clientProgramPrepareLocalQueryRequirement(preparedProgram, 0, 0,
      registry, values, fragment, ordered));
  const sourceFacts = checked(
    moon.clientProgramQueryRequirementSourceEvidenceFacts(requirement));
  if (!Array.isArray(sourceFacts) || sourceFacts.length !== 6 ||
      !sourceFacts.every(value => typeof value === 'string')) {
    throw new Error('InstalledSourceEvidenceFactsUnavailable');
  }
  const [sourceRef, sourceContractCid, carrierSchemaContractCid,
    sourceDataPolicyCid, dataClassification, sourceViewContractCid] =
    sourceFacts;
  if (sourceRef !== sourceAccess?.sourceRef) {
    throw new Error('InstalledSourceProgramMismatch');
  }
  const checkedSource = Object.freeze({
    requirementCid: moon.clientProgramQueryRequirementCid(requirement),
    sourceRef, sourceContractCid, carrierSchemaContractCid,
    sourceDataPolicyCid, dataClassification, sourceViewContractCid,
    inputContractCid:
      moon.clientProgramQueryRequirementInputContractCid(requirement),
    outputContractCid:
      moon.clientProgramQueryRequirementOutputContractCid(requirement),
  });
  const evidenceContext = checked(
    moon.clientProgramPrepareDuckDBSourceEvidenceContext(requirement));
  const contracts = await Promise.all(contractFiles.map(name =>
    readFile(new URL(name, contractRoot), 'utf8')));
  const acquisition = checked(moon.clientProgramPrepareDuckDBAcquisition(
    requirement, schema, table, ...contracts));
  // The Host-resolved physical target is part of what an approval covers:
  // the same checked source read from another schema or table is another
  // read. Physical names are bound by their exact UTF-8 bytes (hex): the
  // database distinguishes names that ActQL's logical text normalization
  // treats as equal. The readable names are display only.
  const exact = name => Buffer.from(name, 'utf8').toString('hex');
  const prepared = Object.freeze({checkedSource,
    readTuple: Object.freeze({connection: sourceAccess.connection ??
      'local-database', resource: sourceAccess.resource ?? database,
    operation: 'read'}),
    physicalBinding: Object.freeze({version:
      'actql-installed-duckdb-target/0.1', database, schema, table,
      utf8_hex: Object.freeze({database: exact(database),
        schema: exact(schema), table: exact(table)})})});
  preparations.set(prepared, Object.freeze({moon, preparedProgram, registry,
    values, fragment, ordered, database, schema, table, sourceAccess,
    requirement, evidenceContext, acquisition}));
  return prepared;
}

export async function openCapturedDuckDBSource({moon, preparedProgram,
  registry, values, fragment, ordered, database, schema, table,
  sourceAccess, transportLimits, signal, preparedSource}) {
  const prepared = preparedSource ?? await prepareCapturedDuckDBSource({moon,
    preparedProgram, registry, values, fragment, ordered, database, schema,
    table, sourceAccess});
  const owner = preparations.get(prepared);
  if (owner === undefined || owner.moon !== moon ||
      owner.preparedProgram !== preparedProgram ||
      owner.registry !== registry || owner.values !== values ||
      owner.fragment !== fragment || owner.ordered !== ordered ||
      owner.database !== database || owner.schema !== schema ||
      owner.table !== table || owner.sourceAccess !== sourceAccess) {
    throw new Error('InstalledSourcePreparationMismatch');
  }
  const {checkedSource} = prepared;
  const {requirement, evidenceContext, acquisition} = owner;
  const grant = await authorizeLocalDatabase(database, sourceAccess);
  const capture = await runNativeHostQuery(grant, acquisition,
    transportLimits, signal);
  try {
    const capturedSource = capture.source();
    if (moon.clientProgramCapturedSourceMatches(preparedProgram,
      capturedSource) !== true) {
      throw new Error('InstalledSourceProgramMismatch');
    }
    const identity = checked(moon.clientProgramIdentifyCapturedSourceRelation(
      capturedSource));
    if (!nativeSourceIdentityMatches(capture, identity)) {
      throw new Error('InstalledSourceObservationMismatch');
    }
    const logicalInput = checked(moon.clientProgramIssueCapturedSourceLogical(
      preparedProgram, capturedSource, identity, requirement));
    const setup = moon.clientProgramOpenCapturedLocalHost(preparedProgram,
      capturedSource, registry, values, 1n, 0n, 0n, 0n,
      fragment, ordered);
    if (setup === undefined) throw new Error('InstalledSourceHostUnavailable');
    return Object.freeze({capture, identity, logicalInput, checkedSource, setup,
      issueSourceEvidence: options => issueNativeSourceEvidence(capture,
        {...options, context: evidenceContext, identity, logicalInput}),
      close: () => capture.close()});
  } catch (cause) {
    capture.close();
    throw cause;
  }
}
