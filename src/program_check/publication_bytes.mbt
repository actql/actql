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
  let artifact = typed_publication_limit_claim(
    claims,
    [0],
    @derivation.Bytes,
    subject,
    @policy.ceiling_value(ceiling),
    0,
    remaining,
  )
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  artifact
}
