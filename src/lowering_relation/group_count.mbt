///|
/// An owned view of the initial exact-count profile, not executable evidence.
/// Keep checked field identities; no argument roots are fabricated for fields.
struct PreparedCountGroup {
  checked : @relation.CheckedOperation
  keys : Array[@schema.FieldName]
  counts : Array[PreparedCount]
  name_bytes : Int
}

///|
pub struct PreparedCount {
  name : String
  field : @schema.FieldName?
  distinct : Bool?
}

///|
/// Owner-bound aggregate input. Expressions retain their checked typed owner;
/// direct fields retain exact schema identity rather than a textual lookup.
pub enum PreparedAggregateArgument {
  AggregateRows
  AggregateField(@schema.FieldName)
  AggregateExpression(Expression)
}

///|
/// Complete typed view of one checked aggregate occurrence.
struct PreparedAggregate {
  name : String
  function : @relation.AggregateFunction
  argument : PreparedAggregateArgument
  filter : Expression?
  result : @contract.Contract
  distinct : Bool?
  order : Array[@relation.OrderTerm]
  item_limit : Int64?
  byte_limit : Int64?
  delimiter : String?
  fraction : Double?
  numeric_observation : Bool
}

///|
/// Complete group view for execution lowering. The checked owner remains the
/// authority for validation and operation identity.
struct PreparedGroup {
  checked : @relation.CheckedOperation
  window : Bool
  keys : Array[@schema.FieldName]
  authored_key_offset : Int
  aggregates : Array[PreparedAggregate]
  name_bytes : Int
  entries : Int
}

///|
pub(all) enum GroupIssue {
  GroupNotFound
  InvalidGroupLimits
  GroupPreparationLimit
  GroupExpressionFailure(ExpressionIssue)
  MissingGroupParameter(String)
  InvalidGroupParameter(String)
  InvalidCheckedAggregate(Int)
}

///|
pub(all) enum CountGroupIssue {
  NotGroup
  UnsupportedAggregate(Int)
  InvalidLimits
  PreparationLimit
} derive(Eq, Debug)

