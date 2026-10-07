///|
/// The small lane has admitted at most eight names of at most 64 UTF16 units.
/// Wide/long-name rows instead retain the role issued by metadata preparation.
fn small_generated_row_source(
  state : BoundedBindingRowsState,
  name : String,
) -> BindingRowSource? {
  if state.json_path is Some(_) && name == state.json_output_name {
    Some(PickedJsonColumn)
  } else if state.watermark is Some(_) {
    match name {
      "watermark_ms" => Some(WatermarkTimeColumn)
      "watermark_late" => Some(WatermarkLateColumn)
      "watermark_decision" => Some(WatermarkDecisionColumn)
      _ => None
    }
  } else if state.lag is Some((_, output, _)) && name == output {
    Some(LagColumn)
  } else {
    None
  }
}

///|
fn generated_row_target(
  state : BoundedBindingRowsState,
  index : Int,
) -> (@schema.FieldName, BindingRowSource)? {
  if state.json_path is Some(_) && index == 0 {
    Some((@schema.Unqualified(state.json_output_name), PickedJsonColumn))
  } else if state.watermark is Some(_) {
    match index {
      0 => Some((@schema.Unqualified("watermark_ms"), WatermarkTimeColumn))
      1 => Some((@schema.Unqualified("watermark_late"), WatermarkLateColumn))
      2 =>
        Some(
          (@schema.Unqualified("watermark_decision"), WatermarkDecisionColumn),
        )
      _ => None
    }
  } else if state.lag is Some((_, output, _)) && index == 0 {
    Some((@schema.Unqualified(output), LagColumn))
  } else {
    None
  }
}

///|
/// A missing input column is legal only for this checked operation's exact
/// generated roles. Compare borrowed spellings without flattening or hashing.
fn advance_generated_row_source(
  state : BoundedBindingRowsState,
  name : @schema.FieldName,
) -> Result[BindingRowSource?, RowIssue] {
  let index = state.metadata_generated_field
  guard generated_row_target(state, index) is Some((target, source)) else {
    return Err(InvalidRows)
  }
  let (order, offset, _) = @schema.compare_reference_fragment(
    name,
    target,
    state.metadata_offset,
    64,
  )
  state.metadata_offset = offset
  match order {
    None => Ok(None)
    Some(0) => {
      let bit = 1 << index
      if (state.metadata_generated_seen & bit) != 0 {
        return Err(InvalidRows)
      }
      state.metadata_generated_seen = state.metadata_generated_seen | bit
      state.metadata_generated_field = -1
      Ok(Some(source))
    }
    Some(_) => {
      state.metadata_generated_field += 1
      Ok(None)
    }
  }
}
