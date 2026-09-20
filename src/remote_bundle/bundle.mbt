///|
pub(all) enum RemoteBundleIssue {
  InvalidBundle
  BundleIdentityMismatch
  InvalidBundleSignature
  InvalidBundleState
  BundleOwnerLimit
  BundleTransitionNotDurable
} derive(Eq, Debug)

///|
pub(all) enum RemoteBundlePhase {
  BundleInstalled
  BundleActive
  BundleDraining
  BundleReclaimed
} derive(Eq, Debug)

///|
struct RemoteBundleManifest {
  issuer_authority : String
  bundle_name : String
  revision : String
  target_triple : String
  component_cid : String
  component_bytes : Int64
  connector_registration : String
  connector_revision : String
  strategy_revision : String
  runtime_bundle_cid : String
}

///|
/// Canonical signature metadata for one admitted bundle manifest. The actual
/// private-key operation and public-key verification are environment
/// operations; this value owns the scheme, preimage and authority binding.
struct RemoteBundleSignatureEnvelope {
  manifest : RemoteBundleManifest
  key_id : String
  signature : String
}

///|
struct RemoteBundleRecord {
  manifest : RemoteBundleManifest
  mut record_revision : Int
  mut phase : RemoteBundlePhase
  mut owners : Int
}

///|
struct RemoteBundleTransition {
  record : RemoteBundleRecord
  before_revision : Int
  before_phase : RemoteBundlePhase
  before_owners : Int
  after_revision : Int
  after_phase : RemoteBundlePhase
  after_owners : Int
}

///|
fn valid_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn bounded(value : String, maximum : Int) -> Bool {
  !value.is_empty() && value.length() <= maximum
}

///|
fn valid_manifest(value : RemoteBundleManifest) -> Bool {
  bounded(value.issuer_authority, 512) &&
  bounded(value.bundle_name, 512) &&
  bounded(value.revision, 512) &&
  bounded(value.target_triple, 512) &&
  valid_cid(value.component_cid) &&
  value.component_bytes >= 0L &&
  bounded(value.connector_registration, 512) &&
  bounded(value.connector_revision, 512) &&
  bounded(value.strategy_revision, 512)
}

///|
fn manifest_body(
  value : RemoteBundleManifest,
) -> Result[String, RemoteBundleIssue] {
  let writer = @encode.writer(16384, 24, 2) catch {
    _ => return Err(InvalidBundle)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "bundle_name")
    @encode.string_value(writer, value.bundle_name)
    @encode.key(writer, "component_bytes")
    @encode.string_value(writer, value.component_bytes.to_string())
    @encode.key(writer, "component_cid")
    @encode.string_value(writer, value.component_cid)
    @encode.key(writer, "connector_registration")
    @encode.string_value(writer, value.connector_registration)
    @encode.key(writer, "connector_revision")
    @encode.string_value(writer, value.connector_revision)
    @encode.key(writer, "issuer_authority")
    @encode.string_value(writer, value.issuer_authority)
    @encode.key(writer, "revision")
    @encode.string_value(writer, value.revision)
    @encode.key(writer, "strategy_revision")
    @encode.string_value(writer, value.strategy_revision)
    @encode.key(writer, "target_triple")
    @encode.string_value(writer, value.target_triple)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-runtime-bundle/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidBundle)
  }
}

///|
fn manifest_identity(
  value : RemoteBundleManifest,
) -> Result[String, RemoteBundleIssue] {
  let body = match manifest_body(value) {
    Ok(body) => body
    Err(issue) => return Err(issue)
  }
  match @sha.text_hex(body) {
    Ok(digest) => Ok("sha256:" + digest)
    Err(_) => Err(InvalidBundle)
  }
}

