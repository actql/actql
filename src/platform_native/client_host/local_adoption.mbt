///|
/// Physical assembly of an explicitly selected Local Host. This retains the
/// existing filesystem lock and custody; it is not a dispatch permit or a new
/// execution Owner. Final journal adoption is required before protected work.
struct NativeLocalAdoptionSession {
  parent : @filesystem.Root
  root : @filesystem.Root
  source_root : @filesystem.Root
  source_ownership : @filesystem.NativeFileOwnership
  lock : @filesystem.Lock
  source_name : String
  source_generation : @filesystem.NativeFileGeneration
  source_body : Bytes
  configuration : @authorization.AdmittedAccountConfiguration
  root_ownership : @filesystem.NativeFileOwnership
  state_path : String
  intent_body : Bytes
  intent_generation : @filesystem.NativeFileGeneration
  intent_cid : String
  mut closed : Bool
  mut close_pending : Bool
}

///|
pub(all) enum NativeLocalAdoptionIssue {
  InvalidInput
  ConfigurationLimit
  Configuration(@authorization.ConfigurationIssue)
  ForeignAccount
  UninstalledBootstrapProfile
  CustodyLost
  SourceChanged
  AmbiguousInitialization
  Closed
  Encoding
  Crypto(@crypto.NativeSignatureIssue)
  Filesystem(@filesystem.NativeFilesystemIssue)
  ReadPending(@filesystem.Reader, @filesystem.NativeFilesystemIssue)
  WritePending(@filesystem.Writer, @filesystem.NativeFilesystemIssue)
  Physical(@sqlite.NativeSqliteIssue)
  Epoch(NativeClientEpochIssue)
  Journal(NativeClientRunJournalIssue)
  Fenced
  TransactionUnknown
  DatabasePending(@sqlite.Database, NativeLocalAdoptionIssue)
  Inspection(NativeClientStateInspectionIssue)
}

