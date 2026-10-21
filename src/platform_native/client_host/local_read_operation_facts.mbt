///|
// These slots belong to the existing closed Native command capture. They are
// cleared before/after its public operation and on relevant invalidation;
// they are neither persistent authority nor a physical cleanup acknowledgement.
fn NativeLocalJournalCapture::clear_read_operation_facts(
  self : NativeLocalJournalCapture,
) -> Unit {
  self.read_material = None
  self.read_scopes.clear()
  self.read_decisions.clear()
  self.read_bindings.clear()
}

///|
fn NativeLocalJournalCapture::operation_scope(
  self : NativeLocalJournalCapture,
  host : NativeLocalHostConnection,
  material : @host.ClientLocalAdoptedHostMaterial[
    @sqlite.Database,
    NativeLocalAdoptionIssue,
  ],
  principal : String,
  connection : String,
) -> Result[String, NativeLocalAdoptionIssue] {
  guard self.opening is JournalAcquired(actual) && physical_equal(actual, host) else {
    return Err(CustodyLost)
  }
  match self.check_original_read_lifetime() {
    Err(issue) => {
      self.clear_read_operation_facts()
      return Err(issue)
    }
    Ok(_) => ()
  }
  if self.read_callback_active && self.read_facts_valid {
    if self.read_material is Some(original) &&
      !physical_equal(original, material) {
      return Err(CustodyLost)
    }
    for (p, c, scope) in self.read_scopes {
      if p == principal && c == connection {
        return Ok(scope)
      }
    }
  }
  let body = match
    @host.client_local_adopted_authority_scope_body(
      material,
      host.database,
      principal,
      connection,
    ) {
    Ok(value) => value
    Err(issue) => return Err(local_current_material_issue(issue))
  }
  native_timing_count(34)
  let scope = match local_adoption_digest(self.crypto, body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if self.read_callback_active && self.read_facts_valid {
    self.read_scopes.push((principal, connection, scope))
  }
  Ok(scope)
}

///|
fn NativeLocalJournalCapture::operation_account(
  self : NativeLocalJournalCapture,
  host : NativeLocalHostConnection,
  material : @host.ClientLocalAdoptedHostMaterial[
    @sqlite.Database,
    NativeLocalAdoptionIssue,
  ],
  tuple : @authorization.AccessTuple,
  target? : String? = None,
) -> Result[@authorization.AccountOutcome, NativeLocalAdoptionIssue] {
  guard self.opening is JournalAcquired(actual) && physical_equal(actual, host) else {
    return Err(CustodyLost)
  }
  match self.check_original_read_lifetime() {
    Err(issue) => {
      self.clear_read_operation_facts()
      return Err(issue)
    }
    Ok(_) => ()
  }
  if self.read_callback_active && self.read_facts_valid {
    if self.read_material is Some(original) &&
      !physical_equal(original, material) {
      return Err(CustodyLost)
    }
    for (original, run, outcome) in self.read_decisions {
      if run == target &&
        original.principal == tuple.principal &&
        original.connection == tuple.connection &&
        original.resource == tuple.resource &&
        original.operation == tuple.operation {
        return Ok(outcome)
      }
    }
  }
  native_timing_count(35)
  let outcome = match
    @host.client_local_adopted_account_outcome(material, host.database, tuple) {
    Ok(value) => value
    Err(issue) => return Err(local_current_material_issue(issue))
  }
  if self.read_callback_active && self.read_facts_valid {
    self.read_decisions.push((tuple, target, outcome))
  }
  Ok(outcome)
}

///|
fn NativeLocalReadPolicyBinding::current_operation_fact(
  self : NativeLocalReadPolicyBinding,
) -> Result[Bool, NativeLocalReadBindingIssue] {
  guard self.capture is Some(capture) &&
    capture.read_callback_active &&
    capture.read_facts_valid else {
    return Ok(false)
  }
  match capture.check_original_read_lifetime() {
    Err(issue) => {
      capture.clear_read_operation_facts()
      return Err(Adoption(issue))
    }
    Ok(_) => ()
  }
  guard capture.opening is JournalAcquired(host) &&
    physical_equal(host, self.host) &&
    self.run_policy_original is Some((_, request, _)) &&
    host.journal.admitted_record is Some((key, _, revision, _, _)) &&
    key == @host.client_request_scope_cid(request) else {
    return Ok(false)
  }
  Ok(
    capture.read_bindings.any(pair => {
      physical_equal(pair.0, self) && pair.1 == revision
    }),
  )
}

///|
fn NativeLocalReadPolicyBinding::retain_current_operation_fact(
  self : NativeLocalReadPolicyBinding,
) -> Unit {
  if self.capture is Some(capture) &&
    capture.read_callback_active &&
    capture.read_facts_valid &&
    self.run_policy_original is Some((_, request, _)) &&
    self.host.journal.admitted_record is Some((key, _, revision, _, _)) &&
    key == @host.client_request_scope_cid(request) {
    capture.read_bindings.push((self, revision))
  }
}
