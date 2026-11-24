type UncheckedContext = {callHost?: unknown; session?: unknown; run?: unknown};
type ProcessStoreContext = Readonly<{callHost: (...args: unknown[]) => unknown; session: string; run: string}>;
declare const processBindingBrand: unique symbol;
export type ProcessStoreBinding = Readonly<{[processBindingBrand]: true}>;

// Process-local installed Host capability. This pure module has no I/O or Store
// implementation. Wire values cannot construct a binding by copying its fields.
const bindings = new WeakMap<object, ProcessStoreContext>();

export function bindProcessStore(context: UncheckedContext | null | undefined) {
  if (!context || typeof context.callHost !== 'function' ||
      typeof context.session !== 'string' || !context.session ||
      typeof context.run !== 'string' || !context.run) throw new TypeError('InvalidProcessStoreContext');
  const binding = Object.freeze({}) as ProcessStoreBinding;
  bindings.set(binding, Object.freeze({callHost: context.callHost as ProcessStoreContext['callHost'], session: context.session, run: context.run}));
  return binding;
}

export function processStoreContext(binding: unknown) {
  const value = bindings.get(binding as object);
  if (!value) throw new TypeError('ForeignProcessStoreBinding');
  return value;
}
