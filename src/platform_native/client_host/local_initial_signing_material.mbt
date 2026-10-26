///|
/// One original initial creation's physical material. Not authenticated journal
/// custody, a configured signer, public-key CID, grant or signing permission.
struct NativeLocalInitialSigningMaterial {
  origin : Ref[Bool]
  root : @filesystem.Root
  library : @crypto.Library
  generation : @filesystem.NativeFileGeneration
  projection : @filesystem.PrivateFileProjection
  public_key_pem : String
  host_attestation : NativeLocalInitialSigningFile
}

///|
// A second physical file in the same one-time initializer, never a replacement
// key for a retained/partial installation or an operational signing permit.
priv struct NativeLocalInitialSigningFile {
  generation : @filesystem.NativeFileGeneration
  projection : @filesystem.PrivateFileProjection
  public_key_pem : String
}

///|
/// Preserve the primary failure separately from original physical cleanup.
/// This failed operation is never changed to successful by a cleanup ACK.
struct NativeLocalInitialSigningFailure {
  original_issue : NativeLocalAdoptionIssue
  mut acquisition : @filesystem.NativeWriterOpenFailure?
  mut writer : @filesystem.Writer?
}

///|
pub fn NativeLocalInitialSigningFailure::issue(
  self : NativeLocalInitialSigningFailure,
) -> NativeLocalAdoptionIssue {
  self.original_issue
}

///|
/// Cleanup only: no key generation, append replay, seal, adoption or new Writer.
pub fn NativeLocalInitialSigningFailure::retry_cleanup(
  self : NativeLocalInitialSigningFailure,
) -> Result[Unit, @filesystem.NativeFilesystemIssue] {
  if self.acquisition is Some(original) {
    match original.retry_cleanup() {
      Err(issue) => return Err(issue)
      Ok(_) => self.acquisition = None
    }
  }
  if self.writer is Some(original) {
    match original.close_retaining_files() {
      Err(issue) => return Err(issue)
      Ok(_) => self.writer = None
    }
  }
  Ok(())
}

///|
fn initial_signing_unavailable(
  issue : NativeLocalAdoptionIssue,
) -> NativeLocalInitialSigningFailure {
  { original_issue: issue, acquisition: None, writer: None, }
}

///|
fn NativeLocalAdoptionSession::initial_signing_refusal(
  self : NativeLocalAdoptionSession,
  issue : NativeLocalAdoptionIssue,
  acquisition? : @filesystem.NativeWriterOpenFailure? = None,
  writer? : @filesystem.Writer? = None,
) -> NativeLocalInitialSigningFailure {
  let failure : NativeLocalInitialSigningFailure = {
    original_issue: issue,
    acquisition,
    writer,
  }
  self.initial_signing_failure.val = Some(failure)
  // Best-effort retirement retains the original failure and same carrier on
  // unconfirmed close. Even a known cleanup never makes this operation ready.
  failure.retry_cleanup() |> ignore
  failure
}

///|
/// Trusted initial installer only. Eligibility comes from the actual exclusive
/// state-directory creation and is consumed before crypto or file acquisition.
/// Existing/reopened/partial state never selects fresh generation, even when
/// every key byte is missing. No caller-provided fresh Boolean is accepted.
pub fn NativeLocalAdoptionSession::create_initial_signing_material(
  self : NativeLocalAdoptionSession,
  crypto : @crypto.Library,
) -> Result[NativeLocalInitialSigningMaterial, NativeLocalInitialSigningFailure] {
  if self.initial_signing_failure.val is Some(failure) {
    return Err(failure)
  }
  match self.check_original() {
    Err(issue) => return Err(initial_signing_unavailable(issue))
    Ok(_) => ()
  }
  if !self.initial_signing_eligible.val {
    return Err(initial_signing_unavailable(AmbiguousInitialization))
  }
  self.initial_signing_eligible.val = false
  for
    name in [
      "local-signing-key.pem", "local-signing-key.pem.stage", "local-host-attestation-key.pem",
      "local-host-attestation-key.pem.stage", "client.sqlite3", "journal-custody.json",
      "journal-initializing.json",
    ] {
    match self.root.inspect_generation(name) {
      Ok(None) => ()
      Ok(Some(_)) => return Err(self.initial_signing_refusal(CustodyLost))
      Err(issue) => return Err(self.initial_signing_refusal(Filesystem(issue)))
    }
  }
  let reviewer = match
    self.create_initial_signing_file(crypto, "local-signing-key.pem") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let host = match
    self.create_initial_signing_file(crypto, "local-host-attestation-key.pem") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Both are actual freshly generated RFC8410 keys. Equal public originals
  // cannot satisfy role separation and never trigger a generation retry.
  if reviewer.public_key_pem == host.public_key_pem {
    return Err(self.initial_signing_refusal(CustodyLost))
  }
  Ok({
    origin: self.initial_signing_eligible,
    root: self.root,
    library: crypto,
    generation: reviewer.generation,
    projection: reviewer.projection,
    public_key_pem: reviewer.public_key_pem,
    host_attestation: host,
  })
}

