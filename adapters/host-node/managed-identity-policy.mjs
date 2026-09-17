// Caller-added managed identity requirements. They may strengthen checked and
// Host-mandatory requirements, never supply or weaken mandatory Host policy.
const policies = new WeakMap();

export function prepareManagedIdentityPolicy(options = {}) {
  const keys = Object.keys(options);
  if (keys.some(key => !['publication', 'consumer'].includes(key))) {
    throw new TypeError('Invalid managed identity policy');
  }
  const {publication = false, consumer = false} = options;
  for (const value of [publication, consumer]) {
    if (typeof value !== 'boolean') {
      throw new TypeError('Invalid managed identity policy');
    }
  }
  const handle = Object.freeze({});
  policies.set(handle, Object.freeze({publication, consumer}));
  return handle;
}

export function preparedManagedIdentityPolicy(handle) {
  if (handle === undefined) {
    return Object.freeze({
      publication: false,
      consumer: false,
    });
  }
  const policy = policies.get(handle);
  if (!policy) throw new TypeError('Unprepared managed identity policy');
  return policy;
}
