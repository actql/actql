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
) -> Result[NativeLocalConfigurationSelection, NativeLocalAdoptionIssue] {
  if names.length() > 8 {
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
      let root = match @filesystem.open_private_root(path) {
        Ok(value) => value
        Err(issue) => return Err(Filesystem(issue))
      }
      let ownership = match root.private_ownership() {
        Ok(value) => value
        Err(issue) => return Err(Filesystem(issue))
      }
      Some({ path, root, ownership, })
    }
  }
  let writer = @encode.writer(8192, 128, 4) catch { _ => return Err(Encoding) }
  let manifest = try {
    @encode.begin_object(writer)
    @encode.key(writer, "files")
    @encode.begin_array(writer)
    for file in files {
      @encode.begin_object(writer)
      @encode.key(writer, "content_cid")
      @encode.string_value(writer, file.content_cid)
      @encode.key(writer, "device")
      @encode.string_value(writer, file.generation.device.to_string())
      @encode.key(writer, "inode")
      @encode.string_value(writer, file.generation.inode.to_string())
      @encode.key(writer, "name")
      @encode.string_value(writer, file.name)
      @encode.key(writer, "size")
      @encode.string_value(writer, file.generation.size.to_string())
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "managed_root")
    match managed {
      None => @encode.null_value(writer)
      Some(root) => {
        @encode.begin_object(writer)
        @encode.key(writer, "device")
        @encode.string_value(writer, root.ownership.device.to_string())
        @encode.key(writer, "inode")
        @encode.string_value(writer, root.ownership.inode.to_string())
        @encode.key(writer, "path")
        @encode.string_value(writer, root.path)
        @encode.end_object(writer)
      }
    }
    @encode.key(writer, "version")
    @encode.string_value(
      writer, "actql-native-local-configuration-selection/0.1",
    )
    @encode.end_object(writer)
    @utf8.encode(@encode.finish(writer))
  } catch {
    _ => return Err(Encoding)
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
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match database.insert("client_local_settings", "manifest", self.manifest) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  for file in self.files {
    match
      database.insert("client_local_settings", "file:" + file.name, file.body) {
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
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard database.read("client_local_settings", "manifest") is Ok(original) &&
    original.revision == 0L &&
    original.body == self.manifest else {
    return Err(CustodyLost)
  }
  for file in self.files {
    guard database.read("client_local_settings", "file:" + file.name)
      is Ok(original) &&
      original.revision == 0L &&
      original.body == file.body else {
      return Err(CustodyLost)
    }
  }
  // Exact membership, bounded independently of the database's total contents.
  let mut cursor = ""
  for _ in 0..<(self.files.length() + 1) {
    guard database.scan_after("client_local_settings", cursor) is Ok(row) else {
      return Err(CustodyLost)
    }
    if row.key != "manifest" &&
      !self.files.any(file => row.key == "file:" + file.name) {
      return Err(CustodyLost)
    }
    cursor = row.key
  }
  guard database.scan_after("client_local_settings", cursor)
    is Err(@sqlite.NotFound) else {
    return Err(CustodyLost)
  }
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
  match self.check_binding() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let body = match
    @host.client_local_authority_scope_body(
      self.session.configuration,
      self.adoption_cid,
      principal,
      connection,
    ) {
    Ok(value) => value
    Err(@host.InvalidInput) => return Err(InvalidInput)
    Err(@host.Encoding) => return Err(Encoding)
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
  self
  .check_binding()
  .map(_ => @authorization.evaluate_account(self.session.configuration, request))
}

///|
/// Inspect selected originals before journal finalization. This is not an
/// initialized Host, authorization decision or protected dispatch permit.
pub fn NativeLocalAdoptionSession::selected_configuration(
  self : NativeLocalAdoptionSession,
  name : String,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  match self.check_original() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  for file in self.settings.files {
    if file.name == name {
      return Ok(file.body)
    }
  }
  Err(InvalidInput)
}
