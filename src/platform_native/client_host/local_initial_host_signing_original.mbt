///|
/// The independent Host-purpose original captured by the same actual fresh
/// initialization. This metadata/projection supplies no Account sign decision,
/// claim, attestation signature, Resolution admission or cleanup acknowledgement.
struct NativeLocalInitialHostSigningOriginal {
  reviewer : NativeLocalInitialSigningOriginal
  projection : @filesystem.PrivateFileProjection
  exported : Bytes
  public_key : @credential.LocalSigningPublicKey
  public_key_pem : String
  signing_subject : (String, String, String)?
}

///|
fn read_local_initial_host_signing_control(
  host : NativeLocalHostConnection,
  body : Bytes,
  signing_original? : NativeLocalInitialSigningOriginal? = None,
) -> Result[NativeLocalInitialSigningFields, NativeLocalAdoptionIssue] {
  read_local_initial_host_signing_control_with_subject(
    host,
    body,
    signing_original~,
  ).map(pair => pair.0)
}

///|
// Consume the Host fields/subject checked by this immediate control admission.
// A later physical or current boundary must still perform its own fresh read.
fn read_local_initial_host_signing_control_with_subject(
  host : NativeLocalHostConnection,
  body : Bytes,
  signing_original? : NativeLocalInitialSigningOriginal? = None,
) -> Result[
  (NativeLocalInitialSigningFields, (String, String, String)?),
  NativeLocalAdoptionIssue,
] {
  guard read_local_initial_signing_control_with_host_key(
      host,
      body,
      signing_original~,
    )
    is Ok(Some((reviewer, Some((fields, subject))))) else {
    return Err(CustodyLost)
  }
  if fields.policy.cid() != reviewer.policy.cid() ||
    fields.issuer != reviewer.issuer {
    return Err(CustodyLost)
  }
  Ok((fields, subject))
}

///|
/// Read the already-authenticated independent Host key generation only.
/// A raw/legacy Reviewer-only control, missing file or partial initialization
/// cannot create or adopt another key, even if a matching PEM is present now.
pub fn NativeLocalHostConnection::restore_initial_host_signing_original(
  self : NativeLocalHostConnection,
  reviewer_original? : NativeLocalInitialSigningOriginal? = None,
) -> Result[NativeLocalInitialHostSigningOriginal, NativeLocalAdoptionIssue] {
  let reviewer = match reviewer_original {
    Some(original) => {
      if !physical_equal(original.host, self) {
        return Err(CustodyLost)
      }
      match original.require_current() {
        Ok(_) => original
        Err(issue) => return Err(issue)
      }
    }
    None =>
      match self.restore_initial_signing_original() {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
  }
  let signing_original = if reviewer.original_read is Some(_) {
    Some(reviewer)
  } else {
    None
  }
  let (fields, subject) = match
    read_local_initial_host_signing_control_with_subject(
      self,
      reviewer.control_body,
      signing_original~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let projection = match
    self.session.root.restore_private_file_projection(fields.exported) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let original : NativeLocalInitialHostSigningOriginal = {
    reviewer,
    projection,
    exported: fields.exported,
    public_key: fields.public_key,
    public_key_pem: fields.public_key_pem,
    // The same original Read admitted this immutable subject with its fields.
    // Keep that DATA; the complete post-projection current check below still
    // authenticates the control and subject after the physical boundary.
    signing_subject: if signing_original is Some(_) {
      subject
    } else {
      match
        read_initial_host_signing_subject(
          self,
          reviewer.control_body,
          fields,
          signing_original~,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    },
  }
  original.require_current().map(_ => original)
}

///|
/// Same original Root/file and authenticated control only; purpose-specific
/// current actor, Account and signing-use gates remain operational obligations.
pub fn NativeLocalInitialHostSigningOriginal::require_current(
  self : NativeLocalInitialHostSigningOriginal,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match self.reviewer.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let host = self.reviewer.host
  let signing_original = if self.reviewer.original_read is Some(_) {
    Some(self.reviewer)
  } else {
    None
  }
  let (fields, subject) = match
    read_local_initial_host_signing_control_with_subject(
      host,
      self.reviewer.control_body,
      signing_original~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if fields.exported != self.exported ||
    fields.public_key_pem != self.public_key_pem ||
    fields.public_key.cid() != self.public_key.cid() ||
    subject != self.signing_subject {
    return Err(CustodyLost)
  }
  guard self.projection.export_original() is Ok(exported) &&
    exported == self.exported else {
    return Err(CustodyLost)
  }
  match host.session.root.restore_private_file_projection(self.exported) {
    Ok(_) => ()
    Err(issue) => return Err(Filesystem(issue))
  }
  self.reviewer.check_host_current()
}

///|
/// Public-key identity DATA only. It neither reads the secret nor signs.
pub fn NativeLocalInitialHostSigningOriginal::public_key(
  self : NativeLocalInitialHostSigningOriginal,
) -> Result[@credential.LocalSigningPublicKey, NativeLocalAdoptionIssue] {
  self.require_current().map(_ => self.public_key)
}

///|
/// Same original initialization issuer DATA, never a generic issuance service.
pub fn NativeLocalInitialHostSigningOriginal::issuer_identity(
  self : NativeLocalInitialHostSigningOriginal,
) -> Result[String, NativeLocalAdoptionIssue] {
  self.require_current().map(_ => self.reviewer.issuer)
}

///|
pub fn NativeLocalInitialHostSigningOriginal::policy(
  self : NativeLocalInitialHostSigningOriginal,
) -> Result[@host.ClientLocalSigningBootstrapPolicy, NativeLocalAdoptionIssue] {
  self.require_current().map(_ => self.reviewer.policy)
}
