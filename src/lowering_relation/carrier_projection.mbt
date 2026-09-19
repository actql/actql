///|
/// Checked Carrier projection retained without re-reading frontend syntax.
struct PreparedCarrierProjection {
  node : PreparedNode
  checked : @projection.CheckedProjection
}

///|
pub(all) enum CarrierProjectionIssue {
  InvalidCarrierProjection
} derive(Eq, Debug)

///|
fn prepare_carrier_projection_node(
  node : PreparedNode,
) -> Result[PreparedCarrierProjection, CarrierProjectionIssue] {
  guard node.payload is CarrierProjection(checked) &&
    node.inputs.length() == 1 &&
    @carrier.kind(@projection.output(checked)) == @carrier.RelationKind &&
    @carrier.kind(@projection.input(checked)) != @carrier.RelationKind else {
    return Err(InvalidCarrierProjection)
  }
  Ok({ node, checked, })
}

///|
pub fn carrier_projection_operation(
  value : PreparedCarrierProjection,
) -> @projection.Operation {
  @projection.operation(value.checked)
}

///|
pub fn carrier_projection_output_carrier(
  value : PreparedCarrierProjection,
) -> @carrier.Carrier {
  @projection.output(value.checked)
}

///|
fn emit_carrier_projection_node(
  prepared : PreparedCarrierProjection,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, prepared.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, prepared.node.inputs[0])
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, operation(prepared.node))
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.end_object(out)
  @encode.end_object(out)
}
