///|
priv enum ReadCryptoReplyIssue {
  ReadResourcesIssue(InstalledArenaLocalHostResourcesIssue)
  ReadComponentIssue(InstalledArenaCryptoIssue)
  ReadLibraryIssue(@signature.NativeSignatureIssue)
}

///|
/// Transport DATA retains the same component and partial Library. Neither an
/// operation reply nor releasing it acknowledges Read/domain/parent retirement.
struct InstalledArenaReadCryptoReply {
  operation : Int
  host : InstalledArenaHost
  pair : InstalledArenaLocalHostResources
  read : InstalledArenaOriginalRead
  component : InstalledArenaCryptoComponent?
  library : @signature.Library?
  issue : ReadCryptoReplyIssue?
  bytes : Bytes?
  verified : Bool?
}

///|
fn read_crypto_reply(
  operation : Int,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  component : InstalledArenaCryptoComponent?,
  library : @signature.Library?,
  issue : ReadCryptoReplyIssue?,
  bytes? : Bytes,
  verified? : Bool,
) -> InstalledArenaReadCryptoReply {
  {
    operation,
    host: read.domain.host,
    pair,
    read,
    component,
    library,
    issue,
    bytes,
    verified,
  }
}

///|
pub fn prepare_installed_arena_read_crypto_reply(
  host : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
) -> InstalledArenaReadCryptoReply {
  let (component, issue) = match
    host.prepare_local_host_read_crypto_control(pair, read) {
    Ok(value) => (Some(value), None)
    Err(Resources(issue)) => (None, Some(ReadResourcesIssue(issue)))
    Err(Crypto(issue)) => (None, Some(ReadComponentIssue(issue)))
  }
  read_crypto_reply(1, pair, read, component, None, issue)
}

///|
fn InstalledArenaHost::require_read_crypto_reply_original(
  self : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  component : InstalledArenaCryptoComponent,
) -> Result[Unit, ReadCryptoReplyIssue] {
  match self.require_local_host_consuming_read_current(pair, read) {
    Err(issue) => return Err(ReadResourcesIssue(issue))
    Ok(_) => ()
  }
  match self.original_crypto_component(component) {
    Err(issue) => return Err(ReadComponentIssue(issue))
    Ok(_) => ()
  }
  if !physical_equal(component.domain, read.domain) ||
    pair.active != Some(HostRead) {
    return Err(
      ReadComponentIssue(
        Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)),
      ),
    )
  }
  component.domain.backing
  .require_backed_read_context_entered(
    self,
    component.domain.domain.unwrap(),
    component.domain,
  )
  .map_err(issue => ReadComponentIssue(Domain(issue)))
}

///|
/// Same physical frame observation for the synchronous foreign transport.
/// The operation itself repeats the original checks; this issues no scope.
pub fn current_installed_arena_read_crypto_original(
  host : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  component : InstalledArenaCryptoComponent,
) -> Bool {
  host.require_read_crypto_reply_original(pair, read, component) is Ok(_)
}

///|
pub fn load_installed_arena_read_crypto_reply(
  host : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  component : InstalledArenaCryptoComponent,
  path : String,
  heap : Int64,
  diagnostic : Int,
) -> InstalledArenaReadCryptoReply {
  let issue = match
    host.require_read_crypto_reply_original(pair, read, component) {
    Err(issue) => Some(issue)
    Ok(_) =>
      match
        host.prepare_local_host_read_crypto(pair, read, path, heap, diagnostic) {
        Err(Resources(issue)) => Some(ReadResourcesIssue(issue))
        Err(Crypto(issue)) => Some(ReadComponentIssue(issue))
        Ok(ReadyCrypto(_)) => None
        Ok(PendingCrypto(_, issue)) => Some(ReadComponentIssue(issue))
      }
  }
  read_crypto_reply(2, pair, read, Some(component), None, issue)
}

