import type {remoteBundleControl} from '../host-common/remote-bundle-control.mjs';

type BundleControl = ReturnType<typeof remoteBundleControl>;
type StoredBundle = Readonly<{
  manifest: unknown;
  record: unknown;
  artifactPath: string;
  reclaimPending: boolean;
}>;
type ReadBundle = (cid: string, control: BundleControl) => StoredBundle | undefined;
type ReadBundleAsync = (cid: string, control: BundleControl) => Promise<StoredBundle | undefined>;

export type RuntimeBundleOperationsStore = Readonly<{
  install(componentPath: string, envelope: object, control: BundleControl): Promise<StoredBundle>;
  list(control: BundleControl): readonly StoredBundle[];
  active(control: BundleControl): StoredBundle | undefined;
  recover(control: BundleControl): Promise<readonly StoredBundle[]>;
  activate: ReadBundle;
  rollback: ReadBundle;
  drain: ReadBundle;
  reclaim: ReadBundleAsync;
  verify: ReadBundleAsync;
  inspect: ReadBundle;
}>;

type Operation = Readonly<{
  kind: string;
  componentPath?: string;
  envelope?: unknown;
  runtimeBundleCid?: string;
}>;
type OperationOptions = Readonly<{
  store: RuntimeBundleOperationsStore;
  control: BundleControl;
  operation: Operation;
}>;

const fail: (code: string) => never = code => {
  throw Object.assign(new Error(code), {code});
};
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;

function snapshot(value: StoredBundle | undefined, control: BundleControl) {
  if (value === undefined) return undefined;
  return Object.freeze({
    runtimeBundleCid: control.identity(value.manifest),
    manifest: control.json(value.manifest),
    artifactPath: value.artifactPath,
    state: Object.freeze([...control.recordProjection(value.record)]),
    reclaimPending: value.reclaimPending,
  });
}

export async function runRuntimeBundleOperation({
  store,
  control,
  operation,
}: OperationOptions = {} as OperationOptions) {
  if (store === null || typeof store !== 'object' ||
      control === null || typeof control !== 'object' ||
      operation === null || typeof operation !== 'object' ||
      !text(operation.kind)) {
    fail('InvalidRemoteBundleOperation');
  }
  if (operation.kind === 'install') {
    if (!text(operation.componentPath) ||
        operation.envelope === null ||
        typeof operation.envelope !== 'object') {
      fail('InvalidRemoteBundleOperation');
    }
    return snapshot(await store.install(
      operation.componentPath,
      operation.envelope,
      control,
    ), control);
  }
  if (operation.kind === 'list') {
    return Object.freeze(store.list(control).map(value =>
      snapshot(value, control)));
  }
  if (operation.kind === 'active') {
    return snapshot(store.active(control), control);
  }
  if (operation.kind === 'recover') {
    return Object.freeze((await store.recover(control)).map(value =>
      snapshot(value, control)));
  }
  if (!text(operation.runtimeBundleCid)) {
    fail('InvalidRemoteBundleOperation');
  }
  const runtimeBundleCid = operation.runtimeBundleCid;
  if (operation.kind === 'activate') {
    return snapshot(store.activate(runtimeBundleCid, control), control);
  }
  if (operation.kind === 'rollback') {
    return snapshot(store.rollback(runtimeBundleCid, control), control);
  }
  if (operation.kind === 'drain') {
    return snapshot(store.drain(runtimeBundleCid, control), control);
  }
  if (operation.kind === 'reclaim') {
    return snapshot(await store.reclaim(runtimeBundleCid, control), control);
  }
  if (operation.kind === 'verify') {
    return snapshot(await store.verify(runtimeBundleCid, control), control);
  }
  if (operation.kind === 'inspect') {
    return snapshot(store.inspect(runtimeBundleCid, control), control);
  }
  fail('UnsupportedRemoteBundleOperation');
}
