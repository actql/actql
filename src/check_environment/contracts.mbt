///|
pub(all) enum ContractIssue {
  InvalidLimits
  BudgetExceeded
  InvalidEnvelope(Int)
  IdentityMismatch(Int)
  ConflictingIdentity(String, String)
  UnknownReference(String, String)
  ReferenceMismatch(String, String)
  WrongKind(String, String)
} derive(Eq, Debug)

///|
struct ContractEnvelope {
  item : Member
  id : String
  version : String
  kind : String
  cid : String
  body : @decode.Cursor
}

///|
struct ContractRegistry {
  environment : WireEnvironment
  entries : Array[ContractEnvelope]
  names : Map[(String, String), Int]
  bytes : Int
  nodes : Int
}

///|
/// Integrity-checked DATA before registry membership is assigned. The existing
/// registry and installed Model configuration share this reader; this record
/// itself never proves Environment membership, issuer truth or authority.
priv struct ContractEnvelopeData {
  original : @decode.Cursor
  id : String
  version : String
  kind : String
  cid : String
  body : @decode.Cursor
  bytes : Int
  nodes : Int
}

///|
fn contract_kind(kind : String) -> Bool {
  match kind {
    "request_schema"
    | "carrier_schema"
    | "carrier_facts"
    | "pushdown"
    | "checkpoint"
    | "command_input"
    | "command_output"
    | "idempotency_key"
    | "reconciliation"
    | "poll"
    | "cancel"
    | "lookup_request_key"
    | "lookup_batch_request"
    | "lookup_response_key"
    | "request_data_handling"
    | "data_policy"
    | "provider_execution_capability" => true
    _ => false
  }
}

///|
fn read_contract_envelope_data(
  root : @decode.Cursor,
  limits : Limits,
  index : Int,
) -> Result[ContractEnvelopeData, ContractIssue] {
  let object = match
    @decode.closed_object(root, [
      "schema", "id", "version", "kind", "body", "cid",
    ]) {
    Ok(v) => v
    Err(_) => return Err(InvalidEnvelope(index))
  }
  let fields = try {
    let schema = string(object, "schema")
    let id = string(object, "id")
    let version = string(object, "version")
    let kind = string(object, "kind")
    let cid = string(object, "cid")
    // Null is legal envelope DATA; each semantic role owns its body grammar.
    let body = match @decode.lookup(object, "body") {
      Some(v) => v
      None => raise Stop(InvalidEnvelope)
    }
    Some((schema, id, version, kind, cid, body))
  } catch {
    _ => None
  }
  guard fields is Some((schema, id, version, kind, cid, body)) else {
    return Err(InvalidEnvelope(index))
  }
  if schema != "actql.contract/0.1" ||
    id == "" ||
    version == "" ||
    !contract_kind(kind) {
    return Err(InvalidEnvelope(index))
  }
  let hashed = try {
    // Charge the complete original, including the supplied self-CID, before
    // excluding only that member from the existing canonical preimage.
    let (_, size, count) = hash(root, limits, false)
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_except(root, writer, Some("cid"))
    let (digest, _, _) = @encode.finish_hash_usage(writer)
    Some(("sha256:" + digest, size, count))
  } catch {
    _ => None
  }
  guard hashed is Some((expected, bytes, nodes)) else {
    return Err(BudgetExceeded)
  }
  if cid != expected {
    return Err(IdentityMismatch(index))
  }
  Ok({ original: root, id, version, kind, cid, body, bytes, nodes, })
}

///|
/// Validates derived registry integrity, not Catalog closure or issuer authority.
/// Limits accumulate across all envelopes; depth is bounded per envelope.
pub fn check_contract_registry(
  environment : WireEnvironment,
  limits : Limits,
) -> Result[ContractRegistry, ContractIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_members < 0 {
    return Err(InvalidLimits)
  }
  let count = member_count(environment, ContractRegistry)
  if count > limits.max_members {
    return Err(BudgetExceeded)
  }
  let entries = []
  let names : Map[(String, String), Int] = Map([])
  let mut bytes = 0
  let mut nodes = 0
  for i in 0..<count {
    let item = member_at(environment, ContractRegistry, i).unwrap()
    let root = member_body(item)
    let remaining = {
      ..limits,
      max_bytes: limits.max_bytes - bytes,
      max_nodes: limits.max_nodes - nodes,
    }
    let data = match read_contract_envelope_data(root, remaining, i) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let { id, version, kind, cid, body, bytes: size, nodes: count, .. } = data
    if names.contains((id, version)) {
      return Err(ConflictingIdentity(id, version))
    }
    bytes += size
    nodes += count
    names[(id, version)] = entries.length()
    entries.push({ item, id, version, kind, cid, body, })
  }
  Ok({ environment, entries, names, bytes, nodes, })
}

///|
pub fn contract_registry_environment(v : ContractRegistry) -> WireEnvironment {
  v.environment
}

///|
pub fn contract_registry_usage(v : ContractRegistry) -> (Int, Int, Int) {
  (v.bytes, v.nodes, v.entries.length())
}

///|
/// Reuse the original complete-envelope hash count. Its admitted closed
/// envelope has one body and only scalar Text siblings, so removing its actual
/// root-field count leaves exactly the body's nodes. No body walk/hash or
/// repeated envelope validation is needed; this is immutable DATA only.
pub fn contract_body_node_count(value : ContractEnvelope) -> Int {
  value.item.entry.nodes -
  @decode.object_length(value.item.entry.cursor).unwrap()
}

///|
pub fn contract_at(v : ContractRegistry, i : Int) -> ContractEnvelope? {
  v.entries.get(i)
}

///|
/// Exact identity and role matching. Does not prove membership in any Catalog.
pub fn resolve_contract(
  v : ContractRegistry,
  id : String,
  version : String,
  cid : String,
  kind : String,
) -> Result[ContractEnvelope, ContractIssue] {
  let i = match v.names.get((id, version)) {
    Some(i) => i
    None => return Err(UnknownReference(id, version))
  }
  let entry = v.entries[i]
  if entry.cid != cid {
    return Err(ReferenceMismatch(id, version))
  }
  if entry.kind != kind {
    return Err(WrongKind(id, version))
  }
  Ok(entry)
}

///|
pub fn contract_member(v : ContractEnvelope) -> Member {
  v.item
}

///|
pub fn contract_identity(v : ContractEnvelope) -> (String, String, String) {
  (v.id, v.version, v.cid)
}

///|
pub fn contract_role(v : ContractEnvelope) -> String {
  v.kind
}

///|
pub fn contract_body(v : ContractEnvelope) -> @decode.Cursor {
  v.body
}
