///|
/// Explicit initial installer metadata only. Every name must already select
/// an authenticated original in this adoption. A name, kind or copied CID
/// provides no key custody, issuer authority, use claim or signing permission.
pub(all) struct NativeLocalSigningInstallationSelection {
  key_configuration_file : String
  reviewer_configuration_file : String?
  checkpoint_kind : @checkpoint.CheckpointKind
}

///|
// Do not grow an installation pool or discover files. Reject malformed
// selections before creating schema/keys. This is syntax/selection validation,
// never the current purpose authorization consumed by the original installer.
fn NativeLocalAdoptionSession::check_signing_installation_selections(
  self : NativeLocalAdoptionSession,
  selections : Array[NativeLocalSigningInstallationSelection],
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if selections.length() > self.settings.files.length() {
    return Err(ConfigurationLimit)
  }
  for index, selection in selections {
    for previous in 0..<index {
      if selections[previous].key_configuration_file ==
        selection.key_configuration_file {
        return Err(InvalidInput)
      }
    }
    guard self.settings.files
      .iter()
      .find_first(file => file.name == selection.key_configuration_file)
      is Some(file) else {
      return Err(InvalidInput)
    }
    let wire = @utf8.decode(file.body) catch { _ => return Err(Encoding) }
    let key = match
      @credential_resource.admit_native_local_signing_key_selection(wire) {
      Ok(value) => value
      Err(_) => return Err(InvalidInput)
    }
    let (enabled, purpose, principal, connection, _, key_id, _, public_key) = @credential_resource.native_local_signing_key_selection_projection(
      key,
    )
    if !enabled ||
      !@credential_resource.native_local_signing_key_selection_allows_kind(
        key,
        selection.checkpoint_kind,
      ) {
      return Err(InvalidInput)
    }
    match (purpose, selection.reviewer_configuration_file) {
      (@credential.HostAttestation, None) => ()
      (@credential.ReviewerProof, Some(name)) => {
        guard self.settings.files.iter().find_first(file => file.name == name)
          is Some(reviewer_file) else {
          return Err(InvalidInput)
        }
        let text = @utf8.decode(reviewer_file.body) catch {
          _ => return Err(Encoding)
        }
        guard admit_native_local_effect_reviewer_selection(text) is Ok(reviewer) &&
          reviewer.enabled &&
          reviewer.principal == principal &&
          reviewer.connection == connection &&
          reviewer.key_id == key_id &&
          reviewer.public_key_pem == public_key else {
          return Err(InvalidInput)
        }
      }
      _ => return Err(InvalidInput)
    }
  }
  Ok(())
}

///|
// Preserve any original physical cleanup/Unknown carrier. This adds no
// auto-retry or fallback capture after a missing/failed restore.
fn signing_bootstrap_issue(
  issue : NativeLocalSigningOriginalIssue,
) -> NativeLocalAdoptionIssue {
  match issue {
    SigningJournal(value) => Journal(value)
    SigningCustody(value) => value
    SigningAccount(_) | SigningOriginalUnavailable => CustodyLost
  }
}

///|
// Only open_journal_selected calls this with its actual first-initialization
// fact. No public Boolean or current policy can manufacture that fact. The
// initial Host transaction has succeeded before any selected installation;
// each original uses the same existing HMAC/counter/reservation transaction.
fn NativeLocalHostConnection::bootstrap_signing_originals(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  selections : Array[NativeLocalSigningInstallationSelection],
  first : Bool,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  for selection in selections {
    let reviewer = match selection.reviewer_configuration_file {
      None => None
      Some(name) =>
        match self.install_effect_reviewer(configuration_file=Some(name)) {
          Ok(value) => Some(value)
          Err(_) => return Err(CustodyLost)
        }
    }
    let account = match
      self.acquire_signing_key_account(
        crypto,
        selection.key_configuration_file,
        selection.checkpoint_kind,
        reviewer~,
      ) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
    let original = if first {
      account.capture_signing_key_original()
    } else {
      account.restore_signing_key_original()
    }
    match original {
      Ok(_) => ()
      Err(issue) => return Err(signing_bootstrap_issue(issue))
    }
  }
  Ok(())
}

///|
/// Explicit trusted initial installation of selected Signing public identities
/// and original private-file generation metadata. This reads no private key
/// body and performs no signature, issuer issue, grant adoption or use claim.
/// Ordinary open_journal remains unchanged and never discovers or enables it.
///
/// Capture is confined to the original first journal initialization. Any
/// existing marker/DB uses authenticated restore only, including when the
/// caller omits existing_only. Missing/legacy/changed originals stay refused;
/// Unknown initialization or append never mints a fresh capture on reopening.
pub fn NativeLocalAdoptionSession::open_journal_with_signing_originals(
  self : NativeLocalAdoptionSession,
  library : @sqlite.Library,
  crypto : @crypto.Library,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
  selections : Array[NativeLocalSigningInstallationSelection],
  max_retained_intent_bytes? : Int64 = 67108864L,
) -> Result[NativeLocalHostConnection, NativeLocalAdoptionIssue] {
  match self.check_signing_installation_selections(selections) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.open_journal_selected(
    library,
    crypto,
    ttl_ms,
    max_records,
    max_snapshot_bytes,
    selections,
    max_retained_intent_bytes~,
  )
}
