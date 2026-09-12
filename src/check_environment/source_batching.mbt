///|
pub(all) enum SourceBatchRole {
  RequestKey
  BatchRequest
  ResponseKey
} derive(Eq, Debug)

///|
struct SourceBatching {
  source : @decode.Cursor
  max_keys : Double
  references : Array[CatalogReference]
  contracts : Array[ProtocolValueContract]
}

///|
fn read_source_batching(
  source : @decode.Cursor,
  values : ProtocolValueContracts,
  budget : SourceRequestBudget,
) -> SourceBatching raise SourceRequestStop {
  // Shape admission has checked the closed body, positive integral bound and
  // preserves_per_key_semantics=true. Resolve the three distinct typed roles
  // through their original occurrences, never by searching for equal bodies.
  let body = request_object(source, budget)
  let references = []
  let contracts = []
  for
    name in [
      "request_key_schema", "batch_request_schema", "response_key_schema",
    ] {
    let slot = @decode.required(body, name).unwrap()
    request_charge(budget, 1, slot)
    let reference = catalog_reference_for_cursor(
      values.policies.references,
      slot,
    ).unwrap()
    references.push(reference)
    contracts.push(values.by_cid[reference.contract.cid])
  }
  let max_keys = @decode.finite_number(
    @decode.required(body, "max_keys_per_request").unwrap(),
  ).unwrap()
  { source, max_keys, references, contracts, }
}

///|
pub fn source_batching_source(v : SourceBatching) -> @decode.Cursor {
  v.source
}

///|
pub fn source_batching_max_keys(v : SourceBatching) -> Double {
  v.max_keys
}

///|
fn batch_role_index(role : SourceBatchRole) -> Int {
  match role {
    RequestKey => 0
    BatchRequest => 1
    ResponseKey => 2
  }
}

///|
pub fn source_batching_reference(
  v : SourceBatching,
  role : SourceBatchRole,
) -> CatalogReference {
  v.references[batch_role_index(role)]
}

///|
pub fn source_batching_contract(
  v : SourceBatching,
  role : SourceBatchRole,
) -> ProtocolValueContract {
  v.contracts[batch_role_index(role)]
}
