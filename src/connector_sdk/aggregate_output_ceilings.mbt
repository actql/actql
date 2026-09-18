///|
/// Closed units for collection-producing aggregate output limits. These are
/// selected checked obligations, not physical allocation estimates.
pub enum AggregateOutputUnit {
  ArrayItems
  StringBytes
} derive(Eq, Debug)

///|
pub fn array_items_output_unit() -> AggregateOutputUnit {
  ArrayItems
}

///|
pub fn string_bytes_output_unit() -> AggregateOutputUnit {
  StringBytes
}

///|
/// A Connector declaration for one exact aggregate occurrence. The common
/// Host still compares this declaration with the owned checked requirement.
pub struct AggregateOutputCeiling {
  step : Int
  aggregate : String
  unit : AggregateOutputUnit
  maximum : Int64
}

///|
/// Construct a finite declaration without granting permission to discharge it.
pub fn aggregate_output_ceiling(
  step : Int,
  aggregate : String,
  unit : AggregateOutputUnit,
  maximum : Int64,
) -> Result[AggregateOutputCeiling, FixedComputeIssue] {
  if step < 0 || maximum < 0L {
    return Err(InvalidLimits)
  }
  Ok({ step, aggregate, unit, maximum, })
}

///|
pub fn aggregate_output_ceiling_step(value : AggregateOutputCeiling) -> Int {
  value.step
}

///|
pub fn aggregate_output_ceiling_name(value : AggregateOutputCeiling) -> String {
  value.aggregate
}

///|
pub fn aggregate_output_ceiling_unit(
  value : AggregateOutputCeiling,
) -> AggregateOutputUnit {
  value.unit
}

///|
pub fn aggregate_output_unit_name(value : AggregateOutputUnit) -> String {
  match value {
    ArrayItems => "array_items"
    StringBytes => "string_bytes"
  }
}

///|
pub fn aggregate_output_ceiling_maximum(
  value : AggregateOutputCeiling,
) -> Int64 {
  value.maximum
}

///|
/// Snapshot exact occurrence declarations. Duplicate occurrence keys are
/// ambiguous even when their numeric values happen to agree.
fn snapshot_aggregate_output_ceilings(
  supplied : Array[AggregateOutputCeiling],
  step_count : Int,
) -> Array[AggregateOutputCeiling]? {
  if step_count < 0 {
    return None
  }
  let snapshot : Array[AggregateOutputCeiling] = []
  for value in supplied {
    if value.step < 0 || value.step >= step_count || value.maximum < 0L {
      return None
    }
    for previous in snapshot {
      if previous.step == value.step &&
        previous.aggregate == value.aggregate &&
        previous.unit == value.unit {
        return None
      }
    }
    snapshot.push(value)
  }
  Some(snapshot)
}

///|
fn find_aggregate_output_ceiling(
  ceilings : Array[AggregateOutputCeiling],
  step : Int,
  aggregate : String,
  unit : AggregateOutputUnit,
) -> Int64? {
  for value in ceilings {
    if value.step == step && value.aggregate == aggregate && value.unit == unit {
      return Some(value.maximum)
    }
  }
  None
}
