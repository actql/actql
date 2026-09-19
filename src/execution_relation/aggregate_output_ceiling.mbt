///|
/// Closed units for selected collection-aggregate limits. These mirror the
/// common Host obligation without importing Connector lifecycle types into the
/// relation evaluator.
pub enum AggregateOutputUnit {
  ArrayItems
  StringBytes
  NestGroupedBytes
  NestAttachedBytes
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
pub fn nest_grouped_bytes_output_unit() -> AggregateOutputUnit {
  NestGroupedBytes
}

///|
pub fn nest_attached_bytes_output_unit() -> AggregateOutputUnit {
  NestAttachedBytes
}

///|
/// An invocation-independent constraint on one exact prepared aggregate.
/// Construction is available only through the owner-validating sequence API.
priv struct SelectedAggregateOutput {
  step : Int
  aggregate : String
  unit : AggregateOutputUnit
  maximum : Int64
}

///|
fn aggregate_output_matches(
  aggregate : @lower.PreparedAggregate,
  unit : AggregateOutputUnit,
) -> Bool {
  match (@lower.group_aggregate_function(aggregate), unit) {
    (@relation.ArrayAgg, ArrayItems) => true
    (@relation.StringAgg, StringBytes) => true
    (_, NestGroupedBytes | NestAttachedBytes) => false
    _ => false
  }
}

///|
fn authored_aggregate_output_limit(
  aggregate : @lower.PreparedAggregate,
  unit : AggregateOutputUnit,
) -> Int64? {
  match unit {
    ArrayItems => @lower.group_aggregate_item_limit(aggregate)
    StringBytes => @lower.group_aggregate_byte_limit(aggregate)
    NestGroupedBytes | NestAttachedBytes => None
  }
}

///|
fn selected_aggregate_output_limit(
  selected : Array[SelectedAggregateOutput],
  aggregate : @lower.PreparedAggregate,
  unit : AggregateOutputUnit,
) -> Int64? {
  let name = @lower.group_aggregate_name(aggregate)
  let mut maximum : Int64? = None
  for value in selected {
    if value.aggregate == name && value.unit == unit {
      maximum = Some(
        match maximum {
          None => value.maximum
          Some(previous) => Int64::min(previous, value.maximum)
        },
      )
    }
  }
  match (maximum, authored_aggregate_output_limit(aggregate, unit)) {
    (None, authored) => authored
    (selected, None) => selected
    (Some(selected), Some(authored)) => Some(Int64::min(selected, authored))
  }
}

///|
fn selected_aggregate_outputs_at(
  selected : Array[SelectedAggregateOutput],
  step : Int,
) -> Array[SelectedAggregateOutput] {
  selected.filter(value => value.step == step)
}
