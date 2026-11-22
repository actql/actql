///|
priv struct NativeLocalSelectedFile {
  name : String
  generation : @filesystem.NativeFileGeneration
  body : Bytes
  content_cid : String
}

///|
priv struct NativeLocalManagedRoot {
  path : String
  root : @filesystem.Root
  ownership : @filesystem.NativeFileOwnership
}

///|
// Installation originals are configuration, not a Program or a Run permit.
// They use the same exclusive adoption and existing physical journal.
priv struct NativeLocalConfigurationSelection {
  files : Array[NativeLocalSelectedFile]
  managed : NativeLocalManagedRoot?
  manifest : Bytes
  manifest_cid : String
  operator_host : NativeLocalOperatorHostOriginal?
  model_provider : String?
}

///|
// Capture can check the maximum shape before its first copy. The actual
// selector partitions the same inventory using the two admitted locator files.
fn local_adoption_configuration_count_supported(
  names : Array[String],
  model : NativeLocalModelConfigurationSelection?,
) -> Bool {
  let host = names.contains("host.json")
  let allowed = if model is Some(_) {
    Int::min(
      @host.client_local_model_configuration_file_limit(),
      names.length() - (if host { 1 } else { 0 }),
    )
  } else {
    0
  }
  @host.client_local_configuration_file_count_supported(
    names.length(),
    host,
    allowed,
  )
}

///|
fn read_native_local_configuration_file(
  source : @filesystem.Root,
  name : String,
  crypto : @crypto.Library,
  construction : ((@authorization.AccountConfigurationConstruction) -> Bool)?,
) -> Result[NativeLocalSelectedFile, NativeLocalAdoptionIssue] {
  match
    local_account_read(source, name, Some(65536L), construction, retain=true) {
    Err(issue) => Err(issue)
    Ok((body, generation)) =>
      local_adoption_digest(crypto, body).map(content_cid => {
        name,
        generation,
        body,
        content_cid,
      })
  }
}

