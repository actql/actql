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
  UnsupportedPolicyField(String)
} derive(Eq, Debug)

///|
struct Witness {
  ceiling : @policy.Ceiling
  unit : @derivation.BoundUnit
  law : String
  cid : String
}

///|
fn mapping(field : String) -> (@derivation.BoundUnit, String)? {
  match field {
    "max_aggregate_array_items" =>
      Some((ArrayItems, "actql.host.aggregate-array-items"))
    "max_artifact_bytes" => Some((Bytes, "actql.host.artifact-bytes"))
    "max_artifact_rows" => Some((Rows, "actql.host.artifact-rows"))
    "max_effect_items" => Some((EffectItems, "actql.host.effect-items"))
    "max_graph_input_edges" => Some((Edges, "actql.host.graph-input-edges"))
    "max_graph_input_nodes" => Some((Nodes, "actql.host.graph-input-nodes"))
    "max_graph_output_rows" => Some((Rows, "actql.host.graph-output"))
    "max_graph_paths" => Some((Paths, "actql.host.graph-paths"))
    "max_infer_items" => Some((DistinctKeys, "actql.host.infer-items"))
    "max_model_request_bytes_per_item" =>
      Some((Bytes, "actql.host.model-request-bytes"))
    "max_nested_value_bytes" => Some((Bytes, "actql.host.nested-value-bytes"))
    "max_relation_output_rows" => Some((Rows, "actql.host.relation-output"))
    "max_temporal_matches_per_key" =>
      Some((MatchesPerKey, "actql.host.temporal-matches"))
    "max_temporal_output_rows" => Some((Rows, "actql.host.temporal-output"))
    _ => None
  }
}

///|
fn unit_text(unit : @derivation.BoundUnit) -> String {
  match unit {
    Rows => "rows"
    DistinctKeys => "distinct_keys"
    EffectItems => "effect_items"
    Bytes => "bytes"
    ArrayItems => "array_items"
    Nodes => "nodes"
    Edges => "edges"
    Paths => "paths"
    MatchesPerKey => "matches_per_key"
  }
}

///|
/// A host_ceiling source witness, not a proven data bound or enforcement fact.
/// Unit, law, role and source cannot be supplied independently by the caller.
pub fn create(
  ceiling : @policy.Ceiling,
  limits : Limits,
) -> Result[Witness, Issue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let field = @policy.ceiling_field(ceiling)
  guard mapping(field) is Some((unit, law)) else {
    return Err(UnsupportedPolicyField(field))
  }
  let pending : Witness = { ceiling, unit, law, cid: "", }
  try {
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_body(pending, writer, false)
    let cid = "sha256:" + @encode.finish_hash(writer)
    Ok({ ..pending, cid, })
  } catch {
    _ => Err(BudgetExceeded)
  }
}

///|
fn emit_body(
  w : Witness,
  writer : @encode.Writer,
  include_identity : Bool,
) -> Unit raise @encode.EncodeFailure {
  let policy_cid = @policy.cid(@policy.ceiling_policy(w.ceiling))
  @encode.begin_object(writer)
  @encode.key(writer, "dependencies")
  @encode.begin_array(writer)
  @encode.string_value(writer, policy_cid)
  @encode.end_array(writer)
  @encode.key(writer, "derivation")
  @encode.begin_object(writer)
  @encode.key(writer, "op")
  @encode.string_value(writer, "source")
  @encode.end_object(writer)
  @encode.key(writer, "law_id")
  @encode.string_value(writer, w.law)
  @encode.key(writer, "role")
  @encode.string_value(writer, "host_ceiling")
  @encode.key(writer, "source")
  @encode.begin_object(writer)
  @encode.key(writer, "field")
  @encode.string_value(writer, @policy.ceiling_field(w.ceiling))
  @encode.key(writer, "kind")
  @encode.string_value(writer, "host_policy")
  @encode.key(writer, "policy_cid")
  @encode.string_value(writer, policy_cid)
  @encode.end_object(writer)
  @encode.key(writer, "unit")
  @encode.string_value(writer, unit_text(w.unit))
  @encode.key(writer, "value")
  @encode.number_value(writer, @policy.ceiling_value(w.ceiling).to_double())
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-bound-witness/0.1")
  if include_identity {
    @encode.key(writer, "witness_cid")
    @encode.string_value(writer, w.cid)
  }
  @encode.end_object(writer)
}

///|
/// Emit the complete canonical wire witness including witness_cid.
/// The supplied Writer independently bounds the full emitted artifact.
pub fn emit(
  w : Witness,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_body(w, writer, true)
}

///|
pub fn cid(w : Witness) -> String {
  w.cid
}

///|
pub fn ceiling(w : Witness) -> @policy.Ceiling {
  w.ceiling
}

///|
pub fn unit(w : Witness) -> @derivation.BoundUnit {
  w.unit
}

///|
pub fn law_id(w : Witness) -> String {
  w.law
}
