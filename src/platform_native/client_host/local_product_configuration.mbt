///|
// Product originals enter the same private filesystem/adoption Owner. This
// physical staging session is not an Account, credential or execution permit.
struct NativeLocalProductConfigurationSession {
  parent : @filesystem.Root
  parent_ownership : @filesystem.NativeFileOwnership
  root : @filesystem.Root
  root_ownership : @filesystem.NativeFileOwnership
  lock : @filesystem.Lock
  directory_name : String
  originals : Array[(String, Bytes)]
  intent : Bytes
  intent_generation : @filesystem.NativeFileGeneration
  intent_cid : String
  mut existing_only : Bool
  mut closed : Bool
  mut close_pending : Bool
}

///|
fn product_original_names(originals : Array[(String, Bytes)]) -> Bool {
  // Account plus ten existing selections and the distinct initialized Host
  // original. Per-file, wire, resource and execution allowances stay fixed.
  if originals.is_empty() ||
    originals.length() > 12 ||
    (
      originals.length() == 12 &&
      !originals.any(original => original.0 == "host.json")
    ) {
    return false
  }
  for index, original in originals {
    let name = original.0
    if !local_adoption_name(name) ||
      name.length() > 64 ||
      name.has_prefix("product-") ||
      original.1.is_empty() ||
      original.1.length() > 65536 ||
      (index > 0 && originals[index - 1].0 >= name) {
      return false
    }
  }
  true
}

///|
fn product_original_manifest(
  originals : Array[(String, Bytes)],
  crypto : @crypto.Library,
) -> Result[String, NativeLocalAdoptionIssue] {
  if !product_original_names(originals) {
    return Err(InvalidInput)
  }
  let fields : Array[(String, String)] = []
  for original in originals {
    let cid = match local_adoption_digest(crypto, original.1) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    fields.push((original.0, cid))
  }
  let body = match local_adoption_record(fields) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(@utf8.decode(body)) catch {
    _ => Err(Encoding)
  }
}

///|
/// Explicit trusted assembly stages bounded product originals before ordinary
/// Host adoption. Existing-only observation never creates files. A lost or
/// ambiguous creation witness is refused rather than repaired from the bundle.
pub fn begin_native_local_product_configuration(
  parent_path : String,
  directory_name : String,
  originals : Array[(String, Bytes)],
  crypto : @crypto.Library,
  existing_only? : Bool = false,
) -> Result[NativeLocalProductConfigurationSession, NativeLocalAdoptionIssue] {
  begin_native_local_product_configuration_original(
    parent_path,
    directory_name,
    originals,
    crypto,
    existing_only~,
  )
}

