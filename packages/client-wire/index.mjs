// Structural Client–Host wire admission only. The Host's MoonBit owners decide
// identities, authorization, state transitions, publication and retry.
const cid = /^sha256:[0-9a-f]{64}$/u;
const exact = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') ===
  [...keys].sort().join('\0');
const boundedText = (value, maximum = 256) => typeof value === 'string' &&
  value.length > 0 && value.length <= maximum &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const refs = value => Array.isArray(value) &&
  value.every(item => boundedText(item)) &&
  new Set(value).size === value.length;

export const clientHostOperations = Object.freeze([
  'connect', 'submit', 'attach', 'lookup-request', 'status', 'wait',
  'cancel', 'reconcile', 'read', 'delivery-attempt',
]);

export function validRunRef(value) {
  return exact(value, ['tenantId', 'authorityScopeCid',
    'runDefinitionCid']) && boundedText(value.tenantId) &&
    cid.test(value.authorityScopeCid) && cid.test(value.runDefinitionCid);
}

export function validClientConnection(value) {
  if (value === null || typeof value !== 'object' ||
      Array.isArray(value)) return false;
  const required = ['mode', 'owner', 'consentRefs', 'runners'];
  const allowed = new Set([...required, 'durability', 'movementPolicyRef',
    'cloudConnectionRef']);
  if (required.some(key => !Object.hasOwn(value, key)) ||
      Object.keys(value).some(key => !allowed.has(key)) ||
      !(value.mode === 'remote' && value.owner === 'remote' ||
        value.mode === 'local' && value.owner === 'local' ||
        value.mode === 'hybrid' && ['local', 'cloud'].includes(value.owner)) ||
      !refs(value.consentRefs) || !refs(value.runners) ||
      value.durability !== undefined &&
        !['volatile', 'durable'].includes(value.durability)) return false;
  if (value.mode === 'hybrid') {
    if (!boundedText(value.movementPolicyRef)) return false;
    return value.owner === 'local'
      ? boundedText(value.cloudConnectionRef)
      : value.cloudConnectionRef === undefined && value.runners.length > 0;
  }
  return value.movementPolicyRef === undefined &&
    value.cloudConnectionRef === undefined && value.runners.length === 0;
}

export function validClientBody(operation, body) {
  const bodyKeys = {
    connect: ['connection'],
    submit: ['connection', 'requestId', 'kind', 'input', 'parameters'],
    attach: ['connection', 'ref'],
    'lookup-request': ['connection', 'requestId'],
    status: ['connection', 'ref'],
    wait: ['connection', 'ref', 'until'],
    cancel: ['connection', 'ref'],
    reconcile: ['connection', 'ref'],
    read: ['connection', 'ref', 'resultName', 'format', 'attemptId'],
    'delivery-attempt': ['connection', 'ref', 'resultName', 'attemptId'],
  }[operation];
  if (bodyKeys === undefined || !exact(body, bodyKeys) ||
      !validClientConnection(body.connection)) return false;
  if (operation === 'connect') return true;
  if (operation === 'submit') {
    return boundedText(body.requestId) &&
      (body.kind === 'aql' && exact(body.input, ['text', 'format']) &&
        typeof body.input.text === 'string' &&
        body.input.text.length > 0 && body.input.text.length <= 65536 &&
        !body.input.text.includes('\u0000') &&
        ['json', 'yaml'].includes(body.input.format) ||
        body.kind === 'program' && body.input !== null &&
        typeof body.input === 'object' && !Array.isArray(body.input));
  }
  if (operation === 'lookup-request') return boundedText(body.requestId);
  if (!validRunRef(body.ref)) return false;
  if (operation === 'read') return boundedText(body.resultName) &&
    boundedText(body.attemptId) &&
    ['json', 'jsonl', 'csv'].includes(body.format);
  if (operation === 'delivery-attempt') return boundedText(body.resultName) &&
    boundedText(body.attemptId);
  if (operation === 'wait') return body.until === null ||
    boundedText(body.until, 128);
  return true;
}
