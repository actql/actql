// Selected first-M1 application DATA, not an admitted Account, permit, key,
// numerical supplier or live-call GO. The existing Host still admits/binds it.
export const firstM1ProviderId = 'models/fixture';
export const firstM1InferEntryId = 'first-m1-infer';
export const firstM1ReviewerId = 'first-m1-reviewer';

export function firstM1AccountConfiguration(principal, modelTaskCid) {
  // Same initial Account name domain, UTF-16 units, NOT UTF-8/wire bytes.
  // Common remains authoritative for normalization, shape and admission.
  if (typeof principal !== 'string' || principal.length === 0 || principal.length > 512 ||
      typeof modelTaskCid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(modelTaskCid)) {
    throw new TypeError('InvalidFirstM1AccountSelection');
  }
  const selected = {any_of: [principal]};
  const connection = {any_of: [firstM1ProviderId]};
  const task = {any_of: [modelTaskCid]};
  // Fixed sorted fields/entries author application input, not an admitted
  // canonical Account. Common still normalizes/validates it and issues its CID.
  return JSON.stringify({account_id: 'first-m1-owner', entries: [
    {connection, entry_id: firstM1InferEntryId, exclusions: [],
      operation: {any_of: ['infer']}, outcome: 'delegate', principal: selected, resource: task},
    {connection, entry_id: 'first-m1-raw', exclusions: [],
      operation: {any_of: ['model_raw_capture']}, outcome: 'allow', principal: selected, resource: task},
    {connection: {all: true}, entry_id: 'first-m1-run', exclusions: [],
      operation: {any_of: ['write']}, outcome: 'allow', principal: selected, resource: {all: true}},
  ], version: 'actql-execution-account-config/0.1'});
}
