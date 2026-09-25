// Physical acquisition for a Host-authorized DuckDB source. The checked
// Program and MoonBit acquisition planner own the source request and query;
// this adapter supplies only the approved database grant and bounded I/O.
import {readFile} from 'node:fs/promises';
import {checked} from '../host-common/runtime-result.mjs';
import {authorizeLocalDatabase} from
  '../connectors/duckdb/node/session.mjs';
import {runNativeHostQuery} from
  '../connectors/duckdb/node/host.mjs';

const contractRoot = new URL('../../spec/contracts/', import.meta.url);
const contractFiles = [
  'actql-query-acquisition.json',
  'actql-query-process-evidence.json',
  'actql-query-two-receipt.json',
];

export async function openCapturedDuckDBSource({moon, preparedProgram,
  registry, values, fragment, ordered, database, schema, table,
  transportLimits, signal}) {
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
  const checkedSource = Object.freeze({
    requirementCid: moon.clientProgramQueryRequirementCid(requirement),
    sourceRef: moon.clientProgramQueryRequirementSourceRef(requirement),
    sourceContractCid:
      moon.clientProgramQueryRequirementSourceContractCid(requirement),
    inputContractCid:
      moon.clientProgramQueryRequirementInputContractCid(requirement),
    outputContractCid:
      moon.clientProgramQueryRequirementOutputContractCid(requirement),
  });
  const contracts = await Promise.all(contractFiles.map(name =>
    readFile(new URL(name, contractRoot), 'utf8')));
  const acquisition = checked(moon.clientProgramPrepareDuckDBAcquisition(
    requirement, schema, table, ...contracts));
  const grant = await authorizeLocalDatabase(database);
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
    const logicalInput = checked(moon.clientProgramIssueCapturedSourceLogical(
      preparedProgram, capturedSource, identity, requirement));
    const setup = moon.clientProgramOpenCapturedLocalHost(preparedProgram,
      capturedSource, registry, values, 1n, 0n, 0n, 0n,
      fragment, ordered);
    if (setup === undefined) throw new Error('InstalledSourceHostUnavailable');
    return Object.freeze({capture, identity, logicalInput, checkedSource, setup,
      close: () => capture.close()});
  } catch (cause) {
    capture.close();
    throw cause;
  }
}