///|
pub fn prepare_bundle_manifest(
  issuer_authority : String,
  bundle_name : String,
  revision : String,
  target_triple : String,
  component_cid : String,
  component_bytes : Int64,
  connector_registration : String,
  connector_revision : String,
  strategy_revision : String,
) -> Result[RemoteBundleManifest, RemoteBundleIssue] {
  let pending : RemoteBundleManifest = {
    issuer_authority,
    bundle_name,
    revision,
    target_triple,
    component_cid,
    component_bytes,
    connector_registration,
    connector_revision,
    strategy_revision,
    runtime_bundle_cid: "pending",
  }
  if !valid_manifest(pending) {
    return Err(InvalidBundle)
  }
  let identity = match manifest_identity(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, runtime_bundle_cid: identity, })
}

///|
pub fn bundle_manifest_identity(value : RemoteBundleManifest) -> String {
  value.runtime_bundle_cid
}

///|
pub fn bundle_manifest_json(
  value : RemoteBundleManifest,
) -> Result[String, RemoteBundleIssue] {
  if !valid_manifest(value) {
    return Err(InvalidBundle)
  }
  let identity = match manifest_identity(value) {
    Ok(result) => result
    Err(issue) => return Err(issue)
  }
  if identity != value.runtime_bundle_cid {
    return Err(BundleIdentityMismatch)
  }
  manifest_body(value)
}

///|
priv suberror RemoteBundleDecodeStop {
  RemoteBundleDecodeStop
}

///|
fn[T] decoded(
  value : Result[T, @decode.Issue],
) -> T raise RemoteBundleDecodeStop {
  match value {
    Ok(result) => result
    Err(_) => raise RemoteBundleDecodeStop
  }
}

///|
fn field(
  object : @decode.ObjectView,
  key : String,
) -> String raise RemoteBundleDecodeStop {
  decoded(@decode.text(decoded(@decode.required(object, key))))
}

///|
fn nonnegative_int64(value : String) -> Int64 raise RemoteBundleDecodeStop {
  if value.is_empty() {
    raise RemoteBundleDecodeStop
  }
  let mut result = 0L
  for index = 0; index < value.length(); index = index + 1 {
    let digit = value[index].to_int() - 48
    if digit < 0 ||
      digit > 9 ||
      result > (9223372036854775807L - digit.to_int64()) / 10L {
      raise RemoteBundleDecodeStop
    }
    result = result * 10L + digit.to_int64()
  }
  result
}

