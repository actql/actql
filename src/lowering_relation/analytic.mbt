///|
pub(all) enum PreparedFrameBoundary {
  PreparedUnboundedPreceding
  PreparedPreceding(Int64)
  PreparedCurrentRow
  PreparedFollowing(Int64)
  PreparedUnboundedFollowing
} derive(Eq, Debug)

///|
pub struct PreparedRowsFrame {
  start : PreparedFrameBoundary
  end : PreparedFrameBoundary
}

///|
pub enum PreparedAnalyticFunction {
  PreparedRowNumber
  PreparedRank
  PreparedDenseRank
  PreparedLag(Expression, Int64)
  PreparedLead(Expression, Int64)
  PreparedFirstValue(Expression)
  PreparedLastValue(Expression)
  PreparedFrameAggregate(PreparedAggregate)
}

///|
struct PreparedAnalyticCall {
  name : String
  function : PreparedAnalyticFunction
  result : @contract.Contract
}

///|
/// Complete owner-bound analytic execution view. Authored peer terms remain
/// separate from position completion so completion never splits peer groups.
struct PreparedAnalytic {
  checked : @relation.CheckedOperation
  partition : Array[@schema.FieldName]
  peer_order : Array[@relation.OrderTerm]
  position_completion : Array[@schema.FieldName]
  retained_position_order : Bool
  frame : PreparedRowsFrame?
  calls : Array[PreparedAnalyticCall]
  name_bytes : Int
  entries : Int
}

///|
pub(all) enum AnalyticIssue {
  AnalyticNotFound
  InvalidAnalyticLimits
  AnalyticPreparationLimit
  AnalyticExpressionFailure(ExpressionIssue)
  MissingAnalyticParameter(String)
  InvalidAnalyticParameter(String)
  InvalidAnalyticCall(Int)
  AnalyticAggregateFailure(GroupIssue)
}

