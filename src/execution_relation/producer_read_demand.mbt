///|
/// Independent metadata demand for the existing linear-search column resolver.
/// Traversal entries and UTF8 name visits are NOT row-operation workspace,
/// cell-value bytes, or allocated array slots. Retained columns is separate.
pub struct ProducerReadDemand {
  entry_visits : Int
  name_visit_bytes : Int
  retained_columns : Int
}

///|
/// Original checked schemas supply cached spelling-byte totals without copying
/// names. Every receiving field can scan every projection and producer column.
/// After a checked projection resolves, its input spelling belongs to producer;
/// the conservative bound covers both resolved references and candidate visits.
/// Failure means invalid facts or real Int representation overflow, not a
/// replacement resource allowance. The enclosing executor still charges work.
pub fn producer_read_schema_demand(
  receiver : @schema.Schema,
  producer : @schema.Schema,
  projection_fields : Int,
) -> ProducerReadDemand? {
  if projection_fields < 0 {
    return None
  }
  let fields = @schema.field_count(receiver).to_int64()
  let columns = @schema.field_count(producer).to_int64()
  let projections = projection_fields.to_int64()
  let receiver_names = @schema.field_reference_name_bytes(receiver).to_int64()
  let producer_names = @schema.field_reference_name_bytes(producer).to_int64()
  if fields < 0L || columns < 0L || receiver_names < 0L || producer_names < 0L {
    return None
  }
  // All inputs are Int bounded; products fit Int64, but the combined visit
  // budget must fit the consumer's Int before addition/multiplication grows.
  let maximum = 2147483647L
  if fields + projections > maximum ||
    (
      fields > 0L &&
      projections + columns > (maximum - fields - projections) / fields
    ) {
    return None
  }
  let entries = fields + projections + fields * (projections + columns)
  let multiplier = if projection_fields == 0 { fields } else { 2L * fields }
  if receiver_names > maximum ||
    (
      multiplier > 0L &&
      producer_names > (maximum - receiver_names) / multiplier
    ) {
    return None
  }
  let names = receiver_names + multiplier * producer_names
  Some({
    entry_visits: entries.to_int(),
    name_visit_bytes: names.to_int(),
    retained_columns: fields.to_int(),
  })
}

///|
pub fn producer_read_demand_entries(value : ProducerReadDemand) -> Int {
  value.entry_visits
}

///|
pub fn producer_read_demand_name_bytes(value : ProducerReadDemand) -> Int {
  value.name_visit_bytes
}

///|
pub fn producer_read_demand_columns(value : ProducerReadDemand) -> Int {
  value.retained_columns
}

///|
/// Metadata demand for the exact receiving/producer owner correspondence.
/// The successful output's schema and column inventory must agree; a foreign
/// receiver or missing original schema cannot obtain a fabricated demand.
pub fn bound_producer_read_demand(
  receiver : @lower.BoundPrepared,
  bound : BoundProducerInput,
) -> ProducerReadDemand? {
  if !physical_equal(receiver, bound.receiver) ||
    !completed_output_available(bound.output) {
    return None
  }
  let target = match bound.consumer_step {
    Some(_) => bound.output.target
    None => Input(bound.input_index)
  }
  guard @lower.preparation_schema_at(@lower.bound_preparation(receiver), target)
    is Some(receiving) else {
    return None
  }
  // Use the completion's own relation projection, including serialization
  // input kernels whose physical relation differs from the authored target.
  let producing = completed_output_relation_schema(bound.output)
  if @schema.field_count(producing) != completed_column_count(bound.output) {
    return None
  }
  let projections = match bound.projection {
    None => 0
    Some(value) => @lower.projection_field_count(value)
  }
  producer_read_schema_demand(receiving, producing, projections)
}
