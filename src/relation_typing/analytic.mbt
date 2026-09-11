///|
pub(all) enum FrameBoundary {
  UnboundedPreceding
  Preceding(CountValue)
  CurrentRow
  Following(CountValue)
  UnboundedFollowing
} derive(Eq, Debug)

///|
pub struct RowsFrame {
  start : FrameBoundary
  end : FrameBoundary
  source : @decode.Cursor
}

///|
pub enum AnalyticFunction {
  RowNumber
  Rank
  DenseRank
  Lag(argument~ : Int, offset~ : CountValue)
  Lead(argument~ : Int, offset~ : CountValue)
  FirstValue(argument~ : Int)
  LastValue(argument~ : Int)
  Aggregate(CheckedAggregate)
}

///|
pub struct AnalyticCall {
  name : String
  source : @decode.Cursor
  function : AnalyticFunction
  result : @contract.Contract
}

///|
struct CheckedAnalytic {
  partition : Array[KeyField]
  order : Array[OrderTerm]
  frame : RowsFrame?
  calls : Array[AnalyticCall]
}

///|
pub fn analytic(value : CheckedOperation) -> CheckedAnalytic? {
  value.analytic
}

///|
pub fn analytic_partition(value : CheckedAnalytic) -> Array[KeyField] {
  value.partition.copy()
}

///|
/// Authored peer keys, never implicitly extended with position tie-breakers.
pub fn analytic_order(value : CheckedAnalytic) -> Array[OrderTerm] {
  value.order.copy()
}

///|
/// Indexed authored peer terms, without position-completion identity terms.
pub fn analytic_term_count(value : CheckedOperation) -> Int {
  value.analytic.map(a => a.order.length()).unwrap_or(0)
}

///|
pub fn analytic_term_at(value : CheckedOperation, index : Int) -> OrderTerm? {
  value.analytic.bind(a => a.order.get(index))
}

///|
pub fn analytic_frame(value : CheckedAnalytic) -> RowsFrame? {
  value.frame
}

///|
pub fn analytic_calls(value : CheckedAnalytic) -> Array[AnalyticCall] {
  value.calls.copy()
}

///|
fn frame_boundary(
  b : Budget,
  source : @decode.Cursor,
  parameters : Map[String, @contract.Contract],
  pending : Array[PendingValidation],
) -> FrameBoundary raise Stop {
  spend(b, source)
  match @decode.view(source) {
    TextValue(name) =>
      match name {
        "unbounded_preceding" => UnboundedPreceding
        "current_row" => CurrentRow
        "unbounded_following" => UnboundedFollowing
        _ => fail(source, InvalidFrame)
      }
    _ => {
      let obj = decoded(
        @decode.closed_object(source, ["preceding", "following"]),
        source,
      )
      match
        (@decode.lookup(obj, "preceding"), @decode.lookup(obj, "following")) {
        (Some(s), None) => Preceding(row_count(b, s, 1L, parameters, pending))
        (None, Some(s)) => Following(row_count(b, s, 1L, parameters, pending))
        _ => fail(source, InvalidFrame)
      }
    }
  }
}

///|
fn boundary_class(value : FrameBoundary) -> Int {
  match value {
    UnboundedPreceding => 0
    Preceding(_) => 1
    CurrentRow => 2
    Following(_) => 3
    UnboundedFollowing => 4
  }
}

///|
fn read_frame(
  b : Budget,
  source : @decode.Cursor,
  parameters : Map[String, @contract.Contract],
  pending : Array[PendingValidation],
) -> RowsFrame raise Stop {
  let obj = decoded(@decode.closed_object(source, ["start", "end"]), source)
  let start = frame_boundary(
    b,
    decoded(@decode.required(obj, "start"), source),
    parameters,
    pending,
  )
  let end = frame_boundary(
    b,
    decoded(@decode.required(obj, "end"), source),
    parameters,
    pending,
  )
  if start is UnboundedFollowing ||
    end is UnboundedPreceding ||
    boundary_class(start) > boundary_class(end) {
    fail(source, InvalidFrame)
  }
  match (start, end) {
    (Preceding(a), Preceding(z)) | (Following(a), Following(z)) =>
      match (a, z) {
        (Literal(a), Literal(z)) =>
          if (start is Preceding(_) && a < z) ||
            (start is Following(_) && a > z) {
            fail(source, InvalidFrame)
          }
        _ => if a != z { pending.push({ kind: BoundFrameOrder, source, }) }
      }
    _ => ()
  }
  { start, end, source, }
}

