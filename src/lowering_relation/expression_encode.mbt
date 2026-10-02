///|
priv enum ExpressionFrame {
  Expr(Expression)
  Value(@value.Value)
  Expressions(Array[Expression], Int)
  Values(@value.FrozenArray[@value.Value], Int)
  Fields(@value.FrozenArray[(String, @value.Value)], Int)
  Vectors(@value.FrozenArray[Double], Int)
  EndObject
  Op(String)
  CaseWhen(Array[(Expression, Expression)])
  Clauses(Array[(Expression, Expression)], Int)
  ClauseWhen(Expression)
  VectorScoreRest(VectorMetric, Expression)
  ObjectExpressions(Array[(String, Expression)], Int)
  PropertyValue(Expression)
}

///|
fn binary_name(op : BinaryOperator) -> String {
  match op {
    Add => "add"
    Subtract => "subtract"
    Multiply => "multiply"
    Divide => "divide"
    Modulo => "modulo"
    Equal => "eq"
    NotEqual => "neq"
    IsDistinctFrom => "is_distinct_from"
    Less => "lt"
    LessEqual => "lte"
    Greater => "gt"
    GreaterEqual => "gte"
    NullIf => "nullif"
  }
}

///|
fn decimal_wire(d : @value.DecimalValue) -> String {
  if d.scale == 0 {
    return d.coefficient
  }
  let negative = d.coefficient.has_prefix("-")
  let chars = d.coefficient.to_array()
  let digits = if negative {
    String::from_array(chars[1:])
  } else {
    d.coefficient
  }
  let padded = String::make((d.scale + 1 - digits.length()).max(0), '0') +
    digits
  let chars = padded.to_array()
  let split = chars.length() - d.scale
  (if negative { "-" } else { "" }) +
  String::from_array(chars[:split]) +
  "." +
  String::from_array(chars[split:])
}

///|
/// Emits only the normative expression node, never a Plan or execution permit.
/// The writer owns byte/value-node/depth limits and publishes only on finish.
pub fn emit_expression(
  root : Expression,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_frames([Expr(root)], output)
}

///|
/// Typed wire projection shared by values lowering and runtime measurement.
/// Does not create a canonical identity or re-admit caller-provided values.
pub fn emit_wire_value(
  value : @value.Value,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_frames([Value(value)], output)
}

