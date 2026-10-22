///|
// Creation hashes the preimage. Measuring the complete witness gives a
// conservative bound for both that pass and this measurement (the complete
// body additionally includes its CID). Neither pass can exceed its caps.
fn publication_host(
  ceiling : @policy.Ceiling,
  budget : IdentityBudget,
) -> @host.Witness raise UnitBuildFailure {
  let bytes = Int::min(budget.bytes, budget.work / 4)
  let nodes = Int::min(budget.nodes, budget.work / 4)
  let host = match
    @host.create(ceiling, {
      max_bytes: bytes,
      max_nodes: nodes,
      max_depth: budget.depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationHost(e)
  }
  let (size, length, _) = @host.measure(host, bytes, nodes, budget.depth) catch {
    e => raise Encoding(e)
  }
  identity_charge(budget, size)
  identity_charge(budget, length)
  identity_charge(budget, size)
  identity_charge(budget, length)
  budget.bytes -= size
  budget.nodes -= length
  host
}

///|
// The returned Unit retains the checked wire claim alongside the exact
// selection/membership. Publication limits are not Unit definition preimages.
fn prepare_unit_publications(
  units : Array[BuiltUnit],
  budget : IdentityBudget,
  conversion? : ProofConversion? = None,
) -> Array[BuiltUnit] raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, units.length())
  let completed : Array[BuiltUnit] = []
  for unit in units {
    identity_charge(remaining, unit.publication_rows.length())
    let publications : Array[PublicationExecution] = []
    for i in 0..<unit.publication_rows.length() {
      publications.push(
        prepare_publication_execution(
          unit,
          i,
          remaining,
          units=Some(units),
          producers=Some(completed),
          conversion~,
        ),
      )
    }
    completed.push({ ..unit, publications, })
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  completed
}

///|
// Metadata is small but still bounded. Measure before allocating the text and
// UTF-8 copy; reserve each pass before performing it. This is not a payload sink.
fn publication_metadata(
  emit : (@encode.Writer) -> Unit raise UnitBuildFailure,
  budget : IdentityBudget,
) -> Bytes raise UnitBuildFailure {
  let measure = @encode.measuring_writer(
    Int::min(budget.bytes, budget.work / 2),
    Int::min(budget.nodes, budget.work / 2),
    budget.depth,
  ) catch {
    e => raise Encoding(e)
  }
  emit(measure)
  let (bytes, nodes, _) = @encode.finish_measurement_usage(measure) catch {
    e => raise Encoding(e)
  }
  identity_charge(budget, bytes)
  identity_charge(budget, nodes)
  identity_charge(budget, bytes)
  identity_charge(budget, nodes)
  identity_charge(budget, bytes)
  let writer = @encode.writer(bytes, nodes, budget.depth) catch {
    e => raise Encoding(e)
  }
  emit(writer)
  let text = @encode.finish(writer) catch { e => raise Encoding(e) }
  budget.bytes -= bytes
  budget.nodes -= nodes
  @utf8.encode(text)
}

///|
// The Host witness is created from the selected ceiling by the enclosing
// constructor. emit_publication_row_body verifies that exact ownership, not
// merely equality of policy values. Arithmetic context is not wire candidates.
fn prepare_publication_row_artifact(
  unit : BuiltUnit,
  index : Int,
  host : @host.Witness,
  budget : IdentityBudget,
  proofs? : Array[ReidentifiedStep]? = None,
  on_body_preparation? : (() -> Unit)? = None,
) -> @wire.LimitClaim raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  guard unit.publication_rows.get(index) is Some(selected) else {
    raise ForeignOwner
  }
  if !physical_equal(
      @host.ceiling(host),
      @context.publication_row_limit_host(selected),
    ) {
    raise ForeignOwner
  }
  let host_wire = publication_host_wire(host, remaining)
  let proofs = match proofs {
    Some(v) => v
    None => publication_proofs([unit], selected, remaining)
  }
  let input_limits : Array[(Bytes, String)] = []
  let witnesses = publication_proof_claims(
    proofs,
    remaining,
    limits=input_limits,
  )
  let mut has_host = false
  for witness in witnesses {
    identity_charge(remaining, @host.cid(host).length())
    if @wire.cid(witness) == @host.cid(host) {
      has_host = true
    }
  }
  if !has_host {
    identity_charge(remaining, 1)
    witnesses.push(host_wire)
  }
  // Cap the validation traversal before running it. The exact reference count
  // is reported by the checked arithmetic collection and charged on success.
  let reference_limit = remaining.work / 2
  identity_charge(remaining, witnesses.length())
  let claims = if input_limits.is_empty() {
    match
      @wire.check_arithmetic_claims(witnesses, {
        max_witnesses: witnesses.length(),
        max_references: reference_limit,
      }) {
      Ok(v) => v
      Err(e) => raise PublicationArithmetic(e)
    }
  } else {
    identity_charge(remaining, input_limits.length())
    let mixed = match
      @wire.check_mixed_claims(witnesses, input_limits, {
        max_entities: witnesses.length() + input_limits.length(),
        max_references: remaining.work / 3,
        max_bytes: remaining.work / 3,
        max_nodes: remaining.work / 3,
        max_depth: remaining.depth,
      }) {
      Ok(v) => v
      Err(e) => raise PublicationMixed(e)
    }
    let (references, bytes, nodes) = @wire.mixed_usage(mixed)
    identity_charge(remaining, references)
    identity_charge(remaining, bytes)
    identity_charge(remaining, nodes)
    @wire.mixed_arithmetic(mixed)
  }
  if input_limits.is_empty() {
    identity_charge(remaining, @wire.claim_reference_count(claims))
  }
  let body = prepare_publication_row_body(
    unit,
    index,
    host,
    remaining,
    proofs=Some(proofs),
    on_body_preparation~,
  )
  let result = publication_row_limit_claim(body, claims, remaining)
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}

