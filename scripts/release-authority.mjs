// A local file, actor name, flag or self-authored approval is not publisher
// authority. Keep old CLI publication closed until the separately protected
// owner-approved executor is connected. This does not establish registry-side
// permission isolation or restrict a credential usable outside these scripts.
export function refuseUnconfiguredPublication() {
  throw new Error('Direct publication is disabled: an external owner-approved release executor is not configured');
}