///|
fn prepare_model_configuration_locators(
  original : NativeLocalSelectedFile,
  limits : @environment.Limits,
  prepare : (@authorization.AccountConfigurationConstruction) -> Bool,
) -> Bool {
  guard native_model_http_configuration_parse(
      original.body.length(),
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(working) else {
    return false
  }
  // Only bounded locator strings may escape parsing into the inventory. The
  // source bytes themselves were already covered by the selected-file read.
  prepare({
    retained: {
      ..local_account_construction_zero,
      record_headers: 4L,
      owned_utf16_units: Int::min(512, original.body.length()).to_int64(),
    },
    execution: {
      record_headers: working.record_headers + 4L,
      reference_slots: working.reference_slots + 4L,
      scalar_words: working.scalar_words,
      owned_utf16_units: working.owned_utf16_units,
      owned_wire_bytes: working.owned_wire_bytes,
    },
  })
}

///|
fn read_model_configuration_selection(
  source : @filesystem.Root,
  names : Array[String],
  account_name : String,
  model : NativeLocalModelConfigurationSelection,
  crypto : @crypto.Library,
  prepare : (@authorization.AccountConfigurationConstruction) -> Bool,
) -> Result[
  (Int, NativeLocalSelectedFile, NativeLocalSelectedFile?),
  NativeLocalAdoptionIssue,
] {
  let selected = Array(
    capacity=@host.client_local_model_configuration_file_limit(),
  )
  for
    file in [
      Some(model.files.setting),
      Some(model.files.installation_revision),
      Some(model.files.configuration_contract),
      Some(model.files.response_profile),
      model.execution,
      model.policy,
    ] {
    if file is Some(name) {
      if name == "host.json" || !names.contains(name) || selected.contains(name) {
        return Err(InvalidInput)
      }
      selected.push(name)
    }
  }
  let setting = match
    read_native_local_configuration_file(
      source,
      model.files.setting,
      crypto,
      Some(prepare),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !prepare_model_configuration_locators(
      setting,
      { max_bytes: 8192, max_nodes: 16, max_depth: 4, max_members: 16, },
      prepare,
    ) {
    return Err(ConfigurationLimit)
  }
  let original = match local_preparation_installation_selection(setting.body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Resolve the credential locator before reading any other selected file.
  // The credential file is never incorporated into authenticated settings.
  if original.credential_file == account_name ||
    names.contains(original.credential_file) ||
    selected.contains(original.provider_file) ||
    original.provider_file == "host.json" ||
    !names.contains(original.provider_file) {
    return Err(InvalidInput)
  }
  selected.push(original.provider_file)
  let policy = match model.policy {
    None => None
    Some(name) => {
      let file = match
        read_native_local_configuration_file(
          source,
          name,
          crypto,
          Some(prepare),
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if !prepare_model_configuration_locators(file, model.limits, prepare) {
        return Err(ConfigurationLimit)
      }
      guard native_model_http_run_policy_selection(file.body, model.limits)
        is Some(policy) else {
        return Err(InvalidInput)
      }
      for name in [policy.retention, policy.metadata, policy.clock, policy.data] {
        if name == "host.json" || !names.contains(name) {
          return Err(InvalidInput)
        }
        if !selected.contains(name) {
          selected.push(name)
        }
      }
      Some(file)
    }
  }
  let distinct = selected.length()
  guard @host.client_local_configuration_file_count_supported(
    names.length(),
    names.contains("host.json"),
    distinct,
  ) else {
    return Err(ConfigurationLimit)
  }
  Ok((distinct, setting, policy))
}

///|
fn quote_model_configuration_inventory(
  count : Int,
  prepare : (@authorization.AccountConfigurationConstruction) -> Bool,
) -> Bool {
  let slots = count.to_int64()
  // Sorted names, the retained exact file vector and its manifest projection
  // coexist. The two preloaded locators rejoin the same vector. CIDs and
  // generation records are retained by this existing adoption receiver.
  let retained : @authorization.AccountConfigurationConstructionUnits = {
    record_headers: 4L + 2L * slots,
    reference_slots: 12L + 5L * slots,
    scalar_words: 1L + 6L * slots,
    owned_utf16_units: 71L * slots,
    owned_wire_bytes: 0L,
  }
  prepare({
    retained,
    execution: {
      ..retained,
      record_headers: retained.record_headers + 34L + 2L * slots,
      reference_slots: retained.reference_slots + 90L + 8L * slots,
      scalar_words: retained.scalar_words + 36L + 6L * slots,
      owned_utf16_units: retained.owned_utf16_units + 136L,
    },
  })
}

///|
fn quote_model_configuration_manifest(
  count : Int,
  model_files : Int,
  prepare : (@authorization.AccountConfigurationConstruction) -> Bool,
) -> Bool {
  guard @host.client_local_configuration_selection_limits(model_files)
    is Some((bytes, nodes, depth)) &&
    @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) else {
    return false
  }
  // File generation scalar strings, returned Bytes and the manifest digest
  // overlap the Common text writer at this existing metadata boundary.
  let retained : @authorization.AccountConfigurationConstructionUnits = {
    ..local_account_construction_zero,
    record_headers: 2L,
    owned_utf16_units: 71L,
    owned_wire_bytes: bytes.to_int64(),
  }
  prepare({
    retained,
    execution: {
      record_headers: writer.record_headers + 14L + 3L * count.to_int64(),
      reference_slots: writer.reference_slots + 22L,
      scalar_words: writer.scalar_words + 12L,
      owned_utf16_units: writer.owned_utf16_units +
      152L +
      60L * count.to_int64(),
      owned_wire_bytes: 2L * bytes.to_int64(),
    },
  })
}

///|
fn select_native_local_configuration(
  source : @filesystem.Root,
  account_name : String,
  names : Array[String],
  managed_path : String?,
  crypto : @crypto.Library,
  custody? : NativeLocalAdoptionOpenFailure? = None,
  root_opening? : NativeLocalAdoptionRootOpening = LegacyPrivateRoots,
  operator_host? : NativeLocalOperatorHostOriginal? = None,
  model_configuration? : NativeLocalModelConfigurationSelection? = None,
  construction? : ((@authorization.AccountConfigurationConstruction) -> Bool)? = None,
) -> Result[NativeLocalConfigurationSelection, NativeLocalAdoptionIssue] {
  if !local_adoption_configuration_count_supported(names, model_configuration) {
    return Err(ConfigurationLimit)
  }
  if operator_host is Some(_) && !names.contains("host.json") {
    return Err(InvalidInput)
  }
  let file_construction = if model_configuration is Some(_) {
    construction
  } else {
    None
  }
  if model_configuration is Some(_) {
    guard file_construction is Some(prepare) &&
      quote_model_configuration_inventory(names.length(), prepare) else {
      return Err(ConfigurationLimit)
    }
  }
  let names = names.copy()
  names.sort()
  for index, name in names {
    if !local_adoption_name(name) ||
      name == account_name ||
      (index > 0 && name == names[index - 1]) {
      return Err(InvalidInput)
    }
  }
  let (model_files, setting, policy) = match
    (model_configuration, file_construction) {
    (None, _) => (0, None, None)
    (Some(model), Some(prepare)) =>
      match
        read_model_configuration_selection(
          source, names, account_name, model, crypto, prepare,
        ) {
        Ok((count, setting, policy)) => (count, Some(setting), policy)
        Err(issue) => return Err(issue)
      }
    _ => return Err(ConfigurationLimit)
  }
  let files = Array(capacity=names.length())
  for name in names {
    let file : NativeLocalSelectedFile = if setting is Some(value) &&
      value.name == name {
      value
    } else if policy is Some(value) && value.name == name {
      value
    } else if name == "host.json" && operator_host is Some(original) {
      match original.check_current() {
        Ok(_) => {
          let content_cid = match local_adoption_digest(crypto, original.body) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          {
            name,
            generation: original.generation,
            body: original.body,
            content_cid,
          }
        }
        Err(issue) => return Err(issue)
      }
    } else {
      match
        read_native_local_configuration_file(
          source, name, crypto, file_construction,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    }
    files.push(file)
  }
  let managed = match managed_path {
    None => None
    Some(path) => {
      if path.length() > 4096 {
        return Err(InvalidInput)
      }
      let root = match
        local_adoption_open_private_root(path, custody, root_opening~) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if custody is Some(original) {
        original.managed = Some(root)
      }
      let ownership = match root.private_ownership() {
        Ok(value) => value
        Err(issue) => return Err(Filesystem(issue))
      }
      Some({ path, root, ownership, })
    }
  }
  if file_construction is Some(prepare) &&
    !quote_model_configuration_manifest(files.length(), model_files, prepare) {
    return Err(ConfigurationLimit)
  }
  let original_files : Array[@host.ClientLocalOriginalConfigurationFile] = files.map(file => {
      content_cid: file.content_cid,
      device: file.generation.device,
      inode: file.generation.inode,
      name: file.name,
      size: file.generation.size,
    },
  )
  let original_managed : @host.ClientLocalOriginalManagedRoot? = managed.map(root => {
    device: root.ownership.device,
    inode: root.ownership.inode,
    path: root.path,
  })
  let manifest = match
    @host.client_local_configuration_selection_body(
      original_files,
      original_managed,
      model_files~,
    ) {
    Ok(body) => body
    Err(@host.ConfigurationLimit) => return Err(ConfigurationLimit)
    Err(_) => return Err(Encoding)
  }
  let manifest_cid = match local_adoption_digest(crypto, manifest) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if file_construction is Some(prepare) {
    let largest = files
      .iter()
      .fold(init=0L, fn(maximum, file) {
        Int64::max(maximum, file.generation.size)
      })
    // The same later current observation can read one file again with all
    // retained bodies and the manifest live. Reserve that overlap once.
    if !prepare(local_account_file_read_construction(largest, false)) {
      return Err(ConfigurationLimit)
    }
  }
  Ok({
    files,
    managed,
    manifest,
    manifest_cid,
    operator_host,
    model_provider: model_configuration.map(selected => selected.provider_id),
  })
}

///|
fn NativeLocalConfigurationSelection::check_source(
  self : NativeLocalConfigurationSelection,
  source : @filesystem.Root,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.managed is Some(managed) {
    guard managed.root.private_ownership() is Ok(current) &&
      current == managed.ownership else {
      return Err(CustodyLost)
    }
  }
  for file in self.files {
    if file.name == "host.json" && self.operator_host is Some(original) {
      match original.check_current() {
        Ok(_) => continue
        Err(issue) => return Err(issue)
      }
    }
    if self.model_provider is Some(_) &&
      !source.verify_generation(file.name, file.generation) {
      return Err(SourceChanged)
    }
    let maximum = if self.model_provider is Some(_) {
      file.generation.size
    } else {
      65536L
    }
    let (body, generation) = match
      local_adoption_read(source, file.name, maximum) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if generation != file.generation || body != file.body {
      return Err(SourceChanged)
    }
  }
  Ok(())
}

///|
fn NativeLocalConfigurationSelection::persist(
  self : NativeLocalConfigurationSelection,
  database : @sqlite.Database,
  bootstrap? : NativeClientJournalBootstrapAccess? = None,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match
    insert_bootstrap_journal_value(
      database,
      "client_local_settings",
      "manifest",
      self.manifest,
      bootstrap,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  for file in self.files {
    match
      insert_bootstrap_journal_value(
        database,
        "client_local_settings",
        "file:" + file.name,
        file.body,
        bootstrap,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
  }
  Ok(())
}

///|
fn NativeLocalConfigurationSelection::check_retained(
  self : NativeLocalConfigurationSelection,
  database : @sqlite.Database,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard read_client_journal_value(
      database, "client_local_settings", "manifest", reads,
    )
    is Ok(original) &&
    original.revision == 0L &&
    original.body == self.manifest else {
    return Err(CustodyLost)
  }
  for file in self.files {
    guard read_client_journal_value(
        database,
        "client_local_settings",
        "file:" + file.name,
        reads,
      )
      is Ok(original) &&
      original.revision == 0L &&
      original.body == file.body else {
      return Err(CustodyLost)
    }
  }
  // This operation uses exactly these admitted files and manifest. Other
  // configuration rows are not its targets and are not an integrity sweep.
  Ok(())
}

///|
/// Return an original selected configuration file, never a discovered file or
/// a fresh Provider observation. This transfers no current execution authority.
pub fn NativeLocalHostConnection::selected_configuration(
  self : NativeLocalHostConnection,
  name : String,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  match self.check_binding() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  for file in self.session.settings.files {
    if file.name == name {
      return Ok(file.body)
    }
  }
  Err(InvalidInput)
}

///|
// Immutable DATA after the enclosing original current check. Exact file/body
// correspondence is mandatory; this projection observes no role or permission.
fn NativeLocalHostConnection::selected_configuration_cid_after_current(
  self : NativeLocalHostConnection,
  name : String,
  body : Bytes,
) -> Result[String, NativeLocalAdoptionIssue] {
  for file in self.session.settings.files {
    if file.name == name {
      if file.body != body {
        return Err(CustodyLost)
      }
      return Ok(file.content_cid)
    }
  }
  Err(CustodyLost)
}

///|
pub fn NativeLocalHostConnection::managed_root_path(
  self : NativeLocalHostConnection,
) -> Result[String?, NativeLocalAdoptionIssue] {
  self
  .check_binding()
  .map(_ => self.session.settings.managed.map(root => root.path))
}

///|
/// Stable admission scope from real adopted Host/account and selected caller.
/// Observing or advancing a Run does not change this configuration identity.
pub fn NativeLocalHostConnection::authority_scope_cid(
  self : NativeLocalHostConnection,
  principal : String,
  connection : String,
  crypto : @crypto.Library,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[String, NativeLocalAdoptionIssue] {
  if capture is Some(owner) {
    guard owner.opening is JournalAcquired(host) &&
      physical_equal(host, self) &&
      physical_equal(owner.crypto, crypto) else {
      return Err(CustodyLost)
    }
    // The same entered Read already retains the immutable account/adoption
    // scope. It is DATA only: every role decision and physical/current fence
    // remains with its original caller, and a selected stale Read refuses.
    return owner.authority_scope_cid_in_original_read(principal, connection)
  }
  let material = match self.adopted_current_material() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Binding just checked the full current Host and admitted these originals.
  // This pure projection has no callback or I/O boundary requiring its
  // current port again; keep the existing canonical scope construction.
  let body = match
    @host.client_local_authority_scope_body(
      material.account,
      material.adoption_cid,
      principal,
      connection,
    ) {
    Ok(value) => value
    Err(issue) => return Err(local_current_material_issue(@host.Scope(issue)))
  }
  local_adoption_digest(crypto, body)
}

///|
/// The existing account Owner makes the decision after every binding check.
/// Adoption and a reference never grant a matching account permission.
pub fn NativeLocalHostConnection::authorize(
  self : NativeLocalHostConnection,
  request : @authorization.AccessTuple,
) -> Result[@authorization.AccountOutcome, NativeLocalAdoptionIssue] {
  native_timing_count(22)
  let material = match self.adopted_current_material() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Evaluate this tuple independently after the same full current admission.
  // No callback, I/O or write separates binding from the pure Account Owner.
  Ok(@authorization.evaluate_account(material.account, request))
}

///|
/// Select captured configuration DATA before journal finalization. This does
/// not observe current files or authorize protected work; journal staging
/// validates the original installation before acquiring its database.
pub fn NativeLocalAdoptionSession::selected_configuration(
  self : NativeLocalAdoptionSession,
  name : String,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  if self.closed || self.close_pending {
    return Err(Closed)
  }
  if self.read_cleanup is Some(issue) {
    return Err(issue)
  }
  if self.initial_signing_failure.val is Some(failure) {
    return Err(failure.issue())
  }
  for file in self.settings.files {
    if file.name == name {
      return Ok(file.body)
    }
  }
  Err(InvalidInput)
}