///|
pub fn open_installed_arena_read_crypto_library_reply(
  host : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  component : InstalledArenaCryptoComponent,
) -> InstalledArenaReadCryptoReply {
  let mut library : @signature.Library? = None
  let issue = match
    host.require_read_crypto_reply_original(pair, read, component) {
    Err(issue) => Some(issue)
    Ok(_) =>
      match host.current_crypto_component(component) {
        Err(issue) => Some(ReadComponentIssue(issue))
        Ok(original) =>
          match original.new_library() {
            Err(issue) => Some(ReadLibraryIssue(issue))
            Ok(@signature.ReadyCryptoLibrary(value)) => {
              library = Some(value)
              None
            }
            Ok(@signature.PendingCryptoLibrary(value, issue)) => {
              library = Some(value)
              Some(ReadLibraryIssue(issue))
            }
          }
      }
  }
  read_crypto_reply(3, pair, read, Some(component), library, issue)
}

///|
fn InstalledArenaHost::require_read_crypto_library_original(
  self : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  component : InstalledArenaCryptoComponent,
  library : @signature.Library,
) -> Result[Unit, ReadCryptoReplyIssue] {
  match self.require_read_crypto_reply_original(pair, read, component) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard component.component is Some(original) && original.owns_library(library) else {
    return Err(
      ReadComponentIssue(
        Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)),
      ),
    )
  }
  Ok(())
}

///|
pub fn close_installed_arena_read_crypto_library_reply(
  host : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  component : InstalledArenaCryptoComponent,
  library : @signature.Library,
) -> InstalledArenaReadCryptoReply {
  let result = match
    host.require_read_crypto_library_original(pair, read, component, library) {
    Err(issue) => Err(issue)
    Ok(_) => library.close_checked().map_err(issue => ReadLibraryIssue(issue))
  }
  read_crypto_reply(
    4,
    pair,
    read,
    Some(component),
    Some(library),
    match result {
      Ok(_) => None
      Err(issue) => Some(issue)
    },
  )
}

///|
pub fn close_installed_arena_read_crypto_reply(
  host : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  component : InstalledArenaCryptoComponent,
) -> InstalledArenaReadCryptoReply {
  let result = match
    host.require_read_crypto_reply_original(pair, read, component) {
    Err(issue) => Err(issue)
    Ok(_) =>
      host
      .close_crypto_component(component)
      .map_err(issue => ReadComponentIssue(issue))
  }
  read_crypto_reply(
    5,
    pair,
    read,
    Some(component),
    None,
    match result {
      Ok(_) => None
      Err(issue) => Some(issue)
    },
  )
}

///|
pub fn hmac_installed_arena_read_crypto_reply(
  host : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  component : InstalledArenaCryptoComponent,
  library : @signature.Library,
  key : Bytes,
  data : Bytes,
) -> InstalledArenaReadCryptoReply {
  let result = match
    host.require_read_crypto_library_original(pair, read, component, library) {
    Err(issue) => Err(issue)
    Ok(_) =>
      library.hmac_sha256(key, data).map_err(issue => ReadLibraryIssue(issue))
  }
  match result {
    Ok(bytes) =>
      read_crypto_reply(
        6,
        pair,
        read,
        Some(component),
        Some(library),
        None,
        bytes~,
      )
    Err(issue) =>
      read_crypto_reply(
        6,
        pair,
        read,
        Some(component),
        Some(library),
        Some(issue),
      )
  }
}

///|
pub fn verify_hmac_installed_arena_read_crypto_reply(
  host : InstalledArenaHost,
  pair : InstalledArenaLocalHostResources,
  read : InstalledArenaOriginalRead,
  component : InstalledArenaCryptoComponent,
  library : @signature.Library,
  key : Bytes,
  data : Bytes,
  signature : Bytes,
) -> InstalledArenaReadCryptoReply {
  let result = match
    host.require_read_crypto_library_original(pair, read, component, library) {
    Err(issue) => Err(issue)
    Ok(_) =>
      library
      .verify_hmac_sha256(key, data, signature)
      .map_err(issue => ReadLibraryIssue(issue))
  }
  match result {
    Ok(verified) =>
      read_crypto_reply(
        7,
        pair,
        read,
        Some(component),
        Some(library),
        None,
        verified~,
      )
    Err(issue) =>
      read_crypto_reply(
        7,
        pair,
        read,
        Some(component),
        Some(library),
        Some(issue),
      )
  }
}

///|
pub fn InstalledArenaReadCryptoReply::original_host(
  self : InstalledArenaReadCryptoReply,
) -> InstalledArenaHost {
  self.host
}

