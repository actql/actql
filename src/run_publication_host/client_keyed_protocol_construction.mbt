///|
// Ephemeral original construction state, not authority, a new Owner or a
// reservation. Only its original lookup may reconcile it, once.
priv struct KeyedProtocolConstruction {
  lookup : ClientKeyedLookupInput
  basis_retained : Int64
  basis_execution : Int64
  controls : Int64
  mut finished : Bool
}

///|
priv enum KeyedProtocolDependencies {
  NoDependencies
  Unmeasured(Array[@publication.CapturedEffectDependencyBody])
  Measured(KeyedDependencySerialCompletion)
}

///|
priv struct KeyedProtocolBuilt[T] {
  value : T
  contracts : Array[@publication.PublicationContract]
  evidence : Array[@publication.RunEvidenceValue]
  texts : Array[String]
  dependencies : KeyedProtocolDependencies
}

///|
// This internal exit can only be issued after original adoption and successful
// reconciliation. It conveys no current authorization or physical-close ACK.
priv struct SettledKeyedProtocolMetadata[T] {
  value : T
}

///|
fn[T] keyed_protocol_built(
  value : T,
  contracts? : Array[@publication.PublicationContract] = [],
  evidence? : Array[@publication.RunEvidenceValue] = [],
  texts? : Array[String] = [],
  dependencies? : KeyedProtocolDependencies = NoDependencies,
) -> KeyedProtocolBuilt[T] {
  { value, contracts, evidence, texts, dependencies, }
}

