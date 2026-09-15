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
let query_two_receipt_cid : String = "sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8"

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
