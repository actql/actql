///|
pub(all) enum ClientExplanationProjectionIssue {
  Original(ClientInteractivePlanIssue)
  InvalidReadLimits
  MalformedCheckedExpression
  Encoding(@encode.EncodeFailure)
} derive(Eq, Debug)

///|
fn explanation_text(
  w : @encode.Writer,
  key : String,
  value : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(w, key)
  @encode.string_value(w, value)
}

///|
fn explanation_type(
  w : @encode.Writer,
  value : @contract.Contract,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(w)
  explanation_text(w, "kind", @contract.contract_type_name(value))
  @encode.key(w, "nullable")
  @encode.bool_value(w, value.nullable)
  explanation_text(w, "projection", "shape_and_nullability")
  @encode.end_object(w)
}

///|
fn explanation_schema(
  w : @encode.Writer,
  schema : @schema.Schema,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(w)
  @encode.key(w, "fields")
  @encode.begin_array(w)
  for i in 0..<@schema.field_count(schema) {
    let field = @schema.field_at(schema, i).unwrap()
    @encode.begin_object(w)
    explanation_text(
      w,
      "name",
      @schema.field_reference_name_at(schema, i).unwrap(),
    )
    explanation_text(
      w,
      "presence",
      match @schema.field_presence(field) {
        Required => "required"
        Conditional => "conditional"
      },
    )
    @encode.key(w, "type")
    explanation_type(w, @schema.field_contract(field))
    @encode.end_object(w)
  }
  @encode.end_array(w)
  @encode.end_object(w)
}

///|
// A first structural projection profile, not the expression language checker.
// No operator rules, evaluation, literal parsing or parameter binding happen here.
fn explanation_predicate_operator(tag : String) -> Bool {
  match tag {
    "and"
    | "or"
    | "not"
    | "eq"
    | "neq"
    | "lt"
    | "lte"
    | "gt"
    | "gte"
    | "is_null"
    | "not_null"
    | "is_distinct_from" => true
    _ => false
  }
}

///|
fn explanation_predicate_supported(
  expression : @expression.TypedExpression,
  max_nodes : Int,
) -> Result[Bool, ClientExplanationProjectionIssue] {
  let count = @expression.node_count(expression)
  if count < 1 {
    return Err(MalformedCheckedExpression)
  }
  if count > max_nodes {
    return Err(InvalidReadLimits)
  }
  for index in 0..<count {
    guard @expression.node_form(expression, index) is Some(form) &&
      @expression.node_at(expression, index) is Some(_) &&
      @expression.child_count(expression, index) is Some(children) else {
      return Err(MalformedCheckedExpression)
    }
    match form {
      Expression(tag, _) =>
        if tag == "literal" ||
          tag == "field" ||
          tag == "$param" ||
          tag == "join_field" {
          if children != 0 {
            return Err(MalformedCheckedExpression)
          }
        } else if !explanation_predicate_operator(tag) {
          return Ok(false)
        }
      // Membership collections and unimplemented forms are not traversed to
      // manufacture a partial expression or disclose a redacted collection size.
      _ => return Ok(false)
    }
    for child in 0..<children {
      guard @expression.child_at(expression, index, child) is Some(target) &&
        target >= 0 &&
        target < count &&
        target != index else {
        return Err(MalformedCheckedExpression)
      }
    }
  }
  Ok(true)
}

///|
fn explanation_join_field(
  w : @encode.Writer,
  body : @decode.Cursor,
) -> Unit raise @encode.EncodeFailure {
  guard @decode.view(body) is ObjectValue(object) &&
    @decode.lookup(object, "side") is Some(side) &&
    @decode.lookup(object, "name") is Some(name) &&
    @decode.text(side) is Ok(side) &&
    @decode.text(name) is Ok(name) &&
    (side == "left" || side == "right") else {
    raise @encode.InvalidStructure
  }
  explanation_text(w, "name", name)
  explanation_text(w, "scope", side)
}

///|
fn explanation_predicate(
  w : @encode.Writer,
  expression : @expression.TypedExpression,
  projected : Bool,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(w)
  if !projected {
    explanation_text(w, "reason", "expression_form_not_projected")
    explanation_text(w, "state", "not_projected")
    @encode.end_object(w)
    return
  }
  @encode.key(w, "nodes")
  @encode.begin_array(w)
  for index in 0..<@expression.node_count(expression) {
    let node = @expression.node_at(expression, index).unwrap()
    guard @expression.node_form(expression, index)
      is Some(Expression(tag, body)) else {
      raise @encode.InvalidStructure
    }
    @encode.begin_object(w)
    if tag == "literal" {
      // Never read this body, serialize its inferred bounds, hash its value or
      // recurse into a JSON literal's object/array members.
      explanation_text(w, "form", "literal_redacted")
    } else if tag == "field" || tag == "$param" {
      explanation_text(
        w,
        "form",
        if tag == "field" {
          "field"
        } else {
          "parameter"
        },
      )
      guard @decode.text(body) is Ok(name) else {
        raise @encode.InvalidStructure
      }
      explanation_text(w, "name", name)
      if tag == "field" {
        explanation_text(w, "scope", "fields")
      }
    } else if tag == "join_field" {
      explanation_text(w, "form", "field")
      explanation_join_field(w, body)
    } else {
      @encode.key(w, "children")
      @encode.begin_array(w)
      for child in 0..<@expression.child_count(expression, index).unwrap() {
        @encode.number_value(
          w,
          @expression.child_at(expression, index, child).unwrap().to_double(),
        )
      }
      @encode.end_array(w)
      explanation_text(w, "form", "operation")
      explanation_text(w, "operator", tag)
    }
    @encode.key(w, "type")
    explanation_type(w, node.contract)
    @encode.end_object(w)
  }
  @encode.end_array(w)
  @encode.key(w, "root")
  @encode.number_value(w, 0)
  explanation_text(w, "state", "projected")
  @encode.end_object(w)
}

