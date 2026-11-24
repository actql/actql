import {types as nodeTypes} from 'node:util';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';

// One physical credential-journal/signing implementation for installed Row
// Sites. The existing Site validates its selected profile/key and authorizes
// each operation before calling sign; this private Host port is not a grant.
// Preserve the original scope members/task attempt and same journal custody.
export function ownCredentialAcquisitionLimits(input: unknown) {
  if (input === undefined) return undefined;
  if (input === null || typeof input !== 'object' || nodeTypes.isProxy(input)) {
    fail('InvalidRowSourceCredentialAcquisitionLimits');
  }
  const descriptors = Object.getOwnPropertyDescriptors(input);
  if (Reflect.ownKeys(descriptors).length !== 2 ||
      ['maxBindings', 'maxSecretBytes'].some(name => {
        const field = descriptors[name];
        return !field || !Object.hasOwn(field, 'value') ||
          !Number.isSafeInteger(field.value) || field.value <= 0 || field.value > 2147483647;
      })) fail('InvalidRowSourceCredentialAcquisitionLimits');
  return Object.freeze({maxBindings: descriptors.maxBindings.value as number,
    maxSecretBytes: descriptors.maxSecretBytes.value as number});
}

// Trusted installing code selects only an existing physical presentation.
// This is not profile DATA, a header name, an auth provider or a grant. The
// physical binding still validates its original registration/auth dependency.
export function ownCredentialSecretPresentation(options: unknown): 'bearer' | 'kintone-api-token' | undefined {
  if (options === null || typeof options !== 'object' || nodeTypes.isProxy(options)) {
    fail('InvalidRowSourceSecretPresentation');
  }
  const field = Object.getOwnPropertyDescriptor(options, 'secretPresentation');
  if (field === undefined) return undefined;
  if (!Object.hasOwn(field, 'value') ||
      !['bearer', 'kintone-api-token'].includes(field.value)) {
    fail('InvalidRowSourceSecretPresentation');
  }
  return field.value;
}