///|
// Preserve the original lookup's mutation fence across synchronous build and
// adoption. Internal body growth preserves that fence; external reentry cannot
// begin a second construction or clean up the live frame. No raw value escapes
// on an extent, settlement or final-current failure, while its adopted backing
// remains owned by the same lookup and its existing cleanup path.
// Callbacks obey the declared no-raise Result contract. A foreign ABI panic
// remains a whole-Host fault/cleanup-only obligation, never a settled exit or
// physical cleanup ACK from this portable boundary.
fn[T] with_keyed_protocol_construction(
  lookup : ClientKeyedLookupInput,
  max_bytes : Int,
  slots : Int64,
  max_nodes : Int,
  max_depth : Int,
  build : (KeyedProtocolConstruction) -> Result[
    KeyedProtocolBuilt[T],
    ClientKeyedRequestIssue,
  ],
  adopt : (T) -> Result[Unit, ClientKeyedRequestIssue],
  extra_controls? : Int64 = 0L,
  copies? : Int = 1,
) -> Result[SettledKeyedProtocolMetadata[T], ClientKeyedRequestIssue] {
  let phase = match
    grow_keyed_lookup_protocol_metadata(
      lookup,
      max_bytes,
      slots,
      extra_controls~,
      copies~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  lookup.growing = true
  defer {
    lookup.growing = false
  }
  let built = build(phase)
  let adopted = match built {
    Err(issue) => Err(issue)
    Ok(built) =>
      if lookup.closed || lookup.left.lookup_issue is Some(_) {
        Err(Assembly("retired_protocol_construction"))
      } else {
        match adopt(built.value) {
          Err(issue) => Err(issue)
          Ok(_) => Ok(built)
        }
      }
  }
  lookup.growing = false
  let built = match adopted {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  finish_keyed_lookup_protocol_metadata(
    lookup,
    phase,
    max_nodes,
    max_depth,
    built.contracts,
    evidence=built.evidence,
    texts=built.texts,
    dependencies=built.dependencies,
  ).map(_ => { value: built.value, })
}

///|
// A dynamic scan is not a maximum-sized protocol writer. Keep its grow port
// inside the same original construction; neither its baseline nor a finish
// capability escapes into callers. This is ephemeral state, not another Owner.
priv struct KeyedBodyConstruction {
  lookup : ClientKeyedLookupInput
  basis_retained : Int64
  basis_execution : Int64
  controls : Int64
  mut finished : Bool
  mut growing : Bool
}

///|
fn keyed_body_construction_controls() -> Int64 {
  // Original phase/grow closure and settled return; build/adopt/Resource
  // Result frontiers; retained-capacity/Some and four shallow extent records.
  // Input-dependent result backing is separately supplied by the caller.
  @execution.preparation_representation_cost({
    record_headers: 16L,
    reference_slots: 12L,
    scalar_words: 30L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
fn grow_keyed_body_construction(
  phase : KeyedBodyConstruction,
  next : @execution.ExecutionCapacity,
) -> Result[Unit, ClientKeyedRequestIssue] {
  if phase.finished || phase.growing {
    return Err(Assembly("unavailable_body_construction"))
  }
  phase.growing = true
  defer {
    phase.growing = false
  }
  keyed_lookup_body_grow(
    phase.lookup,
    phase.basis_retained,
    phase.basis_execution,
    phase.controls,
    Some(next),
  )
}

///|
// A successful build frame has returned before adoption/measurement. Its exact
// retained receipt/body is now on this lookup or in the immutable return frame.
// Failure retains the original peak/adopted data; no physical stop is inferred.
fn[T] with_keyed_body_construction(
  lookup : ClientKeyedLookupInput,
  first : @execution.ExecutionCapacity,
  controls : Int64,
  build : (
    (@execution.ExecutionCapacity) -> Result[Unit, ClientKeyedRequestIssue],
  ) -> Result[T, ClientKeyedRequestIssue],
  adopt : (T) -> Result[Unit, ClientKeyedRequestIssue],
  retained : (T) -> @execution.ExecutionCapacity?,
) -> Result[SettledKeyedProtocolMetadata[T], ClientKeyedRequestIssue] {
  if lookup.closed || lookup.growing || lookup.left.lookup_issue is Some(_) {
    return Err(Assembly("unavailable_body_construction"))
  }
  guard @execution.checked_preparation_add_product(
      controls,
      keyed_body_construction_controls(),
      1L,
    )
    is Some(controls) else {
    return Err(Assembly("capacity_overflow"))
  }
  let basis_retained = lookup.retained_bytes
  let basis_execution = lookup.execution_bytes
  match
    keyed_lookup_body_grow(
      lookup,
      basis_retained,
      basis_execution,
      controls,
      Some(first),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let phase : KeyedBodyConstruction = {
    lookup,
    basis_retained,
    basis_execution,
    controls,
    finished: false,
    growing: false,
  }
  lookup.growing = true
  defer {
    phase.finished = true
    lookup.growing = false
  }
  let built = match build(next => grow_keyed_body_construction(phase, next)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // The grow port is a construction-only borrow, including during adoption.
  phase.finished = true
  if lookup.closed || lookup.left.lookup_issue is Some(_) {
    return Err(Assembly("retired_body_construction"))
  }
  match adopt(built) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard retained(built) is Some(keep) &&
    @execution.checked_preparation_add_product(basis_retained, controls, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(
      r,
      @execution.execution_capacity_retained_bytes(keep),
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(basis_execution, controls, 1L)
    is Some(e) &&
    @execution.checked_preparation_add_product(
      e,
      @execution.execution_capacity_execution_bytes(keep),
      1L,
    )
    is Some(e) else {
    return Err(Assembly("body_retained_capacity"))
  }
  if !client_keyed_left_available(lookup.left) ||
    lookup.closed ||
    lookup.left.lookup_issue is Some(_) {
    return Err(Assembly("retired_body_construction"))
  }
  match
    @resources.reduce_execution_reservation_capacity(
      lookup.ledger,
      lookup.reservation,
      r,
      e,
    ) {
    Err(issue) => return Err(Physical(issue))
    Ok(_) => {
      lookup.retained_bytes = r
      lookup.execution_bytes = e
    }
  }
  if lookup.closed || lookup.left.lookup_issue is Some(_) {
    return Err(Assembly("retired_body_construction"))
  }
  Ok({ value: built, })
}

///|
fn keyed_identity_retained_capacity(
  receipt : @execution.CompletedRelationExportReceipt,
  body : String,
) -> @execution.ExecutionCapacity? {
  guard @execution.completed_relation_export_retained_capacity(receipt)
    is Some(receipt_capacity) &&
    @execution.preparation_representation_cost({
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: body.length().to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(text) &&
    @execution.execution_capacity(text, text) is Some(text_capacity) else {
    return None
  }
  @execution.add_execution_capacity(receipt_capacity, text_capacity)
}
