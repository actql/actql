///|
pub type Kind = @shape.Kind

///|
pub type NullKey = @shape.NullKey

///|
pub type Cardinality = @shape.Cardinality

///|
pub type Guard = @shape.Guard

///|
pub type Obligation = @shape.Obligation

///|
pub type Limits = @shape.Limits

///|
pub type Usage = @shape.Usage

///|
pub type IssueKind = @shape.IssueKind

///|
pub type Issue = @shape.Issue

///|
pub type KeyPair = @shape.KeyPair

///|
pub type Projection = @shape.Projection

///|
pub type CheckedJoin = @shape.CheckedJoin

///|
pub type CheckedCrossJoin = @shape.CheckedCrossJoin

///|
pub type IntervalMode = @shape.IntervalMode

///|
pub type TemporalOperand = @shape.TemporalOperand

///|
pub type CheckedIntervalJoin = @shape.CheckedIntervalJoin

///|
pub fn interval_input_schema(
  v : CheckedIntervalJoin,
  side : @schema.Side,
) -> @schema.Schema {
  @shape.interval_input_schema(v, side)
}

///|
pub fn interval_key_count(v : CheckedIntervalJoin) -> Int {
  @shape.interval_key_count(v)
}

///|
pub fn interval_key_at(v : CheckedIntervalJoin, index : Int) -> KeyPair? {
  @shape.interval_key_at(v, index)
}

///|
pub fn source(v : CheckedJoin) -> @decode.Cursor {
  @shape.source(v)
}

///|
pub fn input_schema(v : CheckedJoin, side : @schema.Side) -> @schema.Schema {
  @shape.input_schema(v, side)
}

///|
pub fn output_schema(v : CheckedJoin) -> @schema.Schema {
  @shape.output_schema(v)
}

///|
pub fn kind(v : CheckedJoin) -> Kind {
  @shape.kind(v)
}

///|
pub fn null_key(v : CheckedJoin) -> NullKey {
  @shape.null_key(v)
}

///|
pub fn keys(v : CheckedJoin) -> Array[KeyPair] {
  @shape.keys(v)
}

///|
pub fn key_count(v : CheckedJoin) -> Int {
  @shape.key_count(v)
}

///|
pub fn key_at(v : CheckedJoin, index : Int) -> KeyPair? {
  @shape.key_at(v, index)
}

///|
pub fn projection(v : CheckedJoin) -> Array[Projection]? {
  @shape.projection(v)
}

///|
pub fn assertion(v : CheckedJoin) -> Cardinality? {
  @shape.assertion(v)
}

///|
pub fn output_guard(v : CheckedJoin) -> Guard? {
  @shape.output_guard(v)
}

///|
pub fn pending_validations(v : CheckedJoin) -> Array[Obligation] {
  @shape.pending_validations(v)
}

///|
/// O(1), without materializing the obligation array.
pub fn pending_validation_count(v : CheckedJoin) -> Int {
  @shape.pending_validation_count(v)
}

///|
/// O(1); invalid indices return None. Retains authored obligation order.
pub fn pending_validation_at(v : CheckedJoin, index : Int) -> Obligation? {
  @shape.pending_validation_at(v, index)
}

///|
pub fn usage(v : CheckedJoin) -> Usage {
  @shape.usage(v)
}

///|
pub fn check(
  body : @decode.Cursor,
  left : @schema.Schema,
  right : @schema.Schema,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedJoin, Issue] {
  @shape.check(body, left, right, parameters, limits)
}

///|
pub fn check_cross(
  body : @decode.Cursor,
  left : @schema.Schema,
  right : @schema.Schema,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedCrossJoin, Issue] {
  @shape.check_cross(body, left, right, parameters, limits)
}

///|
pub fn cross_source(value : CheckedCrossJoin) -> @decode.Cursor {
  @shape.cross_source(value)
}

///|
pub fn cross_input_schema(
  value : CheckedCrossJoin,
  side : @schema.Side,
) -> @schema.Schema {
  @shape.cross_input_schema(value, side)
}

///|
pub fn cross_output_schema(value : CheckedCrossJoin) -> @schema.Schema {
  @shape.cross_output_schema(value)
}

///|
pub fn cross_projection(value : CheckedCrossJoin) -> Array[Projection]? {
  @shape.cross_projection(value)
}

///|
pub fn cross_requires_one_right_row(value : CheckedCrossJoin) -> Bool {
  @shape.cross_requires_one_right_row(value)
}

///|
pub fn cross_output_guard(value : CheckedCrossJoin) -> Guard? {
  @shape.cross_output_guard(value)
}

///|
pub fn cross_pending_validations(value : CheckedCrossJoin) -> Array[Obligation] {
  @shape.cross_pending_validations(value)
}

///|
/// O(1), without materializing the obligation array.
pub fn cross_pending_validation_count(value : CheckedCrossJoin) -> Int {
  @shape.cross_pending_validation_count(value)
}

///|
/// O(1); invalid indices return None. Retains authored obligation order.
pub fn cross_pending_validation_at(
  value : CheckedCrossJoin,
  index : Int,
) -> Obligation? {
  @shape.cross_pending_validation_at(value, index)
}

///|
pub fn cross_usage(value : CheckedCrossJoin) -> Usage {
  @shape.cross_usage(value)
}

///|
pub fn check_interval(
  body : @decode.Cursor,
  left : @schema.Schema,
  right : @schema.Schema,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedIntervalJoin, Issue] {
  @shape.check_interval(body, left, right, parameters, limits)
}

///|
pub fn interval_output_schema(v : CheckedIntervalJoin) -> @schema.Schema {
  @shape.interval_output_schema(v)
}

///|
pub fn interval_source(v : CheckedIntervalJoin) -> @decode.Cursor {
  @shape.interval_source(v)
}

///|
pub fn interval_kind(v : CheckedIntervalJoin) -> Kind {
  @shape.interval_kind(v)
}

///|
pub fn interval_mode(v : CheckedIntervalJoin) -> IntervalMode {
  @shape.interval_mode(v)
}

///|
pub fn interval_operand(
  v : CheckedIntervalJoin,
  side : @schema.Side,
) -> TemporalOperand {
  @shape.interval_operand(v, side)
}

///|
pub fn interval_uses_timestamps(v : CheckedIntervalJoin) -> Bool {
  @shape.interval_uses_timestamps(v)
}

///|
pub fn interval_keys(v : CheckedIntervalJoin) -> Array[KeyPair] {
  @shape.interval_keys(v)
}

///|
pub fn interval_projection(v : CheckedIntervalJoin) -> Array[Projection]? {
  @shape.interval_projection(v)
}

///|
pub fn interval_output_guard(v : CheckedIntervalJoin) -> Guard? {
  @shape.interval_output_guard(v)
}

///|
pub fn interval_pending_validations(
  v : CheckedIntervalJoin,
) -> Array[Obligation] {
  @shape.interval_pending_validations(v)
}

///|
/// O(1), without materializing the obligation array.
pub fn interval_pending_validation_count(v : CheckedIntervalJoin) -> Int {
  @shape.interval_pending_validation_count(v)
}

///|
/// O(1); invalid indices return None. Retains authored obligation order.
pub fn interval_pending_validation_at(
  v : CheckedIntervalJoin,
  index : Int,
) -> Obligation? {
  @shape.interval_pending_validation_at(v, index)
}

///|
pub fn interval_usage(v : CheckedIntervalJoin) -> Usage {
  @shape.interval_usage(v)
}
