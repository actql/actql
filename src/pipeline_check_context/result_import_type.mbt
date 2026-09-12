///|
pub enum ResultImportTypeIssue {
  InvalidLimits
  NotResult
  UnsupportedReceipt
  UnrepresentableRowContract
  Hash(@encode.EncodeFailure)
}

///|
/// Declared Result type identity owned by one incoming occurrence. It is not
/// the complete import interface or an observed Result artifact.
struct ResultImportType {
  incoming : ProgramIncomingLinks
  site : IncomingSite
  contract : @contract.Contract
  cid : String
  bytes : Int
  nodes : Int
}

///|
/// Derive the canonical row contract from the retained publication port, never
/// a caller-supplied equal-shaped type. Hashing uses the bounded shared emitter
/// without serializing a complete text or copying the schema field array.
pub fn identify_result_import_type(
  incoming : ProgramIncomingLinks,
  index : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ResultImportType?, ResultImportTypeIssue] {
  if max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    return Err(InvalidLimits)
  }
  guard incoming.incoming.entries.get(index) is Some(site) else {
    return Ok(None)
  }
  let port = match site.requirement {
    Result(_, _, port) => @stage_results.input_port(port)
    Success(_, _) => return Err(NotResult)
    Receipt(_, _, _) => return Err(UnsupportedReceipt)
  }
  guard @schema.as_object(@results.port_schema(port)) is Some(contract) else {
    return Err(UnrepresentableRowContract)
  }
  try {
    let writer = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
    @contract.emit_checked(contract, writer)
    let (hex, bytes, nodes) = @encode.finish_hash_usage(writer)
    Ok(Some({ incoming, site, contract, cid: "sha256:" + hex, bytes, nodes, }))
  } catch {
    e => Err(Hash(e))
  }
}

///|
pub fn result_import_type_incoming(
  v : ResultImportType,
) -> ProgramIncomingLinks {
  v.incoming
}

///|
pub fn result_import_type_site(v : ResultImportType) -> IncomingSite {
  v.site
}

///|
pub fn result_import_type_contract(v : ResultImportType) -> @contract.Contract {
  v.contract
}

///|
pub fn result_import_type_cid(v : ResultImportType) -> String {
  v.cid
}

///|
/// Incremental emitted bytes/nodes; the containing Program must subtract these
/// from its shared hash budget, including repeated incoming occurrences.
pub fn result_import_type_usage(v : ResultImportType) -> (Int, Int) {
  (v.bytes, v.nodes)
}
