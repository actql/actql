///|
/// Supported verifier interpretation, not permission to issue execution records.
/// Inputs are already admitted immutable canonical bodies, never digest claims.
struct QueryEvidenceContracts {
  _acquisition : @identity.CanonicalValue
  _evidence : @identity.CanonicalValue
  bytes : Int
  nodes : Int
}

///|
pub(all) struct QueryEvidenceLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum QueryEvidenceContractIssue {
  InvalidLimits
  AcquisitionBodyLimit
  UnsupportedAcquisition
  EvidenceBodyLimit
  UnsupportedEvidence
}

///|
let query_evidence_contract_cid : String = "sha256:fad105d74ec20ac8f223f1252d5cc7726585dab15b51b1d934c920c8c3a692cd"

///|
/// The complete pinned evidence body includes its exact acquisition dependency
/// and record schema. Accepting the schema or matching a version is insufficient.
/// Bytes and nodes are cumulative across both bodies, with no per-body reset.
pub fn admit_query_evidence_contracts(
  acquisition : @identity.CanonicalValue,
  evidence : @identity.CanonicalValue,
  limits : QueryEvidenceLimits,
) -> Result[QueryEvidenceContracts, QueryEvidenceContractIssue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let query_usage = try {
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @identity.emit_value(acquisition, writer)
    @encode.finish_hash_usage(writer)
  } catch {
    _ => return Err(AcquisitionBodyLimit)
  }
  if "sha256:" + query_usage.0 != @acquisition.query_acquisition_contract_cid() {
    return Err(UnsupportedAcquisition)
  }
  let evidence_usage = try {
    let writer = @encode.hashing_writer(
      limits.max_bytes - query_usage.1,
      limits.max_nodes - query_usage.2,
      limits.max_depth,
    )
    @identity.emit_value(evidence, writer)
    @encode.finish_hash_usage(writer)
  } catch {
    _ => return Err(EvidenceBodyLimit)
  }
  if "sha256:" + evidence_usage.0 != query_evidence_contract_cid {
    return Err(UnsupportedEvidence)
  }
  Ok({
    _acquisition: acquisition,
    _evidence: evidence,
    bytes: query_usage.1 + evidence_usage.1,
    nodes: query_usage.2 + evidence_usage.2,
  })
}

///|
pub fn query_evidence_contract_usage(
  value : QueryEvidenceContracts,
) -> (Int, Int) {
  (value.bytes, value.nodes)
}
