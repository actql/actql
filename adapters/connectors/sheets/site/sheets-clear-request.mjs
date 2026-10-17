// Language lifetime only. The existing provider owns every nominal request;
// neither an equal projection nor a saved marker is an approval or a grant.
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {sheetsOwnedResult} from './sheets-owned-request.mjs';

const originals = new WeakMap();
const wire = value => canonicalJson(value, {dataKeys: true});
const fail = code => { throw Object.assign(new Error(code), {code}); };
const freeze = value => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
};
const originalOf = (request, binding, moon) => {
  const original = originals.get(request);
  if (original === undefined || (moon !== undefined && moon !== original.moon)) {
    fail('ForeignSheetsClearRequest');
  }
  sheetsOwnedResult(original.moon, original.moon.sheetsClearRequestCid(
    binding ?? original.binding, original.handle));
  return original;
};

export function projectOwnedSheetsClearRequest(moon, binding, handle) {
  const facts = JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsClearRequestJson(binding, handle)));
  const body = sheetsOwnedResult(moon, moon.sheetsClearRequestBody(binding, handle));
  const request = freeze({...facts, body});
  originals.set(request, Object.freeze({moon, binding, handle}));
  return request;
}

export function prepareOwnedSheetsClearRequest(moon, binding, value, target, marker) {
  const handle = sheetsOwnedResult(moon,
    moon.sheetsClearPrepare(binding, wire(value), wire(target), marker));
  return projectOwnedSheetsClearRequest(moon, binding, handle);
}

export function ownedSheetsClearRequestCid(request, binding) {
  const original = originalOf(request, binding);
  return sheetsOwnedResult(original.moon, original.moon.sheetsClearRequestCid(
    binding ?? original.binding, original.handle));
}

export function ownedSheetsClearOutcome(moon, request, status, body) {
  const original = originalOf(request, undefined, moon);
  return JSON.parse(sheetsOwnedResult(moon, moon.sheetsClearOutcomeJson(
    original.binding, original.handle, status, body)));
}

export function ownedSheetsClearRecoveryEntry(moon, binding, effectId, requests) {
  const handles = requests.map(request => originalOf(request, binding, moon).handle);
  return JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsClearRecoveryEntryJson(binding, effectId, handles)));
}
