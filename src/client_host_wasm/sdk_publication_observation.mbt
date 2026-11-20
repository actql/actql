///|
/// Retained original same-Store publication observation shared by existing
/// cancellation and RunState projections. This carrier issues no authority.
priv struct StoredSDKPublicationObservation {
  run : @host.ClientRunJournalEncoding
  fences : Array[(String, String, @host.ClientJournalPhysicalRow?)]
  mut owner : @publication.PublicationCommitPreparation?
  mut view : @publication.PublicationCommitReadView?
  mut observed : Bool
  mut terminal : Bool?
}

///|
fn sdk_publication_observation_original(
  run : @host.ClientRunJournalEncoding,
) -> StoredSDKPublicationObservation {
  { run, fences: [], owner: None, view: None, observed: false, terminal: None, }
}

///|
fn sdk_publication_observation(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  retained : StoredSDKPublicationObservation,
) -> Result[Bool, Int] {
  guard configuration.sdk is Some(sdk) &&
    configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(current) &&
    current.generation is Some((device, inode)) &&
    @host.client_publication_store_binding_body(
      configuration.run_namespace,
      sdk.store_authority_cid,
      device,
      inode,
    )
    is Ok(binding) else {
    return Err(-32)
  }
  let run = retained.run
  // A genuinely unstarted row may precede publication binding. It still uses
  // this SAME adopted physical Store and scoped publication read. Once bound,
  // only that exact original binding can enter the terminal observer.
  match run.publication_binding {
    Some(original) if original != binding => return Err(-32)
    None if run.dispatch_reserved || run.physical_start_claimed =>
      return Err(-32)
    _ => ()
  }
  let check = () => submission_lookup_current(value, record, configuration)
  let contract_limit = 256
  let read = (table, key) => {
    // The scoped index pointer is an additional physical row, not one of the
    // existing loader's bounded contracts. Preserve its full selected profile.
    if retained.fences.length() >= contract_limit + 1 {
      return Err(-34)
    }
    physical_journal_row(current.physical, check, 1, table, key).bind(row => {
      if row is Some(row) && row.key != key {
        return Err(-41)
      }
      // Absence is retained too: a publication racing the pre-write snapshot
      // cannot turn this original nonterminal decision into a write.
      retained.fences.push((table, key, row))
      Ok(row.map(row => row.body))
    })
  }
  let owner = match
    @publication.read_stored_effect_free_publication(
      configuration.run_namespace,
      configuration.authority_scope_cid,
      @publication.publication_contract_identity(run.definition),
      read,
      check,
      contract_limit,
      8388608,
      262144,
      65536,
      64,
      131072,
    ) {
    Ok(None) => {
      retained.terminal = Some(false)
      return Ok(false)
    }
    Ok(Some(owner)) => owner
    Err(Read(code)) => return Err(code)
    Err(_) => return Err(-31)
  }
  retained.owner = Some(owner)
  let mut done = false
  for _ in 0..<250000 {
    match owner.advance(256) {
      Ok((true, _)) => {
        done = true
        break
      }
      Ok((false, _)) => ()
      Err(_) => return Err(-31)
    }
  }
  if !done {
    return Err(-34)
  }
  let view = match owner.finish_view() {
    Ok(view) => view
    Err(_) => return Err(-31)
  }
  retained.view = Some(view)
  guard owner.view_contract(view, 5) is Ok(request) &&
    owner.view_contract(view, 6) is Ok(attempt) &&
    owner.view_contract(view, 7) is Ok(index) &&
    owner.begin_observed_commit(view, request, attempt, index) is Ok(_) else {
    return Err(-31)
  }
  retained.observed = true
  done = false
  for _ in 0..<250000 {
    match owner.advance_observed_commit(view, 256) {
      Ok((true, _)) => {
        done = true
        break
      }
      Ok((false, _)) => ()
      Err(_) => return Err(-31)
    }
  }
  if !done {
    return Err(-34)
  }
  match check() {
    Err(code) => Err(code)
    Ok(_) => {
      retained.terminal = Some(true)
      Ok(true)
    }
  }
}

///|
fn validate_sdk_publication_observation(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  retained : StoredSDKPublicationObservation,
) -> Int {
  guard configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(current) else {
    return -32
  }
  let check = () => submission_lookup_current(value, record, configuration)
  for (table, key, before) in retained.fences {
    match physical_journal_row(current.physical, check, 1, table, key) {
      Err(code) => return code
      Ok(after) =>
        match (before, after) {
          (None, None) => ()
          (Some(a), Some(b)) if a.key == b.key &&
            a.revision == b.revision &&
            a.body == b.body => ()
          _ => return -32
        }
    }
  }
  match check() {
    Ok(_) => 0
    Err(code) => code
  }
}

///|
fn close_sdk_publication_observation(
  retained : StoredSDKPublicationObservation,
) -> Int {
  if retained.owner is Some(owner) {
    owner.cancel()
    if retained.view is Some(view) {
      if retained.observed {
        if owner.release_observed_commit(view) is Err(_) {
          return -9
        }
        retained.observed = false
      }
      if owner.release_view(view) is Err(_) {
        return -9
      }
      retained.view = None
    }
  }
  0
}
