///|
fn local_read_file_inside(path : String, directory : String) -> Bool {
  path == directory ||
  path.has_prefix(if directory == "/" { "/" } else { directory + "/" })
}

///|
/// Acquire and retain only the original parent first. No output is created
/// before the caller has checked this exact attempt's durable history. This
/// receiver is available only under an independently adopted File selection.
pub fn NativeLocalReadPolicyBinding::open_file_output_parent(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  store : @publication_store.Store,
  request : @result_access.NativeResultAccessRequest,
  observed_at : String,
  path : String,
  parent : String,
  name : String,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  if self.selection.sink != File ||
    self.capture is None ||
    self.file_destination is Some(_) ||
    !local_read_file_location(path, parent, name) ||
    local_read_file_inside(path, self.host.session.state_path) {
    return Err(SelectionMismatch)
  }
  match self.prepare_destination_facts(original, store, request, observed_at) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let managed = match self.capture {
    Some(capture) => capture.managed_root_path_in_original_read()
    None => return Err(SelectionMismatch)
  }
  match managed {
    Err(issue) => return Err(Adoption(issue))
    Ok(Some(directory)) if local_read_file_inside(path, directory) =>
      return Err(SelectionMismatch)
    Ok(_) => ()
  }
  let nonce = match self.crypto.random_bytes(32) {
    Ok(value) => value
    Err(issue) => return Err(Adoption(Crypto(issue)))
  }
  let digest = match local_adoption_digest(self.crypto, nonce) {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  let staging_name = ".actql-result-" + digest[7:].to_owned()
  let destination = local_read_file_destination(
    path,
    parent,
    name,
    staging_name,
    self.selection.max_bytes,
  )
  // Retain before the constructor, its first current check or cleanup can fail.
  self.file_destination = Some(destination)
  self.file_store = Some(store)
  self.file_preparation = Some((original, request))
  match destination.open_parent() {
    Ok(_) =>
      self
      .prepare_destination_facts(original, store, request, observed_at)
      .map(_ => ())
    Err(issue) => Err(FileOutput(issue))
  }
}

///|
/// Exclusive physical creation only after history lookup acknowledged absence.
/// It creates no grant, attempt or receipt and never overwrites an existing
/// destination. The same retained receiver owns every partial failure.
pub fn NativeLocalReadPolicyBinding::create_file_output_writer(
  self : NativeLocalReadPolicyBinding,
  observed_at : String,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  if self.selection.sink != File || self.file_original is Some(_) {
    return Err(SelectionMismatch)
  }
  guard self.file_store is Some(store) &&
    self.file_preparation is Some((original, request)) else {
    return Err(FileOutputUnavailable)
  }
  match self.prepare_destination_facts(original, store, request, observed_at) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard self.file_destination is Some(destination) else {
    return Err(FileOutputUnavailable)
  }
  match destination.create_writer() {
    Ok(_) => ()
    Err(issue) => return Err(FileOutput(issue))
  }
  let file_original = match destination.original_data() {
    Ok(value) => value
    Err(issue) => return Err(FileOutput(issue))
  }
  self.file_original = Some(file_original)
  self
  .prepare_destination_facts(original, store, request, observed_at)
  .map(_ => ())
}

///|
/// Actual child/FD acknowledgement only, independent of the read session and
/// delivery outcome. Failed or unconfirmed close remains on this same binding.
/// This method never creates a second destination or performs another write.
pub fn NativeLocalReadPolicyBinding::close_file_output(
  self : NativeLocalReadPolicyBinding,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  match self.file_destination {
    None => ()
    Some(destination) =>
      match destination.close() {
        Ok(_) => ()
        Err(issue) => return Err(FileOutput(issue))
      }
  }
  self.file_store = None
  self.file_preparation = None
  Ok(())
}
