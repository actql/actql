///|
/// Serialization budget only; never issuer authority. Callers cannot mutate or
/// replenish the ledger. Issuers retain cumulative usage across record/capture
/// phases and separately enforce the live execution and retention relationship.
pub fn query_artifact_budget(
  work : Int,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> QueryMaterialBudget? {
  if work < 0 || bytes < 0 || nodes < 0 || depth < 0 {
    return None
  }
  Some({ work, bytes, nodes, depth, })
}

///|
pub fn query_artifact_remaining(value : QueryMaterialBudget) -> (Int, Int, Int) {
  (value.work, value.bytes, value.nodes)
}

///|
pub fn query_artifact_spend_work(
  value : QueryMaterialBudget,
  amount : Int,
) -> Bool {
  if amount < 0 || amount > value.work {
    return false
  }
  value.work -= amount
  true
}

///|
/// Rehash the exact retained requirement document within the supplied budget.
/// This is a material consistency check, not an attempt/provenance verifier.
pub fn query_artifact_request_matches(
  value : QueryMaterialBudget,
  requirement : QueryRequirement,
) -> Bool raise @encode.EncodeFailure {
  let cid = material_hash(value, writer => {
    @encode.emit_document(writer, requirement.material.request)
  })
  cid == requirement.material.request_cid
}
