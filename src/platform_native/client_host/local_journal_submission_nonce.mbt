///|
/// Sample one bounded correlation nonce using this captured original Library
/// under its actual Read. This issues no epoch, signing use or Run; the fresh
/// caller retains the sample, while saved submissions keep their own originals.
pub fn NativeLocalJournalCapture::submission_nonce_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  expected_scope : String,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  let authorized = self.with_current_adoption_material_in_original_read((
    host,
    material,
    _operations,
  ) => {
    match
      self.original_submit_allowed(
        host, material, principal, connection, expected_scope,
      ) {
      Ok(true) => self.crypto.random_bytes(32).map_err(issue => Crypto(issue))
      Ok(false) => Err(AuthorizationDenied)
      Err(issue) => Err(issue)
    }
  })
  let nonce = match authorized {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // A later current/Account failure never retries the physical sample.
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    _operations,
  ) => {
    match
      self.original_submit_allowed(
        host, material, principal, connection, expected_scope,
      ) {
      Ok(true) => Ok(nonce)
      Ok(false) => Err(AuthorizationDenied)
      Err(issue) => Err(issue)
    }
  })
}