///|
fn local_adoption_record(
  fields : Array[(String, String)],
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  let writer = @encode.writer(8192, 64, 4) catch { _ => return Err(Encoding) }
  try {
    @encode.begin_object(writer)
    for field in fields {
      @encode.key(writer, field.0)
      @encode.string_value(writer, field.1)
    }
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn local_adoption_fields(
  body : Bytes,
  keys : Array[String],
) -> Result[Array[String], NativeLocalAdoptionIssue] {
  let value = match
    @source.parse_json_bytes_preserving(body, {
      max_input_bytes: 8192,
      max_nodes: 64,
      max_depth: 4,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let cursor = match
    @decode.admit(value, {
      max_nodes: 64,
      max_depth: 4,
      max_string_bytes: 4096,
      max_total_string_bytes: 8192,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let object = match @decode.closed_object(cursor, keys) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let fields : Array[String] = []
  for key in keys {
    guard @decode.lookup(object, key) is Some(value) &&
      @decode.text(value) is Ok(text) else {
      return Err(CustodyLost)
    }
    fields.push(text)
  }
  let encoded = match
    local_adoption_record(keys.mapi((i, key) => (key, fields[i]))) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if encoded != body {
    return Err(CustodyLost)
  }
  Ok(fields)
}

///|
fn local_adoption_digest(
  crypto : @crypto.Library,
  body : Bytes,
) -> Result[String, NativeLocalAdoptionIssue] {
  let hasher = match crypto.sha256_hasher() {
    Ok(value) => value
    Err(issue) => return Err(Crypto(issue))
  }
  match hasher.update(body) {
    Ok(_) => ()
    Err(issue) => return Err(Crypto(issue))
  }
  hasher
  .finish_hex()
  .map(value => "sha256:" + value)
  .map_err(issue => Crypto(issue))
}

///|
fn local_adoption_read(
  root : @filesystem.Root,
  name : String,
  max_bytes : Int64,
) -> Result[(Bytes, @filesystem.NativeFileGeneration), NativeLocalAdoptionIssue] {
  let generation = match root.inspect_generation(name) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(Filesystem(issue))
  }
  if generation.size < 0L || generation.size > max_bytes {
    return Err(ConfigurationLimit)
  }
  let reader = match root.open_reader(name, generation) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  // Reserve a finite destination from the admitted original size before copying.
  let body : FixedArray[Byte] = FixedArray::make(generation.size.to_int(), 0)
  let mut offset = 0
  let mut failure : @filesystem.NativeFilesystemIssue? = None
  while offset < body.length() {
    match reader.next(65536) {
      Err(issue) => {
        failure = Some(issue)
        break
      }
      Ok(chunk) => {
        if chunk.bytes.is_empty() ||
          chunk.bytes.length() > body.length() - offset {
          failure = Some(@filesystem.GenerationMismatch)
          break
        }
        for i in 0..<chunk.bytes.length() {
          body[offset + i] = chunk.bytes[i]
        }
        offset += chunk.bytes.length()
      }
    }
  }
  if failure is None {
    match reader.finish() {
      Ok(_) => ()
      Err(issue) => failure = Some(issue)
    }
  }
  match reader.close() {
    Ok(_) => ()
    Err(issue) => return Err(ReadPending(reader, issue))
  }
  match failure {
    Some(issue) => Err(Filesystem(issue))
    None => Ok((Bytes::makei(body.length(), i => body[i]), generation))
  }
}

///|
fn local_adoption_write(
  root : @filesystem.Root,
  name : String,
  body : Bytes,
) -> Result[@filesystem.NativeFileGeneration, NativeLocalAdoptionIssue] {
  let writer = match
    root.create_writer(name + ".stage", body.length().to_int64()) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  match writer.append(body) {
    Ok(_) => ()
    Err(issue) => return Err(WritePending(writer, issue))
  }
  match writer.seal(name) {
    Ok(value) => Ok(value)
    Err(issue) => Err(WritePending(writer, issue))
  }
}

///|
fn local_adoption_name(name : String) -> Bool {
  !name.is_empty() &&
  name.length() <= 128 &&
  name != "." &&
  name != ".." &&
  !name.contains("/") &&
  !name.contains("\\") &&
  !name.contains("\u{0000}")
}

///|
/// Begin or inspect the original one-time intent. An existing directory with
/// missing proof is never initialized, even when all its files are absent.
/// Selected account bytes are admitted before any Host-state mutation.
pub fn begin_native_local_host_adoption(
  parent_path : String,
  state_name : String,
  source_path : String,
  source_name : String,
  account_id : String,
  crypto : @crypto.Library,
) -> Result[NativeLocalAdoptionSession, NativeLocalAdoptionIssue] {
  if !local_adoption_name(state_name) ||
    !local_adoption_name(source_name) ||
    account_id.is_empty() ||
    source_path.length() > 4096 {
    return Err(InvalidInput)
  }
  let source_root = match @filesystem.open_private_root(source_path) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let source_ownership = match source_root.private_ownership() {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let (source_body, source_generation) = match
    local_adoption_read(source_root, source_name, 1048576L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let text = @utf8.decode(source_body) catch { _ => return Err(Encoding) }
  let configuration = match
    @authorization.admit_account_configuration_json(text) {
    Ok(value) => value
    Err(issue) => return Err(Configuration(issue))
  }
  if configuration.account_id() != account_id {
    return Err(ForeignAccount)
  }
  // This first assembly profile uses explicit account entries, not a profile
  // generator. A named bootstrap needs its installed original in a later slice.
  if configuration.bootstrap_profile() is Some(_) {
    return Err(UninstalledBootstrapProfile)
  }
  let parent = match @filesystem.open_private_root(parent_path) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let parent_ownership = match parent.private_ownership() {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let lock = match parent.acquire_lock("local-adoption.lock") {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let original = match parent.inspect_directory(state_name) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let created = match original {
    Some(value) => value
    None =>
      match parent.create_directory(state_name) {
        Ok(value) => value
        Err(issue) => return Err(Filesystem(issue))
      }
  }
  let root = match parent.open_child(state_name) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  guard root.private_ownership() is Ok(current) &&
    current == created &&
    parent.private_ownership() is Ok(current_parent) &&
    current_parent == parent_ownership else {
    return Err(CustodyLost)
  }
  match parent.sync_directory() {
    Ok(_) => ()
    Err(issue) => return Err(Filesystem(issue))
  }
  let content_cid = match local_adoption_digest(crypto, source_body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let keys = [
    "account_id", "configuration_cid", "content_cid", "nonce", "parent_device", "parent_inode",
    "root_device", "root_inode", "source_device", "source_file", "source_inode",
    "source_path", "source_root_device", "source_root_inode", "source_size", "state_name",
    "version",
  ]
  let expected = [
    account_id,
    configuration.configuration_cid(),
    content_cid,
    "",
    parent_ownership.device.to_string(),
    parent_ownership.inode.to_string(),
    created.device.to_string(),
    created.inode.to_string(),
    source_generation.device.to_string(),
    source_name,
    source_generation.inode.to_string(),
    source_path,
    source_ownership.device.to_string(),
    source_ownership.inode.to_string(),
    source_generation.size.to_string(),
    state_name,
    "actql-native-local-host-initialization/0.1",
  ]
  let (intent_body, intent_generation) = match original {
    None => {
      let nonce = match crypto.random_bytes(32) {
        Ok(value) => epoch_hex(value)
        Err(issue) => return Err(Crypto(issue))
      }
      expected[3] = nonce
      let body = match
        local_adoption_record(keys.mapi((i, key) => (key, expected[i]))) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let generation = match
        local_adoption_write(root, "initialization.json", body) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      (body, generation)
    }
    Some(_) => {
      let (body, generation) = match
        local_adoption_read(root, "initialization.json", 8192L) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let fields = match local_adoption_fields(body, keys) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if epoch_hex_bytes(fields[3]) is None {
        return Err(CustodyLost)
      }
      for i in 0..<keys.length() {
        if i != 3 && fields[i] != expected[i] {
          return Err(SourceChanged)
        }
      }
      (body, generation)
    }
  }
  let intent_cid = match local_adoption_digest(crypto, intent_body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    parent,
    root,
    source_root,
    source_ownership,
    lock,
    source_name,
    source_generation,
    source_body,
    configuration,
    root_ownership: created,
    state_path: parent_path + "/" + state_name,
    intent_body,
    intent_generation,
    intent_cid,
    closed: false,
    close_pending: false,
  })
}

///|
fn NativeLocalAdoptionSession::check_original(
  self : NativeLocalAdoptionSession,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.closed {
    return Err(Closed)
  }
  guard self.parent.private_ownership() is Ok(_) &&
    self.root.private_ownership() is Ok(current) &&
    current == self.root_ownership &&
    self.source_root.private_ownership() is Ok(current_source) &&
    current_source == self.source_ownership &&
    self.root.verify_generation("initialization.json", self.intent_generation) else {
    return Err(CustodyLost)
  }
  let (intent, _) = match
    local_adoption_read(self.root, "initialization.json", 8192L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if intent != self.intent_body ||
    !self.source_root.verify_generation(
      self.source_name,
      self.source_generation,
    ) {
    return Err(SourceChanged)
  }
  let (source, _) = match
    local_adoption_read(self.source_root, self.source_name, 1048576L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if source != self.source_body {
    return Err(SourceChanged)
  }
  Ok(())
}

///|
/// Copy only under the persisted original intent. Existing content without its
/// exact creation witness stays ambiguous and cannot be overwritten or adopted.
pub fn NativeLocalAdoptionSession::stage_configuration(
  self : NativeLocalAdoptionSession,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match self.check_original() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let existing = match self.root.inspect_generation("account.json") {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let keys = ["device", "inode", "intent_cid", "size", "version"]
  let generation = match existing {
    None => {
      // An initialized or possibly initialized Host must never regenerate an
      // account file, even if both its content and creation witness disappeared.
      for
        name in [
          "client.sqlite3", "journal-custody.json", "journal-initializing.json",
        ] {
        match self.root.inspect_generation(name) {
          Ok(None) => ()
          Ok(Some(_)) => return Err(CustodyLost)
          Err(issue) => return Err(Filesystem(issue))
        }
      }
      match self.root.inspect_generation("configuration-custody.json") {
        Ok(None) => ()
        Ok(Some(_)) => return Err(CustodyLost)
        Err(issue) => return Err(Filesystem(issue))
      }
      let generation = match
        local_adoption_write(self.root, "account.json", self.source_body) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let fields = [
        generation.device.to_string(),
        generation.inode.to_string(),
        self.intent_cid,
        generation.size.to_string(),
        "actql-native-local-configuration-custody/0.1",
      ]
      let body = match
        local_adoption_record(keys.mapi((i, key) => (key, fields[i]))) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        local_adoption_write(self.root, "configuration-custody.json", body) {
        Ok(_) => generation
        Err(issue) => return Err(issue)
      }
    }
    Some(generation) => {
      let (body, _) = match
        local_adoption_read(self.root, "configuration-custody.json", 8192L) {
        Ok(value) => value
        Err(CustodyLost) => return Err(AmbiguousInitialization)
        Err(issue) => return Err(issue)
      }
      let fields = match local_adoption_fields(body, keys) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if fields !=
        [
          generation.device.to_string(),
          generation.inode.to_string(),
          self.intent_cid,
          generation.size.to_string(),
          "actql-native-local-configuration-custody/0.1",
        ] {
        return Err(CustodyLost)
      }
      generation
    }
  }
  let (body, observed) = match
    local_adoption_read(self.root, "account.json", 1048576L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if body != self.source_body || observed != generation {
    return Err(SourceChanged)
  }
  // Staging is not final journal adoption and grants no Source/Effect authority.
  self.check_original()
}

///|
pub fn NativeLocalAdoptionSession::intent_cid(
  self : NativeLocalAdoptionSession,
) -> String {
  self.intent_cid
}

///|
pub fn NativeLocalAdoptionSession::configuration_cid(
  self : NativeLocalAdoptionSession,
) -> String {
  self.configuration.configuration_cid()
}

///|
pub fn NativeLocalAdoptionSession::close(
  self : NativeLocalAdoptionSession,
) -> Bool {
  if self.closed {
    return !self.close_pending
  }
  // Fence reuse before releasing the exclusive physical claim, including a
  // failed/unknown close. A closed descriptor must never authorize another copy.
  self.closed = true
  self.close_pending = !self.lock.close()
  !self.close_pending
}
