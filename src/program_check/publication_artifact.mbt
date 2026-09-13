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
  let writer = @encode.measuring_writer(bytes, nodes, budget.depth) catch {
    e => raise Encoding(e)
  }
  @host.emit(host, writer) catch {
    e => raise Encoding(e)
  }
  let (size, length, _) = @encode.finish_measurement_usage(writer) catch {
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
  let host_bytes = publication_metadata(
    w => @host.emit(host, w) catch { e => raise Encoding(e) },
    remaining,
  )
  identity_charge(remaining, host_bytes.length())
  let host_wire = match
    @wire.admit(host_bytes, @host.cid(host), {
      max_bytes: host_bytes.length(),
      max_nodes: host_bytes.length(),
      max_depth: remaining.depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
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
  let hash = identity_writer(remaining)
  emit_publication_row_body(
    unit,
    index,
    host,
    hash,
    remaining,
    proofs=Some(proofs),
  )
  let cid = identity_finish(remaining, hash)
  let bytes = publication_metadata(
    w => {
      emit_publication_row_body(
        unit,
        index,
        host,
        w,
        remaining,
        cid=Some(cid),
        proofs=Some(proofs),
      )
    },
    remaining,
  )
  identity_charge(remaining, bytes.length())
  let result = match
    @wire.admit_limit(bytes, cid, claims, {
      max_bytes: bytes.length(),
      max_nodes: bytes.length(),
      max_depth: remaining.depth,
      max_candidates: witnesses.length(),
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}
