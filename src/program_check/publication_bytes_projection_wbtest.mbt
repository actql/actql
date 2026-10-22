///|
// Host restriction only: no row proof is reinterpreted as a byte proof.
fn original_prepare_publication_bytes(
  unit : BuiltUnit,
  index : Int,
  budget : IdentityBudget,
) -> @wire.LimitClaim raise UnitBuildFailure {
  guard unit.publication_rows.get(index) is Some(rows) else {
    raise ForeignOwner
  }
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, 1)
  let publication = @context.publication_row_limit_result(rows)
  let policy = @capacity.application_closure_policy(
    @context.checked_capacity(publication.context),
  )
  guard @policy.ceiling(policy, "max_artifact_bytes") is Some(ceiling) else {
    raise PublicationRows(@context.MissingHostCeiling)
  }
  let host = publication_host(ceiling, remaining)
  let witness = publication_host_wire(host, remaining)
  identity_charge(remaining, 2)
  let claims = match
    @wire.check_arithmetic_claims([witness], {
      max_witnesses: 1,
      max_references: 1,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationArithmetic(e)
  }
  let name = @publication.name(@publication.port_result(publication.port))
  for _ in 0..<3 {
    identity_charge(remaining, name.length())
  }
  identity_charge(remaining, unit.definition_cid.length())
  let subject = "unit:" +
    unit.definition_cid +
    "#/results/" +
    name.replace(old="~", new="~0").replace(old="/", new="~1") +
    "/bytes"
  let emit = fn(
    w : @encode.Writer,
    cid : String?,
  ) -> Unit raise UnitBuildFailure {
    try {
      @encode.begin_object(w)
      @encode.key(w, "author_guard_binding")
      @encode.string_value(w, "absent")
      @encode.key(w, "breach")
      @encode.string_value(w, "fail")
      @encode.key(w, "candidates")
      @encode.begin_array(w)
      @host.emit(host, w)
      @encode.end_array(w)
      @encode.key(w, "effective_max")
      @encode.number_value(w, @policy.ceiling_value(ceiling).to_double())
      @encode.key(w, "enforcement")
      @encode.string_value(w, "engine_atomic")
      if cid is Some(cid) {
        @encode.key(w, "resolved_limit_cid")
        @encode.string_value(w, cid)
      }
      @encode.key(w, "subject_ref")
      @encode.string_value(w, subject)
      @encode.key(w, "unit")
      @encode.string_value(w, "bytes")
      @encode.key(w, "version")
      @encode.string_value(w, "actql-resolved-limit/0.1")
      @encode.end_object(w)
    } catch {
      e => raise Encoding(e)
    }
  }
  let hash = identity_writer(remaining)
  emit(hash, None)
  let cid = identity_finish(remaining, hash)
  let bytes = publication_metadata(w => emit(w, Some(cid)), remaining)
  identity_charge(remaining, bytes.length())
  let artifact = match
    @wire.admit_limit(bytes, cid, claims, {
      max_bytes: bytes.length(),
      max_nodes: bytes.length(),
      max_depth: remaining.depth,
      max_candidates: 1,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  artifact
}

///|
test "typed publication byte limit preserves original Host-only wire and logical debits" {
  let construction = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, _, units) = local_construction_fixture(construction)
  let unit = units[0]
  let before = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let after = IdentityBudget::{ ..before, }
  let original = original_prepare_publication_bytes(unit, 0, before)
  let typed = prepare_publication_bytes(unit, 0, after)
  assert_eq(@wire.limit_cid(typed), @wire.limit_cid(original))
  assert_eq(@wire.limit_subject(typed), @wire.limit_subject(original))
  assert_true(@wire.limit_creation_usage(typed) is Some(_))
  assert_true(@wire.limit_creation_usage(original) is None)
  assert_eq(@derivation.minimum_unit(@wire.limit_minimum(typed)), Bytes)
  assert_eq(@derivation.minimum_candidate_count(@wire.limit_minimum(typed)), 1)
  let candidate = @wire.claim_at(@wire.limit_claims(typed), 0).unwrap()
  match @wire.source(candidate) {
    HostPolicy(field, _) => assert_eq(field, "max_artifact_bytes")
    _ => fail("byte publication changed its original Host-only source")
  }
  assert_eq(after.work, before.work)
  assert_eq(after.bytes, before.bytes)
  assert_eq(after.nodes, before.nodes)
  let a = @encode.writer(1000000, 100000, 100)
  let b = @encode.writer(1000000, 100000, 100)
  @wire.emit_limit(original, a)
  @wire.emit_limit(typed, b)
  assert_eq(@encode.finish(a), @encode.finish(b))
  let short = IdentityBudget::{
    work: 10000000 - before.work - 1,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  try prepare_publication_bytes(unit, 0, short) catch {
    UnitBuildFailure::BudgetExceeded => ()
    e => raise e
  } noraise {
    _ => fail("byte publication exceeded original work bound")
  }
  assert_eq(short.work, 10000000 - before.work - 1)
  assert_eq(short.bytes, 1000000)
  assert_eq(short.nodes, 100000)
}
