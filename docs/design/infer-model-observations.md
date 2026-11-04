# Model response observation compatibility

## Version and provenance boundaries

The reviewed INFER provider contract explicitly adds invocation evidence 0.2
and its embedded capture bundle 0.2. This does not advance every owned format,
the private physical-port ABI, the external SDK version or a package release.
The original invocation/bundle 0.1 schema and pins remain registered unchanged.
Compatibility descriptors select exact branches in the existing publication
validator; no permissive version reader, field repair or schema downgrade is
introduced.

| Original representation | Common structural projection |
| --- | --- |
| Evidence/bundle 0.1 | Historical admitted metadata, original required token observations and fixed historical finish assertion. |
| Evidence/bundle 0.2 | Independently optional provider/usage observations, profile-bound completeness assertion and nullable opaque metadata. |
| Unknown version or mixed embedding | Typed structural refusal. |
| Missing defined 0.2 observation field | Refusal; unavailable means explicit null, not omission. |

The existing `run_publication/model_capture_bundle.mbt` reader preserves the
original record and returns a typed `ModelCaptureObservation`. Historical
`stop` is projected separately from a newly provider-reported finish reason.
Known zero and unobserved token counts remain different. The old paired-token
accessor remains exact for old callers; new consumers use both independent
options. The reader does not rewrite the stored body or issue execution proof.

## Metadata and original Artifact custody

Additional metadata is pure opaque JSON object data under the existing bounded
decoder and response/evidence envelope. Null means unobserved; an empty object
means observed empty. Unknown entries remain data even if their names resemble
complete, precision, retry, policy or a CID. Registered completeness, identity
and authority fields are interpreted separately.

The structural projection borrows the immutable subtree already held by its
evidence. It does not stringify or allocate a second metadata tree. A retained
projection can extend that original evidence's lifetime, and is not treated as
zero custody merely because the getter finished. Raw response Artifact custody,
canonical structured-response Artifact custody and checked output are separate
objects. Existing original Artifact references are reused when they contain the
observed data; their CIDs are never replaced by a hash of an inferred value.
All holdings and simultaneous serialization/Store buffers must be funded by
the existing Model/resource Owners before a physical installation adopts them.

## Responsibility separation

The publication validator checks bounded shape and canonical identity. The
existing Model execution binds original Task, request, Slot, typed key, attempt,
checked output, selected response profile and actual observation. Existing
capture/settlement and authenticated Store Owners establish durable custody and
replay. Current dispatch/egress Owners establish authority; metadata and
structural completeness cannot grant it.

The historical synchronous response carrier emits its exact 0.1 generation
observation. The private current response Owner emits the adopted 0.2 body only
from its retained physical response or an admitted original saved observation.
Replay compares two current records by their complete canonical identity; an
original historical record retains its exact bytes and identity. Unknown usage
remains absent observation, and metadata grants no execution authority.

The owned-version inventory registers only reviewed schema, vector, writer,
replay and caller contexts of this specific compatibility decision. A new or
changed context still requires review; it cannot inherit a file-wide exception.
These consuming changes do not establish ordinary public transport adoption or
Decision execution support. Physical installation must preserve the same
original Owners, retired cursor backing, Slot-to-success indirection, output
uses and pending cleanup responsibility.

The composed caller seals its one original Observation before Local transfers
completed output; its synchronous completion callback does not await an external
observer. Response settlement and the retained Observation/Invocation Store
writers keep their existing asynchronous failure boundaries. Each writer is
retained before the fallible observer and cleanup retries that same writer.
Per-attempt captures use the original scoped holding identity rather than a
second whole-Run capture bundle. These phase observations neither reconstruct
an issuer nor establish successful publication or physical cleanup.
