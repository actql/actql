///|
// Host restriction only: no row proof is reinterpreted as a byte proof.
fn prepare_publication_bytes(
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
  let host_bytes = publication_metadata(
    w => @host.emit(host, w) catch { e => raise Encoding(e) },
    remaining,
  )
  identity_charge(remaining, host_bytes.length())
  let witness = match
    @wire.admit(host_bytes, @host.cid(host), {
      max_bytes: host_bytes.length(),
      max_nodes: host_bytes.length(),
      max_depth: remaining.depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
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
