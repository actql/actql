// Trusted Host policy for managed logical identity. Program text and connector
// implementations receive no constructor for this opaque configuration.
const policies = new WeakMap();

export function prepareManagedIdentityPolicy({
  publication = false,
  consumer = false,
  hostPolicy = false,
} = {}) {
  for (const value of [publication, consumer, hostPolicy]) {
    if (typeof value !== 'boolean') {
      throw new TypeError('Invalid managed identity policy');
    }
  }
  const handle = Object.freeze({});
  policies.set(handle, Object.freeze({publication, consumer, hostPolicy}));
  return handle;
}

export function preparedManagedIdentityPolicy(handle) {
  if (handle === undefined) {
    return Object.freeze({
      publication: false,
      consumer: false,
      hostPolicy: false,
    });
  }
  const policy = policies.get(handle);
  if (!policy) throw new TypeError('Unprepared managed identity policy');
  return policy;
}
