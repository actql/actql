///|
pub type AsOfDirection = @evidence.AsOfDirection

///|
pub type AsOfSource = @evidence.AsOfSource

///|
pub type CheckedAsOf = @evidence.CheckedAsOf

///|
pub fn check_asof(
  body : @decode.Cursor,
  left : @carrier.Carrier,
  right : @carrier.Carrier,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedAsOf, Issue] {
  @evidence.check_asof(body, left, right, parameters, limits)
}

///|
pub fn check_asof_sources(
  body : @decode.Cursor,
  left_source : AsOfSource,
  right_source : AsOfSource,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedAsOf, Issue] {
  @evidence.check_asof_sources(
    body, left_source, right_source, parameters, limits,
  )
}

///|
pub fn asof_output_schema(v : CheckedAsOf) -> @schema.Schema {
  @evidence.asof_output_schema(v)
}

///|
pub fn asof_input_records(
  v : CheckedAsOf,
  side : @schema.Side,
) -> @carrier.Knowledge {
  @evidence.asof_input_records(v, side)
}

///|
pub fn asof_projection_count(v : CheckedAsOf) -> Int {
  @evidence.asof_projection_count(v)
}

///|
pub fn asof_projection_at(v : CheckedAsOf, index : Int) -> Projection? {
  @evidence.asof_projection_at(v, index)
}

///|
pub fn asof_kind(v : CheckedAsOf) -> Kind {
  @evidence.asof_kind(v)
}

///|
pub fn asof_direction(v : CheckedAsOf) -> AsOfDirection {
  @evidence.asof_direction(v)
}

///|
pub fn asof_identity(v : CheckedAsOf) -> Array[@schema.FieldName] {
  @evidence.asof_identity(v)
}

///|
pub fn asof_time(v : CheckedAsOf, side : @schema.Side) -> @schema.FieldName {
  @evidence.asof_time(v, side)
}

///|
pub fn asof_uses_timestamp(v : CheckedAsOf, side : @schema.Side) -> Bool {
  @evidence.asof_uses_timestamp(v, side)
}

///|
pub fn asof_tolerance(v : CheckedAsOf) -> @temporal.Milliseconds {
  @evidence.asof_tolerance(v)
}

///|
pub fn asof_keys(v : CheckedAsOf) -> Array[KeyPair] {
  @evidence.asof_keys(v)
}

///|
pub fn asof_tie_break(v : CheckedAsOf) -> Array[@schema.FieldName]? {
  @evidence.asof_tie_break(v)
}

///|
pub fn asof_completed_tie_break(v : CheckedAsOf) -> Array[@schema.FieldName] {
  @evidence.asof_completed_tie_break(v)
}

///|
pub fn asof_key_completion(
  v : CheckedAsOf,
  side : @schema.Side,
) -> @evidence.KeyedRelation? {
  @evidence.asof_key_completion(v, side)
}

///|
pub fn asof_projection(v : CheckedAsOf) -> Array[Projection] {
  @evidence.asof_projection(v)
}

///|
pub fn asof_pending_validations(v : CheckedAsOf) -> Array[Obligation] {
  @evidence.asof_pending_validations(v)
}

///|
/// O(1), without materializing the obligation array.
pub fn asof_pending_validation_count(v : CheckedAsOf) -> Int {
  @evidence.asof_pending_validation_count(v)
}

///|
/// O(1); invalid indices return None. Retains authored obligation order.
pub fn asof_pending_validation_at(v : CheckedAsOf, index : Int) -> Obligation? {
  @evidence.asof_pending_validation_at(v, index)
}

///|
pub fn asof_usage(v : CheckedAsOf) -> Usage {
  @evidence.asof_usage(v)
}

///|
pub fn asof_source(v : CheckedAsOf) -> @decode.Cursor {
  @evidence.asof_source(v)
}
