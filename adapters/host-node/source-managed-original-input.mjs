import {snapshotInitialControlHostInput} from './initial-control-host-input.mjs';

// Reuse the existing pure bounded own-DATA traversal, not its installation
// admission or initial-control credits. The actual Source owner must already
// cover raw acquisition, the first ownKeys, rejection and every retained alias
// under its separate Source phase before calling this captured reader.
//
// The result is DATA only. It does not validate the public submission grammar,
// issue a child, select a Program, authorize I/O or acknowledge any lifetime.
// Preserve all fields and original aliases so the selected recipe can refuse
// unsupported valid inputs, while the unchanged SDK owns semantic validation.
export function readSourceManagedOriginalInput(kind, rawInput, rawOptions, explicitLimits) {
  try {
    return snapshotInitialControlHostInput({kind, input: rawInput, options: rawOptions}, explicitLimits);
  } catch (cause) {
    throw Object.assign(new Error('NodeSourceManagedInputUnavailable', {cause}),
      {code: 'NodeSourceManagedInputUnavailable'});
  }
}
