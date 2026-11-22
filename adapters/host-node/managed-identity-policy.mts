// Caller-added managed identity requirements. They may strengthen checked and
// Host-mandatory requirements, never supply or weaken mandatory Host policy.
type ManagedIdentityPolicy = Readonly<{publication: boolean; consumer: boolean}>;
const policies = new WeakMap<object, ManagedIdentityPolicy>();

export function prepareManagedIdentityPolicy(options: unknown = {}) {
  const keys = Object.keys(options as object);
  if (keys.some(key => !['publication', 'consumer'].includes(key))) {
    throw new TypeError('Invalid managed identity policy');
  }
  const {publication = false, consumer = false} = options as Readonly<{publication?: unknown; consumer?: unknown}>;
  for (const value of [publication, consumer]) {
    if (typeof value !== 'boolean') {
      throw new TypeError('Invalid managed identity policy');
    }
  }
  const handle = Object.freeze({});
  policies.set(handle, Object.freeze({publication, consumer}) as ManagedIdentityPolicy);
  return handle;
}

export function preparedManagedIdentityPolicy(handle: unknown) {
  if (handle === undefined) {
    return Object.freeze({
      publication: false,
      consumer: false,
    });
  }
  const policy = policies.get(handle as object);
  if (!policy) throw new TypeError('Unprepared managed identity policy');
  return policy;
}
