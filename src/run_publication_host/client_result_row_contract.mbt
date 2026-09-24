///|
/// The row type of one checked Unit Result port. Its CID identifies only the
/// canonical value contract; the retained Unit and name identify the port.
pub struct ClientResultRowContractIdentity {
  unit_definition_cid : String
  result_name : String
  wire : String
  cid : String
}

///|
pub(all) enum ClientResultRowContractIssue {
  InvalidLimits
  MissingPublication
  MissingUnitIdentity
  UnrepresentableRowContract
  Encoding(@encode.EncodeFailure)
}

///|
pub fn client_result_row_contract_unit_cid(
  value : ClientResultRowContractIdentity,
) -> String {
  value.unit_definition_cid
}

///|
pub fn client_result_row_contract_name(
  value : ClientResultRowContractIdentity,
) -> String {
  value.result_name
}

///|
pub fn client_result_row_contract_wire(
  value : ClientResultRowContractIdentity,
) -> String {
  value.wire
}

///|
pub fn client_result_row_contract_cid(
  value : ClientResultRowContractIdentity,
) -> String {
  value.cid
}

///|
/// Issue the checked Result row value contract after its declared projection.
/// It does not claim a complete AoA port, Result Plan or Executable Plan.
pub fn issue_prepared_client_result_row_contract(
  value : PreparedClientProgram,
  unit : Int,
  index : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientResultRowContractIdentity, ClientResultRowContractIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let program = @strategy.graph_program(value.graph)
  guard @checked.unit_publication_at(program, unit, index) is Some(publication) else {
    return Err(MissingPublication)
  }
  guard @checked.unit_definition_cid(program, unit) is Some(unit_definition_cid) else {
    return Err(MissingUnitIdentity)
  }
  guard @checked.publication_row_value_contract(publication) is Some(row) else {
    return Err(UnrepresentableRowContract)
  }
  try {
    let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth)
    let text = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @contract.emit_checked(row, hash)
    @contract.emit_checked(row, text)
    let cid = "sha256:" + @encode.finish_hash(hash)
    let wire = @encode.finish(text)
    Ok({
      unit_definition_cid,
      result_name: @checked.publication_result_name(publication),
      wire,
      cid,
    })
  } catch {
    issue => Err(Encoding(issue))
  }
}