///|
fn write_client_explanation_meaning(
  w : @encode.Writer,
  meaning : ClientExplanationMeaning,
  predicate_projected : Bool,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(w)
  match meaning {
    InputOutput => explanation_text(w, "kind", "input_output")
    Values(schema~, ..) => {
      explanation_text(w, "kind", "values")
      @encode.key(w, "schema")
      explanation_schema(w, schema)
    }
    Filter(predicate) => {
      explanation_text(w, "kind", "filter")
      @encode.key(w, "predicate")
      explanation_predicate(w, predicate, predicate_projected)
    }
    Projection(operation) => {
      @encode.key(w, "fields")
      @encode.begin_array(w)
      for index in 0..<@relation.projection_field_count(operation) {
        let field = @relation.projection_field_at(operation, index).unwrap()
        @encode.begin_object(w)
        explanation_text(w, "input", @schema.reference_name(field.input))
        explanation_text(w, "output", @schema.reference_name(field.output))
        @encode.end_object(w)
      }
      @encode.end_array(w)
      explanation_text(w, "kind", "projection")
      explanation_text(
        w,
        "operation",
        match @relation.operation(operation) {
          Select => "select"
          Rename => "rename"
          Drop => "drop"
          _ => raise @encode.InvalidStructure
        },
      )
    }
    Join(join) => {
      explanation_text(
        w,
        "join_kind",
        match @join.kind(join) {
          Inner => "inner"
          Left => "left"
          Right => "right"
          Full => "full"
          Semi => "semi"
          Anti => "anti"
        },
      )
      @encode.key(w, "keys")
      @encode.begin_array(w)
      for index in 0..<@join.key_count(join) {
        let key = @join.key_at(join, index).unwrap()
        @encode.begin_object(w)
        explanation_text(w, "left", @schema.reference_name(key.left))
        explanation_text(w, "right", @schema.reference_name(key.right))
        @encode.end_object(w)
      }
      @encode.end_array(w)
      explanation_text(w, "kind", "join")
      explanation_text(
        w,
        "null_key",
        match @join.null_key(join) {
          NoMatch => "no_match"
          Fail => "fail"
        },
      )
    }
    NotProjected => {
      explanation_text(w, "kind", "not_projected")
      explanation_text(w, "reason", "operation_facts_not_projected")
    }
  }
  @encode.end_object(w)
}

///|
fn client_explanation_meaning_writer(
  value : ClientOperationExplanation,
  prepared : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  measure : Bool,
) -> Result[@encode.Writer, ClientExplanationProjectionIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidReadLimits)
  }
  let meaning = match client_operation_explanation_meaning(value, prepared) {
    Ok(meaning) => meaning
    Err(issue) => return Err(Original(issue))
  }
  let predicate_projected = match meaning {
    Filter(predicate) =>
      match explanation_predicate_supported(predicate, max_nodes) {
        Ok(projected) => projected
        Err(issue) => return Err(issue)
      }
    _ => false
  }
  try {
    let writer = if measure {
      @encode.measuring_writer(max_bytes, max_nodes, max_depth)
    } else {
      @encode.writer(max_bytes, max_nodes, max_depth)
    }
    write_client_explanation_meaning(writer, meaning, predicate_projected)
    Ok(writer)
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
/// Bounded structural DATA only. The caller must fund its read/emit and
/// overlapping original retention; these facts grant no disclosure authority.
pub fn client_operation_explanation_structural_json(
  value : ClientOperationExplanation,
  prepared : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientExplanationProjectionIssue] {
  let writer = match
    client_explanation_meaning_writer(
      value, prepared, max_bytes, max_nodes, max_depth, false,
    ) {
    Ok(writer) => writer
    Err(issue) => return Err(issue)
  }
  Ok(@encode.finish(writer)) catch {
    issue => Err(Encoding(issue))
  }
}

///|
/// Same writer path and exact output geometry, not a reservation/funding ACK.
/// Measuring/control helpers themselves still need the existing caller scope.
pub fn measure_client_operation_explanation_structural(
  value : ClientOperationExplanation,
  prepared : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(Int, Int, Int), ClientExplanationProjectionIssue] {
  let writer = match
    client_explanation_meaning_writer(
      value, prepared, max_bytes, max_nodes, max_depth, true,
    ) {
    Ok(writer) => writer
    Err(issue) => return Err(issue)
  }
  Ok(@encode.finish_measurement_usage(writer)) catch {
    issue => Err(Encoding(issue))
  }
}
