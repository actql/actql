import {checked} from '../../../host-common/runtime-result.mjs';
import {sendRawKintoneWrite} from './kintone-record-write.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const requiredPorts = ['clientProgramKintoneCreateMappingMatchesDeclaration',
  'clientProgramKintoneCreateMappingMatchesRequest', 'clientProgramKintoneCreateExecutionRequest',
  'clientProgramKintoneWriteLimits', 'clientProgramKintoneMutationLimits'];

function originalMapping(moon, mapping, declaration) {
  if (requiredPorts.some(name => typeof moon?.[name] !== 'function')) {
    fail('KintoneCreateExecutionRuntimeUnavailable');
  }
  if (!mapping || !declaration ||
      !moon.clientProgramKintoneCreateMappingMatchesDeclaration(mapping, declaration)) {
    fail('ForeignKintoneCreateMapping');
  }
}

// Mapped values use the same original Form and Mapping. This prepares DATA,
// without provider records, defaults, IDs, insertion decisions or permissions.
export function prepareMappedKintoneCreate({moon, mapping, declaration, bytes, limits}) {
  originalMapping(moon, mapping, declaration);
  if (!(bytes instanceof Uint8Array) || !['maxRequestBytes', 'maxNodes', 'maxDepth',
    'maxFields', 'maxNameUnits', 'maxRows', 'maxIdentityBytes', 'maxComparisonWork']
    .every(name => positive(limits?.[name])) || bytes.byteLength > limits.maxRequestBytes) {
    fail('InvalidKintoneCreateValues');
  }
  const write = moon.clientProgramKintoneWriteLimits(limits.maxFields, limits.maxNameUnits,
    limits.maxNodes, limits.maxDepth, limits.maxRequestBytes, limits.maxRequestBytes);
  const request = moon.clientProgramKintoneMutationLimits(limits.maxRows,
    limits.maxIdentityBytes, limits.maxComparisonWork, limits.maxRequestBytes,
    limits.maxNodes, limits.maxDepth);
  return checked(moon.clientProgramKintoneCreateExecutionRequest(mapping, bytes,
    limits.maxRequestBytes, write, request));
}

// This is a thin caller of the existing physical port, after the Effect Owner's
// original claim. It adds no retries, observations, settlement or cleanup Owner.
export async function sendMappedKintoneCreate({moon, mapping, declaration, request, ...options}) {
  originalMapping(moon, mapping, declaration);
  if (!moon.clientProgramKintoneCreateMappingMatchesRequest(mapping, request)) {
    fail('ForeignKintoneCreateRequest');
  }
  return sendRawKintoneWrite({...options, moon, kind: 'create', request});
}
