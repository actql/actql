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
  InvalidWitness
  IdentityMismatch
} derive(Eq, Debug)

///|
struct Witness {
  ceiling : @policy.Ceiling
  unit : @derivation.BoundUnit
  law : @law.RegisteredLaw
  cid : String
  wire : @wire.WireWitness
  extent : Ref[(Int, Int, Int)?]
}

///|
fn mapping(field : String) -> (@derivation.BoundUnit, String)? {
  match field {
    "max_aggregate_array_items" =>
      Some((ArrayItems, "actql.host.aggregate-array-items"))
    "max_aggregate_string_bytes" =>
      Some((Bytes, "actql.host.aggregate-string-bytes"))
    "max_artifact_bytes" => Some((Bytes, "actql.host.artifact-bytes"))
    "max_artifact_rows" => Some((Rows, "actql.host.artifact-rows"))
    "max_effect_items" => Some((EffectItems, "actql.host.effect-items"))
    "max_file_listing_items" => Some((Rows, "actql.host.file-listing-items"))
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
  guard @law.admit(law) is Some(law) else { return Err(InvalidWitness) }
  match
    @wire.create_host_source(ceiling, unit, law, {
      max_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(wire) =>
      Ok({ ceiling, unit, law, cid: @wire.cid(wire), wire, extent: Ref(None), })
    Err(InvalidLimits) => Err(InvalidLimits)
    Err(_) => Err(BudgetExceeded)
  }
}

///|
/// Emit the complete canonical wire witness including witness_cid.
/// The supplied Writer independently bounds the full emitted artifact.
pub fn emit(
  w : Witness,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @wire.emit(w.wire, writer)
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
  @law.name(w.law)
}

///|
/// The canonical claim already belongs to this original typed Host witness.
/// This projection does not grant or authenticate its policy application.
pub fn wire_witness(w : Witness) -> @wire.WireWitness {
  w.wire
}

///|
/// Measure immutable wire once, then check tighter output bounds locally.
/// Creation bounds cover the preimage; these bounds cover the complete wire.
pub fn measure(
  w : Witness,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> (Int, Int, Int) raise @encode.EncodeFailure {
  if max_bytes < 0 || max_nodes < 1 || max_depth < 0 {
    raise @encode.OutputLimit
  }
  if w.extent.val is Some(original) {
    if original.0 > max_bytes ||
      original.1 > max_nodes ||
      original.2 > max_depth {
      raise @encode.OutputLimit
    }
    return original
  }
  let writer = @encode.measuring_writer(max_bytes, max_nodes, max_depth)
  emit(w, writer)
  let original = @encode.finish_measurement_usage(writer)
  w.extent.val = Some(original)
  original
}
