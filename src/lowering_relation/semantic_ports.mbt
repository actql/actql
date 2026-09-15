///|
/// Resolved Relation ports retained by the same preparation that allocates
/// canonical node identities. These views never revisit frontend operations,
/// invent input evidence, or grant execution authority.
pub fn preparation_input_count(prepared : Prepared) -> Int {
  prepared.input_schemas.length()
}

///|
pub fn preparation_input_schema(
  prepared : Prepared,
  index : Int,
) -> @schema.Schema? {
  prepared.input_schemas.get(index)
}

///|
/// Ordered input occurrences, not a deduplicated predecessor set. A self join
/// retains both occurrences even when they identify the same logical input.
pub fn node_input_target(node : PreparedNode, index : Int) -> @pipeline.Target? {
  node.input_targets.get(index)
}

///|
pub fn node_output_schema(node : PreparedNode) -> @schema.Schema {
  node.output_schema
}

///|
pub fn preparation_schema_at(
  prepared : Prepared,
  target : @pipeline.Target,
) -> @schema.Schema? {
  match target {
    Input(index) => prepared.input_schemas.get(index)
    Step(index) => prepared.nodes.get(index).map(node => node.output_schema)
  }
}

///|
/// Final output of the finite single-output sequence profile. An empty sequence
/// passes its first input through; an input-free empty preparation has no port.
pub fn preparation_output_target(prepared : Prepared) -> @pipeline.Target? {
  if !prepared.nodes.is_empty() {
    Some(@pipeline.Step(prepared.nodes.length() - 1))
  } else if !prepared.input_schemas.is_empty() {
    Some(@pipeline.Input(0))
  } else {
    None
  }
}
