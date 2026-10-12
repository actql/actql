///|
/// Explicit trusted Host installation, never selected from dispatch wire,
/// Source grants, Workspace roles or Reviewer identity. Context is the original
/// Host authorization context; this entry does not mint a replacement CID.
pub(all) struct NativeEffectHostAccountSubject {
  principal : String
  account_id : String
  configuration_cid : String
  authorization_context_cid : String
  read_connection : String
  read_resource : String
  publication_connection : String
  publication_resource : String
}

///|
/// The operator selects a file under an installed filesystem root. The existing
/// bounded reader checks its generation, size and UTF-8 before Core admission.
pub(all) struct NativeEffectHostAccountFile {
  root : String
  name : String
  subject : NativeEffectHostAccountSubject
}

///|
pub(all) enum NativeEffectHostAccountInstallationIssue {
  InvalidSelection
  File(@bounded_files.NativeBoundedTextIssue)
  Configuration(@authorization.ConfigurationIssue)
  OriginalBindingMismatch
}

///|
/// Immutable installer selection, not a cached permission or a new Owner.
struct NativeEffectHostAccountInstallation {
  selected : NativeEffectHostAccountFile
  read_ceiling : Int
}

///|
const HOST_ACCOUNT_READ_MAX_BYTES : Int = 1000000

///|
fn host_account_read_ceiling_valid(read_ceiling : Int) -> Bool {
  read_ceiling > 0 && read_ceiling <= HOST_ACCOUNT_READ_MAX_BYTES
}

///|
fn host_account_subject_valid(subject : NativeEffectHostAccountSubject) -> Bool {
  [
    subject.principal,
    subject.account_id,
    subject.read_connection,
    subject.read_resource,
    subject.publication_connection,
    subject.publication_resource,
  ].all(value => !value.is_empty() && @utf8.encode(value).length() <= 512) &&
  native_reviewer_cid(subject.configuration_cid) &&
  native_reviewer_cid(subject.authorization_context_cid)
}

///|
/// Common admission is the sole canonicalization/CID and permission Owner.
/// The private read seam is used by portable counterexamples, not exposed as a
/// production permission callback. Production always reads the bounded file.
fn host_account_configuration(
  selected : NativeEffectHostAccountFile,
  read : (Int) -> Result[String, @bounded_files.NativeBoundedTextIssue],
  read_ceiling? : Int = 1000000,
) -> Result[
  @authorization.AdmittedAccountConfiguration,
  NativeEffectHostAccountInstallationIssue,
] {
  if !host_account_read_ceiling_valid(read_ceiling) {
    return Err(InvalidSelection)
  }
  let wire = match read(read_ceiling) {
    Ok(value) => value
    Err(issue) => return Err(File(issue))
  }
  if @utf8.encode(wire).length() > read_ceiling {
    return Err(File(@bounded_files.CapacityExceeded))
  }
  let configuration = match
    @authorization.admit_account_configuration_json(wire) {
    Ok(value) => value
    Err(issue) => return Err(Configuration(issue))
  }
  if configuration.account_id() != selected.subject.account_id ||
    configuration.configuration_cid() != selected.subject.configuration_cid {
    return Err(OriginalBindingMismatch)
  }
  Ok(configuration)
}

///|
fn install_host_account_with_read(
  selection : NativeEffectHostAccountFile?,
  read : (Int) -> Result[String, @bounded_files.NativeBoundedTextIssue],
  read_ceiling? : Int = 1000000,
) -> Result[
  NativeEffectHostAccountInstallation?,
  NativeEffectHostAccountInstallationIssue,
] {
  guard selection is Some(selected) else { return Ok(None) }
  if !host_account_read_ceiling_valid(read_ceiling) ||
    selected.root.is_empty() ||
    selected.name.is_empty() ||
    @utf8.encode(selected.root).length() > 4096 ||
    @utf8.encode(selected.name).length() > 4096 ||
    !host_account_subject_valid(selected.subject) {
    return Err(InvalidSelection)
  }
  match host_account_configuration(selected, read, read_ceiling~) {
    Ok(_) => Ok(Some({ selected, read_ceiling, }))
    Err(issue) => Err(issue)
  }
}

