///|
// Closed metadata on the EXISTING Model Scope owner. The compiler order and
// read partitions are fixed before its single original Run binding. Source
// acquisition may finish before the first descriptor; no snapshot is rebased.
priv struct ClientModelReadGroup {
  scopes : Array[ClientModelReadScope]
  reads : Array[ClientModelReadPreparation]
  mut pending_claim : @resources.FundedReadClaim[ClientModelReadOrigin]?
  retained_bytes : Int64
  execution_bytes : Int64
  mut attempted : Bool
  mut busy : Bool
  mut closing : Bool
  mut closed : Bool
}

///|
/// Complete native Scope/read/control construction inventory. The caller must
/// back these retained records and growth overlaps on the SAME preparation
/// before binding, in addition to the original census/descriptor inventory.
/// This returns representation DATA, never resource allowance or authority.
pub fn client_model_read_scopes_construction_inventory(
  count : Int,
) -> @execution.PreparationRepresentationUnits? {
  if count < 2 {
    return None
  }
  let n = count.to_int64()
  // Scope+Origin 2H10R4W each; scope.group Some1H1R1W each;
  // ReadPreparation1H3R2W + consumer Some1H1R1W each.
  // Group1H3R6W and its pending claim Some1H1R1W.
  // The private and returned Scope Arrays, read Array and three original/partition
  // Arrays coexist with the Resource declaration's members/consumer Arrays.
  guard @execution.preparation_array_representation(6L, 6L * n, true)
    is Some(arrays) &&
    @resources.original_read_children_construction_slots(count)
    is Some((h, r, w)) else {
    return None
  }
  Some({
    record_headers: 2L + 5L * n + arrays.record_headers + h,
    reference_slots: 4L + 15L * n + arrays.reference_slots + r,
    scalar_words: 7L + 8L * n + arrays.scalar_words + w,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// Bind the COMPLETE original compiler inventory once to its already installed
/// preparation census. Equal graphs, reordered subsets and another Run refuse
/// before claiming the binding word. Per-child read allowances are partitions
/// of one later read reservation, not independent grants or Ledgers.
pub fn bind_client_model_read_scopes(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plans : Array[ClientInferPlanGraph],
  ledger : @resources.Ledger,
  identity : @resources.OriginalLedgerIdentity,
  retained_bytes : Array[Int64],
  execution_bytes : Array[Int64],
) -> Result[Array[ClientModelReadScope], ClientModelReadPreparationIssue] {
  // Borrow the private compiler Array in place. No copied inventory or
  // temporary public getter projection is needed before this comparison.
  let originals = match compiled.compilation {
    Values(_) => return Err(ForeignRun)
    Tasks(original) => original.infers
    Effects(original) => original.compilation.compiled.infers
  }
  guard plans.length() >= 2 &&
    plans.length() == originals.length() &&
    plans.length() == retained_bytes.length() &&
    plans.length() == execution_bytes.length() &&
    check_client_compiled_run_definition(compiled, definition) is Ok(_) else {
    return Err(ForeignRun)
  }
  let mut r = 0L
  let mut e = 0L
  for index, plan in plans {
    if !physical_equal(originals[index], plan) ||
      retained_bytes[index] <= 0L ||
      execution_bytes[index] <= 0L {
      return Err(ForeignRun)
    }
    guard @execution.checked_preparation_add_product(
        r,
        retained_bytes[index],
        1L,
      )
      is Some(next_r) &&
      @execution.checked_preparation_add_product(e, execution_bytes[index], 1L)
      is Some(next_e) else {
      return Err(Resource(@resources.Resource(@resources.InvalidCharge)))
    }
    r = next_r
    e = next_e
  }
  match @resources.claim_original_ledger_run_binding(identity, ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  // No callbacks after the original one-shot binding until every child has
  // retained the same closed group. The caller funded this inventory first.
  let scopes : Array[ClientModelReadScope] = []
  let group : ClientModelReadGroup = {
    scopes,
    reads: [],
    pending_claim: None,
    retained_bytes: r,
    execution_bytes: e,
    attempted: false,
    busy: false,
    closing: false,
    closed: false,
  }
  for index, plan in plans {
    let origin : ClientModelReadOrigin = {
      compiled,
      model_limits: None,
      definition_cid: @publication.publication_contract_identity(definition),
      plan,
      host_policy_cid: @publication.run_publication_host_policy(
        compiled.admission,
      ),
      execution_context_cid: @publication.run_publication_execution_context(
        compiled.admission,
      ),
    }
    scopes.push({
      origin,
      ledger,
      identity,
      group: Some(group),
      retained_bytes: retained_bytes[index],
      execution_bytes: execution_bytes[index],
      read_attempted: false,
      finished: false,
    })
  }
  Ok(scopes.copy())
}

///|
fn leave_client_model_read_group(group : ClientModelReadGroup) -> Unit {
  group.busy = false
}

///|
fn prepare_client_model_group_read(
  scope : ClientModelReadScope,
  group : ClientModelReadGroup,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[ClientModelReadPreparation, ClientModelReadPreparationIssue] {
  if group.closing ||
    group.closed ||
    scope.finished ||
    scope.read_attempted ||
    retained_bytes != scope.retained_bytes ||
    execution_bytes != scope.execution_bytes {
    return Err(Resource(@resources.SpentClaim))
  }
  let mut selected = -1
  for index, original in group.scopes {
    if physical_equal(original, scope) {
      selected = index
    }
  }
  if selected < 0 {
    return Err(ForeignRun)
  }
  if group.busy {
    return Err(Resource(@resources.CleanupPending))
  }
  group.busy = true
  defer leave_client_model_read_group(group)
  if !group.attempted {
    group.attempted = true
    let first = group.scopes[0]
    let descriptor = match
      @resources.issue_recorded_original_ledger_descriptor(
        first.identity,
        first.origin,
      ) {
      Err(issue) => return Err(Resource(issue))
      Ok(value) => value
    }
    let claim = match
      @resources.fund_original_read(
        first.ledger,
        first.origin,
        descriptor,
        group.retained_bytes,
        group.execution_bytes,
      ) {
      Err(issue) => return Err(Resource(issue))
      Ok(value) => value
    }
    // Retain every original child before a later current observation. A
    // reentrant stop cannot turn the returned capacity into an unissued read.
    group.pending_claim = Some(claim)
    if group.closing {
      return Err(Resource(@resources.CleanupPending))
    }
    let origins : Array[ClientModelReadOrigin] = []
    let retained : Array[Int64] = []
    let execution : Array[Int64] = []
    for original in group.scopes {
      origins.push(original.origin)
      retained.push(original.retained_bytes)
      execution.push(original.execution_bytes)
    }
    let consumers = match
      @resources.claim_funded_read_preparations(
        claim,
        first.origin,
        origins,
        retained,
        execution,
      ) {
      Err(issue) => return Err(Resource(issue))
      Ok(value) => value
    }
    for index, original in group.scopes {
      group.reads.push({
        origin: original.origin,
        claim,
        consumer: Some(consumers[index]),
        consumer_claimed: false,
        retired: false,
      })
    }
  }
  if group.closing || group.reads.length() != group.scopes.length() {
    return Err(Resource(@resources.CleanupPending))
  }
  scope.read_attempted = true
  Ok(group.reads[selected])
}

///|
fn finish_client_model_group_scope(
  scope : ClientModelReadScope,
  group : ClientModelReadGroup,
  physical_cleanup_complete : Bool,
) -> Result[Bool, ClientModelReadPreparationIssue] {
  if group.closed {
    return Ok(true)
  }
  group.closing = true
  if group.busy {
    return Err(Resource(@resources.CleanupPending))
  }
  group.busy = true
  defer leave_client_model_read_group(group)
  if !physical_cleanup_complete {
    return Ok(false)
  }
  if !scope.finished {
    let mut selected = -1
    for index, original in group.scopes {
      if physical_equal(original, scope) {
        selected = index
      }
    }
    if selected < 0 {
      return Err(ForeignRun)
    }
    if selected < group.reads.length() {
      let read = group.reads[selected]
      // An issued read still needs its real child's cleanup. Only a child
      // never returned by this Owner can be retired as never dispatched.
      if scope.read_attempted && !read.retired {
        return Ok(false)
      }
      if !scope.read_attempted && !read.retired {
        match settle_client_model_read(read, true) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
      }
    }
    scope.finished = true
  }
  if !group.scopes.all(original => original.finished) {
    return Ok(false)
  }
  if group.reads.is_empty() && group.pending_claim is Some(claim) {
    // Failure after reservation but before any preparation escaped. The same
    // original pending claim remains here until its checked settlement.
    match @resources.settle_funded_read(claim, true) {
      Err(issue) => return Err(Resource(issue))
      Ok(_) => ()
    }
    group.pending_claim = None
  }
  let first = group.scopes[0]
  let complete = match
    @resources.finish_original_ledger_inventory(first.ledger, true) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  if !complete {
    return Ok(false)
  }
  group.closed = true
  group.pending_claim = None
  group.reads.clear()
  group.reads.shrink_to_fit()
  group.scopes.clear()
  group.scopes.shrink_to_fit()
  Ok(true)
}

///|
/// Pure closed-group identity/lifetime correspondence before Run adoption.
/// This checks the same private compiler order and census; it performs no
/// resource current callback, allocation, descriptor issue or Model send.
pub fn client_model_read_scopes_match_originals(
  scopes : Array[ClientModelReadScope],
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  ledger : @resources.Ledger,
  identity : @resources.OriginalLedgerIdentity,
) -> Bool {
  if scopes.length() < 2 {
    return false
  }
  guard scopes[0].group is Some(group) &&
    !group.closed &&
    !group.closing &&
    scopes.length() == group.scopes.length() else {
    return false
  }
  for index, scope in scopes {
    if !physical_equal(scope, group.scopes[index]) ||
      !client_model_read_scope_original_inventory(scope, ledger, identity) ||
      !client_model_read_scope_live(
        scope,
        compiled,
        definition,
        scope.origin.plan,
      ) {
      return false
    }
  }
  true
}
