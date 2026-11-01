// Physical Sheets I/O only. The provider MoonBit projects typed cells and
// acknowledgements; the common Effect owner decides approval and settlement.
import {prepareSheetsTargetRequest} from './sheets-grid-pages.mjs';
export {prepareSheetsTargetRequest} from './sheets-grid-pages.mjs';
import {invokeScopedCredentialOperation} from
  '../../../host-common/owned-invocation-context.mjs';
import {refusedEffectPreparation} from
  '../../../host-common/effect-preparation-result.mjs';
import {canonicalJson as valueJson} from '../../../../packages/sdk/host-port.mjs';
import {prepareOwnedSheetsRequest, ownedSheetsRequestCid, sheetsOwnedResult} from './sheets-owned-request.mjs';
import {prepareOwnedSheetsClearRequest, ownedSheetsClearRequestCid,
  ownedSheetsClearOutcome} from './sheets-clear-request.mjs';

export const SHEETS_READ_OPERATION = 'sheets:grid:read';
export const SHEETS_APPEND_OPERATION = 'sheets:cells:append';
export const SHEETS_UPDATE_OPERATION = 'sheets:cells:update';
export const SHEETS_CLEAR_OPERATION = 'sheets:cells:clear';
export const SHEETS_LIMITS = Object.freeze({maxRequestBytes: 300_000,
  maxResponseBytes: 2_000_000, maxNodes: 200_000, maxDepth: 32,
  maxCells: 6_400, maxRows: 100});
// Content type and credentials belong to the physical resource owner.
const headers = Object.freeze([['accept', 'application/json']]);
const fields = 'spreadsheetId,sheets(properties(sheetId),data(startRow,startColumn,rowData(values(effectiveValue,userEnteredValue))))';
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

export function projectSheetsTarget({moon, spreadsheetId, columns, range,
  appendSheetId, response}) {
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

export async function checkSheetsTarget({moon, spreadsheetId, columns, range,
  appendSheetId, authorization, credential, callResource, signal}) {
  const request = prepareSheetsTargetRequest(spreadsheetId);
  const response = await exchange({authorization, credential, callResource,
    operation: SHEETS_READ_OPERATION, ...request, signal});
  return projectSheetsTarget({moon, spreadsheetId, columns, range, appendSheetId, response});
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
  // Exact framing belongs to the same portable provider authority as update.
  const requestCid = sheetsOwnedResult(moon,
    moon.sheetsAppendRequestIdentity(origin, path, body));
  return Object.freeze({origin, path, body, spreadsheetId, sheetId,
    value: Object.freeze({...value}), requestCid});
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

// A range target is acquired from checked provider metadata, not from a
// caller-authored ResourceRef or observed row coordinate. Charge the complete
// response before admitting its projection through the ordinary Source owner.
export async function readSheetsRangeTarget({moon, spreadsheetId, columns, range,
  target, authorizationFor, credential, callResource, chargePage, consumePage, signal}) {
  const authorization = await authorizationFor(0);
  const response = await exchange({authorization, credential, callResource,
    operation: SHEETS_READ_OPERATION, ...prepareSheetsTargetRequest(spreadsheetId), signal});
  const charge = await chargePage(response.body);
  if (!response.accepted || response.statusCode !== 200) fail('SheetsTargetUnverified');
  decoded(moon.sheetsTargetJson(response.body, spreadsheetId, JSON.stringify(columns),
    ...rangeArgs(range), range.sheetId, ...codecLimits(SHEETS_LIMITS.maxResponseBytes)));
  signal?.throwIfAborted();
  await consumePage([{target}], {charge});
  return Object.freeze({pages: 1, rows: 1});
}

export function sheetsUpdateRequestCid(request) {
  return ownedSheetsRequestCid(request);
}

// This only encodes a request. Current reference authority, approval, durable
// claim and response custody remain the installed Source/Effect owners'.
export function prepareSheetsUpdate({moon, binding, value, target}) {
  try {
    return prepareOwnedSheetsRequest(moon, binding, value, target);
  } catch (cause) {
    throw ['InvalidSheetsRangeInput', 'SheetsContractRefused'].includes(cause?.code)
      ? refusedEffectPreparation(cause) : cause;
  }
}

export async function sendSheetsUpdate({request, authorization, credential, callResource, signal}) {
  if (authorization?.scope?.resourceOrigin !== request.origin ||
      request.requestCid !== sheetsUpdateRequestCid(request)) fail('InvalidSheetsUpdateBinding');
  const response = await exchange({authorization, credential, callResource,
    operation: SHEETS_UPDATE_OPERATION, path: request.path, body: request.body, signal});
  return Object.freeze({observation: Object.freeze({useCid: response.useCid,
    statusCode: response.statusCode, body: response.body}), headers: response.headers});
}

export function projectSheetsUpdate({moon, request, observation}) {
  // Both one-request AppendCells and UpdateCells batches acknowledge exactly
  // one empty reply. Reuse that codec without inferring a row ID or retry.
  const answer = JSON.parse(moon.sheetsAppendOutcomeJson(observation.statusCode,
    observation.body, request.spreadsheetId, ...codecLimits(SHEETS_LIMITS.maxResponseBytes)));
  if (answer.outcome !== 'Applied') return {kind: 'provider-response'};
  return {kind: 'typed-success-response', outcome: {state: 'applied', result: {
    spreadsheet_id: request.spreadsheetId, sheet_id: request.sheetId,
    acknowledged_rows: request.acknowledgedRows}}};
}

export function prepareSheetsClear({moon, binding, value, target, marker}) {
  try {
    return prepareOwnedSheetsClearRequest(moon, binding, value, target, marker);
  } catch (cause) {
    throw ['InvalidSheetsClearInput', 'SheetsContractRefused'].includes(cause?.code)
      ? refusedEffectPreparation(cause) : cause;
  }
}

export async function sendSheetsClear({request, authorization, credential, callResource, signal}) {
  if (authorization?.scope?.resourceOrigin !== request.origin ||
      request.requestCid !== ownedSheetsClearRequestCid(request)) fail('InvalidSheetsClearBinding');
  const response = await exchange({authorization, credential, callResource,
    operation: SHEETS_CLEAR_OPERATION, path: request.path, body: request.body, signal});
  return Object.freeze({observation: Object.freeze({useCid: response.useCid,
    statusCode: response.statusCode, body: response.body}), headers: response.headers});
}

export function projectSheetsClear({moon, request, observation}) {
  const answer = ownedSheetsClearOutcome(moon, request, observation.statusCode, observation.body);
  if (answer.outcome !== 'Applied') return {kind: 'provider-response'};
  return {kind: 'typed-success-response', outcome: {state: 'applied', result: {
    spreadsheet_id: request.spreadsheetId, sheet_id: request.sheetId,
    cleared_rows: request.clearedRows}}};
}
