///|
priv struct NativeRuntimeBundleHold {
  hold_id : String
  kind : String
}

///|
priv struct NativeRuntimeBundleEntry {
  manifest : @bundle.RemoteBundleManifest
  signature_version : String
  signature_key_id : String
  signature : String
  artifact_name : String
  generation : @filesystem.NativeFileGeneration
  record : @bundle.RemoteBundleRecord
  holds : Array[NativeRuntimeBundleHold]
  reclaim_pending : Bool
}

///|
priv enum NativeRuntimeBundleStagingPhase {
  Intent
  StagingOwned(@filesystem.NativeFileOwnership)
  Sealed(@filesystem.NativeFileGeneration)
}

///|
priv struct NativeRuntimeBundleStaging {
  install_id : String
  manifest : @bundle.RemoteBundleManifest
  signature_version : String
  signature_key_id : String
  signature : String
  artifact_name : String
  staging_name : String
  component_bytes : Int64
  phase : NativeRuntimeBundleStagingPhase
}

///|
priv struct NativeRuntimeBundleComponentCopy {
  runtime_bundle_cid : String
  role : String
  component_cid : String
  component_bytes : Int64
  artifact_name : String
  staging_name : String
  phase : NativeRuntimeBundleStagingPhase
}

///|
/// Private Store journal. Its version is independent of the signed bundle.
priv struct NativeRuntimeBundleCatalog {
  revision : Int64
  active_bundle_cid : String?
  entries : Array[NativeRuntimeBundleEntry]
  staging : Array[NativeRuntimeBundleStaging]
  component_copies : Array[NativeRuntimeBundleComponentCopy]
}

///|
struct NativeRuntimeBundleStore {
  root : @filesystem.Root
  root_path : String
  lock : @filesystem.Lock
  database : @sqlite.Database
  signature_library : @signature.Library
  authorities : Array[NativeRuntimeBundleAuthority]
  admission_authorities : Array[NativeRuntimeBundleAuthority]
  target_triple : String
  capacity_bytes : Int64
  max_bundles : Int
  max_owners : Int
  max_record_bytes : Int
  active_installers : Map[String, Bool]
  mut closed : Bool
}

///|
struct NativeRuntimeBundleInstaller {
  store : NativeRuntimeBundleStore
  install_id : String
  runtime_bundle_cid : String
  physical : @filesystem.Writer
  hash : @sha.Hasher
  component_count : Int
  mut sealed_generation : @filesystem.NativeFileGeneration?
  mut sealed_digest : String
  mut closed : Bool
}

///|
/// A Store allocation contains component bytes concatenated in the signed
/// manifest order. Exact lengths make the framing unambiguous without a
/// second, unsigned index or a second physical allocation.
fn bundle_allocation_bytes(
  manifest : @bundle.RemoteBundleManifest,
) -> Result[Int64, NativeRuntimeBundleStoreIssue] {
  let mut total = 0L
  for component in @bundle.bundle_manifest_components_projection(manifest) {
    let size : Int64 = @string.from_str(component[2]) catch {
      _ => return Err(ComponentMismatch)
    }
    if size < 0L || size > 9223372036854775807L - total {
      return Err(CapacityExceeded)
    }
    total = total + size
  }
  Ok(total)
}

///|
priv suberror NativeBundleCatalogStop {
  NativeBundleCatalogStop
}

///|
fn[T] bundle_result(
  value : Result[T, @bundle.RemoteBundleIssue],
) -> Result[T, NativeRuntimeBundleStoreIssue] {
  match value {
    Ok(result) => Ok(result)
    Err(issue) => Err(Bundle(issue))
  }
}

///|
fn[T] runtime_bundle_result(
  value : Result[T, NativeRuntimeBundleIssue],
) -> Result[T, NativeRuntimeBundleStoreIssue] {
  match value {
    Ok(result) => Ok(result)
    Err(Signature(issue)) => Err(Signature(issue))
    Err(Bundle(issue)) => Err(Bundle(issue))
    Err(AuthorityRejected) => Err(AdmissionRejected)
    Err(InvalidConfiguration | AuthorityCollision) => Err(InvalidConfiguration)
    Err(TargetRejected) => Err(ComponentMismatch)
  }
}

///|
fn valid_authority_set(
  authorities : Array[NativeRuntimeBundleAuthority],
) -> Bool {
  if authorities.is_empty() || authorities.length() > 1024 {
    return false
  }
  for index = 0; index < authorities.length(); index = index + 1 {
    let authority = authorities[index]
    if !bounded(authority.issuer_authority, 512) ||
      !bounded(authority.key_id, 512) ||
      !bounded(authority.public_key_pem, 16384) {
      return false
    }
    for prior = 0; prior < index; prior = prior + 1 {
      if authorities[prior].issuer_authority == authority.issuer_authority &&
        authorities[prior].key_id == authority.key_id {
        return false
      }
    }
  }
  true
}