///|
fn check_analytic(
  b : Budget,
  body : @decode.Cursor,
  input : @schema.Schema,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
  parameters : @parameter.Declarations?,
  parameter_types : Map[String, @contract.Contract],
  bindings : Array[Binding],
  pending : Array[PendingValidation],
) -> (CheckedAnalytic, Array[(@schema.FieldName, @contract.Contract)]) raise Stop {
  let obj = decoded(
    @decode.closed_object(body, [
      "partition_by", "order_by", "functions", "frame",
    ]),
    body,
  )
  let partition = row_keys(
    b,
    decoded(@decode.required(obj, "partition_by"), body),
    visible,
    unique=false,
  )
  let order_source = decoded(@decode.required(obj, "order_by"), body)
  let order = row_order(b, order_source, visible)
  if order.is_empty() {
    fail(order_source, InvalidOrder)
  }
  let frame = @decode.lookup(obj, "frame").map(s => {
    read_frame(b, s, parameter_types, pending)
  })
  let source = decoded(@decode.required(obj, "functions"), body)
  let funcs = decoded(@decode.open_object(source), source)
  let names = decoded(@decode.object_field_names(source), source)
  if names.is_empty() {
    fail(source, EmptyBody)
  }
  spend(b, source, count=names.length())
  names.sort_by(@canonical.compare_utf16)
  let fields : Array[(@schema.FieldName, @contract.Contract)] = []
  for i in 0..<@schema.field_count(input) {
    spend(b, body)
    let f = @schema.field_at(input, i).unwrap()
    fields.push((f.name, f.contract))
  }
  let calls : Array[AnalyticCall] = []
  let mut has_frame_call = false
  let mut needs_position = false
  for name in names {
    let s = @decode.lookup(funcs, name).unwrap()
    field_name(b, s, name)
    if visible.contains(name) {
      fail(s, InputCollision(name))
    }
    let call = decoded(@decode.open_object(s), s)
    let fn_source = decoded(@decode.required(call, "fn"), s)
    let fn_name = decoded(@decode.text(fn_source), fn_source)
    let (function, result) = match fn_name {
      "row_number" | "rank" | "dense_rank" => {
        ignore(decoded(@decode.closed_object(s, ["fn"]), s))
        let fn_value = match fn_name {
          "row_number" => {
            needs_position = true
            AnalyticFunction::RowNumber
          }
          "rank" => AnalyticFunction::Rank
          _ => AnalyticFunction::DenseRank
        }
        (fn_value, @contract.primitive(NumberType, nullable=false))
      }
      "lag" | "lead" | "first_value" | "last_value" => {
        let navigation = fn_name == "lag" || fn_name == "lead"
        ignore(
          decoded(
            @decode.closed_object(
              s,
              if navigation {
                ["fn", "expr", "offset"]
              } else {
                ["fn", "expr"]
              },
            ),
            s,
          ),
        )
        let expr_source = decoded(@decode.required(call, "expr"), s)
        let binding = expression(b, expr_source, None, visible, parameters)
        let result = @contract.with_nullability(
          @typing.result_type(binding.expression),
          true,
        )
        let argument = bindings.length()
        bindings.push(binding)
        needs_position = true
        let fn_value = if navigation {
          let offset = match @decode.lookup(call, "offset") {
            Some(s) => row_count(b, s, 0L, parameter_types, pending)
            None => Literal(1L)
          }
          if fn_name == "lag" {
            AnalyticFunction::Lag(argument~, offset~)
          } else {
            AnalyticFunction::Lead(argument~, offset~)
          }
        } else {
          has_frame_call = true
          if fn_name == "first_value" {
            AnalyticFunction::FirstValue(argument~)
          } else {
            AnalyticFunction::LastValue(argument~)
          }
        }
        (fn_value, result)
      }
      _ => {
        let agg = check_aggregate(
          b,
          name,
          s,
          visible,
          parameters,
          parameter_types,
          bindings,
          pending,
          analytic=true,
        )
        has_frame_call = true
        needs_position = true
        (AnalyticFunction::Aggregate(agg), agg.result)
      }
    }
    fields.push((@schema.Unqualified(name), result))
    calls.push({ name, source: s, function, result, })
  }
  if has_frame_call != (frame is Some(_)) {
    fail(body, InvalidFrame)
  }
  pending.push({ kind: AnalyticPeerOrder, source: order_source, })
  if needs_position {
    pending.push({ kind: AnalyticPositionOrder, source: order_source, })
  }
  pending.push({ kind: AnalyticFrameDemand, source: body, })
  pending.push({ kind: AnalyticEnvelope, source: body, })
  ({ partition, order, frame, calls, }, fields)
}
