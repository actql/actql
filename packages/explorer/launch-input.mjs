import {validRunRef} from '@actql/client-wire';

const refuse = () => {throw Object.assign(new Error('ExplorerInvalidLaunchInput'),
  {code: 'ExplorerInvalidLaunchInput'});};
const exact = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).length === keys.length &&
  keys.every(key => Object.hasOwn(value, key));

// Presentation input only, not an execution request, permission or saved Plan.
// A flat text input keeps authoring bytes separate from its eventual SDK Plan.
export function copyExplorerLaunchInput(value, maxBytes = 65536) {
  if (value === null || value === undefined) return null;
  let copy;
  if (exact(value, ['kind', 'text', 'format']) && value.kind === 'program' &&
      typeof value.text === 'string' && value.text.length > 0 &&
      value.text.length <= maxBytes && ['sql', 'aql', 'aql-text', 'program'].includes(value.format)) {
    copy = {kind: 'program', text: value.text, format: value.format};
  } else if (exact(value, ['kind', 'ref']) && value.kind === 'run' && validRunRef(value.ref)) {
    copy = {kind: 'run', ref: Object.freeze({...value.ref})};
  } else {refuse();}
  // Reuse the existing Gateway request-byte ceiling, including this envelope.
  if (new TextEncoder().encode(JSON.stringify(copy)).byteLength > maxBytes) refuse();
  return Object.freeze(copy);
}