///|
pub fn prepare_analytic(
  owner : BoundPrepared,
  step_index : Int,
  max_entries : Int,
  max_name_bytes : Int,
  limits : ExpressionLimits,
) -> Result[(PreparedAnalytic, ExpressionLimits), AnalyticIssue] {
  if max_entries < 0 ||
    max_name_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_work < 0 ||
    limits.max_depth < 0 ||
    limits.max_literal_nodes < 0 ||
    limits.max_literal_text_bytes < 0 {
    return Err(InvalidAnalyticLimits)
  }
  guard owner.prepared.nodes.get(step_index) is Some(node) &&
    node.payload is Analytic(checked) &&
    @relation.analytic(checked) is Some(analytic) else {
    return Err(AnalyticNotFound)
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
  let mut remaining = limits
  let lower = fn(index : Int) -> Result[Expression, AnalyticIssue] {
    let (expression, usage) = match
      lower_expression_measured(owner, step_index, index, remaining) {
      Ok(value) => value
      Err(issue) => return Err(AnalyticExpressionFailure(issue))
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
    minimum : Int64,
  ) -> Result[Int64, AnalyticIssue] {
    match value {
      Literal(value) =>
        if value >= minimum && value <= 9007199254740991L {
          Ok(value)
        } else {
          Err(InvalidAnalyticParameter(""))
        }
      Parameter(name) => {
        if !spend_name(name) {
          return Err(AnalyticPreparationLimit)
        }
        guard parameter_value(owner, name) is Some(bound) else {
          return Err(MissingAnalyticParameter(name))
        }
        guard bound.value is @value.Number(number) &&
          @scalar.read_safe_integer(number) is Some(value) &&
          value >= minimum else {
          return Err(InvalidAnalyticParameter(name))
        }
        Ok(value)
      }
    }
  }
  let resolve_fraction = fn(
    value : @relation.FractionValue,
  ) -> Result[Double, AnalyticIssue] {
    match value {
      Fraction(value) => Ok(value)
      ParameterFraction(name) => {
        if !spend_name(name) {
          return Err(AnalyticPreparationLimit)
        }
        guard parameter_value(owner, name) is Some(bound) else {
          return Err(MissingAnalyticParameter(name))
        }
        guard bound.value is @value.Number(number) &&
          @scalar.read_finite_number(number) is Some(value) &&
          value >= 0.0 &&
          value <= 1.0 &&
          (value != 0.0 || 1.0 / value > 0.0) else {
          return Err(InvalidAnalyticParameter(name))
        }
        Ok(value)
      }
    }
  }
  let partition : Array[@schema.FieldName] = []
  let peer_order = @relation.analytic_order(analytic)
  let call_count = @relation.analytic_call_count(analytic)
  let mut entries = @relation.analytic_partition_count(analytic)
  if peer_order.length() > max_entries - entries {
    return Err(AnalyticPreparationLimit)
  }
  entries += peer_order.length()
  if call_count > max_entries - entries {
    return Err(AnalyticPreparationLimit)
  }
  entries += call_count
  for i in 0..<@relation.analytic_partition_count(analytic) {
    let field = @relation.analytic_partition_at(analytic, i).unwrap().field
    if !spend_name(@schema.reference_name(field)) {
      return Err(AnalyticPreparationLimit)
    }
    partition.push(field)
  }
  for term in peer_order {
    if !spend_name(@schema.reference_name(term.field)) {
      return Err(AnalyticPreparationLimit)
    }
  }
  let mut requires_position = false
  for i in 0..<call_count {
    let call = @relation.analytic_call_at(analytic, i).unwrap()
    match call.function {
      @relation.Rank | @relation.DenseRank => ()
      _ => requires_position = true
    }
  }
  let position_completion : Array[@schema.FieldName] = []
  let mut retained_position_order = false
  if requires_position {
    guard @pipeline.analytic_position_order(owner.prepared.owner, step_index)
      is Some(order) &&
      @pipeline.step_at(owner.prepared.owner, step_index) is Some(step) &&
      physical_equal(@pipeline.analytic_order_consumer(order), step) &&
      node.input_targets.get(0) == Some(@pipeline.analytic_order_input(order)) else {
      return Err(AnalyticNotFound)
    }
    match @pipeline.analytic_order_completion(order) {
      Some(completion) => {
        let count = @pipeline.sort_completion_count(completion)
        if count > max_entries - entries {
          return Err(AnalyticPreparationLimit)
        }
        entries += count
        for i in 0..<count {
          let field = @pipeline.sort_completion_field(completion, i).unwrap()
          if !spend_name(@schema.reference_name(field)) {
            return Err(AnalyticPreparationLimit)
          }
          position_completion.push(field)
        }
      }
      None => {
        if @pipeline.analytic_order_retained(order) is None {
          return Err(AnalyticNotFound)
        }
        retained_position_order = true
      }
    }
  }
  let frame = match @relation.analytic_frame(analytic) {
    None => None
    Some(frame) => {
      let prepare_boundary = fn(
        boundary : @relation.FrameBoundary,
      ) -> Result[PreparedFrameBoundary, AnalyticIssue] {
        match boundary {
          UnboundedPreceding => Ok(PreparedUnboundedPreceding)
          Preceding(value) =>
            resolve_count(value, 1L).map(value => PreparedPreceding(value))
          CurrentRow => Ok(PreparedCurrentRow)
          Following(value) =>
            resolve_count(value, 1L).map(value => PreparedFollowing(value))
          UnboundedFollowing => Ok(PreparedUnboundedFollowing)
        }
      }
      let start = match prepare_boundary(frame.start) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let end = match prepare_boundary(frame.end) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      Some({ start, end, })
    }
  }
  let input_schema = @relation.input_schema(checked)
  let calls : Array[PreparedAnalyticCall] = []
  for i in 0..<call_count {
    let call = @relation.analytic_call_at(analytic, i).unwrap()
    if !spend_name(call.name) {
      return Err(AnalyticPreparationLimit)
    }
    let function = match call.function {
      @relation.RowNumber => PreparedRowNumber
      @relation.Rank => PreparedRank
      @relation.DenseRank => PreparedDenseRank
      @relation.Lag(argument~, offset~) => {
        let expression = match lower(argument) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        let offset = match resolve_count(offset, 0L) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        PreparedLag(expression, offset)
      }
      @relation.Lead(argument~, offset~) => {
        let expression = match lower(argument) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        let offset = match resolve_count(offset, 0L) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        PreparedLead(expression, offset)
      }
      @relation.FirstValue(argument~) =>
        match lower(argument) {
          Ok(value) => PreparedFirstValue(value)
          Err(issue) => return Err(issue)
        }
      @relation.LastValue(argument~) =>
        match lower(argument) {
          Ok(value) => PreparedLastValue(value)
          Err(issue) => return Err(issue)
        }
      @relation.Aggregate(aggregate) => {
        let aggregate_lower = fn(
          index : Int,
        ) -> Result[Expression, GroupIssue] {
          match lower(index) {
            Ok(value) => Ok(value)
            Err(AnalyticExpressionFailure(issue)) =>
              Err(GroupExpressionFailure(issue))
            Err(_) => Err(GroupPreparationLimit)
          }
        }
        let aggregate_count = fn(
          value : @relation.CountValue,
        ) -> Result[Int64, GroupIssue] {
          match resolve_count(value, 1L) {
            Ok(value) => Ok(value)
            Err(MissingAnalyticParameter(name)) =>
              Err(MissingGroupParameter(name))
            Err(InvalidAnalyticParameter(name)) =>
              Err(InvalidGroupParameter(name))
            Err(_) => Err(GroupPreparationLimit)
          }
        }
        let aggregate_fraction = fn(
          value : @relation.FractionValue,
        ) -> Result[Double, GroupIssue] {
          match resolve_fraction(value) {
            Ok(value) => Ok(value)
            Err(MissingAnalyticParameter(name)) =>
              Err(MissingGroupParameter(name))
            Err(InvalidAnalyticParameter(name)) =>
              Err(InvalidGroupParameter(name))
            Err(_) => Err(GroupPreparationLimit)
          }
        }
        let prepared = match
          prepare_aggregate_occurrence(
            aggregate,
            i,
            input_schema,
            max_entries - entries,
            aggregate_lower,
            aggregate_count,
            aggregate_fraction,
            spend_name,
          ) {
          Ok((value, order_terms)) => {
            if order_terms != 0 {
              return Err(InvalidAnalyticCall(i))
            }
            value
          }
          Err(issue) => return Err(AnalyticAggregateFailure(issue))
        }
        PreparedFrameAggregate(prepared)
      }
    }
    calls.push({ name: call.name, function, result: call.result, })
  }
  Ok(
    (
      {
        checked,
        partition,
        peer_order,
        position_completion,
        retained_position_order,
        frame,
        calls,
        name_bytes: max_name_bytes - remaining_names,
        entries,
      },
      remaining,
    ),
  )
}

///|
pub fn analytic_checked(value : PreparedAnalytic) -> @relation.CheckedOperation {
  value.checked
}

///|
pub fn analytic_input_schema(value : PreparedAnalytic) -> @schema.Schema {
  @relation.input_schema(value.checked)
}

///|
pub fn analytic_output_schema(value : PreparedAnalytic) -> @schema.Schema {
  @relation.output_schema(value.checked)
}

///|
pub fn analytic_partition_count(value : PreparedAnalytic) -> Int {
  value.partition.length()
}

///|
pub fn analytic_partition_at(
  value : PreparedAnalytic,
  index : Int,
) -> @schema.FieldName? {
  value.partition.get(index)
}

///|
pub fn analytic_peer_term_count(value : PreparedAnalytic) -> Int {
  value.peer_order.length()
}

///|
pub fn analytic_peer_term_at(
  value : PreparedAnalytic,
  index : Int,
) -> (@schema.FieldName, Bool, Bool)? {
  value.peer_order
  .get(index)
  .map(term => (term.field, term.direction is Desc, term.nulls is First))
}

///|
pub fn analytic_position_term_count(value : PreparedAnalytic) -> Int {
  value.peer_order.length() + value.position_completion.length()
}

///|
pub fn analytic_position_term_at(
  value : PreparedAnalytic,
  index : Int,
) -> (@schema.FieldName, Bool, Bool)? {
  if index < 0 {
    None
  } else if index < value.peer_order.length() {
    analytic_peer_term_at(value, index)
  } else {
    value.position_completion
    .get(index - value.peer_order.length())
    .map(field => (field, false, false))
  }
}

///|
pub fn analytic_uses_retained_position_order(value : PreparedAnalytic) -> Bool {
  value.retained_position_order
}

///|
pub fn analytic_frame(value : PreparedAnalytic) -> PreparedRowsFrame? {
  value.frame
}

///|
pub fn prepared_frame_start(value : PreparedRowsFrame) -> PreparedFrameBoundary {
  value.start
}

///|
pub fn prepared_frame_end(value : PreparedRowsFrame) -> PreparedFrameBoundary {
  value.end
}

///|
pub fn analytic_call_count(value : PreparedAnalytic) -> Int {
  value.calls.length()
}

///|
pub fn analytic_call_at(
  value : PreparedAnalytic,
  index : Int,
) -> PreparedAnalyticCall? {
  value.calls.get(index)
}

///|
pub fn analytic_call_name(value : PreparedAnalyticCall) -> String {
  value.name
}

///|
pub fn analytic_call_function(
  value : PreparedAnalyticCall,
) -> PreparedAnalyticFunction {
  value.function
}

///|
pub fn analytic_call_result(value : PreparedAnalyticCall) -> @contract.Contract {
  value.result
}

///|
pub fn analytic_requires_expression_context(value : PreparedAnalytic) -> Bool {
  for call in value.calls {
    if call.function is PreparedFrameAggregate(aggregate) &&
      group_aggregate_requires_expression_context(aggregate) {
      return true
    }
  }
  false
}

///|
pub fn analytic_name_bytes(value : PreparedAnalytic) -> Int {
  value.name_bytes
}

///|
pub fn analytic_entry_count(value : PreparedAnalytic) -> Int {
  value.entries
}

///|
fn emit_prepared_frame_boundary(
  value : PreparedFrameBoundary,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match value {
    PreparedUnboundedPreceding =>
      @encode.string_value(out, "unbounded_preceding")
    PreparedCurrentRow => @encode.string_value(out, "current_row")
    PreparedUnboundedFollowing =>
      @encode.string_value(out, "unbounded_following")
    PreparedPreceding(distance) => {
      @encode.begin_object(out)
      @encode.key(out, "preceding")
      @encode.number_value(out, distance.to_double())
      @encode.end_object(out)
    }
    PreparedFollowing(distance) => {
      @encode.begin_object(out)
      @encode.key(out, "following")
      @encode.number_value(out, distance.to_double())
      @encode.end_object(out)
    }
  }
}

///|
fn emit_analytic_aggregate_call(
  aggregate : PreparedAggregate,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  if !aggregate.order.is_empty() {
    raise @encode.InvalidStructure
  }
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
}

///|
fn emit_analytic_params(
  analytic : PreparedAnalytic,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  if analytic.frame is Some(frame) {
    @encode.key(out, "frame")
    @encode.begin_object(out)
    @encode.key(out, "end")
    emit_prepared_frame_boundary(frame.end, out)
    @encode.key(out, "start")
    emit_prepared_frame_boundary(frame.start, out)
    @encode.end_object(out)
  }
  @encode.key(out, "functions")
  @encode.begin_object(out)
  for call in analytic.calls {
    @encode.key(out, call.name)
    @encode.begin_object(out)
    match call.function {
      PreparedRowNumber => {
        @encode.key(out, "fn")
        @encode.string_value(out, "row_number")
      }
      PreparedRank => {
        @encode.key(out, "fn")
        @encode.string_value(out, "rank")
      }
      PreparedDenseRank => {
        @encode.key(out, "fn")
        @encode.string_value(out, "dense_rank")
      }
      PreparedLag(expression, offset) | PreparedLead(expression, offset) => {
        @encode.key(out, "expr")
        emit_expression_source(expression, out)
        @encode.key(out, "fn")
        @encode.string_value(
          out,
          if call.function is PreparedLag(_, _) {
            "lag"
          } else {
            "lead"
          },
        )
        @encode.key(out, "offset")
        @encode.number_value(out, offset.to_double())
      }
      PreparedFirstValue(expression) | PreparedLastValue(expression) => {
        @encode.key(out, "expr")
        emit_expression_source(expression, out)
        @encode.key(out, "fn")
        @encode.string_value(
          out,
          if call.function is PreparedFirstValue(_) {
            "first_value"
          } else {
            "last_value"
          },
        )
      }
      PreparedFrameAggregate(aggregate) =>
        emit_analytic_aggregate_call(aggregate, out)
    }
    @encode.end_object(out)
  }
  @encode.end_object(out)
  @encode.key(out, "order_by")
  @encode.begin_array(out)
  for term in analytic.peer_order {
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
  @encode.key(out, "partition_by")
  @encode.begin_array(out)
  for field in analytic.partition {
    @encode.string_value(out, @schema.reference_name(field))
  }
  @encode.end_array(out)
  @encode.end_object(out)
}
