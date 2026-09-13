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
  IdentityMismatch
  InvalidJson
  InvalidBody
  UnsupportedVersion
  InvalidCeiling(String)
  NoncanonicalArtifact
} derive(Eq, Debug)

///|
struct Policy {
  cid : String
  values : Map[String, Int64]
}

///|
/// An exact field of an admitted policy; not an observed bound or enforcement.
struct Ceiling {
  policy : Policy
  field : String
  value : Int64
}

///|
let fields : Array[String] = [
  "max_aggregate_array_items", "max_artifact_bytes", "max_artifact_rows", "max_effect_items",
  "max_graph_input_edges", "max_graph_input_nodes", "max_graph_output_rows", "max_graph_paths",
  "max_infer_items", "max_model_input_tokens_per_item", "max_model_request_bytes_per_item",
  "max_model_total_duration_ms", "max_nested_value_bytes", "max_nested_value_depth",
  "max_relation_output_rows", "max_temporal_matches_per_key", "max_temporal_output_rows",
]

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] decoded(v : Result[T, @decode.Issue]) -> T raise Stop {
  match v {
    Ok(x) => x
    Err(_) => raise Stop(InvalidBody)
  }
}

///|
/// expected_cid is selected by the trusted Check Environment, not by the body.
/// This verifies integrity and form, not who authorized the selected policy.
pub fn admit(
  bytes : Bytes,
  expected_cid : String,
  limits : Limits,
) -> Result[Policy, Issue] {
  try {
    if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
      raise Stop(InvalidLimits)
    }
    if bytes.length() > limits.max_bytes {
      raise Stop(BudgetExceeded)
    }
    let cid = "sha256:" + @sha.hex(bytes)
    if cid != expected_cid {
      raise Stop(IdentityMismatch)
    }
    let node = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes: limits.max_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(e) =>
        match e.issue {
          InputLimit | NodeLimit | DepthLimit => raise Stop(BudgetExceeded)
          _ => raise Stop(InvalidJson)
        }
    }
    let cursor = match
      @decode.admit(node, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_bytes,
        max_total_string_bytes: limits.max_bytes,
      }) {
      Ok(v) => v
      Err(_) => raise Stop(BudgetExceeded)
    }
    let names = fields.copy()
    names.push("max_aggregate_string_bytes")
    names.push("version")
    let object = decoded(@decode.closed_object(cursor, names))
    if decoded(@decode.text(decoded(@decode.required(object, "version")))) !=
      "actql-capacity-host-policy/0.1" {
      raise Stop(UnsupportedVersion)
    }
    let values : Map[String, Int64] = Map([])
    for field in fields {
      let source = decoded(@decode.required(object, field))
      let value = match @decode.safe_integer(source) {
        Ok(n) => n
        Err(_) => raise Stop(InvalidCeiling(field))
      }
      if value <= 0L {
        raise Stop(InvalidCeiling(field))
      }
      values[field] = value
    }
    if @decode.lookup(object, "max_aggregate_string_bytes") is Some(source) {
      let value = match @decode.safe_integer(source) {
        Ok(n) => n
        Err(_) => raise Stop(InvalidCeiling("max_aggregate_string_bytes"))
      }
      if value <= 0L {
        raise Stop(InvalidCeiling("max_aggregate_string_bytes"))
      }
      values["max_aggregate_string_bytes"] = value
    }
    let policy : Policy = { cid, values, }
    let canonical = canonical_hash(policy, limits) catch {
      _ => raise Stop(NoncanonicalArtifact)
    }
    if "sha256:" + canonical != cid {
      raise Stop(NoncanonicalArtifact)
    }
    Ok(policy)
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
fn canonical_hash(
  p : Policy,
  limits : Limits,
) -> String raise @encode.EncodeFailure {
  let w = @encode.hashing_writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  @encode.begin_object(w)
  for name in fields {
    @encode.key(w, name)
    @encode.number_value(w, p.values.get(name).unwrap().to_double())
    // The optional string ceiling sorts immediately after the array ceiling.
    if name == "max_aggregate_array_items" &&
      p.values.get("max_aggregate_string_bytes") is Some(value) {
      @encode.key(w, "max_aggregate_string_bytes")
      @encode.number_value(w, value.to_double())
    }
  }
  @encode.key(w, "version")
  @encode.string_value(w, "actql-capacity-host-policy/0.1")
  @encode.end_object(w)
  @encode.finish_hash(w)
}

///|
pub fn cid(policy : Policy) -> String {
  policy.cid
}

///|
pub fn ceiling(policy : Policy, field : String) -> Ceiling? {
  policy.values.get(field).map(value => { policy, field, value, })
}

///|
pub fn ceiling_policy(ceiling : Ceiling) -> Policy {
  ceiling.policy
}

///|
pub fn ceiling_field(ceiling : Ceiling) -> String {
  ceiling.field
}

///|
pub fn ceiling_value(ceiling : Ceiling) -> Int64 {
  ceiling.value
}
