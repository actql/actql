///|
/// Resolved Relation ports retained by the same preparation that allocates
/// canonical node identities. These views never revisit frontend operations,
/// invent input evidence, or grant execution authority.
pub fn preparation_input_count(prepared : Prepared) -> Int {
  prepared.input_carriers.length()
}

///|
pub fn preparation_input_schema(
  prepared : Prepared,
  index : Int,
) -> @schema.Schema? {
  prepared.input_schemas.get(index)
}

///|
/// Exact checked Carrier at one receiving input position. This is semantic
/// metadata only; it is not a runtime value, read authority, or completion.
pub fn preparation_input_carrier(
  prepared : Prepared,
  index : Int,
) -> @carrier.Carrier? {
  prepared.input_carriers.get(index)
}

///|
/// Input provenance category, not proof that a producer has completed.
pub fn preparation_input_is_produced(prepared : Prepared, index : Int) -> Bool {
  @pipeline.input_producer(prepared.owner, index) is Some(_)
}

///|
pub fn preparation_input_keys(
  prepared : Prepared,
  index : Int,
) -> @evidence.KeySet? {
  @pipeline.candidate_keys(prepared.owner, @pipeline.Input(index))
}

///|
/// Ordered input occurrences, not a deduplicated predecessor set. A self join
/// retains both occurrences even when they identify the same logical input.
pub fn node_input_target(node : PreparedNode, index : Int) -> @pipeline.Target? {
  node.input_targets.get(index)
}

///|
pub fn node_input_count(node : PreparedNode) -> Int {
  node.input_targets.length()
}

///|
pub fn node_output_schema(node : PreparedNode) -> @schema.Schema {
  node.output_schema
}

///|
/// Exact checked Carrier produced by this node. Lowering retains the typed
/// result instead of reconstructing Carrier roles from an operation name.
pub fn node_output_carrier(node : PreparedNode) -> @carrier.Carrier {
  node.output_carrier
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
/// Exact checked Carrier at a prepared semantic port.
pub fn preparation_carrier_at(
  prepared : Prepared,
  target : @pipeline.Target,
) -> @carrier.Carrier? {
  match target {
    Input(index) => prepared.input_carriers.get(index)
    Step(index) => prepared.nodes.get(index).map(node => node.output_carrier)
  }
}

///|
/// Final output of the finite single-output sequence profile. An empty sequence
/// passes its first input through; an input-free empty preparation has no port.
pub fn preparation_output_target(prepared : Prepared) -> @pipeline.Target? {
  if !prepared.nodes.is_empty() {
    Some(@pipeline.Step(prepared.nodes.length() - 1))
  } else if !prepared.input_carriers.is_empty() {
    Some(@pipeline.Input(0))
  } else {
    None
  }
}
