///|
// The original Adoption constructor owns the acquisition order, original
// selection and refusal paths. Transport adapters do not reproduce this body.
fn begin_native_local_host_adoption_original(
  parent_path : String,
  state_name : String,
  source_path : String,
  source_name : String,
  account_id : String,
  crypto : @crypto.Library,
  configuration_files? : Array[String] = [],
  managed_root_path? : String? = None,
  existing_only? : Bool = false,
  custody? : NativeLocalAdoptionOpenFailure? = None,
  root_opening? : NativeLocalAdoptionRootOpening = LegacyPrivateRoots,
  product_original? : NativeLocalProductConfigurationSession? = None,
) -> Result[NativeLocalAdoptionSession, NativeLocalAdoptionIssue] {
  if !local_adoption_name(state_name) ||
    !local_adoption_name(source_name) ||
    account_id.is_empty() ||
    source_path.length() > 4096 {
    return Err(InvalidInput)
  }
  let source_root = match
    local_adoption_open_private_root(source_path, custody, root_opening~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if custody is Some(original) {
    original.source_root = Some(source_root)
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
  // Only the actual installer may join the selected finite Mock original.
  // Ordinary/manual adoption still refuses a named but uninstalled profile.
  if configuration.bootstrap_profile() is Some(profile) {
    guard product_original is Some(product) else {
      return Err(UninstalledBootstrapProfile)
    }
    match
      product.require_mock_bootstrap_original(
        source_ownership, source_name, source_body, profile,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let settings = match
    select_native_local_configuration(
      source_root,
      source_name,
      configuration_files,
      managed_root_path,
      crypto,
      custody~,
      root_opening~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let parent = match
    local_adoption_open_private_root(parent_path, custody, root_opening~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if custody is Some(original) {
    original.parent = Some(parent)
  }
  let parent_ownership = match parent.private_ownership() {
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
  let original = match parent.inspect_directory(state_name) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let created = match original {
    Some(value) => value
    None if existing_only => return Err(CustodyLost)
    None =>
      match parent.create_directory(state_name) {
        Ok(value) => value
        Err(issue) => return Err(Filesystem(issue))
      }
  }
  let root = match local_adoption_open_child(parent, state_name, custody) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if custody is Some(original) {
    original.root = Some(root)
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
    "root_device", "root_inode", "settings_cid", "source_device", "source_file",
    "source_inode", "source_path", "source_root_device", "source_root_inode", "source_size",
    "state_name", "version",
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
    settings.manifest_cid,
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
        @host.client_local_initialization_record_body(expected).map_err(_ => {
          NativeLocalAdoptionIssue::Encoding
        }) {
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
    settings,
    existing_only,
    initial_signing_eligible: Ref(original is None),
    initial_signing_failure: Ref(None),
    root_ownership: created,
    state_path: parent_path + "/" + state_name,
    intent_body,
    intent_generation,
    intent_cid,
    closed: false,
    close_pending: false,
    read_cleanup: None,
    lock_close_attempted: false,
    journal_open_failure: None,
  })
}