///|
// Preserve the original metadata and admission work debits. The complete
// immutable wire extent is checked against this enclosing budget, while its
// original typed claim is reused without text, UTF8 or JSON reconstruction.
fn publication_host_wire(
  host : @host.Witness,
  budget : IdentityBudget,
) -> @wire.WireWitness raise UnitBuildFailure {
  let (bytes, nodes, _) = @host.measure(
    host,
    Int::min(budget.bytes, budget.work / 2),
    budget.nodes,
    budget.depth,
  ) catch {
    e => raise Encoding(e)
  }
  identity_charge(budget, bytes)
  identity_charge(budget, nodes)
  identity_charge(budget, bytes)
  identity_charge(budget, nodes)
  identity_charge(budget, bytes)
  budget.bytes -= bytes
  budget.nodes -= nodes
  identity_charge(budget, bytes)
  @host.wire_witness(host)
}

///|
// The body and arithmetic collection were prepared from the same original
// publication. Construct the canonical claim directly; do not parse and hash
// our own serialized output again. Keep the original logical encoding debits.
fn publication_row_limit_claim(
  body : PreparedPublicationRowBody,
  claims : @wire.ArithmeticClaims,
  budget : IdentityBudget,
) -> @wire.LimitClaim raise UnitBuildFailure {
  let indices : Array[Int] = []
  let mut previous = ""
  for (cid, _) in body.candidates {
    if cid == previous {
      continue
    }
    previous = cid
    guard @wire.claim_index(claims, cid) is Some(index) else {
      raise PublicationWire(@wire.InvalidWitness)
    }
    indices.push(index)
  }
  typed_publication_limit_claim(
    claims,
    indices,
    @derivation.Rows,
    body.subject,
    body.maximum,
    body.candidates.length(),
    budget,
  )
}

///|
// A row projection meters its original candidate traversals; the Host-only
// byte projection has no such separate traversal debit. Both retain the same
// bounded canonical preimage/full-wire and admission work accounting.
fn typed_publication_limit_claim(
  claims : @wire.ArithmeticClaims,
  indices : Array[Int],
  unit : @derivation.BoundUnit,
  subject : String,
  maximum : Int64,
  traversal_work : Int,
  budget : IdentityBudget,
) -> @wire.LimitClaim raise UnitBuildFailure {
  // The old hash writer is bounded before the emitter's candidate charge.
  let hash_bytes = Int::min(budget.bytes, budget.work)
  let hash_nodes = Int::min(budget.nodes, budget.work)
  identity_charge(budget, traversal_work)
  let claim = match
    @wire.create_limit(claims, indices, unit, subject, @wire.EngineAtomic, {
      max_bytes: hash_bytes,
      max_nodes: hash_nodes,
      max_depth: budget.depth,
      max_candidates: @wire.claim_count(claims),
    }) {
    Ok(value) => value
    Err(BudgetExceeded) => raise Encoding(@encode.OutputLimit)
    Err(issue) => raise PublicationWire(issue)
  }
  if @derivation.minimum_value(@wire.limit_minimum(claim)) != maximum ||
    @derivation.minimum_guard_binding(@wire.limit_minimum(claim)) != Absent {
    raise PublicationWire(@wire.InvalidWitness)
  }
  let (preimage_bytes, preimage_nodes) = @wire.limit_creation_usage(claim).unwrap()
  identity_charge(budget, preimage_bytes)
  identity_charge(budget, preimage_nodes)
  budget.bytes -= preimage_bytes
  budget.nodes -= preimage_nodes
  let max_bytes = Int::min(budget.bytes, budget.work / 2)
  let max_nodes = Int::min(budget.nodes, budget.work / 2)
  identity_charge(budget, traversal_work)
  let (bytes, nodes, _) = @wire.measure_limit(
    claim,
    max_bytes,
    max_nodes,
    budget.depth,
  ) catch {
    e => raise Encoding(e)
  }
  identity_charge(budget, bytes)
  identity_charge(budget, nodes)
  identity_charge(budget, bytes)
  identity_charge(budget, nodes)
  identity_charge(budget, bytes)
  identity_charge(budget, traversal_work)
  budget.bytes -= bytes
  budget.nodes -= nodes
  identity_charge(budget, bytes)
  claim
}