///|
pub fn InstalledArenaReadCryptoReply::original_resources(
  self : InstalledArenaReadCryptoReply,
) -> InstalledArenaLocalHostResources {
  self.pair
}

///|
pub fn InstalledArenaReadCryptoReply::original_read(
  self : InstalledArenaReadCryptoReply,
) -> InstalledArenaOriginalRead {
  self.read
}

///|
pub fn InstalledArenaReadCryptoReply::original_component(
  self : InstalledArenaReadCryptoReply,
) -> InstalledArenaCryptoComponent? {
  self.component
}

///|
pub fn InstalledArenaReadCryptoReply::original_library(
  self : InstalledArenaReadCryptoReply,
) -> @signature.Library? {
  self.library
}

///|
pub fn InstalledArenaReadCryptoReply::operation_tag(
  self : InstalledArenaReadCryptoReply,
) -> Int {
  self.operation
}

///|
pub fn InstalledArenaReadCryptoReply::issue_origin(
  self : InstalledArenaReadCryptoReply,
) -> Int {
  match self.issue {
    None => 0
    Some(ReadResourcesIssue(Domain(_))) => 1
    Some(ReadResourcesIssue(Read(_))) => 2
    Some(ReadResourcesIssue(Sqlite(_))) => 3
    Some(ReadComponentIssue(Domain(_))) => 4
    Some(ReadComponentIssue(Signature(_))) | Some(ReadLibraryIssue(_)) => 5
  }
}

///|
fn read_crypto_signature_family(issue : @signature.NativeSignatureIssue) -> Int {
  match issue {
    UnsupportedTarget => 1
    InvalidInput => 2
    LibraryLoad(_) => 3
    InvalidPublicKey(_) => 4
    InvalidPrivateKey(_) => 5
    UnsupportedKey(_) => 6
    Verification(_) => 7
    Signing(_) => 8
    CleanupPending => 9
    CloseUnconfirmed(_) => 10
  }
}

///|
pub fn InstalledArenaReadCryptoReply::issue_family(
  self : InstalledArenaReadCryptoReply,
) -> Int {
  match self.issue {
    None => 0
    Some(ReadResourcesIssue(Domain(@bootstrap.Bootstrap(issue)))) =>
      installed_arena_issue_family(Some(issue))
    Some(ReadResourcesIssue(Domain(@bootstrap.Accounting(_)))) => 8
    Some(ReadResourcesIssue(Read(issue))) =>
      original_read_issue_family(Some(issue))
    Some(ReadResourcesIssue(Sqlite(issue))) =>
      sqlite_reply_issue_family(Some(issue))
    Some(ReadComponentIssue(Domain(@bootstrap.Bootstrap(issue)))) =>
      installed_arena_issue_family(Some(issue))
    Some(ReadComponentIssue(Domain(@bootstrap.Accounting(_)))) => 8
    Some(ReadComponentIssue(Signature(issue)))
    | Some(ReadLibraryIssue(issue)) => read_crypto_signature_family(issue)
  }
}

///|
pub fn InstalledArenaReadCryptoReply::close_confirmed(
  self : InstalledArenaReadCryptoReply,
) -> Bool {
  self.issue is None &&
  (
    self.operation == 4 ||
    (self.operation == 5 && self.component is Some(original) && original.closed)
  )
}

///|
pub fn InstalledArenaReadCryptoReply::output_length(
  self : InstalledArenaReadCryptoReply,
) -> Int {
  match self.bytes {
    Some(bytes) => bytes.length()
    None => -1
  }
}

///|
pub fn InstalledArenaReadCryptoReply::output_byte(
  self : InstalledArenaReadCryptoReply,
  index : Int,
) -> Int {
  match self.bytes {
    Some(bytes) =>
      if index >= 0 && index < bytes.length() {
        bytes[index].to_int()
      } else {
        -1
      }
    None => -1
  }
}

///|
pub fn InstalledArenaReadCryptoReply::verification(
  self : InstalledArenaReadCryptoReply,
) -> Int {
  match self.verified {
    Some(true) => 1
    Some(false) => 0
    None => -1
  }
}
