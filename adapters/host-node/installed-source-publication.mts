import type {installedConnectorFor} from './installed-connectors.mjs';

type PublicationBindings = Readonly<{
  root: string;
  principalId: string;
  moon: unknown;
  installation: ReturnType<typeof installedConnectorFor>;
  profile: unknown;
  resolveSecret?: unknown;
  runtimeBundleCid?: string;
  providerMoon?: unknown;
}>;
type OriginalPublication = {
  path: unknown;
  requestId: string;
  signal?: AbortSignal;
  phase: 'preparing' | 'active' | 'retiring';
  used: boolean;
  bindings: PublicationBindings | undefined;
  profileWire: string | undefined;
};

// The installed Source keeps this one request registry and supplies the
// profile reader it already uses to read and select the installed adapter.
export function createInstalledSourcePublicationRequests(readProfile: (path: unknown) => Promise<unknown>) {
  // Provenance of this explicit Host call, not a grant or a durable preparation.
  // Only publishInstalledSourceProfile issues a member. Cold DATA and another
  // publication with equal configuration cannot recreate the original request.
  const publicationRequests = new WeakMap<object, OriginalPublication>();
  const publicationBindings = Object.freeze(['root', 'principalId', 'moon',
    'installation', 'profile', 'resolveSecret', 'runtimeBundleCid', 'providerMoon'] as const);

  const publicationFailure: (code: string) => never = code => {
    throw Object.assign(new TypeError(code), {code});
  };

  function originalPublicationRequest(request: unknown) {
    const original = request !== null && typeof request === 'object'
      ? publicationRequests.get(request) : undefined;
    if (original === undefined) publicationFailure('ForeignInstalledSourcePublication');
    return original;
  }

  // Read-only lookup, including while original cleanup is pending. This UUID is
  // the Host's original request coordinate, never an issuer or a permission.
  function installedSourcePublicationRequestId(request: unknown) {
    return originalPublicationRequest(request).requestId;
  }

  // A synchronous fence for the exact trusted installer pair. In particular it
  // can follow an awaited Account/Site/egress/resource check immediately before
  // the same journal claim/send, with no new await or caller boolean admission.
  // Those checks and physical cleanup are independent duties of that Site.
  function assertInstalledSourcePublicationRequest(request: unknown, originals: unknown) {
    const original = originalPublicationRequest(request);
    if (original.phase !== 'active') publicationFailure('InstalledSourcePublicationClosed');
    original.signal?.throwIfAborted();
    if (originals === null || typeof originals !== 'object') {
      publicationFailure('ForeignInstalledSourcePublicationBinding');
    }
    const descriptors = Object.getOwnPropertyDescriptors(originals);
    for (const name of publicationBindings) {
      const descriptor = descriptors[name];
      // Optional runtime fields may be absent only when the original was too.
      if (descriptor === undefined && original.bindings![name] === undefined) continue;
      if (descriptor === undefined || !Object.hasOwn(descriptor, 'value') ||
          descriptor.value !== original.bindings![name]) {
        publicationFailure('ForeignInstalledSourcePublicationBinding');
      }
    }
    original.used = true;
  }

  // Observe only this request's original Host profile. This is not Account,
  // issuer, Site generation, credential, egress or funding authorization. The
  // physical adapter must still check all of those, and then use the synchronous
  // original-pair fence above. No replacement profile is returned to the caller.
  async function observeInstalledSourcePublicationCurrent(request: unknown, originals: unknown) {
    assertInstalledSourcePublicationRequest(request, originals);
    const original = originalPublicationRequest(request);
    try {
      const observed = await readProfile(original.path);
      assertInstalledSourcePublicationRequest(request, originals);
      if (JSON.stringify(observed) !== original.profileWire) {
        publicationFailure('InstalledSourcePublicationChanged');
      }
    } catch (cause) {
      // Observed replacement/failure cannot reopen this request if a caller later
      // restores equal bytes. Keep the original aliases for its cleanup only.
      original.phase = 'retiring';
      throw cause;
    }
  }

  return {publicationRequests, installedSourcePublicationRequestId,
    assertInstalledSourcePublicationRequest, observeInstalledSourcePublicationCurrent};
}