///|
fn authorities_are_subset(
  authorities : Array[NativeRuntimeBundleAuthority],
  candidates : Array[NativeRuntimeBundleAuthority],
) -> Bool {
  for candidate in candidates {
    let mut found = false
    for authority in authorities {
      if authority.issuer_authority == candidate.issuer_authority &&
        authority.key_id == candidate.key_id &&
        authority.public_key_pem == candidate.public_key_pem {
        found = true
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
fn[T] filesystem_result(
  value : Result[T, @filesystem.NativeFilesystemIssue],
) -> Result[T, NativeRuntimeBundleStoreIssue] {
  match value {
    Ok(result) => Ok(result)
    Err(issue) => Err(Filesystem(issue))
  }
}

///|
fn bounded(value : String, maximum : Int) -> Bool {
  !value.is_empty() && value.length() <= maximum
}

///|
fn active_cid(catalog : NativeRuntimeBundleCatalog) -> String? {
  catalog.active_bundle_cid
}

///|
fn entry_cid(value : NativeRuntimeBundleEntry) -> String {
  @bundle.bundle_manifest_identity(value.manifest)
}

///|
fn staging_cid(value : NativeRuntimeBundleStaging) -> String {
  @bundle.bundle_manifest_identity(value.manifest)
}

///|
fn component_copy_names(
  runtime_bundle_cid : String,
  role : String,
) -> (String, String) {
  let key = @sha.hex(@utf8.encode(runtime_bundle_cid + "\u0000" + role))
  ("runtime-copy-" + key, "runtime-copy-stage-" + key)
}

///|
fn staging_snapshot(
  value : NativeRuntimeBundleStaging,
) -> NativeRuntimeBundleInstallSnapshot {
  {
    install_id: value.install_id,
    runtime_bundle_cid: staging_cid(value),
    artifact_name: value.artifact_name,
    staging_name: value.staging_name,
    reserved_bytes: value.component_bytes,
  }
}

///|
fn same_allocation(
  left : NativeRuntimeBundleEntry,
  right : NativeRuntimeBundleEntry,
) -> Bool {
  left.artifact_name == right.artifact_name &&
  left.generation == right.generation
}

///|
fn allocation_key(value : NativeRuntimeBundleEntry) -> String {
  let preimage = value.artifact_name +
    "\u0000" +
    value.generation.device.to_string() +
    "\u0000" +
    value.generation.inode.to_string() +
    "\u0000" +
    value.generation.size.to_string()
  @sha.hex(@utf8.encode(preimage))
}

///|
fn catalog_capacity_usage(
  catalog : NativeRuntimeBundleCatalog,
) -> Result[@sqlite.NativeCapacityUsage, NativeRuntimeBundleStoreIssue] {
  let allocations : Array[String] = []
  let mut reserved_bytes = 0L
  for entry in catalog.entries {
    if @bundle.bundle_record_projection(entry.record)[1] != "3" {
      let key = allocation_key(entry)
      let mut seen = false
      for allocation in allocations {
        if allocation == key {
          seen = true
        }
      }
      if !seen {
        if entry.generation.size < 0L ||
          entry.generation.size > 9223372036854775807L - reserved_bytes {
          return Err(CapacityExceeded)
        }
        allocations.push(key)
        reserved_bytes = reserved_bytes + entry.generation.size
      }
    }
  }
  for staging in catalog.staging {
    if staging.component_bytes < 0L ||
      staging.component_bytes > 9223372036854775807L - reserved_bytes {
      return Err(CapacityExceeded)
    }
    reserved_bytes = reserved_bytes + staging.component_bytes
    allocations.push("staging\u0000" + staging.install_id)
  }
  for copy in catalog.component_copies {
    if copy.component_bytes < 0L ||
      copy.component_bytes > 9223372036854775807L - reserved_bytes {
      return Err(CapacityExceeded)
    }
    reserved_bytes = reserved_bytes + copy.component_bytes
    allocations.push("component\u0000" + copy.artifact_name)
  }
  Ok({ reserved_bytes, reserved_objects: allocations.length().to_int64(), })
}

///|
fn allocation_is_reserved(
  catalog : NativeRuntimeBundleCatalog,
  candidate : NativeRuntimeBundleEntry,
) -> Bool {
  for entry in catalog.entries {
    if @bundle.bundle_record_projection(entry.record)[1] != "3" &&
      same_allocation(entry, candidate) {
      return true
    }
  }
  false
}

///|
fn entry_index(
  catalog : NativeRuntimeBundleCatalog,
  runtime_bundle_cid : String,
) -> Int? {
  for index = 0; index < catalog.entries.length(); index = index + 1 {
    if entry_cid(catalog.entries[index]) == runtime_bundle_cid {
      return Some(index)
    }
  }
  None
}

///|
fn staging_index(
  catalog : NativeRuntimeBundleCatalog,
  install_id : String,
) -> Int? {
  for index = 0; index < catalog.staging.length(); index = index + 1 {
    if catalog.staging[index].install_id == install_id {
      return Some(index)
    }
  }
  None
}

///|
fn component_copy_index(
  catalog : NativeRuntimeBundleCatalog,
  runtime_bundle_cid : String,
  role : String,
) -> Int? {
  for index = 0; index < catalog.component_copies.length(); index = index + 1 {
    let copy = catalog.component_copies[index]
    if copy.runtime_bundle_cid == runtime_bundle_cid && copy.role == role {
      return Some(index)
    }
  }
  None
}

///|
fn same_staging_request(
  left : NativeRuntimeBundleStaging,
  right : NativeRuntimeBundleStaging,
) -> Bool {
  left.install_id == right.install_id &&
  staging_cid(left) == staging_cid(right) &&
  left.signature_version == right.signature_version &&
  left.signature_key_id == right.signature_key_id &&
  left.signature == right.signature &&
  left.artifact_name == right.artifact_name &&
  left.staging_name == right.staging_name &&
  left.component_bytes == right.component_bytes &&
  @bundle.bundle_manifest_json(left.manifest) ==
  @bundle.bundle_manifest_json(right.manifest)
}

///|
fn snapshot(value : NativeRuntimeBundleEntry) -> NativeRuntimeBundleSnapshot {
  {
    runtime_bundle_cid: entry_cid(value),
    manifest_json: @bundle.bundle_manifest_json(value.manifest).unwrap(),
    artifact_name: value.artifact_name,
    generation: value.generation,
    state: @bundle.bundle_record_projection(value.record),
    reclaim_pending: value.reclaim_pending,
  }
}

///|
fn emit_hold(
  writer : @encode.Writer,
  hold : NativeRuntimeBundleHold,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "hold_id")
  @encode.string_value(writer, hold.hold_id)
  @encode.key(writer, "kind")
  @encode.string_value(writer, hold.kind)
  @encode.end_object(writer)
}

///|
fn emit_entry(
  writer : @encode.Writer,
  entry : NativeRuntimeBundleEntry,
) -> Unit raise @encode.EncodeFailure {
  let state = @bundle.bundle_record_projection(entry.record)
  @encode.begin_object(writer)
  @encode.key(writer, "artifact_name")
  @encode.string_value(writer, entry.artifact_name)
  @encode.key(writer, "device")
  @encode.string_value(writer, entry.generation.device.to_string())
  @encode.key(writer, "holds")
  @encode.begin_array(writer)
  for hold in entry.holds {
    emit_hold(writer, hold)
  }
  @encode.end_array(writer)
  @encode.key(writer, "inode")
  @encode.string_value(writer, entry.generation.inode.to_string())
  @encode.key(writer, "manifest_json")
  @encode.string_value(
    writer,
    @bundle.bundle_manifest_json(entry.manifest).unwrap(),
  )
  @encode.key(writer, "owners")
  @encode.string_value(writer, state[2])
  @encode.key(writer, "phase")
  @encode.string_value(writer, state[1])
  @encode.key(writer, "reclaim_pending")
  @encode.bool_value(writer, entry.reclaim_pending)
  @encode.key(writer, "record_revision")
  @encode.string_value(writer, state[0])
  @encode.key(writer, "runtime_bundle_cid")
  @encode.string_value(writer, entry_cid(entry))
  @encode.key(writer, "signature")
  @encode.string_value(writer, entry.signature)
  @encode.key(writer, "signature_key_id")
  @encode.string_value(writer, entry.signature_key_id)
  @encode.key(writer, "signature_version")
  @encode.string_value(writer, entry.signature_version)
  @encode.key(writer, "size")
  @encode.string_value(writer, entry.generation.size.to_string())
  @encode.end_object(writer)
}

///|
fn emit_staging(
  writer : @encode.Writer,
  staging : NativeRuntimeBundleStaging,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  let (phase, device, inode, size) = match staging.phase {
    Intent => ("intent", "", "", "")
    StagingOwned(ownership) =>
      (
        "staging-owned",
        ownership.device.to_string(),
        ownership.inode.to_string(),
        "",
      )
    Sealed(generation) =>
      (
        "sealed",
        generation.device.to_string(),
        generation.inode.to_string(),
        generation.size.to_string(),
      )
  }
  @encode.key(writer, "allocation_device")
  @encode.string_value(writer, device)
  @encode.key(writer, "allocation_inode")
  @encode.string_value(writer, inode)
  @encode.key(writer, "allocation_size")
  @encode.string_value(writer, size)
  @encode.key(writer, "allocation_state")
  @encode.string_value(writer, phase)
  @encode.key(writer, "artifact_name")
  @encode.string_value(writer, staging.artifact_name)
  @encode.key(writer, "component_bytes")
  @encode.string_value(writer, staging.component_bytes.to_string())
  @encode.key(writer, "install_id")
  @encode.string_value(writer, staging.install_id)
  @encode.key(writer, "manifest_json")
  @encode.string_value(
    writer,
    @bundle.bundle_manifest_json(staging.manifest).unwrap(),
  )
  @encode.key(writer, "runtime_bundle_cid")
  @encode.string_value(writer, staging_cid(staging))
  @encode.key(writer, "signature")
  @encode.string_value(writer, staging.signature)
  @encode.key(writer, "signature_key_id")
  @encode.string_value(writer, staging.signature_key_id)
  @encode.key(writer, "signature_version")
  @encode.string_value(writer, staging.signature_version)
  @encode.key(writer, "staging_name")
  @encode.string_value(writer, staging.staging_name)
  @encode.end_object(writer)
}

///|
fn emit_component_copy(
  writer : @encode.Writer,
  copy : NativeRuntimeBundleComponentCopy,
) -> Unit raise @encode.EncodeFailure {
  let (phase, device, inode, size) = match copy.phase {
    Intent => ("intent", "", "", "")
    StagingOwned(ownership) =>
      (
        "staging-owned",
        ownership.device.to_string(),
        ownership.inode.to_string(),
        "",
      )
    Sealed(generation) =>
      (
        "sealed",
        generation.device.to_string(),
        generation.inode.to_string(),
        generation.size.to_string(),
      )
  }
  @encode.begin_object(writer)
  @encode.key(writer, "allocation_device")
  @encode.string_value(writer, device)
  @encode.key(writer, "allocation_inode")
  @encode.string_value(writer, inode)
  @encode.key(writer, "allocation_size")
  @encode.string_value(writer, size)
  @encode.key(writer, "allocation_state")
  @encode.string_value(writer, phase)
  @encode.key(writer, "artifact_name")
  @encode.string_value(writer, copy.artifact_name)
  @encode.key(writer, "component_bytes")
  @encode.string_value(writer, copy.component_bytes.to_string())
  @encode.key(writer, "component_cid")
  @encode.string_value(writer, copy.component_cid)
  @encode.key(writer, "role")
  @encode.string_value(writer, copy.role)
  @encode.key(writer, "runtime_bundle_cid")
  @encode.string_value(writer, copy.runtime_bundle_cid)
  @encode.key(writer, "staging_name")
  @encode.string_value(writer, copy.staging_name)
  @encode.end_object(writer)
}

///|
fn catalog_bytes(
  catalog : NativeRuntimeBundleCatalog,
  max_record_bytes : Int,
) -> Result[Bytes, NativeRuntimeBundleStoreIssue] {
  let writer = @encode.writer(max_record_bytes, max_record_bytes, 5) catch {
    _ => return Err(StateCollision)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "active_bundle_cid")
    @encode.string_value(writer, catalog.active_bundle_cid.unwrap_or(""))
    @encode.key(writer, "component_copies")
    @encode.begin_array(writer)
    for copy in catalog.component_copies {
      emit_component_copy(writer, copy)
    }
    @encode.end_array(writer)
    @encode.key(writer, "entries")
    @encode.begin_array(writer)
    for entry in catalog.entries {
      emit_entry(writer, entry)
    }
    @encode.end_array(writer)
    @encode.key(writer, "staging")
    @encode.begin_array(writer)
    for staging in catalog.staging {
      emit_staging(writer, staging)
    }
    @encode.end_array(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-runtime-bundle-catalog/0.1")
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(StateCollision)
  }
}

///|
fn[T] decoded(
  value : Result[T, @decode.Issue],
) -> T raise NativeBundleCatalogStop {
  match value {
    Ok(result) => result
    Err(_) => raise NativeBundleCatalogStop
  }
}

///|
fn text(
  object : @decode.ObjectView,
  key : String,
) -> String raise NativeBundleCatalogStop {
  decoded(@decode.text(decoded(@decode.required(object, key))))
}

///|
fn signed_int(value : String) -> Int raise NativeBundleCatalogStop {
  let number : Int64 = @string.from_str(value) catch {
    _ => raise NativeBundleCatalogStop
  }
  if number < 0L || number > 2147483647L {
    raise NativeBundleCatalogStop
  }
  number.to_int()
}

///|
fn signed_int64(value : String) -> Int64 raise NativeBundleCatalogStop {
  @string.from_str(value) catch {
    _ => raise NativeBundleCatalogStop
  }
}

///|
fn unsigned_int64(value : String) -> UInt64 raise NativeBundleCatalogStop {
  @string.from_str(value) catch {
    _ => raise NativeBundleCatalogStop
  }
}

///|
fn decode_hold(
  cursor : @decode.Cursor,
) -> NativeRuntimeBundleHold raise NativeBundleCatalogStop {
  let object = decoded(@decode.closed_object(cursor, ["hold_id", "kind"]))
  let hold = { hold_id: text(object, "hold_id"), kind: text(object, "kind"), }
  if !bounded(hold.hold_id, 512) || !bounded(hold.kind, 512) {
    raise NativeBundleCatalogStop
  }
  hold
}

///|
fn decode_entry(
  store : NativeRuntimeBundleStore,
  cursor : @decode.Cursor,
) -> NativeRuntimeBundleEntry raise NativeBundleCatalogStop {
  let object = decoded(
    @decode.closed_object(cursor, [
      "artifact_name", "device", "holds", "inode", "manifest_json", "owners", "phase",
      "reclaim_pending", "record_revision", "runtime_bundle_cid", "signature", "signature_key_id",
      "signature_version", "size",
    ]),
  )
  let runtime_bundle_cid = text(object, "runtime_bundle_cid")
  let manifest_json = text(object, "manifest_json")
  let signature_version = text(object, "signature_version")
  let signature_key_id = text(object, "signature_key_id")
  let signature = text(object, "signature")
  let manifest = match
    admit_signed_bundle(
      store.signature_library,
      store.authorities,
      signature_version,
      signature_key_id,
      runtime_bundle_cid,
      manifest_json,
      signature,
      store.target_triple,
    ) {
    Ok(value) => value
    Err(_) => raise NativeBundleCatalogStop
  }
  let generation : @filesystem.NativeFileGeneration = {
    device: unsigned_int64(text(object, "device")),
    inode: unsigned_int64(text(object, "inode")),
    size: signed_int64(text(object, "size")),
  }
  if generation.size < 0L {
    raise NativeBundleCatalogStop
  }
  let record = match
    @bundle.restore_bundle_record(
      manifest,
      signed_int(text(object, "record_revision")),
      signed_int(text(object, "phase")),
      signed_int(text(object, "owners")),
    ) {
    Ok(value) => value
    Err(_) => raise NativeBundleCatalogStop
  }
  let holds_cursor = decoded(@decode.required(object, "holds"))
  let hold_count = match @decode.array_length(holds_cursor) {
    Some(value) => value
    None => raise NativeBundleCatalogStop
  }
  if hold_count > store.max_owners {
    raise NativeBundleCatalogStop
  }
  let holds : Array[NativeRuntimeBundleHold] = []
  for index = 0; index < hold_count; index = index + 1 {
    guard @decode.element_at(holds_cursor, index) is Some(hold_cursor) else {
      raise NativeBundleCatalogStop
    }
    let hold = decode_hold(hold_cursor)
    for prior in holds {
      if prior.hold_id == hold.hold_id {
        raise NativeBundleCatalogStop
      }
    }
    holds.push(hold)
  }
  let state = @bundle.bundle_record_projection(record)
  if state[2] != hold_count.to_string() {
    raise NativeBundleCatalogStop
  }
  let artifact_name = text(object, "artifact_name")
  if !bounded(artifact_name, 128) {
    raise NativeBundleCatalogStop
  }
  {
    manifest,
    signature_version,
    signature_key_id,
    signature,
    artifact_name,
    generation,
    record,
    holds,
    reclaim_pending: decoded(
      @decode.boolean(decoded(@decode.required(object, "reclaim_pending"))),
    ),
  }
}

///|
fn decode_staging(
  store : NativeRuntimeBundleStore,
  cursor : @decode.Cursor,
) -> NativeRuntimeBundleStaging raise NativeBundleCatalogStop {
  let object = decoded(
    @decode.closed_object(cursor, [
      "allocation_device", "allocation_inode", "allocation_size", "allocation_state",
      "artifact_name", "component_bytes", "install_id", "manifest_json", "runtime_bundle_cid",
      "signature", "signature_key_id", "signature_version", "staging_name",
    ]),
  )
  let runtime_bundle_cid = text(object, "runtime_bundle_cid")
  let manifest_json = text(object, "manifest_json")
  let signature_version = text(object, "signature_version")
  let signature_key_id = text(object, "signature_key_id")
  let signature = text(object, "signature")
  let manifest = match
    admit_signed_bundle(
      store.signature_library,
      store.authorities,
      signature_version,
      signature_key_id,
      runtime_bundle_cid,
      manifest_json,
      signature,
      store.target_triple,
    ) {
    Ok(value) => value
    Err(_) => raise NativeBundleCatalogStop
  }
  let component_bytes = signed_int64(text(object, "component_bytes"))
  let expected_bytes = match bundle_allocation_bytes(manifest) {
    Ok(value) => value
    Err(_) => raise NativeBundleCatalogStop
  }
  let install_id = text(object, "install_id")
  let artifact_name = text(object, "artifact_name")
  let staging_name = text(object, "staging_name")
  if component_bytes < 0L ||
    component_bytes != expected_bytes ||
    !bounded(install_id, 512) ||
    !bounded(artifact_name, 128) ||
    !bounded(staging_name, 128) ||
    artifact_name == staging_name {
    raise NativeBundleCatalogStop
  }
  let state = text(object, "allocation_state")
  let device = text(object, "allocation_device")
  let inode = text(object, "allocation_inode")
  let size = text(object, "allocation_size")
  let phase = match state {
    "intent" => {
      if !device.is_empty() || !inode.is_empty() || !size.is_empty() {
        raise NativeBundleCatalogStop
      }
      Intent
    }
    "staging-owned" => {
      if device.is_empty() || inode.is_empty() || !size.is_empty() {
        raise NativeBundleCatalogStop
      }
      StagingOwned({
        device: unsigned_int64(device),
        inode: unsigned_int64(inode),
      })
    }
    "sealed" => {
      if device.is_empty() || inode.is_empty() || size.is_empty() {
        raise NativeBundleCatalogStop
      }
      let generation : @filesystem.NativeFileGeneration = {
        device: unsigned_int64(device),
        inode: unsigned_int64(inode),
        size: signed_int64(size),
      }
      if generation.size < 0L || generation.size != component_bytes {
        raise NativeBundleCatalogStop
      }
      Sealed(generation)
    }
    _ => raise NativeBundleCatalogStop
  }
  {
    install_id,
    manifest,
    signature_version,
    signature_key_id,
    signature,
    artifact_name,
    staging_name,
    component_bytes,
    phase,
  }
}

///|
fn decode_component_copy(
  cursor : @decode.Cursor,
  entries : Array[NativeRuntimeBundleEntry],
) -> NativeRuntimeBundleComponentCopy raise NativeBundleCatalogStop {
  let object = decoded(
    @decode.closed_object(cursor, [
      "allocation_device", "allocation_inode", "allocation_size", "allocation_state",
      "artifact_name", "component_bytes", "component_cid", "role", "runtime_bundle_cid",
      "staging_name",
    ]),
  )
  let runtime_bundle_cid = text(object, "runtime_bundle_cid")
  let role = text(object, "role")
  let component_cid = text(object, "component_cid")
  let component_bytes = signed_int64(text(object, "component_bytes"))
  let (artifact_name, staging_name) = component_copy_names(
    runtime_bundle_cid, role,
  )
  if text(object, "artifact_name") != artifact_name ||
    text(object, "staging_name") != staging_name ||
    component_bytes <= 0L {
    raise NativeBundleCatalogStop
  }
  let mut found = false
  for entry in entries {
    if entry_cid(entry) == runtime_bundle_cid &&
      @bundle.bundle_record_projection(entry.record)[1] != "3" {
      for
        component in @bundle.bundle_manifest_components_projection(
          entry.manifest,
        ) {
        if component[0] == role &&
          component[1] == component_cid &&
          component[2] == component_bytes.to_string() {
          found = true
        }
      }
    }
  }
  if !found {
    raise NativeBundleCatalogStop
  }
  let device = text(object, "allocation_device")
  let inode = text(object, "allocation_inode")
  let size = text(object, "allocation_size")
  let phase = match text(object, "allocation_state") {
    "intent" => {
      if !device.is_empty() || !inode.is_empty() || !size.is_empty() {
        raise NativeBundleCatalogStop
      }
      Intent
    }
    "staging-owned" => {
      if device.is_empty() || inode.is_empty() || !size.is_empty() {
        raise NativeBundleCatalogStop
      }
      StagingOwned({
        device: unsigned_int64(device),
        inode: unsigned_int64(inode),
      })
    }
    "sealed" => {
      if device.is_empty() || inode.is_empty() || size.is_empty() {
        raise NativeBundleCatalogStop
      }
      let generation : @filesystem.NativeFileGeneration = {
        device: unsigned_int64(device),
        inode: unsigned_int64(inode),
        size: signed_int64(size),
      }
      if generation.size != component_bytes {
        raise NativeBundleCatalogStop
      }
      Sealed(generation)
    }
    _ => raise NativeBundleCatalogStop
  }
  {
    runtime_bundle_cid,
    role,
    component_cid,
    component_bytes,
    artifact_name,
    staging_name,
    phase,
  }
}

///|
fn admit_catalog(
  store : NativeRuntimeBundleStore,
  revision : Int64,
  bytes : Bytes,
) -> Result[NativeRuntimeBundleCatalog, NativeRuntimeBundleStoreIssue] {
  try {
    let body = @utf8.decode(bytes) catch { _ => raise NativeBundleCatalogStop }
    let node = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes: store.max_record_bytes,
        max_nodes: store.max_record_bytes,
        max_depth: 5,
      }) {
      Ok(value) => value
      Err(_) => raise NativeBundleCatalogStop
    }
    let cursor = decoded(
      @decode.admit(node, {
        max_nodes: store.max_record_bytes,
        max_depth: 5,
        max_string_bytes: store.max_record_bytes,
        max_total_string_bytes: store.max_record_bytes,
      }),
    )
    let open = decoded(@decode.open_object(cursor))
    let version = text(open, "version")
    if version != "actql-native-runtime-bundle-catalog/0.1" {
      return Err(UnsupportedCatalog)
    }
    if @decode.required(open, "component_copies") is Err(_) ||
      @decode.required(open, "staging") is Err(_) {
      return Err(UnsupportedCatalog)
    }
    let object = decoded(
      @decode.closed_object(cursor, [
        "active_bundle_cid", "component_copies", "entries", "staging", "version",
      ]),
    )
    let active_text = text(object, "active_bundle_cid")
    let entries_cursor = decoded(@decode.required(object, "entries"))
    let entry_count = match @decode.array_length(entries_cursor) {
      Some(value) => value
      None => raise NativeBundleCatalogStop
    }
    if entry_count > store.max_bundles {
      raise NativeBundleCatalogStop
    }
    let entries : Array[NativeRuntimeBundleEntry] = []
    for index = 0; index < entry_count; index = index + 1 {
      guard @decode.element_at(entries_cursor, index) is Some(entry_cursor) else {
        raise NativeBundleCatalogStop
      }
      let entry = decode_entry(store, entry_cursor)
      for prior in entries {
        if entry_cid(prior) == entry_cid(entry) {
          raise NativeBundleCatalogStop
        }
        for hold in entry.holds {
          for prior_hold in prior.holds {
            if hold.hold_id == prior_hold.hold_id {
              raise NativeBundleCatalogStop
            }
          }
        }
      }
      entries.push(entry)
    }
    let staging_cursor = decoded(@decode.required(object, "staging"))
    let staging_count = match @decode.array_length(staging_cursor) {
      Some(length) => length
      None => raise NativeBundleCatalogStop
    }
    if entry_count + staging_count > store.max_bundles {
      raise NativeBundleCatalogStop
    }
    let staging : Array[NativeRuntimeBundleStaging] = []
    for index = 0; index < staging_count; index = index + 1 {
      guard @decode.element_at(staging_cursor, index) is Some(stage_cursor) else {
        raise NativeBundleCatalogStop
      }
      let stage = decode_staging(store, stage_cursor)
      for entry in entries {
        if entry_cid(entry) == staging_cid(stage) ||
          entry.artifact_name == stage.artifact_name {
          raise NativeBundleCatalogStop
        }
      }
      for prior in staging {
        if prior.install_id == stage.install_id ||
          staging_cid(prior) == staging_cid(stage) ||
          prior.artifact_name == stage.artifact_name ||
          prior.staging_name == stage.staging_name ||
          prior.artifact_name == stage.staging_name ||
          prior.staging_name == stage.artifact_name {
          raise NativeBundleCatalogStop
        }
      }
      staging.push(stage)
    }
    let component_copies : Array[NativeRuntimeBundleComponentCopy] = []
    let copy_cursor = decoded(@decode.required(object, "component_copies"))
    let copy_count = match @decode.array_length(copy_cursor) {
      Some(value) => value
      None => raise NativeBundleCatalogStop
    }
    if copy_count > store.max_bundles * 16 {
      raise NativeBundleCatalogStop
    }
    for index = 0; index < copy_count; index = index + 1 {
      guard @decode.element_at(copy_cursor, index) is Some(value) else {
        raise NativeBundleCatalogStop
      }
      let copy = decode_component_copy(value, entries)
      for prior in component_copies {
        if prior.artifact_name == copy.artifact_name {
          raise NativeBundleCatalogStop
        }
      }
      component_copies.push(copy)
    }
    let active_bundle_cid = if active_text.is_empty() {
      None
    } else {
      let mut found = false
      for entry in entries {
        if entry_cid(entry) == active_text &&
          @bundle.bundle_record_projection(entry.record)[1] == "1" {
          found = true
        }
      }
      if !found {
        raise NativeBundleCatalogStop
      }
      Some(active_text)
    }
    let catalog = {
      revision,
      active_bundle_cid,
      entries,
      staging,
      component_copies,
    }
    let canonical = match catalog_bytes(catalog, store.max_record_bytes) {
      Ok(value) => value
      Err(_) => raise NativeBundleCatalogStop
    }
    if canonical != bytes || @utf8.decode(canonical) != body {
      raise NativeBundleCatalogStop
    }
    Ok(catalog)
  } catch {
    NativeBundleCatalogStop => Err(StateCollision)
    _ => Err(StateCollision)
  }
}

///|
fn admit_store_catalog(
  store : NativeRuntimeBundleStore,
  revision : Int64,
  bytes : Bytes,
) -> Result[NativeRuntimeBundleCatalog, NativeRuntimeBundleStoreIssue] {
  let catalog = match admit_catalog(store, revision, bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let usage = match catalog_capacity_usage(catalog) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if usage.reserved_bytes > store.capacity_bytes {
    Err(CapacityExceeded)
  } else {
    Ok(catalog)
  }
}

///|
fn initial_catalog_bytes(
  max_record_bytes : Int,
) -> Result[Bytes, NativeRuntimeBundleStoreIssue] {
  catalog_bytes(
    {
      revision: 0L,
      active_bundle_cid: None,
      entries: [],
      staging: [],
      component_copies: [],
    },
    max_record_bytes,
  )
}

///|
fn require_open(
  store : NativeRuntimeBundleStore,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  if store.closed {
    Err(Closed)
  } else {
    Ok(())
  }
}

///|
fn load_catalog(
  store : NativeRuntimeBundleStore,
) -> Result[NativeRuntimeBundleCatalog, NativeRuntimeBundleStoreIssue] {
  match require_open(store) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let value = match store.database.read("runtime_bundle", "catalog") {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  admit_store_catalog(store, value.revision, value.body)
}

///|
fn persist_catalog(
  store : NativeRuntimeBundleStore,
  current : NativeRuntimeBundleCatalog,
  next : NativeRuntimeBundleCatalog,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  let body = match catalog_bytes(next, store.max_record_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    store.database.compare_exchange(
      "runtime_bundle",
      "catalog",
      current.revision,
      body,
    ) {
    Ok(revision) if revision == current.revision + 1L => Ok(())
    Ok(_) | Err(@sqlite.Collision) => Err(StateCollision)
    Err(issue) => Err(Database(issue))
  }
}

///|
fn with_catalog_revision(
  catalog : NativeRuntimeBundleCatalog,
  active_bundle_cid : String?,
  entries : Array[NativeRuntimeBundleEntry],
) -> NativeRuntimeBundleCatalog {
  {
    revision: catalog.revision + 1L,
    active_bundle_cid,
    entries,
    staging: catalog.staging,
    component_copies: catalog.component_copies,
  }
}

///|
fn with_catalog_staging(
  catalog : NativeRuntimeBundleCatalog,
  entries : Array[NativeRuntimeBundleEntry],
  staging : Array[NativeRuntimeBundleStaging],
) -> NativeRuntimeBundleCatalog {
  {
    revision: catalog.revision + 1L,
    active_bundle_cid: active_cid(catalog),
    entries,
    staging,
    component_copies: catalog.component_copies,
  }
}

///|
fn with_catalog_copies(
  catalog : NativeRuntimeBundleCatalog,
  copies : Array[NativeRuntimeBundleComponentCopy],
) -> NativeRuntimeBundleCatalog {
  {
    revision: catalog.revision + 1L,
    active_bundle_cid: active_cid(catalog),
    entries: catalog.entries,
    staging: catalog.staging,
    component_copies: copies,
  }
}

///|
fn open_runtime_bundle_store_with_authorities(
  sqlite_library : @sqlite.Library,
  signature_library : @signature.Library,
  root_path : String,
  authorities : Array[NativeRuntimeBundleAuthority],
  admission_authorities : Array[NativeRuntimeBundleAuthority],
  target_triple : String,
  capacity_bytes : Int64,
  max_bundles : Int,
  max_owners : Int,
  max_record_bytes : Int64,
) -> Result[NativeRuntimeBundleStore, NativeRuntimeBundleStoreIssue] {
  if root_path.is_empty() ||
    !valid_authority_set(authorities) ||
    admission_authorities.length() > authorities.length() ||
    !authorities_are_subset(authorities, admission_authorities) ||
    !bounded(target_triple, 512) ||
    capacity_bytes < 0L ||
    max_bundles < 1 ||
    max_bundles > 1024 ||
    max_owners < 1 ||
    max_owners > 100000 ||
    max_record_bytes < 1024L ||
    max_record_bytes > 16777216L {
    return Err(InvalidConfiguration)
  }
  let root = match @filesystem.open_root(root_path) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let lock = match root.acquire_lock(".actql-runtime-bundle.lock") {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let database = match
    sqlite_library.open_database(
      root_path + "/.actql-runtime-bundle.sqlite3",
      max_record_bytes,
    ) {
    Ok(value) => value
    Err(issue) => {
      ignore(lock.close())
      return Err(Database(issue))
    }
  }
  let store = {
    root,
    root_path,
    lock,
    database,
    signature_library,
    authorities: authorities.copy(),
    admission_authorities: admission_authorities.copy(),
    target_triple,
    capacity_bytes,
    max_bundles,
    max_owners,
    max_record_bytes: max_record_bytes.to_int(),
    active_installers: Map([]),
    closed: false,
  }
  match database.read("runtime_bundle", "catalog") {
    Ok(value) =>
      match admit_store_catalog(store, value.revision, value.body) {
        Ok(_) => Ok(store)
        Err(issue) => {
          database.close()
          ignore(lock.close())
          Err(issue)
        }
      }
    Err(@sqlite.NotFound) => {
      let initial = match initial_catalog_bytes(store.max_record_bytes) {
        Ok(value) => value
        Err(issue) => {
          database.close()
          ignore(lock.close())
          return Err(issue)
        }
      }
      match database.insert("runtime_bundle", "catalog", initial) {
        Ok(_) => Ok(store)
        Err(@sqlite.Collision) =>
          match database.read("runtime_bundle", "catalog") {
            Ok(value) =>
              match admit_store_catalog(store, value.revision, value.body) {
                Ok(_) => Ok(store)
                Err(issue) => {
                  database.close()
                  ignore(lock.close())
                  Err(issue)
                }
              }
            Err(issue) => {
              database.close()
              ignore(lock.close())
              Err(Database(issue))
            }
          }
        Err(issue) => {
          database.close()
          ignore(lock.close())
          Err(Database(issue))
        }
      }
    }
    Err(issue) => {
      database.close()
      ignore(lock.close())
      Err(Database(issue))
    }
  }
}

///|
/// Open a Store using one verification set for historical records and a
/// potentially narrower set for new bundle admission.
pub fn open_runtime_bundle_store_with_trust(
  sqlite_library : @sqlite.Library,
  signature_library : @signature.Library,
  root_path : String,
  trust : Array[NativeRuntimeBundleTrust],
  target_triple : String,
  capacity_bytes : Int64,
  max_bundles : Int,
  max_owners : Int,
  max_record_bytes : Int64,
) -> Result[NativeRuntimeBundleStore, NativeRuntimeBundleStoreIssue] {
  if trust.is_empty() || trust.length() > 1024 {
    return Err(InvalidConfiguration)
  }
  let authorities : Array[NativeRuntimeBundleAuthority] = []
  let admission_authorities : Array[NativeRuntimeBundleAuthority] = []
  for entry in trust {
    for prior in authorities {
      if prior.issuer_authority == entry.authority.issuer_authority &&
        prior.key_id == entry.authority.key_id {
        return Err(InvalidConfiguration)
      }
    }
    authorities.push(entry.authority)
    if entry.admit_new_bundles {
      admission_authorities.push(entry.authority)
    }
  }
  open_runtime_bundle_store_with_authorities(
    sqlite_library, signature_library, root_path, authorities, admission_authorities,
    target_triple, capacity_bytes, max_bundles, max_owners, max_record_bytes,
  )
}

///|
/// Open a Store whose configured verification keys may all admit new bundles.
/// Use `open_runtime_bundle_store_with_trust` when rotation or revocation needs
/// to retain historical verification without allowing new bundle admission.
pub fn open_runtime_bundle_store(
  sqlite_library : @sqlite.Library,
  signature_library : @signature.Library,
  root_path : String,
  authorities : Array[NativeRuntimeBundleAuthority],
  target_triple : String,
  capacity_bytes : Int64,
  max_bundles : Int,
  max_owners : Int,
  max_record_bytes : Int64,
) -> Result[NativeRuntimeBundleStore, NativeRuntimeBundleStoreIssue] {
  open_runtime_bundle_store_with_authorities(
    sqlite_library, signature_library, root_path, authorities, authorities, target_triple,
    capacity_bytes, max_bundles, max_owners, max_record_bytes,
  )
}

///|
fn verify_component(
  store : NativeRuntimeBundleStore,
  entry : NativeRuntimeBundleEntry,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  let expected_bytes = match bundle_allocation_bytes(entry.manifest) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if entry.generation.size != expected_bytes ||
    !store.root.verify_generation(entry.artifact_name, entry.generation) {
    return Err(ComponentMismatch)
  }
  let reader = match
    filesystem_result(
      store.root.open_reader(entry.artifact_name, entry.generation),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut total = 0L
  for component in @bundle.bundle_manifest_components_projection(entry.manifest) {
    let expected_component_bytes : Int64 = @string.from_str(component[2]) catch {
      _ => {
        ignore(reader.close())
        return Err(ComponentMismatch)
      }
    }
    let hash = @sha.hasher()
    let mut remaining = expected_component_bytes
    while remaining > 0L {
      let limit = if remaining < 65536L { remaining.to_int() } else { 65536 }
      let chunk = match filesystem_result(reader.next(limit)) {
        Ok(value) => value
        Err(issue) => {
          ignore(reader.close())
          return Err(issue)
        }
      }
      if chunk.bytes.is_empty() || chunk.bytes.length().to_int64() > remaining {
        ignore(reader.close())
        return Err(ComponentMismatch)
      }
      @sha.update(hash, chunk.bytes) catch {
        _ => {
          ignore(reader.close())
          return Err(ComponentMismatch)
        }
      }
      remaining = remaining - chunk.bytes.length().to_int64()
      total = total + chunk.bytes.length().to_int64()
      if chunk.eof && remaining > 0L {
        ignore(reader.close())
        return Err(ComponentMismatch)
      }
    }
    let digest = @sha.finish_hex(hash) catch {
      _ => {
        ignore(reader.close())
        return Err(ComponentMismatch)
      }
    }
    if "sha256:" + digest != component[1] {
      ignore(reader.close())
      return Err(ComponentMismatch)
    }
  }
  let terminal = match filesystem_result(reader.next(1)) {
    Ok(value) => value
    Err(issue) => {
      ignore(reader.close())
      return Err(issue)
    }
  }
  if !terminal.eof || !terminal.bytes.is_empty() {
    ignore(reader.close())
    return Err(ComponentMismatch)
  }
  match filesystem_result(reader.finish()) {
    Ok(_) => ()
    Err(issue) => {
      ignore(reader.close())
      return Err(issue)
    }
  }
  match filesystem_result(reader.close()) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if total != expected_bytes {
    Err(ComponentMismatch)
  } else {
    Ok(())
  }
}

///|
fn after_transition(
  entry : NativeRuntimeBundleEntry,
  transition : @bundle.RemoteBundleTransition,
  holds : Array[NativeRuntimeBundleHold],
  reclaim_pending : Bool,
) -> Result[NativeRuntimeBundleEntry, NativeRuntimeBundleStoreIssue] {
  let states = @bundle.bundle_transition_projection(transition)
  let after = states.1
  let revision = signed_int(after[0]) catch { _ => return Err(StateCollision) }
  let phase = signed_int(after[1]) catch { _ => return Err(StateCollision) }
  let owners = signed_int(after[2]) catch { _ => return Err(StateCollision) }
  let record = match
    bundle_result(
      @bundle.restore_bundle_record(entry.manifest, revision, phase, owners),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..entry, record, holds, reclaim_pending, })
}

///|
fn replace_entry(
  entries : Array[NativeRuntimeBundleEntry],
  index : Int,
  value : NativeRuntimeBundleEntry,
) -> Array[NativeRuntimeBundleEntry] {
  let result = entries.copy()
  result[index] = value
  result
}

///|
fn remove_staging_at(
  staging : Array[NativeRuntimeBundleStaging],
  index : Int,
) -> Array[NativeRuntimeBundleStaging] {
  let result : Array[NativeRuntimeBundleStaging] = []
  for position = 0; position < staging.length(); position = position + 1 {
    if position != index {
      result.push(staging[position])
    }
  }
  result
}

///|
fn replace_staging_at(
  staging : Array[NativeRuntimeBundleStaging],
  index : Int,
  value : NativeRuntimeBundleStaging,
) -> Array[NativeRuntimeBundleStaging] {
  let result = staging.copy()
  result[index] = value
  result
}

///|
fn replace_copy_at(
  copies : Array[NativeRuntimeBundleComponentCopy],
  index : Int,
  replacement : NativeRuntimeBundleComponentCopy,
) -> Array[NativeRuntimeBundleComponentCopy] {
  let result = copies.copy()
  result[index] = replacement
  result
}

///|
fn remove_copy_at(
  copies : Array[NativeRuntimeBundleComponentCopy],
  index : Int,
) -> Array[NativeRuntimeBundleComponentCopy] {
  let result : Array[NativeRuntimeBundleComponentCopy] = []
  for at = 0; at < copies.length(); at = at + 1 {
    if at != index {
      result.push(copies[at])
    }
  }
  result
}

///|
fn record_copy_phase(
  store : NativeRuntimeBundleStore,
  expected : NativeRuntimeBundleComponentCopy,
  phase : NativeRuntimeBundleStagingPhase,
) -> Result[NativeRuntimeBundleComponentCopy, NativeRuntimeBundleStoreIssue] {
  let current = match load_catalog(store) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard component_copy_index(
      current,
      expected.runtime_bundle_cid,
      expected.role,
    )
    is Some(index) else {
    return Err(StateCollision)
  }
  let actual = current.component_copies[index]
  if actual.component_cid != expected.component_cid ||
    actual.artifact_name != expected.artifact_name ||
    !same_staging_phase(actual.phase, expected.phase) {
    return Err(StateCollision)
  }
  let replacement = { ..actual, phase, }
  let next = with_catalog_copies(
    current,
    replace_copy_at(current.component_copies, index, replacement),
  )
  match persist_catalog(store, current, next) {
    Ok(_) => Ok(replacement)
    Err(issue) => Err(issue)
  }
}

///|
fn recover_component_copy_with_operations(
  store : NativeRuntimeBundleStore,
  expected : NativeRuntimeBundleComponentCopy,
  operations : NativeRuntimeBundleCleanupOperations,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  match
    recover_physical_allocation(
      operations,
      expected.phase,
      expected.staging_name,
      expected.artifact_name,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let current = match load_catalog(store) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard component_copy_index(
      current,
      expected.runtime_bundle_cid,
      expected.role,
    )
    is Some(index) else {
    return Err(StateCollision)
  }
  let actual = current.component_copies[index]
  if actual.component_cid != expected.component_cid ||
    !same_staging_phase(actual.phase, expected.phase) {
    return Err(StateCollision)
  }
  persist_catalog(
    store,
    current,
    with_catalog_copies(
      current,
      remove_copy_at(current.component_copies, index),
    ),
  )
}

///|
fn recover_component_copy(
  store : NativeRuntimeBundleStore,
  expected : NativeRuntimeBundleComponentCopy,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  recover_component_copy_with_operations(
    store,
    expected,
    cleanup_operations(store),
  )
}

///|
fn same_staging_phase(
  left : NativeRuntimeBundleStagingPhase,
  right : NativeRuntimeBundleStagingPhase,
) -> Bool {
  match (left, right) {
    (Intent, Intent) => true
    (StagingOwned(left), StagingOwned(right)) => left == right
    (Sealed(left), Sealed(right)) => left == right
    _ => false
  }
}

///|
fn allocation_is_owned_by(
  generation : @filesystem.NativeFileGeneration,
  ownership : @filesystem.NativeFileOwnership,
) -> Bool {
  generation.device == ownership.device && generation.inode == ownership.inode
}

///|
priv struct NativeRuntimeBundleCleanupOperations {
  inspect : (String) -> Result[
    @filesystem.NativeFileGeneration?,
    NativeRuntimeBundleStoreIssue,
  ]
  reclaim : (String, @filesystem.NativeFileGeneration) -> Result[
    Unit,
    NativeRuntimeBundleStoreIssue,
  ]
  sync : () -> Result[Unit, NativeRuntimeBundleStoreIssue]
}

///|
fn cleanup_operations(
  store : NativeRuntimeBundleStore,
) -> NativeRuntimeBundleCleanupOperations {
  {
    inspect: name => filesystem_result(store.root.inspect_generation(name)),
    reclaim: (name, generation) => {
      filesystem_result(store.root.reclaim_generation(name, generation))
    },
    sync: () => filesystem_result(store.root.sync_directory()),
  }
}

///|
fn remove_staging_record(
  store : NativeRuntimeBundleStore,
  expected : NativeRuntimeBundleStaging,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  let current = match load_catalog(store) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard staging_index(current, expected.install_id) is Some(index) else {
    return Err(StateCollision)
  }
  let actual = current.staging[index]
  if !same_staging_request(actual, expected) ||
    !same_staging_phase(actual.phase, expected.phase) {
    return Err(StateCollision)
  }
  let staging = remove_staging_at(current.staging, index)
  let next = with_catalog_staging(current, current.entries, staging)
  persist_catalog(store, current, next)
}

///|
fn record_staging_phase(
  store : NativeRuntimeBundleStore,
  expected : NativeRuntimeBundleStaging,
  phase : NativeRuntimeBundleStagingPhase,
) -> Result[NativeRuntimeBundleStaging, NativeRuntimeBundleStoreIssue] {
  let current = match load_catalog(store) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard staging_index(current, expected.install_id) is Some(index) else {
    return Err(StateCollision)
  }
  let actual = current.staging[index]
  if !same_staging_request(actual, expected) ||
    !same_staging_phase(actual.phase, expected.phase) {
    return Err(StateCollision)
  }
  let replacement = { ..actual, phase, }
  let staging = replace_staging_at(current.staging, index, replacement)
  let next = with_catalog_staging(current, current.entries, staging)
  match persist_catalog(store, current, next) {
    Ok(_) => Ok(replacement)
    Err(issue) => Err(issue)
  }
}

///|
fn reclaim_owned_name(
  operations : NativeRuntimeBundleCleanupOperations,
  name : String,
  ownership : @filesystem.NativeFileOwnership,
) -> Result[Bool, NativeRuntimeBundleStoreIssue] {
  let generation = match (operations.inspect)(name) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match generation {
    None => Ok(false)
    Some(value) => {
      if !allocation_is_owned_by(value, ownership) {
        return Err(Filesystem(@filesystem.GenerationMismatch))
      }
      match (operations.reclaim)(name, value) {
        Ok(_) => Ok(true)
        Err(issue) => Err(issue)
      }
    }
  }
}

///|
fn recover_physical_allocation(
  operations : NativeRuntimeBundleCleanupOperations,
  phase : NativeRuntimeBundleStagingPhase,
  staging_name : String,
  artifact_name : String,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  match phase {
    Intent => {
      let staging = match (operations.inspect)(staging_name) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let artifact = match (operations.inspect)(artifact_name) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if staging is Some(_) || artifact is Some(_) {
        return Err(RecoveryRequired)
      }
    }
    StagingOwned(ownership) => {
      match reclaim_owned_name(operations, staging_name, ownership) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let artifact = match (operations.inspect)(artifact_name) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match artifact {
        Some(generation) if allocation_is_owned_by(generation, ownership) =>
          match (operations.reclaim)(artifact_name, generation) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
        // This phase owns the staging allocation, not a foreign preexisting
        // final name. Only a final name with the recorded ownership can be a
        // crash residue from seal.
        Some(_) | None => ()
      }
    }
    Sealed(generation) => {
      let ownership : @filesystem.NativeFileOwnership = {
        device: generation.device,
        inode: generation.inode,
      }
      match reclaim_owned_name(operations, staging_name, ownership) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let artifact = match (operations.inspect)(artifact_name) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match artifact {
        None => ()
        Some(actual) if actual == generation =>
          match (operations.reclaim)(artifact_name, actual) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
        Some(_) => return Err(Filesystem(@filesystem.GenerationMismatch))
      }
    }
  }
  (operations.sync)()
}

///|
fn recover_staging_allocation(
  operations : NativeRuntimeBundleCleanupOperations,
  expected : NativeRuntimeBundleStaging,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  recover_physical_allocation(
    operations,
    expected.phase,
    expected.staging_name,
    expected.artifact_name,
  )
}

///|
fn recover_staging_install_with_operations(
  store : NativeRuntimeBundleStore,
  install_id : String,
  operations : NativeRuntimeBundleCleanupOperations,
) -> Result[Bool, NativeRuntimeBundleStoreIssue] {
  if store.active_installers.contains(install_id) {
    return Err(CleanupPending)
  }
  let initial = match load_catalog(store) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard staging_index(initial, install_id) is Some(initial_index) else {
    return Ok(false)
  }
  let expected = initial.staging[initial_index]
  match recover_staging_allocation(operations, expected) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match remove_staging_record(store, expected) {
    Ok(_) => Ok(true)
    Err(issue) => Err(issue)
  }
}

///|
fn recover_staging_install(
  store : NativeRuntimeBundleStore,
  install_id : String,
) -> Result[Bool, NativeRuntimeBundleStoreIssue] {
  recover_staging_install_with_operations(
    store,
    install_id,
    cleanup_operations(store),
  )
}

///|
pub fn NativeRuntimeBundleStore::begin_install(
  self : NativeRuntimeBundleStore,
  install_id : String,
  version : String,
  key_id : String,
  runtime_bundle_cid : String,
  body : String,
  signature : String,
) -> Result[NativeRuntimeBundleInstaller, NativeRuntimeBundleStoreIssue] {
  match require_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !bounded(install_id, 512) || self.active_installers.contains(install_id) {
    return Err(InvalidConfiguration)
  }
  if self.admission_authorities.is_empty() {
    return Err(AdmissionRejected)
  }
  let manifest = match
    runtime_bundle_result(
      admit_signed_bundle(
        self.signature_library,
        self.admission_authorities,
        version,
        key_id,
        runtime_bundle_cid,
        body,
        signature,
        self.target_triple,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let component_bytes = match bundle_allocation_bytes(manifest) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if component_bytes < 0L {
    return Err(ComponentMismatch)
  }
  let install_key = @sha.hex(
    @utf8.encode(install_id + "\u0000" + runtime_bundle_cid),
  )
  let artifact_name = "runtime-bundle-" +
    @sha.hex(@utf8.encode(runtime_bundle_cid))
  let candidate : NativeRuntimeBundleStaging = {
    install_id,
    manifest,
    signature_version: version,
    signature_key_id: key_id,
    signature,
    artifact_name,
    staging_name: "runtime-stage-" + install_key,
    component_bytes,
    phase: Intent,
  }
  let current = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if entry_index(current, runtime_bundle_cid) is Some(_) {
    return Err(ExistingBundle)
  }
  for staging in current.staging {
    if staging.install_id == install_id {
      return if same_staging_request(staging, candidate) {
        Err(RecoveryRequired)
      } else {
        Err(StateCollision)
      }
    }
    if staging_cid(staging) == runtime_bundle_cid ||
      staging.artifact_name == artifact_name {
      return Err(ExistingBundle)
    }
  }
  if current.entries.length() + current.staging.length() >= self.max_bundles {
    return Err(BundleLimit)
  }
  let usage = match catalog_capacity_usage(current) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if usage.reserved_bytes > self.capacity_bytes ||
    component_bytes > self.capacity_bytes - usage.reserved_bytes {
    return Err(CapacityExceeded)
  }
  let staging = current.staging.copy()
  staging.push(candidate)
  let next = with_catalog_staging(current, current.entries, staging)
  match persist_catalog(self, current, next) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let physical = match
    filesystem_result(
      self.root.create_writer(candidate.staging_name, component_bytes),
    ) {
    Ok(value) => value
    Err(issue) =>
      return match issue {
        Filesystem(@filesystem.Conflict) =>
          match remove_staging_record(self, candidate) {
            Ok(_) => Err(issue)
            Err(_) => Err(CleanupPending)
          }
        _ =>
          match recover_staging_install(self, install_id) {
            Ok(_) => Err(issue)
            Err(_) => Err(CleanupPending)
          }
      }
  }
  match
    record_staging_phase(self, candidate, StagingOwned(physical.ownership())) {
    Ok(_) => ()
    Err(_) => return Err(CleanupPending)
  }
  self.active_installers[install_id] = true
  Ok({
    store: self,
    install_id,
    runtime_bundle_cid,
    physical,
    hash: @sha.hasher(),
    component_count: @bundle.bundle_manifest_component_count(manifest),
    sealed_generation: None,
    sealed_digest: "",
    closed: false,
  })
}

///|
pub fn NativeRuntimeBundleInstaller::append(
  self : NativeRuntimeBundleInstaller,
  chunk : Bytes,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  match filesystem_result(self.physical.append(chunk)) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if self.component_count == 1 {
    @sha.update(self.hash, chunk) catch {
      _ => return Err(StateCollision)
    }
  }
  Ok(())
}

///|
pub fn NativeRuntimeBundleInstaller::seal(
  self : NativeRuntimeBundleInstaller,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let initial = match load_catalog(self.store) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard staging_index(initial, self.install_id) is Some(initial_index) else {
    return Err(StateCollision)
  }
  let mut expected = initial.staging[initial_index]
  if staging_cid(expected) != self.runtime_bundle_cid ||
    self.physical.written() != expected.component_bytes {
    return Err(ComponentMismatch)
  }
  if self.sealed_generation is None {
    let generation = match
      filesystem_result(self.physical.seal(expected.artifact_name)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    self.sealed_generation = Some(generation)
    if self.component_count == 1 {
      let digest = @sha.finish_hex(self.hash) catch {
        _ => return Err(ComponentMismatch)
      }
      self.sealed_digest = "sha256:" + digest
    }
  }
  let generation = self.sealed_generation.unwrap()
  expected = match expected.phase {
    Sealed(recorded) => {
      if recorded != generation {
        return Err(StateCollision)
      }
      expected
    }
    StagingOwned(ownership) => {
      if !allocation_is_owned_by(generation, ownership) {
        return Err(ComponentMismatch)
      }
      match record_staging_phase(self.store, expected, Sealed(generation)) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    }
    Intent => return Err(StateCollision)
  }
  let projection = @bundle.bundle_manifest_projection(expected.manifest)
  if self.component_count == 1 && self.sealed_digest != projection[5] {
    return Err(ComponentMismatch)
  }
  if generation.size != expected.component_bytes ||
    !self.store.root.verify_generation(expected.artifact_name, generation) {
    return Err(ComponentMismatch)
  }
  let candidate : NativeRuntimeBundleEntry = {
    manifest: expected.manifest,
    signature_version: expected.signature_version,
    signature_key_id: expected.signature_key_id,
    signature: expected.signature,
    artifact_name: expected.artifact_name,
    generation,
    record: @bundle.open_bundle_record(expected.manifest),
    holds: [],
    reclaim_pending: false,
  }
  if self.component_count > 1 {
    match verify_component(self.store, candidate) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let current = match load_catalog(self.store) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard staging_index(current, self.install_id) is Some(index) else {
    return Err(StateCollision)
  }
  if !same_staging_request(current.staging[index], expected) ||
    entry_index(current, self.runtime_bundle_cid) is Some(_) {
    return Err(StateCollision)
  }
  let entries = current.entries.copy()
  entries.push(candidate)
  let staging = remove_staging_at(current.staging, index)
  let next = with_catalog_staging(current, entries, staging)
  match persist_catalog(self.store, current, next) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  ignore(self.store.active_installers.remove(self.install_id))
  self.closed = true
  Ok(snapshot(candidate))
}

///|
pub fn NativeRuntimeBundleInstaller::cancel(
  self : NativeRuntimeBundleInstaller,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  if self.closed {
    return Ok(())
  }
  match filesystem_result(self.physical.cancel()) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  ignore(self.store.active_installers.remove(self.install_id))
  let current = match load_catalog(self.store) {
    Ok(value) => value
    Err(issue) => {
      self.store.active_installers[self.install_id] = true
      return Err(issue)
    }
  }
  guard staging_index(current, self.install_id) is Some(index) else {
    self.store.active_installers[self.install_id] = true
    return Err(StateCollision)
  }
  let expected = current.staging[index]
  match remove_staging_record(self.store, expected) {
    Ok(_) => {
      self.closed = true
      Ok(())
    }
    Err(issue) => {
      self.store.active_installers[self.install_id] = true
      Err(issue)
    }
  }
}

///|
pub fn NativeRuntimeBundleStore::inspect_install(
  self : NativeRuntimeBundleStore,
  install_id : String,
) -> Result[NativeRuntimeBundleInstallSnapshot?, NativeRuntimeBundleStoreIssue] {
  let catalog = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match staging_index(catalog, install_id) {
    Some(index) => Ok(Some(staging_snapshot(catalog.staging[index])))
    None => Ok(None)
  }
}

///|
pub fn NativeRuntimeBundleStore::recover_install(
  self : NativeRuntimeBundleStore,
  install_id : String,
) -> Result[Bool, NativeRuntimeBundleStoreIssue] {
  if !bounded(install_id, 512) {
    return Err(InvalidConfiguration)
  }
  recover_staging_install(self, install_id)
}

///|
pub fn NativeRuntimeBundleStore::adopt(
  self : NativeRuntimeBundleStore,
  version : String,
  key_id : String,
  runtime_bundle_cid : String,
  body : String,
  signature : String,
  artifact_name : String,
  generation : @filesystem.NativeFileGeneration,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  match require_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !bounded(artifact_name, 128) || generation.size < 0L {
    return Err(InvalidConfiguration)
  }
  if self.admission_authorities.is_empty() {
    return Err(AdmissionRejected)
  }
  let manifest = match
    runtime_bundle_result(
      admit_signed_bundle(
        self.signature_library,
        self.admission_authorities,
        version,
        key_id,
        runtime_bundle_cid,
        body,
        signature,
        self.target_triple,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let component_bytes = match bundle_allocation_bytes(manifest) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if generation.size != component_bytes {
    return Err(ComponentMismatch)
  }
  let candidate : NativeRuntimeBundleEntry = {
    manifest,
    signature_version: version,
    signature_key_id: key_id,
    signature,
    artifact_name,
    generation,
    record: @bundle.open_bundle_record(manifest),
    holds: [],
    reclaim_pending: false,
  }
  match verify_component(self, candidate) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let current = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match entry_index(current, runtime_bundle_cid) {
    Some(index) => {
      let existing = current.entries[index]
      if existing.signature_version != version ||
        existing.signature_key_id != key_id ||
        existing.signature != signature ||
        existing.artifact_name != artifact_name ||
        existing.generation != generation ||
        @bundle.bundle_manifest_json(existing.manifest) != Ok(body) {
        return Err(ExistingBundle)
      }
      return Ok(snapshot(existing))
    }
    None => ()
  }
  for staging in current.staging {
    if staging_cid(staging) == runtime_bundle_cid ||
      staging.artifact_name == artifact_name {
      return Err(RecoveryRequired)
    }
  }
  if current.entries.length() + current.staging.length() >= self.max_bundles {
    return Err(BundleLimit)
  }
  if !allocation_is_reserved(current, candidate) {
    let usage = match catalog_capacity_usage(current) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if usage.reserved_bytes > self.capacity_bytes ||
      component_bytes > self.capacity_bytes - usage.reserved_bytes {
      return Err(CapacityExceeded)
    }
  }
  let entries = current.entries.copy()
  entries.push(candidate)
  let next = with_catalog_revision(current, active_cid(current), entries)
  match persist_catalog(self, current, next) {
    Ok(_) => Ok(snapshot(candidate))
    Err(issue) => Err(issue)
  }
}

///|
pub fn NativeRuntimeBundleStore::inspect(
  self : NativeRuntimeBundleStore,
  runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleSnapshot?, NativeRuntimeBundleStoreIssue] {
  let catalog = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match entry_index(catalog, runtime_bundle_cid) {
    Some(index) => Ok(Some(snapshot(catalog.entries[index])))
    None => Ok(None)
  }
}

///|
pub fn NativeRuntimeBundleStore::active(
  self : NativeRuntimeBundleStore,
) -> Result[NativeRuntimeBundleSnapshot?, NativeRuntimeBundleStoreIssue] {
  let catalog = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match active_cid(catalog) {
    Some(cid) => {
      guard entry_index(catalog, cid) is Some(index) else {
        return Err(StateCollision)
      }
      Ok(Some(snapshot(catalog.entries[index])))
    }
    None => Ok(None)
  }
}

///|
/// Bind the physically observed component to the exact active bundle. The
/// caller obtains no runtime authority for installed, inactive, mismatched, or
/// physically changed bytes.
fn NativeRuntimeBundleStore::bind_active_component(
  self : NativeRuntimeBundleStore,
  observed_component_cid : String,
  observed_target_triple : String,
  process_hold_id : String,
) -> Result[NativeActiveRuntimeBinding, NativeRuntimeBundleStoreIssue] {
  let catalog = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard active_cid(catalog) is Some(runtime_bundle_cid) else {
    return Err(MissingBundle)
  }
  guard entry_index(catalog, runtime_bundle_cid) is Some(index) else {
    return Err(StateCollision)
  }
  let entry = catalog.entries[index]
  match verify_component(self, entry) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let projection = @bundle.bundle_manifest_projection(entry.manifest)
  if observed_component_cid != projection[5] ||
    observed_target_triple != projection[4] ||
    observed_target_triple != self.target_triple {
    return Err(ComponentMismatch)
  }
  Ok(
    native_active_runtime_binding(
      runtime_bundle_cid,
      projection[5],
      projection[4],
      projection[7],
      projection[8],
      projection[9],
      process_hold_id,
    ),
  )
}

///|
/// Verify the exact active component and durably retain its process-level
/// bundle holding in one retryable operation. A supervisor must keep the
/// returned holding until physical process stop is confirmed; dispatch-level
/// holdings remain independent.
pub fn NativeRuntimeBundleStore::acquire_active_component(
  self : NativeRuntimeBundleStore,
  observed_component_cid : String,
  observed_target_triple : String,
  process_hold_id : String,
) -> Result[NativeActiveRuntimeBinding, NativeRuntimeBundleStoreIssue] {
  if !bounded(process_hold_id, 512) {
    return Err(InvalidConfiguration)
  }
  let binding = match
    self.bind_active_component(
      observed_component_cid, observed_target_triple, process_hold_id,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    self.retain(binding.runtime_bundle_cid, process_hold_id, "runtime-process") {
    Ok(_) => Ok(binding)
    Err(issue) => Err(issue)
  }
}

///|
/// Return the exact currently held active entry after its physical bytes and
/// process authority have both been revalidated.
fn NativeRuntimeBundleStore::active_entry_for_binding(
  self : NativeRuntimeBundleStore,
  binding : NativeActiveRuntimeBinding,
) -> Result[NativeRuntimeBundleEntry, NativeRuntimeBundleStoreIssue] {
  let catalog = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard active_cid(catalog) is Some(active) &&
    active == binding.runtime_bundle_cid &&
    entry_index(catalog, active) is Some(index) else {
    return Err(MissingBundle)
  }
  let entry = catalog.entries[index]
  match verify_component(self, entry) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let projection = @bundle.bundle_manifest_projection(entry.manifest)
  if projection[5] != binding.component_cid ||
    projection[4] != binding.target_triple ||
    projection[7] != binding.connector_registration ||
    projection[8] != binding.connector_revision ||
    projection[9] != binding.strategy_revision {
    return Err(ComponentMismatch)
  }
  for hold in entry.holds {
    if hold.hold_id == binding.process_hold_id && hold.kind == "runtime-process" {
      return Ok(entry)
    }
  }
  Err(MissingBundle)
}

///|
/// Revalidate the active component and its exact process holding before a
/// runtime can admit more work. Historical component identity alone never
/// restores current execution authority.
pub fn NativeRuntimeBundleStore::verify_active_component_binding(
  self : NativeRuntimeBundleStore,
  binding : NativeActiveRuntimeBinding,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  match self.active_entry_for_binding(binding) {
    Ok(_) => Ok(())
    Err(issue) => Err(issue)
  }
}

///|
/// Resolve a signed component from the exact active bundle while the process
/// holding is still live. The source file is the Store-owned allocation, not
/// a caller-selected library path. Its generation must be checked again by
/// the physical loader when opening the file.
pub fn NativeRuntimeBundleStore::active_component_source(
  self : NativeRuntimeBundleStore,
  binding : NativeActiveRuntimeBinding,
  role : String,
) -> Result[NativeRuntimeBundleComponentSource, NativeRuntimeBundleStoreIssue] {
  let entry = match self.active_entry_for_binding(binding) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut offset = 0L
  for component in @bundle.bundle_manifest_components_projection(entry.manifest) {
    let bytes : Int64 = @string.from_str(component[2]) catch {
      _ => return Err(ComponentMismatch)
    }
    if component[0] == role {
      return Ok(
        native_bundle_component_source(
          self.root_path,
          binding.runtime_bundle_cid,
          role,
          component[1],
          bytes,
          entry.artifact_name,
          entry.generation,
          offset,
        ),
      )
    }
    if bytes < 0L || bytes > 9223372036854775807L - offset {
      return Err(ComponentMismatch)
    }
    offset = offset + bytes
  }
  Err(ComponentMismatch)
}

///|
/// Materialize one signed component as a Store-owned allocation. The extra
/// physical bytes are reserved before the bounded copy and remain charged
/// through all failure and recovery states until deletion is confirmed.
pub fn NativeRuntimeBundleStore::materialize_active_component(
  self : NativeRuntimeBundleStore,
  binding : NativeActiveRuntimeBinding,
  role : String,
) -> Result[NativeRuntimeBundleComponentSource, NativeRuntimeBundleStoreIssue] {
  let source = match self.active_component_source(binding, role) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let current = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match component_copy_index(current, source.runtime_bundle_cid, role) {
    Some(index) => {
      let copy = current.component_copies[index]
      return match copy.phase {
        Sealed(generation) =>
          if !self.root.verify_generation(copy.artifact_name, generation) {
            Err(ComponentMismatch)
          } else {
            Ok(
              native_bundle_component_source(
                self.root_path,
                source.runtime_bundle_cid,
                role,
                source.component_cid,
                source.component_bytes,
                copy.artifact_name,
                generation,
                0L,
              ),
            )
          }
        _ => Err(RecoveryRequired)
      }
    }
    None => ()
  }
  let usage = match catalog_capacity_usage(current) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if usage.reserved_bytes > self.capacity_bytes ||
    source.component_bytes > self.capacity_bytes - usage.reserved_bytes {
    return Err(CapacityExceeded)
  }
  let (artifact_name, staging_name) = component_copy_names(
    source.runtime_bundle_cid,
    role,
  )
  let intent : NativeRuntimeBundleComponentCopy = {
    runtime_bundle_cid: source.runtime_bundle_cid,
    role,
    component_cid: source.component_cid,
    component_bytes: source.component_bytes,
    artifact_name,
    staging_name,
    phase: Intent,
  }
  let copies = current.component_copies.copy()
  copies.push(intent)
  match persist_catalog(self, current, with_catalog_copies(current, copies)) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let writer = match
    filesystem_result(
      self.root.create_writer(staging_name, source.component_bytes),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let owned = match
    record_copy_phase(self, intent, StagingOwned(writer.ownership())) {
    Ok(value) => value
    Err(issue) => {
      ignore(writer.cancel())
      return Err(issue)
    }
  }
  let reader = match
    filesystem_result(
      self.root.open_reader(source.artifact_name, source.generation),
    ) {
    Ok(value) => value
    Err(issue) => {
      ignore(writer.cancel())
      return Err(issue)
    }
  }
  let mut skip = source.offset
  while skip > 0L {
    let limit = if skip < 65536L { skip.to_int() } else { 65536 }
    let chunk = match filesystem_result(reader.next(limit)) {
      Ok(value) => value
      Err(issue) => {
        ignore(reader.close())
        ignore(writer.cancel())
        return Err(issue)
      }
    }
    if chunk.bytes.is_empty() || chunk.bytes.length().to_int64() > skip {
      ignore(reader.close())
      ignore(writer.cancel())
      return Err(ComponentMismatch)
    }
    skip = skip - chunk.bytes.length().to_int64()
  }
  let hash = @sha.hasher()
  let mut remaining = source.component_bytes
  while remaining > 0L {
    let limit = if remaining < 65536L { remaining.to_int() } else { 65536 }
    let chunk = match filesystem_result(reader.next(limit)) {
      Ok(value) => value
      Err(issue) => {
        ignore(reader.close())
        ignore(writer.cancel())
        return Err(issue)
      }
    }
    if chunk.bytes.is_empty() || chunk.bytes.length().to_int64() > remaining {
      ignore(reader.close())
      ignore(writer.cancel())
      return Err(ComponentMismatch)
    }
    match filesystem_result(writer.append(chunk.bytes)) {
      Ok(_) => ()
      Err(issue) => {
        ignore(reader.close())
        ignore(writer.cancel())
        return Err(issue)
      }
    }
    @sha.update(hash, chunk.bytes) catch {
      _ => {
        ignore(reader.close())
        ignore(writer.cancel())
        return Err(ComponentMismatch)
      }
    }
    remaining = remaining - chunk.bytes.length().to_int64()
  }
  match filesystem_result(reader.close()) {
    Ok(_) => ()
    Err(issue) => {
      ignore(writer.cancel())
      return Err(issue)
    }
  }
  let digest = @sha.finish_hex(hash) catch {
    _ => {
      ignore(writer.cancel())
      return Err(ComponentMismatch)
    }
  }
  if "sha256:" + digest != source.component_cid {
    ignore(writer.cancel())
    return Err(ComponentMismatch)
  }
  let generation = match filesystem_result(writer.seal(artifact_name)) {
    Ok(value) => value
    Err(issue) => {
      ignore(writer.cancel())
      return Err(issue)
    }
  }
  let committed_copy = match
    record_copy_phase(self, owned, Sealed(generation)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if committed_copy.component_bytes != generation.size ||
    !self.root.verify_generation(artifact_name, generation) {
    return Err(ComponentMismatch)
  }
  Ok(
    native_bundle_component_source(
      self.root_path,
      source.runtime_bundle_cid,
      role,
      source.component_cid,
      source.component_bytes,
      artifact_name,
      generation,
      0L,
    ),
  )
}

///|
pub fn NativeRuntimeBundleStore::list(
  self : NativeRuntimeBundleStore,
) -> Result[Array[NativeRuntimeBundleSnapshot], NativeRuntimeBundleStoreIssue] {
  let catalog = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let result : Array[NativeRuntimeBundleSnapshot] = []
  for entry in catalog.entries {
    result.push(snapshot(entry))
  }
  Ok(result)
}

///|
pub fn NativeRuntimeBundleStore::verify(
  self : NativeRuntimeBundleStore,
  runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  let catalog = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard entry_index(catalog, runtime_bundle_cid) is Some(index) else {
    return Err(MissingBundle)
  }
  let entry = catalog.entries[index]
  match verify_component(self, entry) {
    Ok(_) => Ok(snapshot(entry))
    Err(issue) => Err(issue)
  }
}

///|
pub fn NativeRuntimeBundleStore::activate(
  self : NativeRuntimeBundleStore,
  runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  let current = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard entry_index(current, runtime_bundle_cid) is Some(target_index) else {
    return Err(MissingBundle)
  }
  let target = current.entries[target_index]
  if target.reclaim_pending {
    return Err(CleanupPending)
  }
  match verify_component(self, target) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if active_cid(current) == Some(runtime_bundle_cid) {
    return Ok(snapshot(target))
  }
  let prior_record = match active_cid(current) {
    Some(cid) => {
      guard entry_index(current, cid) is Some(index) else {
        return Err(StateCollision)
      }
      Some(current.entries[index].record)
    }
    None => None
  }
  let activation = match
    bundle_result(
      @bundle.prepare_bundle_activation(
        prior_record,
        current.entries[target_index].record,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let entries = current.entries.copy()
  for index = 0
      index < @bundle.bundle_activation_transition_count(activation)
      index = index + 1 {
    let transition = match
      bundle_result(@bundle.bundle_activation_transition_at(activation, index)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let cid = @bundle.bundle_transition_key(transition)
    guard entry_index(current, cid) is Some(entry_at) else {
      return Err(StateCollision)
    }
    entries[entry_at] = match
      after_transition(
        current.entries[entry_at],
        transition,
        current.entries[entry_at].holds,
        current.entries[entry_at].reclaim_pending,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  let next = with_catalog_revision(current, Some(runtime_bundle_cid), entries)
  match persist_catalog(self, current, next) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match bundle_result(@bundle.commit_bundle_activation(activation, true)) {
    Ok(_) => Ok(snapshot(next.entries[target_index]))
    Err(issue) => Err(issue)
  }
}

///|
pub fn NativeRuntimeBundleStore::rollback(
  self : NativeRuntimeBundleStore,
  runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  self.activate(runtime_bundle_cid)
}

///|
pub fn NativeRuntimeBundleStore::drain(
  self : NativeRuntimeBundleStore,
  runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  let current = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard entry_index(current, runtime_bundle_cid) is Some(index) else {
    return Err(MissingBundle)
  }
  let entry = current.entries[index]
  if @bundle.bundle_record_projection(entry.record)[1] == "2" {
    return Ok(snapshot(entry))
  }
  let transition = match
    bundle_result(
      @bundle.prepare_active_bundle_drain(active_cid(current), entry.record),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let replacement = match
    after_transition(entry, transition, entry.holds, entry.reclaim_pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let entries = replace_entry(current.entries, index, replacement)
  let next = with_catalog_revision(current, None, entries)
  match persist_catalog(self, current, next) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match bundle_result(@bundle.commit_bundle_transition(transition, true)) {
    Ok(_) => Ok(snapshot(replacement))
    Err(issue) => Err(issue)
  }
}

///|
pub fn NativeRuntimeBundleStore::retain(
  self : NativeRuntimeBundleStore,
  runtime_bundle_cid : String,
  hold_id : String,
  kind : String,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  if !bounded(hold_id, 512) || !bounded(kind, 512) {
    return Err(InvalidConfiguration)
  }
  let current = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for entry in current.entries {
    for hold in entry.holds {
      if hold.hold_id == hold_id {
        if entry_cid(entry) == runtime_bundle_cid && hold.kind == kind {
          return Ok(snapshot(entry))
        }
        return Err(HoldCollision)
      }
    }
  }
  guard entry_index(current, runtime_bundle_cid) is Some(index) else {
    return Err(MissingBundle)
  }
  let entry = current.entries[index]
  let transition = match
    bundle_result(
      @bundle.prepare_active_bundle_retain(
        active_cid(current),
        entry.record,
        self.max_owners,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let holds = entry.holds.copy()
  holds.push({ hold_id, kind, })
  let replacement = match
    after_transition(entry, transition, holds, entry.reclaim_pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let entries = replace_entry(current.entries, index, replacement)
  let next = with_catalog_revision(current, active_cid(current), entries)
  match persist_catalog(self, current, next) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match bundle_result(@bundle.commit_bundle_transition(transition, true)) {
    Ok(_) => Ok(snapshot(replacement))
    Err(issue) => Err(issue)
  }
}

///|
pub fn NativeRuntimeBundleStore::release(
  self : NativeRuntimeBundleStore,
  hold_id : String,
) -> Result[Bool, NativeRuntimeBundleStoreIssue] {
  if !bounded(hold_id, 512) {
    return Err(InvalidConfiguration)
  }
  let current = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut found_entry = -1
  let mut found_hold = -1
  for entry_index = 0
      entry_index < current.entries.length()
      entry_index = entry_index + 1 {
    let entry = current.entries[entry_index]
    for hold_index = 0
        hold_index < entry.holds.length()
        hold_index = hold_index + 1 {
      if entry.holds[hold_index].hold_id == hold_id {
        found_entry = entry_index
        found_hold = hold_index
      }
    }
  }
  if found_entry < 0 {
    return Ok(false)
  }
  let entry = current.entries[found_entry]
  let transition = match
    bundle_result(@bundle.prepare_bundle_release(entry.record)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let holds : Array[NativeRuntimeBundleHold] = []
  for index = 0; index < entry.holds.length(); index = index + 1 {
    if index != found_hold {
      holds.push(entry.holds[index])
    }
  }
  let replacement = match
    after_transition(entry, transition, holds, entry.reclaim_pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let entries = replace_entry(current.entries, found_entry, replacement)
  let next = with_catalog_revision(current, active_cid(current), entries)
  match persist_catalog(self, current, next) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match bundle_result(@bundle.commit_bundle_transition(transition, true)) {
    Ok(_) => Ok(true)
    Err(issue) => Err(issue)
  }
}

///|
fn allocation_in_use(
  catalog : NativeRuntimeBundleCatalog,
  allocation : NativeRuntimeBundleEntry,
  except_bundle_cid : String,
) -> Bool {
  for entry in catalog.entries {
    let state = @bundle.bundle_record_projection(entry.record)
    if entry_cid(entry) != except_bundle_cid &&
      same_allocation(entry, allocation) &&
      state[1] != "3" {
      return true
    }
  }
  false
}

///|
pub fn NativeRuntimeBundleStore::reclaim(
  self : NativeRuntimeBundleStore,
  runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleSnapshot, NativeRuntimeBundleStoreIssue] {
  let initial = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard entry_index(initial, runtime_bundle_cid) is Some(initial_index) else {
    return Err(MissingBundle)
  }
  let initial_entry = initial.entries[initial_index]
  let initial_state = @bundle.bundle_record_projection(initial_entry.record)
  if initial_state[1] == "3" {
    return Ok(snapshot(initial_entry))
  }
  if !initial_entry.reclaim_pending {
    match
      bundle_result(
        @bundle.prepare_inactive_bundle_reclaim(
          active_cid(initial),
          initial_entry.record,
        ),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let pending = { ..initial_entry, reclaim_pending: true, }
    let entries = replace_entry(initial.entries, initial_index, pending)
    let next = with_catalog_revision(initial, active_cid(initial), entries)
    match persist_catalog(self, initial, next) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let current = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let owned_copies : Array[NativeRuntimeBundleComponentCopy] = []
  for copy in current.component_copies {
    if copy.runtime_bundle_cid == runtime_bundle_cid {
      owned_copies.push(copy)
    }
  }
  for copy in owned_copies {
    match recover_component_copy(self, copy) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let current = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard entry_index(current, runtime_bundle_cid) is Some(index) else {
    return Err(StateCollision)
  }
  let entry = current.entries[index]
  if !entry.reclaim_pending {
    return Err(StateCollision)
  }
  if !allocation_in_use(current, entry, runtime_bundle_cid) {
    match
      filesystem_result(
        self.root.reclaim_generation(entry.artifact_name, entry.generation),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let transition = match
    bundle_result(
      @bundle.prepare_inactive_bundle_reclaim(active_cid(current), entry.record),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let replacement = match
    after_transition(entry, transition, entry.holds, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let entries = replace_entry(current.entries, index, replacement)
  let next = with_catalog_revision(current, active_cid(current), entries)
  match persist_catalog(self, current, next) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match bundle_result(@bundle.commit_bundle_transition(transition, true)) {
    Ok(_) => Ok(snapshot(replacement))
    Err(issue) => Err(issue)
  }
}

///|
pub fn NativeRuntimeBundleStore::recover(
  self : NativeRuntimeBundleStore,
) -> Result[Array[NativeRuntimeBundleSnapshot], NativeRuntimeBundleStoreIssue] {
  if !self.active_installers.is_empty() {
    return Err(CleanupPending)
  }
  let initial = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let installs : Array[String] = []
  for staging in initial.staging {
    installs.push(staging.install_id)
  }
  for install_id in installs {
    match recover_staging_install(self, install_id) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let pending_copies : Array[NativeRuntimeBundleComponentCopy] = []
  for copy in initial.component_copies {
    match copy.phase {
      Sealed(_) => ()
      _ => pending_copies.push(copy)
    }
  }
  for copy in pending_copies {
    match recover_component_copy(self, copy) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let current = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let reclaim : Array[String] = []
  for entry in current.entries {
    if entry.reclaim_pending {
      reclaim.push(entry_cid(entry))
    }
  }
  for cid in reclaim {
    match self.reclaim(cid) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  self.list()
}

///|
pub fn NativeRuntimeBundleStore::capacity_usage(
  self : NativeRuntimeBundleStore,
) -> Result[@sqlite.NativeCapacityUsage, NativeRuntimeBundleStoreIssue] {
  match require_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let catalog = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  catalog_capacity_usage(catalog)
}

///|
pub fn NativeRuntimeBundleStore::close(
  self : NativeRuntimeBundleStore,
) -> Result[Bool, NativeRuntimeBundleStoreIssue] {
  if self.closed {
    return Ok(false)
  }
  if !self.active_installers.is_empty() {
    return Err(CleanupPending)
  }
  let catalog = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !catalog.staging.is_empty() {
    return Err(CleanupPending)
  }
  for copy in catalog.component_copies {
    match copy.phase {
      Sealed(_) => ()
      _ => return Err(CleanupPending)
    }
  }
  self.database.close()
  if !self.lock.close() {
    return Err(CleanupPending)
  }
  self.closed = true
  Ok(true)
}
