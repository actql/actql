///|
pub(all) struct Limits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  InvalidSnapshot
  IdentityMismatch
  NonCanonicalBytes
  TypeContract(@contract.AdmissionError)
} derive(Eq, Debug)

///|
pub(all) enum Completeness {
  Complete
  Partial
} derive(Eq, Debug)

///|
pub struct Materialization {
  input_cid : String
  completeness : Completeness
  integration_binding_cid : String?
}

///|
struct Snapshot {
  reference : @reference.Reference
  schema : @schema.Schema
  contract : @contract.Contract
  materialization : Materialization?
  scores : Array[(String, ScoreDeclaration)]?
  score_source : @decode.Cursor?
  cid : String
  bytes : Int
  nodes : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn string(object : @decode.ObjectView, name : String) -> String raise Stop {
  guard @decode.required(object, name) is Ok(cursor) &&
    @decode.text(cursor) is Ok(value) else {
    raise Stop(InvalidSnapshot)
  }
  value
}

///|
fn valid_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  let mut i = 0
  for ch in value.iter() {
    if i >= 7 && !((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) {
      return false
    }
    i += 1
  }
  true
}

///|
pub fn emit(
  v : Snapshot,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  if v.materialization is Some(m) {
    @encode.key(writer, "completeness")
    @encode.string_value(
      writer,
      match m.completeness {
        Complete => "complete"
        Partial => "partial"
      },
    )
    @encode.key(writer, "input_cid")
    @encode.string_value(writer, m.input_cid)
    if m.integration_binding_cid is Some(cid) {
      @encode.key(writer, "integration_binding_cid")
      @encode.string_value(writer, cid)
    }
  }
  @encode.key(writer, "output_carrier")
  @encode.string_value(writer, "relation")
  @encode.key(writer, "schema")
  @contract.emit_checked(v.contract, writer)
  emit_scores(v, writer)
  @encode.key(writer, "source_ref")
  @encode.string_value(writer, @reference.stringify(v.reference))
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-local-input-schema/0.1")
  @encode.end_object(writer)
}

///|
/// Check canonical bytes and content identity, not environment or Host authority.
pub fn read(
  bytes : Bytes,
  expected_cid : String,
  limits : Limits,
) -> Result[Snapshot, Issue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  if !valid_cid(expected_cid) || "sha256:" + @sha.hex(bytes) != expected_cid {
    return Err(IdentityMismatch)
  }
  let node = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(v) => v
    Err(e) =>
      return Err(
        match e.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidSnapshot
        },
      )
  }
  let cursor = match
    @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(v) => v
    Err(_) => return Err(BudgetExceeded)
  }
  try {
    let object = match
      @decode.closed_object(cursor, [
        "version", "source_ref", "output_carrier", "schema", "input_cid", "completeness",
        "integration_binding_cid", "score_contracts",
      ]) {
      Ok(v) => v
      Err(_) => raise Stop(InvalidSnapshot)
    }
    if string(object, "version") != "actql-local-input-schema/0.1" ||
      string(object, "output_carrier") != "relation" {
      raise Stop(InvalidSnapshot)
    }
    let reference = match
      @reference.read(string(object, "source_ref"), max_bytes=limits.max_bytes) {
      Ok(v) => v
      Err(_) => raise Stop(InvalidSnapshot)
    }
    let schema_cursor = match @decode.required(object, "schema") {
      Ok(v) => v
      Err(_) => raise Stop(InvalidSnapshot)
    }
    let contract = match
      @contract.read_checked(schema_cursor, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_text_bytes: limits.max_bytes,
      }) {
      Ok(v) => v
      Err(e) => raise Stop(TypeContract(e))
    }
    let schema = match @schema.from_object(contract) {
      Ok(v) => v
      Err(_) => raise Stop(InvalidSnapshot)
    }
    if contract.nullable {
      raise Stop(InvalidSnapshot)
    }
    let has_input = @decode.lookup(object, "input_cid") is Some(_)
    let has_complete = @decode.lookup(object, "completeness") is Some(_)
    let has_binding = @decode.lookup(object, "integration_binding_cid")
      is Some(_)
    if has_input != has_complete || (has_binding && !has_input) {
      raise Stop(InvalidSnapshot)
    }
    let materialization = if has_input {
      let input_cid = string(object, "input_cid")
      if !valid_cid(input_cid) {
        raise Stop(InvalidSnapshot)
      }
      let completeness = match string(object, "completeness") {
        "complete" => Complete
        "partial" => Partial
        _ => raise Stop(InvalidSnapshot)
      }
      let integration_binding_cid = if has_binding {
        let cid = string(object, "integration_binding_cid")
        if !valid_cid(cid) {
          raise Stop(InvalidSnapshot)
        }
        Some(cid)
      } else {
        None
      }
      Some({ input_cid, completeness, integration_binding_cid, })
    } else {
      None
    }
    let pending : Snapshot = {
      reference,
      schema,
      contract,
      materialization,
      scores: read_scores(object, schema),
      score_source: @decode.lookup(object, "score_contracts"),
      cid: expected_cid,
      bytes: bytes.length(),
      nodes: 0,
    }
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit(pending, writer)
    let (hash, _, nodes) = @encode.finish_hash_usage(writer)
    if "sha256:" + hash != expected_cid {
      raise Stop(NonCanonicalBytes)
    }
    Ok({ ..pending, nodes, })
  } catch {
    Stop(e) => Err(e)
    _ => Err(BudgetExceeded)
  }
}

///|
pub fn source_reference(v : Snapshot) -> @reference.Reference {
  v.reference
}

///|
pub fn schema(v : Snapshot) -> @schema.Schema {
  v.schema
}

///|
pub fn materialization(v : Snapshot) -> Materialization? {
  v.materialization
}

///|
pub fn cid(v : Snapshot) -> String {
  v.cid
}

///|
pub fn usage(v : Snapshot) -> (Int, Int) {
  (v.bytes, v.nodes)
}
