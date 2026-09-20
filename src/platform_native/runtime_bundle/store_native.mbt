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
priv struct NativeRuntimeBundleCatalog {
  revision : Int64
  active_bundle_cid : String?
  entries : Array[NativeRuntimeBundleEntry]
}

///|
struct NativeRuntimeBundleStore {
  root : @filesystem.Root
  database : @sqlite.Database
  signature_library : @signature.Library
  authorities : Array[NativeRuntimeBundleAuthority]
  target_triple : String
  capacity_bytes : Int64
  max_bundles : Int
  max_owners : Int
  max_record_bytes : Int
  mut closed : Bool
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
    Err(_) => Err(StateCollision)
  }
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
    @encode.key(writer, "entries")
    @encode.begin_array(writer)
    for entry in catalog.entries {
      emit_entry(writer, entry)
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
    let object = decoded(
      @decode.closed_object(cursor, ["active_bundle_cid", "entries", "version"]),
    )
    if text(object, "version") != "actql-native-runtime-bundle-catalog/0.1" {
      raise NativeBundleCatalogStop
    }
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
    let catalog = { revision, active_bundle_cid, entries, }
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
  if usage.reserved_bytes > store.capacity_bytes ||
    usage.reserved_objects > store.max_bundles.to_int64() {
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
    { revision: 0L, active_bundle_cid: None, entries: [], },
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
  { revision: catalog.revision + 1L, active_bundle_cid, entries, }
}

///|
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
  if root_path.is_empty() ||
    authorities.is_empty() ||
    authorities.length() > 1024 ||
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
  let database = match
    sqlite_library.open_database(
      root_path + "/.actql-runtime-bundle.sqlite3",
      max_record_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  let store = {
    root,
    database,
    signature_library,
    authorities: authorities.copy(),
    target_triple,
    capacity_bytes,
    max_bundles,
    max_owners,
    max_record_bytes: max_record_bytes.to_int(),
    closed: false,
  }
  match database.read("runtime_bundle", "catalog") {
    Ok(value) =>
      match admit_store_catalog(store, value.revision, value.body) {
        Ok(_) => Ok(store)
        Err(issue) => {
          database.close()
          Err(issue)
        }
      }
    Err(@sqlite.NotFound) => {
      let initial = match initial_catalog_bytes(store.max_record_bytes) {
        Ok(value) => value
        Err(issue) => {
          database.close()
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
                  Err(issue)
                }
              }
            Err(issue) => {
              database.close()
              Err(Database(issue))
            }
          }
        Err(issue) => {
          database.close()
          Err(Database(issue))
        }
      }
    }
    Err(issue) => {
      database.close()
      Err(Database(issue))
    }
  }
}

///|
fn verify_component(
  store : NativeRuntimeBundleStore,
  entry : NativeRuntimeBundleEntry,
) -> Result[Unit, NativeRuntimeBundleStoreIssue] {
  let projection = @bundle.bundle_manifest_projection(entry.manifest)
  let expected_bytes : Int64 = @string.from_str(projection[6]) catch {
    _ => return Err(ComponentMismatch)
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
  let hash = @sha.hasher()
  let mut total = 0L
  let mut eof = false
  while !eof {
    let chunk = match filesystem_result(reader.next(65536)) {
      Ok(value) => value
      Err(issue) => {
        ignore(reader.close())
        return Err(issue)
      }
    }
    @sha.update(hash, chunk.bytes) catch {
      _ => {
        ignore(reader.close())
        return Err(ComponentMismatch)
      }
    }
    total = total + chunk.bytes.length().to_int64()
    if total > expected_bytes {
      ignore(reader.close())
      return Err(ComponentMismatch)
    }
    eof = chunk.eof
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
  let digest = @sha.finish_hex(hash) catch {
    _ => return Err(ComponentMismatch)
  }
  if total != expected_bytes || "sha256:" + digest != projection[5] {
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
  let manifest = match
    runtime_bundle_result(
      admit_signed_bundle(
        self.signature_library,
        self.authorities,
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
  let projection = @bundle.bundle_manifest_projection(manifest)
  let component_bytes : Int64 = @string.from_str(projection[6]) catch {
    _ => return Err(ComponentMismatch)
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
  if current.entries.length() >= self.max_bundles {
    return Err(BundleLimit)
  }
  if !allocation_is_reserved(current, candidate) {
    let usage = match catalog_capacity_usage(current) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if usage.reserved_bytes > self.capacity_bytes ||
      usage.reserved_objects >= self.max_bundles.to_int64() ||
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
pub fn NativeRuntimeBundleStore::close(self : NativeRuntimeBundleStore) -> Bool {
  if self.closed {
    false
  } else {
    self.database.close()
    self.closed = true
    true
  }
}
