///|
// The existing Native file implementation supports only one key per call,
// one page and one attempt. Its actual batch order is the canonical key order;
// accepting a permuted list would describe a different physical history.
fn native_file_lookup_batch_order_valid(value : @json.CanonicalValue) -> Bool {
  guard @json.object_field(value, "batches") is Some(@json.Array(batches)) else {
    return false
  }
  let count = @json.array_count(batches)
  for index in 0..<count {
    guard @json.array_at(batches, index) is Some(batch) &&
      @json.object_field(batch, "batch_index")
      is Some(@json.Number(batch_index)) &&
      batch_index == index.to_double() &&
      @json.object_field(batch, "key_indices") is Some(@json.Array(keys)) &&
      @json.array_count(keys) == 1 &&
      @json.array_at(keys, 0) is Some(@json.Number(key_index)) &&
      key_index == index.to_double() else {
      return false
    }
  }
  true
}

///|
/// Immutable predispatch DATA for the existing single-key Native reader.
/// The original checked compiler supplies its barrier CID and the same lookup
/// supplies its admitted key set and transport. Caller backing precedes entry.
/// This constructs no Request, activation, attempt, permission or Store ACK.
pub fn issue_native_file_lookup_batch_plan(
  barrier_cid : String,
  keys : PublicationContract,
  transport : PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationContractIssue] {
  guard valid_contract_cid(barrier_cid) &&
    keys.name == "request_key_set" &&
    transport.name == "native_file_lookup_transport" &&
    contract_string(keys, "source_view_contract_cid") ==
    contract_string(transport, "source_view_contract_cid") &&
    contract_string(keys, "request_schema_cid") ==
    contract_string(transport, "request_schema_cid") &&
    lookup_request_key_set_tuple_count(keys) is Some(count) else {
    return Err(InvalidField("native_file_lookup_originals"))
  }
  let body = try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "barrier_cid")
    @encode.string_value(writer, barrier_cid)
    @encode.key(writer, "batches")
    @encode.begin_array(writer)
    for index in 0..<count {
      @encode.begin_object(writer)
      @encode.key(writer, "batch_index")
      @encode.number_value(writer, index.to_double())
      @encode.key(writer, "key_indices")
      @encode.begin_array(writer)
      @encode.number_value(writer, index.to_double())
      @encode.end_array(writer)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "request_key_set_cid")
    @encode.string_value(writer, keys.identity)
    @encode.key(writer, "transport_plan_cid")
    @encode.string_value(writer, transport.identity)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-lookup-batch-plan/0.1")
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  seal_publication_contract(
    "native_file_lookup_batch_plan", body, max_bytes, max_nodes, max_depth,
  )
}
