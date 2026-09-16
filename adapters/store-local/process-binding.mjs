// Process-local installed Host capability. This pure module has no I/O or Store
// implementation. Wire values cannot construct a binding by copying its fields.
const bindings = new WeakMap();

export function bindProcessStore(context) {
  if (!context || typeof context.callHost !== 'function' ||
      typeof context.session !== 'string' || !context.session ||
      typeof context.run !== 'string' || !context.run) throw new TypeError('InvalidProcessStoreContext');
  const binding = Object.freeze({});
  bindings.set(binding, Object.freeze({callHost: context.callHost, session: context.session, run: context.run}));
  return binding;
}

export function processStoreContext(binding) {
  const value = bindings.get(binding);
  if (!value) throw new TypeError('ForeignProcessStoreBinding');
  return value;
}
