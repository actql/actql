///|
// The Host witness is created from the selected ceiling by the enclosing
// constructor. emit_publication_row_body verifies that exact ownership, not
// merely equality of policy values. Arithmetic context is not wire candidates.
fn original_prepare_publication_row_artifact(
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
  let hash = identity_writer(remaining)
  emit_prepared_publication_row_body(body, hash, remaining)
  let cid = identity_finish(remaining, hash)
  let bytes = publication_metadata(
    w => emit_prepared_publication_row_body(body, w, remaining, cid=Some(cid)),
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

///|
test "typed publication limit preserves canonical bytes and original logical debits" {
  let construction = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, _, units) = remote_construction_fixture(construction)
  let unit = units[0]
  let host = @host.create(
    @context.publication_row_limit_host(unit.publication_rows[0]),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, },
  ).unwrap()
  let before = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let after = IdentityBudget::{ ..before, }
  let old = original_prepare_publication_row_artifact(unit, 0, host, before)
  let typed = prepare_publication_row_artifact(unit, 0, host, after)
  assert_eq(@wire.limit_cid(typed), @wire.limit_cid(old))
  assert_eq(@wire.limit_subject(typed), @wire.limit_subject(old))
  assert_true(@wire.limit_creation_usage(typed) is Some(_))
  assert_true(@wire.limit_creation_usage(old) is None)
  assert_eq(after.work, before.work)
  assert_eq(after.bytes, before.bytes)
  assert_eq(after.nodes, before.nodes)
  let a = @encode.writer(1000000, 100000, 100)
  let b = @encode.writer(1000000, 100000, 100)
  @wire.emit_limit(old, a)
  @wire.emit_limit(typed, b)
  assert_eq(@encode.finish(a), @encode.finish(b))
}