///|
fn emit_frames(
  pending : Array[ExpressionFrame],
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  while pending.pop() is Some(frame) {
    match frame {
      EndObject => @encode.end_object(output)
      Op(name) => {
        @encode.key(output, "op")
        @encode.string_value(output, name)
      }
      Expr(expr) => {
        @encode.begin_object(output)
        @encode.key(output, "body")
        pending.push(EndObject)
        match expr.body {
          Field(name, _) => {
            pending.push(Op("field"))
            @encode.string_value(output, name)
          }
          Literal(value) => {
            pending.push(Op("literal"))
            pending.push(Value(value.value))
          }
          TypedNull => {
            pending.push(Op("typed_null"))
            @encode.begin_object(output)
            @encode.key(output, "contract")
            @contract.emit_checked(expr.contract, output)
            @encode.end_object(output)
          }
          Object(fields) => {
            pending.push(Op("object"))
            @encode.begin_object(output)
            pending.push(ObjectExpressions(fields, 0))
          }
          Property(value, name, _) => {
            pending.push(Op("property"))
            @encode.begin_object(output)
            @encode.key(output, "name")
            @encode.string_value(output, name)
            pending.push(EndObject)
            pending.push(PropertyValue(value))
          }
          Cast(child) => {
            pending.push(Op("cast"))
            @encode.begin_object(output)
            @encode.key(output, "target")
            emit_cast_target(expr.contract, output)
            @encode.key(output, "value")
            pending.push(EndObject)
            pending.push(Expr(child))
          }
          Unary(op, arg) => {
            pending.push(
              Op(
                match op {
                  Negate => "negate"
                  Not => "not"
                  IsNull => "is_null"
                  NotNull => "not_null"
                  IsTrue => "is_true"
                  IsFalse => "is_false"
                  IsUnknown => "is_unknown"
                },
              ),
            )
            pending.push(Expr(arg))
          }
          Binary(op, left, right) => {
            pending.push(Op(binary_name(op)))
            @encode.begin_array(output)
            pending.push(Expressions([left, right], 0))
          }
          VectorScore(metric, left, right) => {
            pending.push(Op("vector_score"))
            @encode.begin_object(output)
            @encode.key(output, "left")
            pending.push(EndObject)
            pending.push(VectorScoreRest(metric, right))
            pending.push(Expr(left))
          }
          VectorConcat(children) => {
            pending.push(Op("vector_concat"))
            @encode.begin_array(output)
            pending.push(Expressions(children, 0))
          }
          Many(op, args) => {
            pending.push(
              Op(
                match op {
                  And => "and"
                  Or => "or"
                  Coalesce => "coalesce"
                  Concat => "concat"
                  ConcatStrict => "concat_strict"
                },
              ),
            )
            @encode.begin_array(output)
            pending.push(Expressions(args, 0))
          }
          Conditional(condition, yes, no) => {
            pending.push(Op("if"))
            @encode.begin_array(output)
            pending.push(Expressions([condition, yes, no], 0))
          }
          Case(clauses, otherwise) => {
            pending.push(Op("case"))
            @encode.begin_object(output)
            @encode.key(output, "else")
            pending.push(EndObject)
            pending.push(CaseWhen(clauses))
            pending.push(Expr(otherwise))
          }
        }
      }
      Expressions(items, index) =>
        if items.get(index) is Some(value) {
          pending.push(Expressions(items, index + 1))
          pending.push(Expr(value))
        } else {
          @encode.end_array(output)
        }
      PropertyValue(value) => {
        @encode.key(output, "value")
        pending.push(Expr(value))
      }
      ObjectExpressions(fields, index) =>
        if fields.get(index) is Some((name, value)) {
          @encode.key(output, name)
          pending.push(ObjectExpressions(fields, index + 1))
          pending.push(Expr(value))
        } else {
          @encode.end_object(output)
        }
      CaseWhen(clauses) => {
        @encode.key(output, "when")
        @encode.begin_array(output)
        pending.push(Clauses(clauses, 0))
      }
      Clauses(clauses, index) =>
        if clauses.get(index) is Some((condition, then_)) {
          pending.push(Clauses(clauses, index + 1))
          @encode.begin_object(output)
          @encode.key(output, "then")
          pending.push(EndObject)
          pending.push(ClauseWhen(condition))
          pending.push(Expr(then_))
        } else {
          @encode.end_array(output)
        }
      ClauseWhen(condition) => {
        @encode.key(output, "when")
        pending.push(Expr(condition))
      }
      VectorScoreRest(metric, right) => {
        @encode.key(output, "metric")
        @encode.string_value(
          output,
          match metric {
            Cosine => "cosine"
            Dot => "dot"
            L2 => "l2"
          },
        )
        @encode.key(output, "right")
        pending.push(Expr(right))
      }
      Value(value) =>
        match value {
          @value.Null => @encode.null_value(output)
          @value.Number(n) => @encode.number_value(output, n)
          @value.Boolean(b) => @encode.bool_value(output, b)
          @value.Text(s) | @value.Date(s) | @value.Timestamp(s) =>
            @encode.string_value(output, s)
          @value.Decimal(d) => @encode.string_value(output, decimal_wire(d))
          @value.Array(items) => {
            @encode.begin_array(output)
            pending.push(Values(items, 0))
          }
          @value.Object(fields) => {
            @encode.begin_object(output)
            pending.push(Fields(fields, 0))
          }
          @value.Vector(items) => {
            @encode.begin_array(output)
            pending.push(Vectors(items, 0))
          }
          @value.Reference(_) => abort("opaque reference literal")
        }
      Values(items, index) =>
        if @value.element_at(items, index) is Some(value) {
          pending.push(Values(items, index + 1))
          pending.push(Value(value))
        } else {
          @encode.end_array(output)
        }
      Fields(fields, index) =>
        if @value.element_at(fields, index) is Some((name, value)) {
          @encode.key(output, name)
          pending.push(Fields(fields, index + 1))
          pending.push(Value(value))
        } else {
          @encode.end_object(output)
        }
      Vectors(items, index) =>
        if @value.element_at(items, index) is Some(value) {
          @encode.number_value(output, value)
          pending.push(Vectors(items, index + 1))
        } else {
          @encode.end_array(output)
        }
    }
  }
}
