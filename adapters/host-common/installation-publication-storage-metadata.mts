// Same-Store physical observation to Common DATA. This is a private Host
// assembly helper, not a Store issuer or installation publication admission.
import {checked} from './runtime-result.mjs';

import type {SynchronousRuntimeData} from './runtime-result.mjs';
import type {openLocalPublicationStore} from '../store-local/publication-store.mjs';

type Store = Pick<Awaited<ReturnType<typeof openLocalPublicationStore>>, 'status' |
  'observeOriginalInstallationPublicationStorageBinding' | 'originalInstallationPublicationStorageBindingEvidence'>;
type Runtime = Readonly<{
  clientInstallationPublicationStoragePrepare(storeContractWire: string, storeAuthorityCid: string, keyGenerationCid: string,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientInstallationPublicationStorageWire(binding: unknown): string;
  clientInstallationPublicationStorageCid(binding: unknown): string;
}>;
type Ports = Readonly<{
  Prepare: Runtime['clientInstallationPublicationStoragePrepare'];
  Wire: Runtime['clientInstallationPublicationStorageWire'];
  Cid: Runtime['clientInstallationPublicationStorageCid'];
}>;
type Bounds = Readonly<Record<(typeof limitNames)[number], number>>;
type StoreFields = Readonly<Record<(typeof fieldNames)[number], string>>;
type StorageMetadata = Readonly<{
  observe(): Promise<StorageMetadata>;
  binding(): unknown;
  wire(): string;
  cid(): string;
  forget(): boolean;
}>;

const fail = (code: string): never => {throw Object.assign(new Error(code), {code});};
const fieldNames = Object.freeze(['storeContractWire', 'storeAuthorityCid',
  'keyGenerationCid', 'privateNamespace'] as const);
const limitNames = Object.freeze(['maxWireBytes', 'maxNodes', 'maxDepth'] as const);

function data<Name extends string>(value: unknown, names: readonly Name[]): Record<Name, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    fail('InvalidInstallationPublicationStorageMetadata');
  }
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const keys = Reflect.ownKeys(descriptors);
  if (keys.length !== names.length || keys.some(key => !names.includes(key as Name))) {
    fail('InvalidInstallationPublicationStorageMetadata');
  }
  return Object.fromEntries(names.map(name => {
    const descriptor = descriptors[name];
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) {
      fail('InvalidInstallationPublicationStorageMetadata');
    }
    return [name, descriptor.value];
  })) as Record<Name, unknown>;
}

// The caller supplies the actual private bootstrap's Store reference and its
// original synchronous current fence. A fake object cannot become authority by
// passing this DATA helper; the enclosing Host still proves original membership.
export function createInstallationPublicationStorageMetadata(moon: Runtime | undefined, store: Store | undefined,
  limits: Bounds, assertCurrent: (() => SynchronousRuntimeData) | undefined): StorageMetadata {
  let bounds: Bounds | undefined = data(limits, limitNames) as Bounds;
  if (limitNames.some(name => !Number.isSafeInteger(bounds![name]) ||
      bounds![name] < 1 || bounds![name] > 2147483647) ||
      typeof assertCurrent !== 'function') {
    fail('InvalidInstallationPublicationStorageMetadata');
  }
  let ports: Ports | undefined = Object.fromEntries((['Prepare', 'Wire', 'Cid'] as const).map(name =>
    [name, moon?.[('clientInstallationPublicationStorage' + name) as keyof Runtime]])) as unknown as Ports;
  let observe = store?.observeOriginalInstallationPublicationStorageBinding;
  let evidence = store?.originalInstallationPublicationStorageBindingEvidence;
  let status = store?.status;
  if (Object.values(ports).some(port => typeof port !== 'function') ||
      [observe, evidence, status].some(port => typeof port !== 'function')) {
    fail('InstallationPublicationStorageRuntimeUnavailable');
  }
  let pending = false, forgotten = false, original: unknown, binding: unknown, fields: StoreFields | undefined;
  const own = (receiver: unknown) => {
    if (receiver !== view) fail('ForeignInstallationPublicationStorageMetadata');
    if (forgotten) fail('InstallationPublicationStorageMetadataForgotten');
  };
  const current = () => Reflect.apply(assertCurrent!, undefined, []);
  const originalFields = (handle: unknown) => {
    const found = data(Reflect.apply(evidence!, store, [handle]), fieldNames) as StoreFields;
    if (fieldNames.some(name => typeof found[name] !== 'string') ||
        found.privateNamespace !== 'publication-private') {
      fail('InvalidInstallationPublicationStorageMetadata');
    }
    return found;
  };
  const sameFields = (found: StoreFields) => fieldNames.every(name => fields![name] === found[name]);
  const read = (receiver: unknown) => {
    own(receiver);
    current();
    if (binding === undefined) fail('InstallationPublicationStorageUnobserved');
    if (!sameFields(originalFields(original))) fail('InstallationPublicationStorageChanged');
    return binding;
  };
  const view: StorageMetadata = Object.freeze({
    async observe() {
      own(this);
      if (pending) fail('InstallationPublicationStorageObservationPending');
      pending = true;
      try {
        current();
        const handle = await Reflect.apply(observe!, store, []);
        current();
        const found = originalFields(handle);
        if (binding !== undefined) {
          if (handle !== original || !sameFields(found)) {
            fail('InstallationPublicationStorageChanged');
          }
        } else {
          const admitted = checked(Reflect.apply(ports!.Prepare, moon,
            [found.storeContractWire, found.storeAuthorityCid, found.keyGenerationCid,
              bounds!.maxWireBytes, bounds!.maxNodes, bounds!.maxDepth]));
          // No await follows the current and same-original checks before
          // assigning this one borrowed DATA value. A closed Store refuses.
          current();
          originalFields(handle);
          original = handle; fields = found; binding = admitted;
        }
        return view;
      } finally { pending = false; }
    },
    binding() { return read(this); },
    wire() { const value = read(this); return Reflect.apply(ports!.Wire, moon, [value]); },
    cid() { const value = read(this); return Reflect.apply(ports!.Cid, moon, [value]); },
    // Alias retirement only AFTER the actual same Store reports closed.
    // This does not close it or acknowledge another Owner's physical duty.
    forget() {
      own(this);
      if (pending || Reflect.apply(status!, store, []).closed !== true) return false;
      forgotten = true;
      original = undefined; binding = undefined; fields = undefined;
      bounds = undefined; ports = undefined;
      observe = undefined; evidence = undefined; status = undefined;
      moon = undefined; store = undefined; assertCurrent = undefined;
      return true;
    },
  });
  return view;
}
