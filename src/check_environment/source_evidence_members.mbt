///|
/// Checked logical selection, not a runtime grant or acquisition receipt.
pub(all) struct ConnectorSourceEvidenceSelector {
  source_ref : String
  source_contract_cid : String
  source_view_contract_cid : String
  carrier_schema_contract_cid : String
  source_data_policy_cid : String
  data_classification : String
} derive(Eq)

///|
pub(all) enum SourceEvidenceMemberIssue {
  MissingMember
  AmbiguousMember
  InvalidMember
  ContractMismatch(String)
  CapabilityMismatch
} derive(Eq, Debug)

///|
struct ConnectorSourceEvidenceMembers {
  schema : Member
  capability : Member
  contracts : Array[String]
}

///|
fn evidence_member_text(body : @decode.Cursor, name : String) -> String? {
  match @decode.open_object(body) {
    Ok(object) =>
      match @decode.required(object, name) {
        Ok(value) => @decode.text(value).to_option()
        Err(_) => None
      }
    Err(_) => None
  }
}

///|
fn evidence_member_cid(value : String) -> Bool {
  value.length() == 71 && value.has_prefix("sha256:") &&
  value[7:].iter().all(c =>
    (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
}

///|
fn select_evidence_member(
  environment : WireEnvironment,
  section : Section,
  selector : ConnectorSourceEvidenceSelector,
) -> Result[Member, SourceEvidenceMemberIssue] {
  let mut selected = None
  for i in 0..<member_count(environment, section) {
    let item = member_at(environment, section, i).unwrap()
    let body = member_body(item)
    if evidence_member_text(body, "source_ref") != Some(selector.source_ref) {
      continue
    }
    if selected is Some(_) {
      return Err(AmbiguousMember)
    }
    for (name, expected) in [
      ("source_contract_cid", selector.source_contract_cid),
      ("source_view_contract_cid", selector.source_view_contract_cid),
      ("read_mode", "snapshot"),
    ] {
      if evidence_member_text(body, name) != Some(expected) {
        return Err(ContractMismatch(name))
      }
    }
    selected = Some(item)
  }
  match selected {
    Some(item) => Ok(item)
    None => Err(MissingMember)
  }
}

///|
/// Retains exact environment membership. Full member bodies have no self-CID
/// field or exclusions. Runtime schema, used capabilities and current read
/// authority must still be verified by the acquisition issuer.
pub fn select_connector_source_evidence_members(
  environment : WireEnvironment,
  selector : ConnectorSourceEvidenceSelector,
) -> Result[ConnectorSourceEvidenceMembers, SourceEvidenceMemberIssue] {
  for cid in [selector.source_contract_cid, selector.source_view_contract_cid,
    selector.carrier_schema_contract_cid, selector.source_data_policy_cid] {
    if !evidence_member_cid(cid) {
      return Err(InvalidMember)
    }
  }
  if !selector.source_ref.has_prefix("connector://") {
    return Err(InvalidMember)
  }
  let schema = match select_evidence_member(environment, SchemaSnapshots, selector) {
    Ok(item) => item
    Err(issue) => return Err(issue)
  }
  match connector_source_snapshot_selector(schema) {
    Ok(Some(actual)) => {
      if actual != selector { return Err(ContractMismatch("schema_snapshot")) }
    }
    _ => return Err(InvalidMember)
  }
  let capability = match
    select_evidence_member(environment, ConnectorCapabilities, selector) {
    Ok(item) => item
    Err(issue) => return Err(issue)
  }
  let body = member_body(capability)
  let object = match @decode.closed_object(body, ["source_ref",
    "source_contract_cid", "source_view_contract_cid", "read_mode",
    "capability_contract_cids"]) {
    Ok(object) => object
    Err(_) => return Err(InvalidMember)
  }
  guard @decode.required(object, "capability_contract_cids") is Ok(array) else {
    return Err(InvalidMember)
  }
  guard @decode.array_length(array) is Some(count) else {
    return Err(InvalidMember)
  }
  let contracts = []
  let mut previous = ""
  for i in 0..<count {
    guard @decode.text(@decode.element_at(array, i).unwrap()) is Ok(cid) else {
      return Err(InvalidMember)
    }
    if !evidence_member_cid(cid) || cid <= previous {
      return Err(InvalidMember)
    }
    contracts.push(cid)
    previous = cid
  }
  Ok({ schema, capability, contracts, })
}

///|
pub fn connector_source_evidence_member_cids(
  members : ConnectorSourceEvidenceMembers,
) -> (String, String) {
  (member_cid(members.schema), member_cid(members.capability))
}

///|
/// Static compatibility only. The issuer supplies contracts from the verified
/// acquisition, never from an application's claim that a capability was used.
pub fn connector_source_evidence_supports(
  members : ConnectorSourceEvidenceMembers,
  used_contract_cids : Array[String],
) -> Bool {
  used_contract_cids.length() > 0 &&
  used_contract_cids.all(cid => members.contracts.contains(cid))
}

///|
/// Partition Connector snapshots from Local snapshots without interpreting
/// either as runtime evidence. Catalog correspondence is checked when selecting
/// the checked Query's source evidence members.
pub fn connector_source_snapshot_selector(
  item : Member,
) -> Result[ConnectorSourceEvidenceSelector?, SourceEvidenceMemberIssue] {
  if member_section(item) != SchemaSnapshots { return Err(InvalidMember) }
  let body = member_body(item)
  guard evidence_member_text(body, "source_ref") is Some(source_ref) else {
    return Err(InvalidMember)
  }
  if !source_ref.has_prefix("connector://") { return Ok(None) }
  let object = match @decode.closed_object(body, ["source_ref", "source_contract_cid",
    "source_view_contract_cid", "read_mode", "output_carrier",
    "carrier_schema_contract_cid", "source_data_policy_cid",
    "data_classification"]) {
    Ok(value) => value
    Err(_) => return Err(InvalidMember)
  }
  let fields = []
  for name in ["source_contract_cid", "source_view_contract_cid",
    "carrier_schema_contract_cid", "source_data_policy_cid"] {
    guard @decode.required(object, name) is Ok(raw) else {
      return Err(InvalidMember)
    }
    guard @decode.text(raw) is Ok(cid) else { return Err(InvalidMember) }
    if !evidence_member_cid(cid) { return Err(InvalidMember) }
    fields.push(cid)
  }
  guard evidence_member_text(body, "data_classification") is Some(classification) else {
    return Err(InvalidMember)
  }
  if evidence_member_text(body, "output_carrier") != Some("relation") ||
    evidence_member_text(body, "read_mode") != Some("snapshot") ||
    !["public", "internal", "confidential", "restricted", "unknown"].contains(classification) {
    return Err(InvalidMember)
  }
  Ok(Some({ source_ref, source_contract_cid: fields[0],
    source_view_contract_cid: fields[1], carrier_schema_contract_cid: fields[2],
    source_data_policy_cid: fields[3], data_classification: classification, }))
}