///|
pub fn admit_bundle_manifest_json(
  body : String,
  claimed_runtime_bundle_cid : String,
) -> Result[RemoteBundleManifest, RemoteBundleIssue] {
  try {
    let node = match
      @source.parse_json_bytes(@utf8.encode(body), {
        max_input_bytes: 16384,
        max_nodes: 24,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise RemoteBundleDecodeStop
    }
    let cursor = decoded(
      @decode.admit(node, {
        max_nodes: 24,
        max_depth: 2,
        max_string_bytes: 16384,
        max_total_string_bytes: 16384,
      }),
    )
    let object = decoded(
      @decode.closed_object(cursor, [
        "bundle_name", "component_bytes", "component_cid", "connector_registration",
        "connector_revision", "issuer_authority", "revision", "strategy_revision",
        "target_triple", "version",
      ]),
    )
    if field(object, "version") != "actql-remote-runtime-bundle/0.1" {
      raise RemoteBundleDecodeStop
    }
    let manifest = match
      prepare_bundle_manifest(
        field(object, "issuer_authority"),
        field(object, "bundle_name"),
        field(object, "revision"),
        field(object, "target_triple"),
        field(object, "component_cid"),
        nonnegative_int64(field(object, "component_bytes")),
        field(object, "connector_registration"),
        field(object, "connector_revision"),
        field(object, "strategy_revision"),
      ) {
      Ok(value) => value
      Err(_) => raise RemoteBundleDecodeStop
    }
    if bundle_manifest_json(manifest) != Ok(body) {
      raise RemoteBundleDecodeStop
    }
    if manifest.runtime_bundle_cid != claimed_runtime_bundle_cid {
      Err(BundleIdentityMismatch)
    } else {
      Ok(manifest)
    }
  } catch {
    RemoteBundleDecodeStop => Err(InvalidBundle)
  }
}

///|
pub fn bundle_manifest_projection(
  value : RemoteBundleManifest,
) -> Array[String] {
  [
    value.runtime_bundle_cid,
    value.issuer_authority,
    value.bundle_name,
    value.revision,
    value.target_triple,
    value.component_cid,
    value.component_bytes.to_string(),
    value.connector_registration,
    value.connector_revision,
    value.strategy_revision,
  ]
}

///|
fn valid_signature(value : String) -> Bool {
  if value.length() != 86 {
    return false
  }
  for character in value.iter() {
    if !((character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      character == '-' ||
      character == '_') {
      return false
    }
  }
  let terminal = value[value.length() - 1]
  terminal == 'A' || terminal == 'Q' || terminal == 'g' || terminal == 'w'
}

///|
pub fn bundle_signature_preimage(
  manifest : RemoteBundleManifest,
) -> Result[Bytes, RemoteBundleIssue] {
  let body = match bundle_manifest_json(manifest) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(
    @utf8.encode(
      "actql-remote-runtime-bundle-signature/0.1\u{0000}" +
      manifest.runtime_bundle_cid +
      "\u{0000}" +
      body,
    ),
  )
}

///|
pub fn prepare_bundle_signature_envelope(
  manifest : RemoteBundleManifest,
  key_id : String,
  signature : String,
) -> Result[RemoteBundleSignatureEnvelope, RemoteBundleIssue] {
  if !bounded(key_id, 512) || !valid_signature(signature) {
    return Err(InvalidBundleSignature)
  }
  match bundle_signature_preimage(manifest) {
    Ok(_) => Ok({ manifest, key_id, signature, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn admit_bundle_signature_envelope(
  version : String,
  key_id : String,
  runtime_bundle_cid : String,
  body : String,
  signature : String,
) -> Result[RemoteBundleSignatureEnvelope, RemoteBundleIssue] {
  if version != "actql-remote-runtime-bundle-signature/0.1" {
    return Err(InvalidBundleSignature)
  }
  let manifest = match admit_bundle_manifest_json(body, runtime_bundle_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  prepare_bundle_signature_envelope(manifest, key_id, signature)
}

///|
pub fn bundle_signature_envelope_projection(
  envelope : RemoteBundleSignatureEnvelope,
) -> Array[String] {
  [
    "actql-remote-runtime-bundle-signature/0.1",
    envelope.key_id,
    envelope.manifest.runtime_bundle_cid,
    bundle_manifest_json(envelope.manifest).unwrap(),
    envelope.signature,
    envelope.manifest.issuer_authority,
  ]
}

///|
pub fn bundle_signature_envelope_manifest(
  envelope : RemoteBundleSignatureEnvelope,
) -> RemoteBundleManifest {
  envelope.manifest
}

///|
fn phase_code(value : RemoteBundlePhase) -> Int {
  match value {
    BundleInstalled => 0
    BundleActive => 1
    BundleDraining => 2
    BundleReclaimed => 3
  }
}

///|
fn code_phase(value : Int) -> RemoteBundlePhase? {
  match value {
    0 => Some(BundleInstalled)
    1 => Some(BundleActive)
    2 => Some(BundleDraining)
    3 => Some(BundleReclaimed)
    _ => None
  }
}

///|
pub fn open_bundle_record(value : RemoteBundleManifest) -> RemoteBundleRecord {
  { manifest: value, record_revision: 0, phase: BundleInstalled, owners: 0, }
}

///|
fn transition(
  record : RemoteBundleRecord,
  phase : RemoteBundlePhase,
  owners : Int,
) -> Result[RemoteBundleTransition, RemoteBundleIssue] {
  if record.record_revision < 0 || record.owners < 0 || owners < 0 {
    return Err(InvalidBundleState)
  }
  Ok({
    record,
    before_revision: record.record_revision,
    before_phase: record.phase,
    before_owners: record.owners,
    after_revision: record.record_revision + 1,
    after_phase: phase,
    after_owners: owners,
  })
}

///|
pub fn prepare_bundle_activate(
  record : RemoteBundleRecord,
) -> Result[RemoteBundleTransition, RemoteBundleIssue] {
  if record.phase != BundleInstalled && record.phase != BundleDraining {
    return Err(InvalidBundleState)
  }
  transition(record, BundleActive, record.owners)
}

///|
pub fn prepare_bundle_drain(
  record : RemoteBundleRecord,
) -> Result[RemoteBundleTransition, RemoteBundleIssue] {
  if record.phase != BundleActive {
    return Err(InvalidBundleState)
  }
  transition(record, BundleDraining, record.owners)
}

///|
pub fn prepare_bundle_retain(
  record : RemoteBundleRecord,
  max_owners : Int,
) -> Result[RemoteBundleTransition, RemoteBundleIssue] {
  if max_owners < 0 || record.phase != BundleActive {
    return Err(InvalidBundleState)
  }
  if record.owners >= max_owners {
    return Err(BundleOwnerLimit)
  }
  transition(record, record.phase, record.owners + 1)
}

///|
pub fn prepare_bundle_release(
  record : RemoteBundleRecord,
) -> Result[RemoteBundleTransition, RemoteBundleIssue] {
  if record.phase == BundleReclaimed || record.owners <= 0 {
    return Err(InvalidBundleState)
  }
  transition(record, record.phase, record.owners - 1)
}

///|
pub fn prepare_bundle_reclaim(
  record : RemoteBundleRecord,
) -> Result[RemoteBundleTransition, RemoteBundleIssue] {
  if record.owners != 0 ||
    (record.phase != BundleInstalled && record.phase != BundleDraining) {
    return Err(InvalidBundleState)
  }
  transition(record, BundleReclaimed, 0)
}

///|
pub fn bundle_transition_projection(
  value : RemoteBundleTransition,
) -> (Array[String], Array[String]) {
  (
    [
      value.before_revision.to_string(),
      phase_code(value.before_phase).to_string(),
      value.before_owners.to_string(),
    ],
    [
      value.after_revision.to_string(),
      phase_code(value.after_phase).to_string(),
      value.after_owners.to_string(),
    ],
  )
}

///|
pub fn bundle_transition_key(value : RemoteBundleTransition) -> String {
  value.record.manifest.runtime_bundle_cid
}

///|
pub fn commit_bundle_transition(
  value : RemoteBundleTransition,
  durable : Bool,
) -> Result[RemoteBundleRecord, RemoteBundleIssue] {
  if !durable {
    return Err(BundleTransitionNotDurable)
  }
  let record = value.record
  if record.record_revision == value.after_revision &&
    record.phase == value.after_phase &&
    record.owners == value.after_owners {
    return Ok(record)
  }
  if record.record_revision != value.before_revision ||
    record.phase != value.before_phase ||
    record.owners != value.before_owners {
    return Err(InvalidBundleState)
  }
  record.record_revision = value.after_revision
  record.phase = value.after_phase
  record.owners = value.after_owners
  Ok(record)
}

///|
pub fn bundle_record_projection(value : RemoteBundleRecord) -> Array[String] {
  [
    value.record_revision.to_string(),
    phase_code(value.phase).to_string(),
    value.owners.to_string(),
  ]
}

///|
pub fn restore_bundle_record(
  manifest : RemoteBundleManifest,
  revision : Int,
  phase : Int,
  owners : Int,
) -> Result[RemoteBundleRecord, RemoteBundleIssue] {
  guard code_phase(phase) is Some(restored_phase) else {
    return Err(InvalidBundleState)
  }
  if revision < 0 ||
    owners < 0 ||
    (restored_phase == BundleReclaimed && owners != 0) {
    return Err(InvalidBundleState)
  }
  Ok({ manifest, record_revision: revision, phase: restored_phase, owners, })
}