///|
/// Missing selection stays None. A selected missing, invalid or foreign file
/// is an installation failure, not Missing and never an implicit Allow.
/// The immutable operator ceiling bounds every later physical read before
/// Common admission; omission preserves the original 1,000,000-byte maximum.
/// It is not an authorization decision or a resource funding profile.
pub fn install_native_effect_host_account(
  selection : NativeEffectHostAccountFile?,
  read_ceiling? : Int = 1000000,
) -> Result[
  NativeEffectHostAccountInstallation?,
  NativeEffectHostAccountInstallationIssue,
] {
  install_host_account_with_read(
    selection,
    limit => {
      guard selection is Some(selected) else {
        return Err(@bounded_files.Missing)
      }
      @bounded_files.read_bounded_text_file(
        selected.root,
        selected.name,
        limit.to_int64(),
      )
    },
    read_ceiling~,
  )
}

///|
pub fn NativeEffectHostAccountInstallation::subject(
  self : NativeEffectHostAccountInstallation,
) -> NativeEffectHostAccountSubject {
  self.selected.subject
}

///|
pub fn NativeEffectHostAccountInstallation::read_current_configuration(
  self : NativeEffectHostAccountInstallation,
) -> @authorization.AdmittedAccountConfiguration? {
  match
    host_account_configuration(
      self.selected,
      limit => {
        @bounded_files.read_bounded_text_file(
          self.selected.root,
          self.selected.name,
          limit.to_int64(),
        )
      },
      read_ceiling=self.read_ceiling,
    ) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
fn host_account_permission(
  selected : NativeEffectHostAccountFile,
  configuration : @authorization.AdmittedAccountConfiguration,
  dispatch_cid : String,
  publication : Bool,
) -> Bool {
  let subject = selected.subject
  let (connection, resource, operation, boundary) = if publication {
    (
      subject.publication_connection,
      subject.publication_resource,
      "write",
      @authorization.Transfer,
    )
  } else {
    (
      subject.read_connection,
      subject.read_resource,
      "read",
      @authorization.Acquisition,
    )
  }
  // Delegated configurations require a currently verified Host answer. This
  // finite file installer has no such supplier and leaves them unresolved.
  @authorization.bind_dispatch_authorization(
    configuration,
    { principal: subject.principal, connection, resource, operation, },
    boundary,
    dispatch_cid,
    subject.authorization_context_cid,
  )
  is Ok(_)
}

///|
fn host_account_current_with_read(
  selected : NativeEffectHostAccountFile,
  dispatch_cid : String,
  publication : Bool,
  read : (Int) -> Result[String, @bounded_files.NativeBoundedTextIssue],
  read_ceiling? : Int = 1000000,
) -> Bool {
  guard host_account_configuration(selected, read, read_ceiling~) is Ok(first) &&
    host_account_permission(selected, first, dispatch_cid, publication) else {
    return false
  }
  // Re-admit and decide again after the first Core decision. No cached Allow,
  // unchanged-file predicate or permanently true current callback is installed.
  guard host_account_configuration(selected, read, read_ceiling~) is Ok(last) else {
    return false
  }
  host_account_permission(selected, last, dispatch_cid, publication)
}

///|
pub fn NativeEffectHostAccountInstallation::current_permission(
  self : NativeEffectHostAccountInstallation,
  dispatch_cid : String,
  publication : Bool,
) -> Bool {
  host_account_current_with_read(
    self.selected,
    dispatch_cid,
    publication,
    limit => {
      @bounded_files.read_bounded_text_file(
        self.selected.root,
        self.selected.name,
        limit.to_int64(),
      )
    },
    read_ceiling=self.read_ceiling,
  )
}
