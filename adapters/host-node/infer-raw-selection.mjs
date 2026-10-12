// Installation-owned selection, not Run input or a new policy/authority issuer.
// Opaque originals stay with their existing Common owners; only the physical
// installation declaration is snapshotted before continuation's first await.
const fields = ['profile', 'installation', 'probability', 'retention', 'metadata',
  'clock', 'data', 'selectedAt', 'availableUntil', 'deleteBy',
  'extensionCeilingAt', 'metadataDeleteBy', 'selectionAvailable'];

function record(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.values(Object.getOwnPropertyDescriptors(value)).some(d => !('value' in d))) {
    throw new TypeError('InvalidInferRawCaptureSelection');
  }
  return value;
}

export function snapshotModelRawCaptureSelection(value) {
  if (value === undefined) return undefined;
  record(value);
  if (Object.keys(value).sort().join(',') !== [...fields].sort().join(',') ||
      typeof value.selectionAvailable !== 'function') {
    throw new TypeError('InvalidInferRawCaptureSelection');
  }
  const installation = record(value.installation);
  // The existing physical installation contract permits no external SDK.
  // Preserve that absence; it is not an invented SDK or support capability.
  const sdk = installation.sdk === undefined || installation.sdk === null
    ? installation.sdk : Object.freeze({...record(installation.sdk)});
  return Object.freeze({...value,
    installation: Object.freeze({...installation, sdk})});
}
