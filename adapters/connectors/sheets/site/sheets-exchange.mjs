// Physical Sheets I/O only. The provider MoonBit projects typed cells and
// acknowledgements; the common Effect owner decides approval and settlement.
import {createHash} from 'node:crypto';
import {invokeScopedCredentialOperation} from
  '../../../host-common/owned-invocation-context.mjs';
import {refusedEffectPreparation} from
  '../../../host-common/effect-preparation-result.mjs';
import {canonicalJson as valueJson} from '../../../../packages/sdk/host-port.mjs';

export const SHEETS_READ_OPERATION = 'sheets:grid:read';
export const SHEETS_APPEND_OPERATION = 'sheets:cells:append';
export const SHEETS_LIMITS = Object.freeze({maxRequestBytes: 300_000,
  maxResponseBytes: 2_000_000, maxNodes: 200_000, maxDepth: 32,
  maxCells: 6_400, maxRows: 100});
// Content type and credentials belong to the physical resource owner.
const headers = Object.freeze([['accept', 'application/json']]);
const fields = 'spreadsheetId,sheets(properties(sheetId),data(startRow,startColumn,rowData(values(effectiveValue,userEnteredValue))))';
const metadataFields = 'spreadsheetId,sheets(properties(sheetId,sheetType,gridProperties(rowCount,columnCount)))';
const fail = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };
const basePath = id => {
  if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/u.test(id)) {
    fail('InvalidSheetsSpreadsheetId');
  }
  return `/v4/spreadsheets/${id}`;
};
const rangeArgs = range => [range.sheetId, range.startRow, range.endRow,
  range.startColumn, range.endColumn];
const codecLimits = bytes => [bytes, SHEETS_LIMITS.maxNodes,
  SHEETS_LIMITS.maxDepth, SHEETS_LIMITS.maxCells];
const decoded = wire => {
  const result = JSON.parse(wire);
  if (result.refused !== undefined) fail('SheetsContractRefused', result.refused);
  return result;
};

export function checkSheetsGridConfiguration(moon, columns, range) {
  return decoded(moon.sheetsGridRequestJson(JSON.stringify(columns),
    ...rangeArgs(range), ...codecLimits(SHEETS_LIMITS.maxRequestBytes))).body;
}

async function exchange({authorization, credential, callResource, operation,
  path, body, method = 'POST', signal}) {
  signal?.throwIfAborted();
  return invokeScopedCredentialOperation({authorization, credential,
    callResource, operation, method, path, body, headers,
    responseHeaders: [], maxRequestBytes: SHEETS_LIMITS.maxRequestBytes,
    maxResponseBytes: SHEETS_LIMITS.maxResponseBytes, signal});
}

export async function checkSheetsTarget({moon, spreadsheetId, columns, range,
  appendSheetId, authorization, credential, callResource, signal}) {
  const response = await exchange({authorization, credential, callResource,
    operation: SHEETS_READ_OPERATION, method: 'GET',
    path: `${basePath(spreadsheetId)}?fields=${encodeURIComponent(metadataFields)}`,
    signal});
  if (!response.accepted || response.statusCode !== 200) {
    fail('SheetsTargetUnverified');
  }
  try {
    decoded(moon.sheetsTargetJson(response.body, spreadsheetId,
      JSON.stringify(columns), ...rangeArgs(range), appendSheetId,
      ...codecLimits(SHEETS_LIMITS.maxResponseBytes)));
  } catch (cause) {
    throw refusedEffectPreparation(cause);
  }
}

export async function readSheetsGrid({moon, spreadsheetId, columns, range,
  credential, callResource, authorizationFor, chargePage, consumePage, signal}) {
  const body = checkSheetsGridConfiguration(moon, columns, range);
  const authorization = await authorizationFor(0);
  const response = await exchange({authorization, credential, callResource,
    operation: SHEETS_READ_OPERATION,
    path: `${basePath(spreadsheetId)}:getByDataFilter?fields=${encodeURIComponent(fields)}`,
    body, signal});
  const charge = await chargePage(response.body);
  if (!response.accepted || response.statusCode !== 200) fail('SheetsReadRejected');
  const {page} = decoded(moon.sheetsGridPageJson(response.body, spreadsheetId,
    JSON.stringify(columns), ...rangeArgs(range),
    ...codecLimits(SHEETS_LIMITS.maxResponseBytes)));
  if (page.rows.length > SHEETS_LIMITS.maxRows) fail('SheetsReadRowLimit');
  signal?.throwIfAborted();
  await consumePage(page.rows, {charge});
  return Object.freeze({pages: 1, rows: page.rows.length,
    excludedBlankRows: page.excludedBlankRows});
}

export function prepareSheetsAppend({moon, origin, spreadsheetId, sheetId,
  columns, value}) {
  let body;
  try {
    body = decoded(moon.sheetsAppendRequestJson(JSON.stringify(columns),
      valueJson(value, {dataKeys: true}), sheetId,
      ...codecLimits(SHEETS_LIMITS.maxRequestBytes))).body;
  } catch (cause) {
    // Only the pure codec's observed row refusal is definitive. Unexpected
    // runtime failures and physical transport uncertainty are not reclassified.
    throw cause?.code === 'SheetsContractRefused' ? refusedEffectPreparation(cause) : cause;
  }
  const path = `${basePath(spreadsheetId)}:batchUpdate`;
  // Exact wire bytes, not the NFC serializer used for configuration identity.
  const hash = createHash('sha256');
  for (const part of ['actql-sheets-append-request/0.1', origin, 'POST', path, body]) {
    const bytes = Buffer.from(part, 'utf8');
    hash.update(`${bytes.length}:`); hash.update(bytes);
  }
  return Object.freeze({origin, path, body, spreadsheetId, sheetId,
    value: Object.freeze({...value}), requestCid: `sha256:${hash.digest('hex')}`});
}

export async function sendSheetsAppend({request, authorization, credential,
  callResource, signal}) {
  if (authorization?.scope?.resourceOrigin !== request.origin ||
      request.path !== `${basePath(request.spreadsheetId)}:batchUpdate`) {
    fail('InvalidSheetsAppendBinding');
  }
  // Exactly one physical send from a fresh common durable claim. No retry.
  const response = await exchange({authorization, credential, callResource,
    operation: SHEETS_APPEND_OPERATION, path: request.path, body: request.body,
    signal});
  return Object.freeze({observation: Object.freeze({useCid: response.useCid,
    statusCode: response.statusCode, body: response.body}), headers: response.headers});
}

export function projectSheetsAppend({moon, request, observation}) {
  const answer = JSON.parse(moon.sheetsAppendOutcomeJson(observation.statusCode,
    observation.body, request.spreadsheetId,
    ...codecLimits(SHEETS_LIMITS.maxResponseBytes)));
  if (answer.outcome !== 'Applied') return {kind: 'provider-response'};
  return {kind: 'typed-success-response', outcome: {state: 'applied', result: {
    spreadsheet_id: request.spreadsheetId, sheet_id: request.sheetId,
    acknowledged_rows: 1}}};
}
