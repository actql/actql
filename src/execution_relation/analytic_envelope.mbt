///|
/// Invocation-independent checked ceilings for one prepared analytic step.
/// Construction is available only through the owner-validating sequence API.
priv struct SelectedAnalyticEnvelope {
  step : Int
  input_wire_bytes : Int64
  output_wire_bytes : Int64
  partition_wire_bytes : Int64
  frame_memberships : Int64
  output_rows : Int64
}

///|
fn selected_analytic_envelope_at(
  selected : Array[SelectedAnalyticEnvelope],
  step : Int,
) -> SelectedAnalyticEnvelope? {
  for value in selected {
    if value.step == step {
      return Some(value)
    }
  }
  None
}