///|
fn NativeLocalAdoptionSession::create_initial_signing_file(
  self : NativeLocalAdoptionSession,
  crypto : @crypto.Library,
  name : String,
) -> Result[NativeLocalInitialSigningFile, NativeLocalInitialSigningFailure] {
  // Acquire/retain the actual exclusive Writer before creating secret material.
  let writer = match
    self.root.create_writer_with_custody(name + ".stage", 119L) {
    Ok(value) => value
    Err(failure) =>
      return Err(
        self.initial_signing_refusal(
          Filesystem(failure.issue()),
          acquisition=Some(failure),
        ),
      )
  }
  let (private_pem, public_pem) = match crypto.generate_ed25519_key_pair() {
    Ok(value) => value
    Err(issue) =>
      return Err(
        self.initial_signing_refusal(Crypto(issue), writer=Some(writer)),
      )
  }
  // RFC8410 representation lengths are checked format facts, not a memory
  // reservation or proof of the full Library/Writer/installer overlap budget.
  if private_pem.length() != 119 || public_pem.length() != 113 {
    return Err(self.initial_signing_refusal(Encoding, writer=Some(writer)))
  }
  match writer.append(private_pem) {
    Err(issue) =>
      return Err(
        self.initial_signing_refusal(
          WritePending(writer, issue),
          writer=Some(writer),
        ),
      )
    Ok(_) => ()
  }
  let generation = match writer.seal(name) {
    Err(issue) =>
      return Err(
        self.initial_signing_refusal(
          WritePending(writer, issue),
          writer=Some(writer),
        ),
      )
    Ok(value) => value
  }
  match self.check_original() {
    Err(issue) => return Err(self.initial_signing_refusal(issue))
    Ok(_) => ()
  }
  let projection = match self.root.adopt_private_file_projection(name) {
    Err(issue) => return Err(self.initial_signing_refusal(Filesystem(issue)))
    Ok(value) => value
  }
  Ok({ generation, projection, public_key_pem: public_pem, })
}

///|
/// Current physical correspondence only, before the existing authenticated
/// installation journal adopts it. DATA/PEM/path equality never selects origin.
pub fn NativeLocalAdoptionSession::initial_signing_public_key(
  self : NativeLocalAdoptionSession,
  material : NativeLocalInitialSigningMaterial,
) -> Result[String, NativeLocalAdoptionIssue] {
  match self.check_original() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(material.origin, self.initial_signing_eligible) ||
    !physical_equal(material.root, self.root) ||
    !self.root.verify_generation("local-signing-key.pem", material.generation) {
    return Err(CustodyLost)
  }
  match self.initial_host_signing_public_key(material) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let original = match material.projection.export_original() {
    Err(issue) => return Err(Filesystem(issue))
    Ok(value) => value
  }
  match self.root.restore_private_file_projection(original) {
    Err(issue) => Err(Filesystem(issue))
    Ok(_) => Ok(material.public_key_pem)
  }
}

///|
fn NativeLocalAdoptionSession::initial_host_signing_public_key(
  self : NativeLocalAdoptionSession,
  material : NativeLocalInitialSigningMaterial,
) -> Result[String, NativeLocalAdoptionIssue] {
  match self.check_original() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let selected = material.host_attestation
  if !physical_equal(material.origin, self.initial_signing_eligible) ||
    !physical_equal(material.root, self.root) ||
    !self.root.verify_generation(
      "local-host-attestation-key.pem",
      selected.generation,
    ) {
    return Err(CustodyLost)
  }
  let exported = match selected.projection.export_original() {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  match self.root.restore_private_file_projection(exported) {
    Ok(_) => Ok(selected.public_key_pem)
    Err(issue) => Err(Filesystem(issue))
  }
}
