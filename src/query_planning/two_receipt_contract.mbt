///|
/// Full pinned interpretation, with the already admitted acquisition/evidence
/// dependency bodies retained. This is not execution or issuer authority.
struct QueryTwoReceiptContract {
  _dependencies : QueryEvidenceContracts
  _body : @identity.CanonicalValue
  bytes : Int
  nodes : Int
}

///|
let query_two_receipt_cid : String = "sha256:d3d2737da6d73801f85208a2cdfe50c412e9f7b24e8bf9807e6f804e11757dd7"

///|
pub fn query_two_receipt_contract_cid(
  _value : QueryTwoReceiptContract,
) -> String {
  query_two_receipt_cid
}

///|
pub fn admit_query_two_receipt_contract(
  dependencies : QueryEvidenceContracts,
  body : @identity.CanonicalValue,
  limits : QueryEvidenceLimits,
) -> Result[QueryTwoReceiptContract, QueryEvidenceContractIssue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if dependencies.bytes > limits.max_bytes ||
    dependencies.nodes > limits.max_nodes {
    return Err(EvidenceBodyLimit)
  }
  let usage = try {
    let writer = @encode.hashing_writer(
      limits.max_bytes - dependencies.bytes,
      limits.max_nodes - dependencies.nodes,
      limits.max_depth,
    )
    @identity.emit_value(body, writer)
    @encode.finish_hash_usage(writer)
  } catch {
    _ => return Err(EvidenceBodyLimit)
  }
  if "sha256:" + usage.0 != query_two_receipt_cid {
    return Err(UnsupportedEvidence)
  }
  Ok({
    _dependencies: dependencies,
    _body: body,
    bytes: dependencies.bytes + usage.1,
    nodes: dependencies.nodes + usage.2,
  })
}

///|
pub fn query_two_receipt_contract_usage(
  value : QueryTwoReceiptContract,
) -> (Int, Int) {
  (value.bytes, value.nodes)
}
