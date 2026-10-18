import {checked} from '../../../host-common/runtime-result.mjs';
import {sendRawKintoneDelete} from './kintone-record-delete.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;

function originalMapping(moon, mapping, declaration) {
  if (typeof moon?.clientProgramKintoneDeleteMappingMatchesDeclaration !== 'function' ||
      typeof moon?.clientProgramKintoneDeleteMappingMatchesRequest !== 'function') {
    fail('KintoneDeleteExecutionRuntimeUnavailable');
  }
  if (!mapping || !declaration ||
      !moon.clientProgramKintoneDeleteMappingMatchesDeclaration(mapping, declaration)) {
    fail('ForeignKintoneDeleteMapping');
  }
}

// The original Effect Owner must already hold its durable claim. This adds
// only the selected Mapping correspondence, never a claim, retry or cleanup.
export async function sendMappedKintoneDelete({moon, mapping, declaration, request, ...options}) {
  originalMapping(moon, mapping, declaration);
  if (!moon.clientProgramKintoneDeleteMappingMatchesRequest(mapping, request)) {
    fail('ForeignKintoneDeleteRequest');
  }
  return sendRawKintoneDelete({...options, moon, request});
}

// Classify one typed response against one exact admitted Preview row. Physical
// custody, authority, approval, saved-response receipt and Ledger settlement
// remain independent obligations of the original Effect and Credential owners.
export function projectMappedKintoneDeleteOutcome({moon, mapping, declaration,
  request, response, preview, memberIndex, rowIndex, limits}) {
  originalMapping(moon, mapping, declaration);
  const names = ['clientProgramKintoneDeletePreviewOutcome',
    'clientProgramKintoneDeletePreviewOutcomeWire', 'clientProgramKintoneDeletePreviewOutcomeRowCid',
    'clientProgramKintoneDeletePreviewOutcomeResponseSha256', 'clientProgramKintoneDeletePreviewOutcomeMatches',
    'clientProgramKintoneValueLimits', 'clientProgramKintoneMutationLimits',
    'clientProgramKintoneDeleteBody'];
  if (names.some(name => typeof moon?.[name] !== 'function')) {
    fail('KintoneDeleteOutcomeRuntimeUnavailable');
  }
  if (!Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
      !Number.isSafeInteger(rowIndex) || rowIndex < 0 ||
      !['maxRequestBytes', 'maxResponseBytes', 'maxNodes', 'maxDepth', 'maxRows',
        'maxIdentityBytes', 'maxComparisonWork', 'maxColumns', 'maxNameUnits',
        'maxValueNodes', 'maxValueDepth', 'maxValueTextBytes']
        .every(name => positive(limits?.[name]))) fail('InvalidKintoneDeleteOutcome');
  if (Buffer.byteLength(moon.clientProgramKintoneDeleteBody(request)) > limits.maxRequestBytes) {
    fail('InvalidKintoneDeleteOutcome');
  }
  const values = moon.clientProgramKintoneValueLimits(limits.maxColumns, limits.maxNameUnits,
    limits.maxValueNodes, limits.maxValueDepth, limits.maxValueTextBytes);
  const bounds = moon.clientProgramKintoneMutationLimits(limits.maxRows,
    limits.maxIdentityBytes, limits.maxComparisonWork, limits.maxResponseBytes,
    limits.maxNodes, limits.maxDepth);
  const projected = checked(moon.clientProgramKintoneDeletePreviewOutcome(mapping,
    request, response, preview, memberIndex, rowIndex, values, bounds));
  if (!moon.clientProgramKintoneDeletePreviewOutcomeMatches(projected,
    mapping, request, preview, memberIndex, rowIndex)) fail('ForeignKintoneDeleteOutcome');
  return Object.freeze({kind: 'typed-success-response', projected,
    outcome: JSON.parse(moon.clientProgramKintoneDeletePreviewOutcomeWire(projected)),
    rowPreviewCid: moon.clientProgramKintoneDeletePreviewOutcomeRowCid(projected),
    responseSha256: moon.clientProgramKintoneDeletePreviewOutcomeResponseSha256(projected)});
}
