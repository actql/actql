// Language lifetime only: immutable physical projections retain their original
// provider handle privately. No handle is serialized or rebuilt from a DTO.
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
const originals = new WeakMap();
const wire = value => canonicalJson(value, {dataKeys: true});
const fail = code => { throw Object.assign(new Error(code), {code}); };

export function sheetsOwnedResult(moon, result) {
  try { return checked(result); }
  catch (failure) {
    if (failure?.code !== 'MoonBitHostFailure') throw failure;
    const projected = JSON.parse(moon.sheetsRangeFailureJson(failure.cause));
    throw Object.assign(new Error(projected.code, {cause: projected.refused}), {code: projected.code});
  }
}

const freeze = value => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
};

export function projectOwnedSheetsRequest(moon, binding, handle) {
  const facts = JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsRangeRequestJson(binding, handle)));
  // Borrow the exact body separately: wrapping it in another JSON string would
  // duplicate/escape a request-sized payload and narrow the original limit.
  const body = sheetsOwnedResult(moon, moon.sheetsRangeRequestBody(binding, handle));
  const request = freeze({...facts, body});
  originals.set(request, Object.freeze({moon, binding, handle}));
  return request;
}

export function prepareOwnedSheetsRequest(moon, binding, value, target) {
  const handle = sheetsOwnedResult(moon,
    moon.sheetsRangePrepare(binding, wire(value), wire(target)));
  return projectOwnedSheetsRequest(moon, binding, handle);
}

export function ownedSheetsRequestCid(request, binding) {
  const original = originals.get(request);
  if (original === undefined) fail('ForeignSheetsRangeRequest');
  const {moon, handle} = original;
  // The connector, not JS record equality, admits the original nominal owner.
  return sheetsOwnedResult(moon,
    moon.sheetsRangeRequestCid(binding ?? original.binding, handle));
}