///|
pub fn prepare_count_group(
  checked : @relation.CheckedOperation,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[PreparedCountGroup, CountGroupIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  guard @relation.group(checked) is Some(group) else { return Err(NotGroup) }
  // The shared checked accessor preserves repeated grouping occurrences.
  // Schema width does not bound their count. Check the actual occurrences
  // before constructing further arrays or processing names.
  let count = @relation.aggregate_count(group)
  if count > max_entries {
    return Err(PreparationLimit)
  }
  let checked_keys = @relation.group_keys(group)
  if checked_keys.length() > max_entries - count {
    return Err(PreparationLimit)
  }
  let mut remaining = max_name_bytes
  let spend_name = fn(name : String) -> Bool {
    if name.length() > remaining {
      return false
    }
    let bytes = @utf8.encode(name).length()
    if bytes > remaining {
      return false
    }
    remaining -= bytes
    true
  }
  let keys = []
  for key in checked_keys {
    if !spend_name(@schema.reference_name(key.field)) {
      return Err(PreparationLimit)
    }
    keys.push(key.field)
  }
  let counts = []
  for i in 0..<count {
    let aggregate = @relation.aggregate_at(group, i).unwrap()
    if @relation.aggregate_function(aggregate) != @relation.Count ||
      @relation.aggregate_filter(aggregate) is Some(_) ||
      @relation.aggregate_distinct(aggregate) == Some(true) {
      return Err(UnsupportedAggregate(i))
    }
    let field = match @relation.aggregate_argument(aggregate) {
      Rows => None
      Field(key) => Some(key.field)
      Expression(_) => return Err(UnsupportedAggregate(i))
    }
    let name = @relation.aggregate_name(aggregate)
    if !spend_name(name) {
      return Err(PreparationLimit)
    }
    if field is Some(field) && !spend_name(@schema.reference_name(field)) {
      return Err(PreparationLimit)
    }
    counts.push({
      name,
      field,
      distinct: @relation.aggregate_distinct(aggregate),
    })
  }
  Ok({ checked, keys, counts, name_bytes: max_name_bytes - remaining, })
}

///|
pub fn count_group_checked(
  group : PreparedCountGroup,
) -> @relation.CheckedOperation {
  group.checked
}

///|
pub fn count_group_key_count(group : PreparedCountGroup) -> Int {
  group.keys.length()
}

///|
pub fn count_group_input_schema(group : PreparedCountGroup) -> @schema.Schema {
  @relation.input_schema(group.checked)
}

///|
pub fn count_group_output_schema(group : PreparedCountGroup) -> @schema.Schema {
  @relation.output_schema(group.checked)
}

///|
pub fn count_group_key_at(
  group : PreparedCountGroup,
  index : Int,
) -> @schema.FieldName? {
  group.keys.get(index)
}

///|
pub fn count_group_aggregate_count(group : PreparedCountGroup) -> Int {
  group.counts.length()
}

///|
pub fn count_group_aggregate_at(
  group : PreparedCountGroup,
  index : Int,
) -> PreparedCount? {
  group.counts.get(index)
}

///|
/// Lowers one checked aggregate occurrence for group and analytic consumers.
/// The caller supplies owner-bound expression and Parameter resolution.
fn prepare_aggregate_occurrence(
  aggregate : @relation.CheckedAggregate,
  ordinal : Int,
  input_schema : @schema.Schema,
  max_order_terms : Int,
  lower : (Int) -> Result[Expression, GroupIssue],
  resolve_count : (@relation.CountValue) -> Result[Int64, GroupIssue],
  resolve_fraction : (@relation.FractionValue) -> Result[Double, GroupIssue],
  spend_name : (String) -> Bool,
) -> Result[(PreparedAggregate, Int), GroupIssue] {
  let name = @relation.aggregate_name(aggregate)
  if max_order_terms < 0 || !spend_name(name) {
    return Err(GroupPreparationLimit)
  }
  let filter = match @relation.aggregate_filter(aggregate) {
    None => None
    Some(index) =>
      match lower(index) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
  }
  let (argument, input_contract) = match
    @relation.aggregate_argument(aggregate) {
    Rows => (AggregateRows, None)
    Field(key) => {
      let field = key.field
      if !spend_name(@schema.reference_name(field)) {
        return Err(GroupPreparationLimit)
      }
      guard @schema.lookup(input_schema, field) is Some(contract) else {
        return Err(InvalidCheckedAggregate(ordinal))
      }
      (AggregateField(field), Some(contract))
    }
    Expression(index) =>
      match lower(index) {
        Ok(value) => {
          let contract = expression_contract(value)
          (AggregateExpression(value), Some(contract))
        }
        Err(issue) => return Err(issue)
      }
  }
  let order = @relation.aggregate_order(aggregate)
  if order.length() > max_order_terms {
    return Err(GroupPreparationLimit)
  }
  for term in order {
    if !spend_name(@schema.reference_name(term.field)) {
      return Err(GroupPreparationLimit)
    }
  }
  let item_limit = match @relation.aggregate_item_limit(aggregate) {
    None => None
    Some(value) =>
      match resolve_count(value) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
  }
  let byte_limit = match @relation.aggregate_byte_limit(aggregate) {
    None => None
    Some(value) =>
      match resolve_count(value) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
  }
  let fraction = match @relation.aggregate_fraction(aggregate) {
    None => None
    Some(value) =>
      match resolve_fraction(value) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
  }
  let function = @relation.aggregate_function(aggregate)
  let numeric_observation = (
      function is @relation.Sum || function is @relation.Avg
    ) &&
    input_contract is Some({ shape: @contract.Number, .. })
  Ok(
    (
      {
        name,
        function,
        argument,
        filter,
        result: @relation.aggregate_result(aggregate),
        distinct: @relation.aggregate_distinct(aggregate),
        order,
        item_limit,
        byte_limit,
        delimiter: @relation.aggregate_delimiter(aggregate),
        fraction,
        numeric_observation,
      },
      order.length(),
    ),
  )
}

///|
/// Prepares every normative group aggregate from the exact checked step.
/// This is a typed execution view, not registry or numeric-observation
/// admission.
pub fn prepare_group(
  owner : BoundPrepared,
  step_index : Int,
  max_entries : Int,
  max_name_bytes : Int,
  limits : ExpressionLimits,
) -> Result[(PreparedGroup, ExpressionLimits), GroupIssue] {
  if max_entries < 0 ||
    max_name_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_work < 0 ||
    limits.max_depth < 0 ||
    limits.max_literal_nodes < 0 ||
    limits.max_literal_text_bytes < 0 {
    return Err(InvalidGroupLimits)
  }
  guard owner.prepared.nodes.get(step_index) is Some(node) else {
    return Err(GroupNotFound)
  }
  let (checked, window) = match node.payload {
    CountGroup(checked) => (checked, false)
    WindowGroup(checked) => (checked, true)
    _ => return Err(GroupNotFound)
  }
  guard @relation.group(checked) is Some(group) else {
    return Err(GroupNotFound)
  }
  let aggregate_count = @relation.aggregate_count(group)
  let checked_keys = @relation.group_keys(group)
  if checked_keys.length() > max_entries ||
    aggregate_count > max_entries - checked_keys.length() {
    return Err(GroupPreparationLimit)
  }
  let mut remaining_names = max_name_bytes
  let spend_name = fn(name : String) -> Bool {
    if name.length() > remaining_names {
      return false
    }
    let bytes = @utf8.encode(name).length()
    if bytes > remaining_names {
      return false
    }
    remaining_names -= bytes
    true
  }
  let keys : Array[@schema.FieldName] = []
  for key in checked_keys {
    if !spend_name(@schema.reference_name(key.field)) {
      return Err(GroupPreparationLimit)
    }
    keys.push(key.field)
  }
  let authored_key_offset = if window { 2 } else { 0 }
  if window {
    guard checked_keys.length() >= 2 &&
      @pipeline.step_at(owner.prepared.owner, step_index) is Some(step) &&
      @pipeline.window_evidence(step) is Some(evidence) else {
      return Err(GroupNotFound)
    }
    let (start, end) = @pipeline.window_fields(evidence)
    if checked_keys[0].field != start || checked_keys[1].field != end {
      return Err(GroupNotFound)
    }
  }
  let mut remaining = limits
  let lower = fn(index : Int) -> Result[Expression, GroupIssue] {
    let (expression, usage) = match
      lower_expression_measured(owner, step_index, index, remaining) {
      Ok(value) => value
      Err(issue) => return Err(GroupExpressionFailure(issue))
    }
    remaining = {
      ..remaining,
      max_nodes: remaining.max_nodes - usage.nodes,
      max_work: remaining.max_work - usage.work,
      max_literal_nodes: remaining.max_literal_nodes - usage.literal_nodes,
      max_literal_text_bytes: remaining.max_literal_text_bytes -
      usage.literal_bytes,
    }
    Ok(expression)
  }
  let resolve_count = fn(
    value : @relation.CountValue,
  ) -> Result[Int64, GroupIssue] {
    match value {
      Literal(value) => Ok(value)
      Parameter(name) => {
        if !spend_name(name) {
          return Err(GroupPreparationLimit)
        }
        guard parameter_value(owner, name) is Some(bound) else {
          return Err(MissingGroupParameter(name))
        }
        guard bound.value is @value.Number(number) &&
          @scalar.read_safe_integer(number) is Some(value) &&
          value >= 1L else {
          return Err(InvalidGroupParameter(name))
        }
        Ok(value)
      }
    }
  }
  let resolve_fraction = fn(
    value : @relation.FractionValue,
  ) -> Result[Double, GroupIssue] {
    match value {
      Fraction(value) => Ok(value)
      ParameterFraction(name) => {
        if !spend_name(name) {
          return Err(GroupPreparationLimit)
        }
        guard parameter_value(owner, name) is Some(bound) else {
          return Err(MissingGroupParameter(name))
        }
        guard bound.value is @value.Number(number) &&
          @scalar.read_finite_number(number) is Some(value) &&
          value >= 0.0 &&
          value <= 1.0 &&
          (value != 0.0 || 1.0 / value > 0.0) else {
          return Err(InvalidGroupParameter(name))
        }
        Ok(value)
      }
    }
  }
  let input_schema = @relation.input_schema(checked)
  let aggregates : Array[PreparedAggregate] = []
  let mut entries = checked_keys.length() + aggregate_count
  for i in 0..<aggregate_count {
    let aggregate = @relation.aggregate_at(group, i).unwrap()
    let (prepared, order_terms) = match
      prepare_aggregate_occurrence(
        aggregate,
        i,
        input_schema,
        max_entries - entries,
        lower,
        resolve_count,
        resolve_fraction,
        spend_name,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    entries += order_terms
    aggregates.push(prepared)
  }
  Ok(
    (
      {
        checked,
        window,
        keys,
        authored_key_offset,
        aggregates,
        name_bytes: max_name_bytes - remaining_names,
        entries,
      },
      remaining,
    ),
  )
}

///|
pub fn group_checked(group : PreparedGroup) -> @relation.CheckedOperation {
  group.checked
}

///|
pub fn group_is_window(group : PreparedGroup) -> Bool {
  group.window
}

///|
pub fn group_input_schema(group : PreparedGroup) -> @schema.Schema {
  @relation.input_schema(group.checked)
}

///|
pub fn group_output_schema(group : PreparedGroup) -> @schema.Schema {
  @relation.output_schema(group.checked)
}

///|
pub fn group_key_count(group : PreparedGroup) -> Int {
  group.keys.length()
}

///|
pub fn group_key_at(group : PreparedGroup, index : Int) -> @schema.FieldName? {
  group.keys.get(index)
}

///|
pub fn group_aggregate_count(group : PreparedGroup) -> Int {
  group.aggregates.length()
}

///|
pub fn group_aggregate_at(
  group : PreparedGroup,
  index : Int,
) -> PreparedAggregate? {
  group.aggregates.get(index)
}

///|
pub fn group_name_bytes(group : PreparedGroup) -> Int {
  group.name_bytes
}

///|
pub fn group_entry_count(group : PreparedGroup) -> Int {
  group.entries
}

///|
pub fn group_aggregate_name(value : PreparedAggregate) -> String {
  value.name
}

///|
pub fn group_aggregate_function(
  value : PreparedAggregate,
) -> @relation.AggregateFunction {
  value.function
}

///|
pub fn group_aggregate_argument(
  value : PreparedAggregate,
) -> PreparedAggregateArgument {
  value.argument
}

///|
pub fn group_aggregate_filter(value : PreparedAggregate) -> Expression? {
  value.filter
}

///|
pub fn group_aggregate_result(value : PreparedAggregate) -> @contract.Contract {
  value.result
}

///|
pub fn group_aggregate_distinct(value : PreparedAggregate) -> Bool? {
  value.distinct
}

///|
pub fn group_aggregate_order_count(value : PreparedAggregate) -> Int {
  value.order.length()
}

///|
pub fn group_aggregate_order_at(
  value : PreparedAggregate,
  index : Int,
) -> @relation.OrderTerm? {
  value.order.get(index)
}

///|
pub fn group_aggregate_order_term_at(
  value : PreparedAggregate,
  index : Int,
) -> (@schema.FieldName, Bool, Bool)? {
  value.order
  .get(index)
  .map(term => (term.field, term.direction is Desc, term.nulls is First))
}

///|
pub fn group_aggregate_item_limit(value : PreparedAggregate) -> Int64? {
  value.item_limit
}

///|
pub fn group_aggregate_byte_limit(value : PreparedAggregate) -> Int64? {
  value.byte_limit
}

///|
pub fn group_aggregate_delimiter(value : PreparedAggregate) -> String? {
  value.delimiter
}

///|
pub fn group_aggregate_fraction(value : PreparedAggregate) -> Double? {
  value.fraction
}

///|
pub fn group_aggregate_requires_numeric_observation(
  value : PreparedAggregate,
) -> Bool {
  value.numeric_observation
}

///|
pub fn group_aggregate_requires_expression_context(
  value : PreparedAggregate,
) -> Bool {
  value.filter is Some(_) || value.argument is AggregateExpression(_)
}

///|
fn group_aggregate_function_name(
  function : @relation.AggregateFunction,
) -> String {
  match function {
    Count => "count"
    CountIf => "count_if"
    Sum => "sum"
    Avg => "avg"
    Min => "min"
    Max => "max"
    ArrayAgg => "array_agg"
    StringAgg => "string_agg"
    First => "first"
    Last => "last"
    PercentileDisc => "percentile_disc"
    PercentileCont => "percentile_cont"
    VarPop => "var_pop"
    VarSamp => "var_samp"
    StddevPop => "stddev_pop"
    StddevSamp => "stddev_samp"
  }
}

///|
fn emit_group_params(
  group : PreparedGroup,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "aggs")
  @encode.begin_object(out)
  for aggregate in group.aggregates {
    @encode.key(out, aggregate.name)
    @encode.begin_object(out)
    if aggregate.delimiter is Some(delimiter) {
      @encode.key(out, "delimiter")
      @encode.string_value(out, delimiter)
    }
    if aggregate.distinct is Some(distinct) {
      @encode.key(out, "distinct")
      @encode.bool_value(out, distinct)
    }
    match aggregate.argument {
      AggregateRows => ()
      AggregateField(field) => {
        @encode.key(out, "field")
        @encode.string_value(out, @schema.reference_name(field))
      }
      AggregateExpression(expression) => {
        @encode.key(out, "expr")
        emit_expression_source(expression, out)
      }
    }
    if aggregate.filter is Some(filter) {
      @encode.key(out, "filter")
      emit_expression_source(filter, out)
    }
    @encode.key(out, "fn")
    @encode.string_value(out, group_aggregate_function_name(aggregate.function))
    if aggregate.fraction is Some(fraction) {
      @encode.key(out, "fraction")
      @encode.number_value(out, fraction)
    }
    if aggregate.byte_limit is Some(limit) {
      @encode.key(out, "max_bytes")
      @encode.number_value(out, limit.to_double())
    }
    if aggregate.item_limit is Some(limit) {
      @encode.key(out, "max_items")
      @encode.number_value(out, limit.to_double())
    }
    if !aggregate.order.is_empty() {
      @encode.key(out, "order_by")
      @encode.begin_array(out)
      for term in aggregate.order {
        @encode.begin_object(out)
        @encode.key(out, "dir")
        @encode.string_value(
          out,
          if term.direction is Desc {
            "desc"
          } else {
            "asc"
          },
        )
        @encode.key(out, "field")
        @encode.string_value(out, @schema.reference_name(term.field))
        @encode.key(out, "nulls")
        @encode.string_value(
          out,
          if term.nulls is First {
            "first"
          } else {
            "last"
          },
        )
        @encode.end_object(out)
      }
      @encode.end_array(out)
    }
    @encode.end_object(out)
  }
  @encode.end_object(out)
  @encode.key(out, "by")
  @encode.begin_array(out)
  for i = group.authored_key_offset; i < group.keys.length(); i = i + 1 {
    @encode.string_value(out, @schema.reference_name(group.keys[i]))
  }
  @encode.end_array(out)
  @encode.end_object(out)
}

///|
fn emit_count_group_params(
  group : PreparedCountGroup,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "aggs")
  @encode.begin_object(out)
  for count in group.counts {
    @encode.key(out, count.name)
    @encode.begin_object(out)
    if count.distinct is Some(value) {
      @encode.key(out, "distinct")
      @encode.bool_value(out, value)
    }
    if count.field is Some(field) {
      @encode.key(out, "field")
      @encode.string_value(out, @schema.reference_name(field))
    }
    @encode.key(out, "fn")
    @encode.string_value(out, "count")
    @encode.end_object(out)
  }
  @encode.end_object(out)
  @encode.key(out, "by")
  @encode.begin_array(out)
  for field in group.keys {
    @encode.string_value(out, @schema.reference_name(field))
  }
  @encode.end_array(out)
  @encode.end_object(out)
}