///|
fn begin_native_local_product_configuration_original(
  parent_path : String,
  directory_name : String,
  originals : Array[(String, Bytes)],
  crypto : @crypto.Library,
  existing_only? : Bool = false,
  custody? : NativeLocalAdoptionOpenFailure? = None,
  root_opening? : NativeLocalAdoptionRootOpening = LegacyPrivateRoots,
) -> Result[NativeLocalProductConfigurationSession, NativeLocalAdoptionIssue] {
  if !local_adoption_name(directory_name) || parent_path.length() > 4096 {
    return Err(InvalidInput)
  }
  let originals = originals.copy()
  originals.sort_by((a, b) => a.0.compare(b.0))
  let manifest = match product_original_manifest(originals, crypto) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let parent = match
    local_product_open_parent(parent_path, custody, root_opening) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if custody is Some(original) {
    original.parent = Some(parent)
  }
  let parent_ownership = match parent.bootstrap_parent_ownership() {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let lock = match local_adoption_acquire_lock(parent, custody) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if custody is Some(original) {
    original.lock = Some(lock)
  }
  guard parent.bootstrap_parent_ownership() is Ok(current_parent) &&
    current_parent == parent_ownership else {
    return Err(CustodyLost)
  }
  let intent = match
    local_adoption_record([
      ("directory", directory_name),
      ("originals", manifest),
      ("parent_device", parent_ownership.device.to_string()),
      ("parent_inode", parent_ownership.inode.to_string()),
    ]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let observed_intent = match
    parent.inspect_generation("product-initialization.json") {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let (root, root_ownership, intent_generation) = match observed_intent {
    None => {
      if existing_only {
        return Err(CustodyLost)
      }
      // An existing directory is not evidence of a first creation, even empty.
      match parent.inspect_directory(directory_name) {
        Ok(None) => ()
        Ok(Some(_)) => return Err(AmbiguousInitialization)
        Err(issue) => return Err(Filesystem(issue))
      }
      match parent.inspect_generation("product-directory-custody.json") {
        Ok(None) => ()
        Ok(Some(_)) => return Err(CustodyLost)
        Err(issue) => return Err(Filesystem(issue))
      }
      for index in 0..<11 {
        for suffix in [".claim", ".custody"] {
          match
            parent.inspect_generation(
              "product-original-" + index.to_string() + suffix,
            ) {
            Ok(None) => ()
            Ok(Some(_)) => return Err(CustodyLost)
            Err(issue) => return Err(Filesystem(issue))
          }
        }
      }
      let intent_generation = match
        local_adoption_write(parent, "product-initialization.json", intent) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      guard parent.bootstrap_parent_ownership() is Ok(current_parent) &&
        current_parent == parent_ownership else {
        return Err(CustodyLost)
      }
      let ownership = match parent.create_directory(directory_name) {
        Ok(value) => value
        Err(issue) => return Err(Filesystem(issue))
      }
      let root = match
        local_adoption_open_child(parent, directory_name, custody) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if custody is Some(original) {
        original.root = Some(root)
      }
      guard root.private_ownership() is Ok(current_child) &&
        current_child == ownership &&
        parent.bootstrap_parent_ownership() is Ok(current_parent) &&
        current_parent == parent_ownership else {
        return Err(CustodyLost)
      }
      let witness = match product_directory_witness(directory_name, ownership) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        local_adoption_write(parent, "product-directory-custody.json", witness) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      (root, ownership, intent_generation)
    }
    Some(generation) => {
      let (original_intent, observed) = match
        local_adoption_read(parent, "product-initialization.json", 8192L) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if original_intent != intent || observed != generation {
        return Err(SourceChanged)
      }
      let root = match
        local_adoption_open_child(parent, directory_name, custody) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if custody is Some(original) {
        original.root = Some(root)
      }
      let ownership = match root.private_ownership() {
        Ok(value) => value
        Err(issue) => return Err(Filesystem(issue))
      }
      let (witness, _) = match
        local_adoption_read(parent, "product-directory-custody.json", 8192L) {
        Ok(value) => value
        Err(CustodyLost) => return Err(AmbiguousInitialization)
        Err(issue) => return Err(issue)
      }
      guard product_directory_witness(directory_name, ownership) is Ok(expected) &&
        expected == witness else {
        return Err(CustodyLost)
      }
      (root, ownership, generation)
    }
  }
  let intent_cid = match local_adoption_digest(crypto, intent) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let session : NativeLocalProductConfigurationSession = {
    parent,
    parent_ownership,
    root,
    root_ownership,
    lock,
    directory_name,
    originals,
    intent,
    intent_generation,
    intent_cid,
    // Only the live, successful first creation may create the selected files.
    // A reopened intent is not proof that an absent claim was never committed.
    existing_only: existing_only || observed_intent is Some(_),
    closed: false,
    close_pending: false,
  }
  session.check_original().map(_ => session)
}

///|
fn product_directory_witness(
  name : String,
  ownership : @filesystem.NativeFileOwnership,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  local_adoption_record([
    ("device", ownership.device.to_string()),
    ("directory", name),
    ("inode", ownership.inode.to_string()),
  ])
}

///|
fn NativeLocalProductConfigurationSession::check_original(
  self : NativeLocalProductConfigurationSession,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.closed {
    return Err(Closed)
  }
  // Product work counters stay separate from domain census slots 4..15/60..62.
  native_timing_count(28)
  guard self.parent.bootstrap_parent_ownership() is Ok(parent) &&
    parent == self.parent_ownership &&
    self.root.private_ownership() is Ok(root) &&
    root == self.root_ownership &&
    self.parent.inspect_directory(self.directory_name) is Ok(Some(named)) &&
    named == self.root_ownership else {
    return Err(CustodyLost)
  }
  let (intent, generation) = match
    local_adoption_read(self.parent, "product-initialization.json", 8192L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if intent != self.intent || generation != self.intent_generation {
    return Err(CustodyLost)
  }
  let (witness, _) = match
    local_adoption_read(self.parent, "product-directory-custody.json", 8192L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard product_directory_witness(self.directory_name, self.root_ownership)
    is Ok(expected) &&
    expected == witness else {
    return Err(CustodyLost)
  }
  Ok(())
}

///|
pub fn NativeLocalProductConfigurationSession::stage_configuration(
  self : NativeLocalProductConfigurationSession,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  // A new explicit staging call observes the Product again. The private
  // restore path consumes its immediately preceding constructor observation.
  match self.check_original() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.stage_configuration_after_original_check()
}

///|
// Only the explicit checked entrance above and the immediately returned
// constructor below reach this synchronous interval under the same Lock.
// No application callback or authorization decision is retained across calls.
fn NativeLocalProductConfigurationSession::stage_configuration_after_original_check(
  self : NativeLocalProductConfigurationSession,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.closed {
    return Err(Closed)
  }
  native_timing_count(58)
  let allow_creation = !self.existing_only
  // Fence further creation before any I/O. A failed or interrupted staging
  // attempt is not converted into permission to retry an absent original.
  self.existing_only = true
  for index, original in self.originals {
    let claim_name = "product-original-" + index.to_string() + ".claim"
    let witness_name = "product-original-" + index.to_string() + ".custody"
    let claim = match
      local_adoption_record([
        ("intent_cid", self.intent_cid),
        ("name", original.0),
      ]) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let has_claim = match self.parent.inspect_generation(claim_name) {
      Ok(value) => value is Some(_)
      Err(issue) => return Err(Filesystem(issue))
    }
    let body = if !has_claim {
      if !allow_creation {
        return Err(CustodyLost)
      }
      for
        (owner, name) in [(self.root, original.0), (self.parent, witness_name)] {
        match owner.inspect_generation(name) {
          Ok(None) => ()
          Ok(Some(_)) => return Err(AmbiguousInitialization)
          Err(issue) => return Err(Filesystem(issue))
        }
      }
      // The durable claim precedes creation. An interrupted claim is unknown;
      // it cannot regenerate a removed file or be relabelled as never started.
      match local_adoption_write(self.parent, claim_name, claim) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let generation = match
        local_adoption_write(self.root, original.0, original.1) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let witness = match
        product_file_witness(generation, self.intent_cid, original.0) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match local_adoption_write(self.parent, witness_name, witness) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      native_timing_count(29)
      let (body, observed) = match
        local_adoption_read(self.root, original.0, 65536L) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if observed != generation {
        return Err(SourceChanged)
      }
      body
    } else {
      let (observed_claim, _) = match
        local_adoption_read(self.parent, claim_name, 8192L) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if observed_claim != claim {
        return Err(CustodyLost)
      }
      let (witness, _) = match
        local_adoption_read(self.parent, witness_name, 8192L) {
        Ok(value) => value
        Err(CustodyLost) => return Err(AmbiguousInitialization)
        Err(issue) => return Err(issue)
      }
      native_timing_count(29)
      let (body, generation) = match
        local_adoption_read(self.root, original.0, 65536L) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      guard product_file_witness(generation, self.intent_cid, original.0)
        is Ok(expected) &&
        expected == witness else {
        return Err(CustodyLost)
      }
      // This same read proves both the witnessed generation and exact bytes.
      // Trusted local reads do not create another validation boundary.
      body
    }
    if body != original.1 {
      return Err(SourceChanged)
    }
  }
  Ok(())
}

///|
fn product_file_witness(
  generation : @filesystem.NativeFileGeneration,
  intent_cid : String,
  name : String,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  local_adoption_record([
    ("device", generation.device.to_string()),
    ("inode", generation.inode.to_string()),
    ("intent_cid", intent_cid),
    ("name", name),
    ("size", generation.size.to_string()),
  ])
}

///|
pub fn NativeLocalProductConfigurationSession::close(
  self : NativeLocalProductConfigurationSession,
) -> Bool {
  // Fence before physical release; failed close retains the same retry handle.
  if self.closed {
    return !self.close_pending
  }
  self.closed = true
  self.close_pending = !self.lock.close()
  !self.close_pending
}

///|
/// Restore the retained selection, including its original expiry and physical
/// paths. Missing originals never fall back to freshly generated product data.
pub fn restore_native_local_product_configuration(
  parent_path : String,
  directory_name : String,
  crypto : @crypto.Library,
) -> Result[NativeLocalProductConfigurationSession, NativeLocalAdoptionIssue] {
  restore_native_local_product_configuration_original(
    parent_path, directory_name, crypto,
  )
}

///|
fn restore_native_local_product_configuration_original(
  parent_path : String,
  directory_name : String,
  crypto : @crypto.Library,
  custody? : NativeLocalAdoptionOpenFailure? = None,
  root_opening? : NativeLocalAdoptionRootOpening = LegacyPrivateRoots,
) -> Result[NativeLocalProductConfigurationSession, NativeLocalAdoptionIssue] {
  if !local_adoption_name(directory_name) || parent_path.length() > 4096 {
    return Err(InvalidInput)
  }
  let parent = match
    local_product_open_parent(parent_path, custody, root_opening) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if custody is Some(original) {
    original.parent = Some(parent)
  }
  let parent_ownership = match parent.bootstrap_parent_ownership() {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let (intent, _) = match
    local_adoption_read(parent, "product-initialization.json", 8192L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let fields = match
    local_adoption_fields(intent, [
      "directory", "originals", "parent_device", "parent_inode",
    ]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // The original retained parent is checked before opening child originals.
  // A fresh metadata observation is never substituted for missing custody.
  if fields[2] != parent_ownership.device.to_string() ||
    fields[3] != parent_ownership.inode.to_string() {
    return Err(CustodyLost)
  }
  guard parent.bootstrap_parent_ownership() is Ok(current_parent) &&
    current_parent == parent_ownership else {
    return Err(CustodyLost)
  }
  if fields[0] != directory_name {
    return Err(SourceChanged)
  }
  let body = match
    @source.parse_json_bytes_preserving(@utf8.encode(fields[1]), {
      max_input_bytes: 4096,
      max_nodes: 32,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let cursor = match
    @decode.admit(body, {
      max_nodes: 32,
      max_depth: 2,
      max_string_bytes: 256,
      max_total_string_bytes: 4096,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let object = match @decode.open_object(cursor) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let keys = match @decode.object_field_names(cursor) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  keys.sort()
  if keys.is_empty() ||
    keys.length() > 12 ||
    (keys.length() == 12 && !keys.contains("host.json")) {
    return Err(CustodyLost)
  }
  let root = match local_adoption_open_child(parent, directory_name, custody) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if custody is Some(original) {
    original.root = Some(root)
  }
  guard root.private_ownership() is Ok(_) else { return Err(CustodyLost) }
  if !product_original_names(keys.map(name => (name, b"{}"))) {
    return Err(CustodyLost)
  }
  let originals : Array[(String, Bytes)] = []
  for name in keys {
    guard @decode.lookup(object, name) is Some(value) &&
      @decode.text(value) is Ok(cid) else {
      return Err(CustodyLost)
    }
    let (original, _) = match local_adoption_read(root, name, 65536L) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard local_adoption_digest(crypto, original) is Ok(observed) &&
      observed == cid else {
      return Err(SourceChanged)
    }
    originals.push((name, original))
  }
  // The scoped observation Roots have no authority to initialize anything.
  // Retire these actual descriptors before the same locked constructor checks
  // the original selection again. A failed close keeps the same out-slot.
  if custody is Some(original) {
    match root.close() {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => original.root = None
    }
    match parent.close() {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => original.parent = None
    }
  }
  let session = match
    begin_native_local_product_configuration_original(
      parent_path,
      directory_name,
      originals,
      crypto,
      existing_only=true,
      custody~,
      root_opening~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // The successful constructor just checked this same locked Product. Consume
  // that observation while checking each original file, without another entry.
  session.stage_configuration_after_original_check().map(_ => session)
}

///|
// Join the installed finite Mock metadata to the SAME excluded Product
// original. A profile CID, equal Account elsewhere, or arbitrary caller DATA
// cannot replace its live original Root/intent/Account selection. This is
// bootstrap provenance only; each Source/Model/write still needs its own
// original implementation and current Account authorization at dispatch.
fn NativeLocalProductConfigurationSession::require_mock_bootstrap_original(
  self : Self,
  source_ownership : @filesystem.NativeFileOwnership,
  source_name : String,
  source_body : Bytes,
  profile : @authorization.BootstrapProfile,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if profile != @authorization.local_mock_profile_identity() ||
    source_name != "account.json" ||
    source_ownership != self.root_ownership ||
    !self.originals.any(entry => {
      entry.0 == source_name && entry.1 == source_body
    }) {
    return Err(UninstalledBootstrapProfile)
  }
  self.check_original()
}
