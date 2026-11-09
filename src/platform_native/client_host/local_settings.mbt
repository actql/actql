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
) -> Result[NativeLocalConfigurationSelection, NativeLocalAdoptionIssue] {
  // The same codec/capture inventory: ten existing configuration originals
  // plus the distinct initialized Host file, not another implementation slot.
  if names.length() > 11 ||
    (names.length() == 11 && !names.contains("host.json")) {
    return Err(ConfigurationLimit)
  }
  let names = names.copy()
  names.sort()
  let files : Array[NativeLocalSelectedFile] = []
  for index, name in names {
    if !local_adoption_name(name) ||
      name == account_name ||
      (index > 0 && name == names[index - 1]) {
      return Err(InvalidInput)
    }
    let (body, generation) = match local_adoption_read(source, name, 65536L) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let content_cid = match local_adoption_digest(crypto, body) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    files.push({ name, generation, body, content_cid, })
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
      original_files, original_managed,
    ) {
    Ok(body) => body
    Err(@host.ConfigurationLimit) => return Err(ConfigurationLimit)
    Err(_) => return Err(Encoding)
  }
  let manifest_cid = match local_adoption_digest(crypto, manifest) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ files, managed, manifest, manifest_cid, })
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
    let (body, generation) = match
      local_adoption_read(source, file.name, 65536L) {
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
) -> Result[String, NativeLocalAdoptionIssue] {
  let material = match self.adopted_current_material() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let body = match
    @host.client_local_adopted_authority_scope_body(
      material,
      self.database,
      principal,
      connection,
    ) {
    Ok(value) => value
    Err(issue) => return Err(local_current_material_issue(issue))
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
  @host.client_local_adopted_account_outcome(material, self.database, request).map_err(
    local_current_material_issue,
  )
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
