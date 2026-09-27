///|
pub(all) struct Input {
  relation : Array[@query.NamePart]
  name : String
  source : InputSource
  visible_fields : Array[String]
}

///|
pub(all) enum InputSource {
  Captured(@wire.Cursor)
  GeneratedValues(@wire.Cursor)
}

///|
pub(all) struct Context {
  program_id : String
  stage_id : String
  stage_result : String
  result_name : String
  captured_stage : String?
  inputs : Array[Input]
}

///|
pub(all) struct Limits {
  source : @builder.Limits
  program : @program.Limits
  max_expression_work : Int
}

///|
pub(all) enum Issue {
  InvalidContext
  UnknownRelation
  AmbiguousRelation
  UnknownColumn
  DuplicateOutput
  UnsupportedProjection
  UnsupportedGrouping
  UnsupportedAggregate
  UnsupportedHaving
  UnsupportedOrdering
  UnsupportedAnalytic
  Construction(@builder.Issue)
  Expression(@expression.Diagnostic)
  Admission(@program.SyntaxError)
}

///|
priv suberror Abort {
  Abort(Issue)
}

///|
priv struct Construction {
  builder : @builder.Builder
  generated : @origin.Origin
}

///|
fn Construction::add(
  self : Construction,
  value : @builder.Value,
) -> @builder.Node raise Abort {
  match @builder.add(self.builder, value, self.generated) {
    Ok(node) => node
    Err(error) => raise Abort(Construction(error))
  }
}

///|
fn Construction::text(
  self : Construction,
  value : String,
) -> @builder.Node raise Abort {
  self.add(String(value))
}

///|
fn Construction::object(
  self : Construction,
  fields : Array[(String, @builder.Node)],
) -> @builder.Node raise Abort {
  self.add(
    Object(
      fields.map(pair => { key: pair.0, origin: self.generated, value: pair.1, }),
    ),
  )
}

///|
fn Construction::array(
  self : Construction,
  elements : Array[@builder.Node],
) -> @builder.Node raise Abort {
  self.add(Array(elements))
}

///|
fn ascii_upper(value : String) -> String {
  let out = StringBuilder()
  for char in value {
    let code = char.to_int()
    out.write_char(
      (if code >= 97 && code <= 122 { code - 32 } else { code }).unsafe_to_char(),
    )
  }
  out.to_string()
}

///|
fn same_name(left : @query.NamePart, right : @query.NamePart) -> Bool {
  if left.quoted || right.quoted {
    left.value == right.value
  } else {
    ascii_upper(left.value) == ascii_upper(right.value)
  }
}

///|
fn same_path(
  left : Array[@query.NamePart],
  right : Array[@query.NamePart],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for i in 0..<left.length() {
    if !same_name(left[i], right[i]) {
      return false
    }
  }
  true
}

///|
// Compare semantic source trees, ignoring grouping parentheses and spans.
// Indices are local to each expression owner and cannot be compared directly.
fn same_expression(left : @query.Expression, right : @query.Expression) -> Bool {
  let pending = [(@query.expression_root(left), @query.expression_root(right))]
  while pending.pop() is Some((a_index, b_index)) {
    let a = @query.expression_node(left, a_index).unwrap().kind
    let b = @query.expression_node(right, b_index).unwrap().kind
    match (a, b) {
      (Parenthesized(child), _) => pending.push((child, b_index))
      (_, Parenthesized(child)) => pending.push((a_index, child))
      (Reference(x), Reference(y)) => if !same_path(x, y) { return false }
      (Call(x, ax), Call(y, ay)) => {
        if !same_path(x, y) || ax.length() != ay.length() {
          return false
        }
        for i in 0..<ax.length() {
          pending.push((ax[i], ay[i]))
        }
      }
      (Unary(x, child_a), Unary(y, child_b)) => {
        if x != y {
          return false
        }
        pending.push((child_a, child_b))
      }
      (Binary(x, left_a, right_a), Binary(y, left_b, right_b)) => {
        if x != y {
          return false
        }
        pending.push((left_a, left_b))
        pending.push((right_a, right_b))
      }
      (Predicate(x, ax), Predicate(y, ay)) => {
        if x != y || ax.length() != ay.length() {
          return false
        }
        for i in 0..<ax.length() {
          pending.push((ax[i], ay[i]))
        }
      }
      (SearchedCase(ax, a_else), SearchedCase(ay, b_else)) => {
        if ax.length() != ay.length() {
          return false
        }
        for i in 0..<ax.length() {
          pending.push((ax[i].0, ay[i].0))
          pending.push((ax[i].1, ay[i].1))
        }
        pending.push((a_else, b_else))
      }
      (Cast(a_child, a_type), Cast(b_child, b_type)) => {
        if a_type != b_type {
          return false
        }
        pending.push((a_child, b_child))
      }
      _ => if a != b { return false }
    }
  }
  true
}

///|
fn selected_input(query : @query.Query, context : Context) -> Input raise Abort {
  let relation = @query.relation(query)
  let mut found : Input? = None
  for input in context.inputs {
    if same_path(relation, input.relation) {
      if found is Some(_) {
        raise Abort(AmbiguousRelation)
      }
      found = Some(input)
    }
  }
  match found {
    Some(input) => input
    None => raise Abort(UnknownRelation)
  }
}

///|
fn columns(input : Input) -> Array[String] raise Abort {
  let source = match input.source {
    Captured(declaration) => declaration
    GeneratedValues(step) => {
      let step = match @wire.open_object(step) {
        Ok(object) => object
        Err(_) => raise Abort(InvalidContext)
      }
      let name = match @wire.lookup(step, "as") {
        Some(name) =>
          match @wire.text(name) {
            Ok(value) => value
            Err(_) => raise Abort(InvalidContext)
          }
        None => raise Abort(InvalidContext)
      }
      if name != input.name {
        raise Abort(InvalidContext)
      }
      match @wire.lookup(step, "values") {
        Some(values) => values
        None => raise Abort(InvalidContext)
      }
    }
  }
  let declaration = match @wire.open_object(source) {
    Ok(object) => object
    Err(_) => raise Abort(InvalidContext)
  }
  match @wire.lookup(declaration, "schema") {
    Some(schema) => {
      let actual = match @wire.object_field_names(schema) {
        Ok(fields) => fields
        Err(_) => raise Abort(InvalidContext)
      }
      if actual.length() != input.visible_fields.length() {
        raise Abort(InvalidContext)
      }
      for i in 0..<actual.length() {
        if actual[i] != input.visible_fields[i] {
          raise Abort(InvalidContext)
        }
      }
      actual
    }
    None => input.visible_fields.copy()
  }
}

///|
fn resolve_column(
  path : Array[@query.NamePart],
  query : @query.Query,
  input : Input,
  fields : Array[String],
) -> String? {
  if path.length() == 0 || path.length() > 2 {
    return None
  }
  if path.length() == 2 {
    let qualifier = match @query.relation_alias(query) {
      Some(name) => name
      None => @query.relation(query).last().unwrap()
    }
    if !same_name(path[0], qualifier) {
      return None
    }
  }
  let mut found : String? = None
  let name = path[path.length() - 1]
  for field in fields {
    if same_name(name, { value: field, quoted: false, }) {
      if found is Some(_) {
        return None
      }
      found = Some(field)
    }
  }
  ignore(input)
  found
}

///|
fn output_name(
  projection : @query.Projection,
  query : @query.Query,
  input : Input,
  fields : Array[String],
) -> String raise Abort {
  match projection.name {
    Some(name) => name.value
    None =>
      match projection.expression {
        Some(expression) =>
          match
            @query.expression_node(
              expression,
              @query.expression_root(expression),
            ).unwrap().kind {
            Reference(path) =>
              match resolve_column(path, query, input, fields) {
                Some(column) => column
                None => raise Abort(UnknownColumn)
              }
            _ => raise Abort(UnsupportedProjection)
          }
        None => raise Abort(UnsupportedProjection)
      }
  }
}

///|
fn append_expression(
  construction : Construction,
  expression : @query.Expression,
  query : @query.Query,
  input : Input,
  fields : Array[String],
  max_work : Int,
) -> @builder.Node raise Abort {
  match
    @expression.append(
      expression,
      path => resolve_column(path, query, input, fields),
      construction.builder,
      max_work,
    ) {
    Ok(node) => node
    Err(error) => raise Abort(Expression(error))
  }
}

///|
fn selected_projections(query : @query.Query) -> Array[@query.Projection] {
  for index in 0..<@query.operation_count(query) {
    match @query.operation_at(query, index) {
      Some(Select(projections, _)) => return projections
      _ => ()
    }
  }
  []
}

///|
fn group_key_expression(
  key : @query.Expression,
  projections : Array[@query.Projection],
) -> @query.Expression raise Abort {
  let mut root_index = @query.expression_root(key)
  while @query.expression_node(key, root_index).unwrap().kind
        is Parenthesized(child) {
    root_index = child
  }
  let root = @query.expression_node(key, root_index).unwrap()
  if root.kind is Number(_) {
    raise Abort(UnsupportedGrouping)
  }
  guard root.kind is Reference(path) && path.length() == 1 else { return key }
  let mut matched : @query.Expression? = None
  for projection in projections {
    match projection.name {
      Some(name) if same_name(name, path[0]) => {
        if matched is Some(_) || projection.aggregate is Some(_) {
          raise Abort(UnsupportedGrouping)
        }
        matched = projection.expression
      }
      _ => ()
    }
  }
  match matched {
    Some(expression) => expression
    None => key
  }
}

///|
fn lower_aggregate(
  construction : Construction,
  call : @query.AggregateCall,
  query : @query.Query,
  input : Input,
  fields : Array[String],
  max_work : Int,
) -> @builder.Node raise Abort {
  let name = match call.function_name {
    "COUNT" => "count"
    "COUNTIF" => "count_if"
    "SUM" => "sum"
    "AVG" => "avg"
    "MIN" => "min"
    "MAX" => "max"
    "ARRAY_AGG" => "array_agg"
    "STRING_AGG" => "string_agg"
    _ => raise Abort(UnsupportedAggregate)
  }
  let entries : Array[(String, @builder.Node)] = [
    ("fn", construction.text(name)),
  ]
  match call.argument {
    Some(argument) => {
      let root = @query.expression_node(
        argument,
        @query.expression_root(argument),
      ).unwrap()
      match root.kind {
        Reference(path) =>
          match resolve_column(path, query, input, fields) {
            Some(field) => entries.push(("field", construction.text(field)))
            None => raise Abort(UnknownColumn)
          }
        _ =>
          entries.push(
            (
              "expr",
              append_expression(
                construction, argument, query, input, fields, max_work,
              ),
            ),
          )
      }
    }
    None =>
      if name != "count" || call.distinct {
        raise Abort(UnsupportedAggregate)
      }
  }
  if call.distinct {
    entries.push(("distinct", construction.add(Bool(true))))
  }
  if name == "array_agg" || name == "string_agg" {
    let order : Array[@builder.Node] = []
    for term in call.order_by {
      let root = @query.expression_node(
        term.expression,
        @query.expression_root(term.expression),
      ).unwrap()
      guard root.kind is Reference(path) else {
        raise Abort(UnsupportedAggregate)
      }
      let field = match resolve_column(path, query, input, fields) {
        Some(field) => field
        None => raise Abort(UnknownColumn)
      }
      order.push(
        construction.object([
          ("field", construction.text(field)),
          ("dir", construction.text(term.direction)),
          ("nulls", construction.text(term.nulls)),
        ]),
      )
    }
    entries.push(("order_by", construction.array(order)))
  }
  match call.delimiter {
    Some(delimiter) => entries.push(("delimiter", construction.text(delimiter)))
    None => ()
  }
  construction.object(entries)
}

///|
fn analytic_boundary(
  construction : Construction,
  boundary : @query.FrameBoundary,
) -> @builder.Node raise Abort {
  match boundary {
    UnboundedPreceding => construction.text("unbounded_preceding")
    CurrentRow => construction.text("current_row")
    UnboundedFollowing => construction.text("unbounded_following")
    Preceding(distance) =>
      construction.object([
        ("preceding", construction.add(Number(distance.to_double()))),
      ])
    Following(distance) =>
      construction.object([
        ("following", construction.add(Number(distance.to_double()))),
      ])
  }
}

///|
fn lower_analytic_call(
  construction : Construction,
  call : @query.AnalyticCall,
  query : @query.Query,
  input : Input,
  fields : Array[String],
  max_work : Int,
) -> @builder.Node raise Abort {
  match call.aggregate {
    Some(aggregate) => {
      if call.window.frame is None {
        raise Abort(UnsupportedAnalytic)
      }
      if !["COUNT", "SUM", "AVG", "MIN", "MAX"].contains(
          aggregate.function_name,
        ) {
        raise Abort(UnsupportedAnalytic)
      }
      lower_aggregate(construction, aggregate, query, input, fields, max_work)
    }
    None => {
      let expression = call.expression.unwrap()
      let root = @query.expression_node(
        expression,
        @query.expression_root(expression),
      ).unwrap()
      guard root.kind is Call(path, arguments) && path.length() == 1 else {
        raise Abort(UnsupportedAnalytic)
      }
      let name = ascii_upper(path[0].value)
      let needs_frame = name == "FIRST_VALUE" || name == "LAST_VALUE"
      if needs_frame != (call.window.frame is Some(_)) {
        raise Abort(UnsupportedAnalytic)
      }
      let wire_name = match name {
        "ROW_NUMBER" => "row_number"
        "RANK" => "rank"
        "DENSE_RANK" => "dense_rank"
        "LAG" => "lag"
        "LEAD" => "lead"
        "FIRST_VALUE" => "first_value"
        "LAST_VALUE" => "last_value"
        _ => raise Abort(UnsupportedAnalytic)
      }
      let entries = [("fn", construction.text(wire_name))]
      if name == "ROW_NUMBER" || name == "RANK" || name == "DENSE_RANK" {
        if !arguments.is_empty() {
          raise Abort(UnsupportedAnalytic)
        }
      } else {
        if arguments.is_empty() ||
          arguments.length() >
          (if name == "LAG" || name == "LEAD" { 2 } else { 1 }) {
          raise Abort(UnsupportedAnalytic)
        }
        let argument = @query.expression_child(expression, arguments[0]).unwrap()
        entries.push(
          (
            "expr",
            append_expression(
              construction, argument, query, input, fields, max_work,
            ),
          ),
        )
        if arguments.length() == 2 {
          let offset = @query.expression_node(expression, arguments[1]).unwrap()
          match offset.kind {
            Number(text) => {
              let mut value = 0L
              for unit in text {
                let digit = unit.to_int() - 48
                if digit < 0 ||
                  digit > 9 ||
                  value > (9007199254740991L - digit.to_int64()) / 10L {
                  raise Abort(UnsupportedAnalytic)
                }
                value = value * 10L + digit.to_int64()
              }
              entries.push(
                ("offset", construction.add(Number(value.to_double()))),
              )
            }
            ParameterReference(parameter) =>
              entries.push(
                (
                  "offset",
                  construction.object([("$param", construction.text(parameter))]),
                ),
              )
            _ => raise Abort(UnsupportedAnalytic)
          }
        }
      }
      construction.object(entries)
    }
  }
}

///|
fn same_analytic_window(
  left : @query.AnalyticWindow,
  right : @query.AnalyticWindow,
) -> Bool {
  if left.partition_by.length() != right.partition_by.length() ||
    left.order_by.length() != right.order_by.length() ||
    left.frame != right.frame {
    return false
  }
  for index in 0..<left.partition_by.length() {
    if !same_path(left.partition_by[index], right.partition_by[index]) {
      return false
    }
  }
  for index in 0..<left.order_by.length() {
    let a = left.order_by[index]
    let b = right.order_by[index]
    if a.direction != b.direction ||
      a.nulls != b.nulls ||
      !same_expression(a.expression, b.expression) {
      return false
    }
  }
  true
}

///|
fn lower_analytic(
  construction : Construction,
  projections : Array[@query.Projection],
  query : @query.Query,
  input : Input,
  fields : Array[String],
  max_work : Int,
) -> @builder.Node raise Abort {
  let call = projections[0].analytic.unwrap()
  let partitions : Array[@builder.Node] = []
  for path in call.window.partition_by {
    let field = match resolve_column(path, query, input, fields) {
      Some(field) => field
      None => raise Abort(UnknownColumn)
    }
    partitions.push(construction.text(field))
  }
  let order : Array[@builder.Node] = []
  for term in call.window.order_by {
    let root = @query.expression_node(
      term.expression,
      @query.expression_root(term.expression),
    ).unwrap()
    guard root.kind is Reference(path) else { raise Abort(UnsupportedOrdering) }
    let field = match resolve_column(path, query, input, fields) {
      Some(field) => field
      None => raise Abort(UnknownColumn)
    }
    order.push(
      construction.object([
        ("field", construction.text(field)),
        ("dir", construction.text(term.direction)),
        ("nulls", construction.text(term.nulls)),
      ]),
    )
  }
  let functions : Array[(String, @builder.Node)] = []
  for projection in projections {
    functions.push(
      (
        projection.name.unwrap().value,
        lower_analytic_call(
          construction,
          projection.analytic.unwrap(),
          query,
          input,
          fields,
          max_work,
        ),
      ),
    )
  }
  let body = [
    ("partition_by", construction.array(partitions)),
    ("order_by", construction.array(order)),
    ("functions", construction.object(functions)),
  ]
  match call.window.frame {
    Some(frame) =>
      body.push(
        (
          "frame",
          construction.object([
            ("start", analytic_boundary(construction, frame.start)),
            ("end", analytic_boundary(construction, frame.end)),
          ]),
        ),
      )
    None => ()
  }
  construction.object(body)
}

///|
fn having_column(
  path : Array[@query.NamePart],
  query : @query.Query,
  input : Input,
  active_fields : Array[String],
  projections : Array[@query.Projection],
  group_keys : Array[(@query.Expression, String)],
) -> String? {
  if path.length() == 1 {
    let mut selected : String? = None
    let mut matched = false
    let mut ambiguous = false
    for projection in projections {
      match projection.name {
        Some(name) if same_name(name, path[0]) => {
          matched = true
          if selected is Some(_) {
            ambiguous = true
          }
          if projection.aggregate is Some(_) {
            selected = Some(name.value)
          } else {
            match projection.expression {
              Some(expression) => {
                let mut slot : String? = None
                for pair in group_keys {
                  if same_expression(pair.0, expression) {
                    slot = Some(pair.1)
                  }
                }
                selected = match slot {
                  Some(_) => slot
                  None =>
                    match
                      @query.expression_node(
                        expression,
                        @query.expression_root(expression),
                      ).unwrap().kind {
                      Reference(source) =>
                        resolve_column(source, query, input, active_fields)
                      _ => None
                    }
                }
              }
              None => selected = None
            }
          }
        }
        _ => ()
      }
    }
    if ambiguous {
      return None
    }
    if matched {
      return selected
    }
  }
  resolve_column(path, query, input, active_fields)
}

///|
fn compile_steps(
  construction : Construction,
  query : @query.Query,
  input : Input,
  fields : Array[String],
  max_work : Int,
  start_at : Int,
  preserve_identity_select : Bool,
) -> (Array[@builder.Node], Array[String]) raise Abort {
  let step_entries : Array[Array[(String, @builder.Node)]] = []
  let mut output = fields.copy()
  let mut active_fields = fields.copy()
  let mut grouped = false
  let grouped_keys : Array[(@query.Expression, String)] = []
  let mut first = true
  let mut pending_select : Array[(String, @builder.Node)]? = None
  let mut pending_bindings : Array[(String, String)] = []
  let mut selected_expressions : Array[(@query.Expression, String)] = []
  for i in start_at..<@query.operation_count(query) {
    let operation = @query.operation_at(query, i).unwrap()
    let entries : Array[(String, @builder.Node)] = []
    let mut deferred = false
    let mut add_distinct = false
    if first {
      entries.push(("from", construction.text(input.name)))
      first = false
    }
    match operation {
      Where(predicate) =>
        entries.push(
          (
            "filter",
            append_expression(
              construction, predicate, query, input, active_fields, max_work,
            ),
          ),
        )
      Extend(projections) => {
        let derived : Array[(String, @builder.Node)] = []
        let new_fields : Array[String] = []
        let snapshot = active_fields.copy()
        for projection in projections {
          let name = projection.name.unwrap().value
          if snapshot.any(field => ascii_upper(field) == ascii_upper(name)) ||
            new_fields.any(field => ascii_upper(field) == ascii_upper(name)) {
            raise Abort(DuplicateOutput)
          }
          derived.push(
            (
              name,
              append_expression(
                construction,
                projection.expression.unwrap(),
                query,
                input,
                snapshot,
                max_work,
              ),
            ),
          )
          new_fields.push(name)
        }
        entries.push(("derive", construction.object(derived)))
        for name in new_fields {
          active_fields.push(name)
          output.push(name)
        }
      }
      Set(_) | Drop(_) | Rename(_) | Alias(_) =>
        raise Abort(UnsupportedProjection)
      Group(keys, projections) => {
        let derives : Array[(String, @builder.Node)] = []
        let key_names : Array[String] = []
        let by : Array[@builder.Node] = []
        for index in 0..<keys.length() {
          let expression = group_key_expression(keys[index], projections)
          let mut root_index = @query.expression_root(expression)
          while @query.expression_node(expression, root_index).unwrap().kind
                is Parenthesized(child) {
            root_index = child
          }
          let root = @query.expression_node(expression, root_index).unwrap()
          let name = match root.kind {
            Reference(path) =>
              match resolve_column(path, query, input, active_fields) {
                Some(field) => field
                None => raise Abort(UnknownColumn)
              }
            _ => {
              let name = "aql_group_key_" + index.to_string()
              if active_fields.contains(name) || key_names.contains(name) {
                raise Abort(UnsupportedGrouping)
              }
              derives.push(
                (
                  name,
                  append_expression(
                    construction, expression, query, input, active_fields, max_work,
                  ),
                ),
              )
              name
            }
          }
          key_names.push(name)
          by.push(construction.text(name))
          grouped_keys.push((expression, name))
        }
        if !derives.is_empty() {
          let derive_step : Array[(String, @builder.Node)] = []
          if entries.length() == 1 {
            derive_step.push(entries[0])
            entries.clear()
          }
          derive_step.push(("derive", construction.object(derives)))
          step_entries.push(derive_step)
        }
        let aggregates : Array[(String, @builder.Node)] = []
        let result_fields : Array[String] = []
        for name in key_names {
          if !result_fields.contains(name) {
            result_fields.push(name)
          }
        }
        for projection in projections {
          match projection.aggregate {
            Some(call) => {
              let name = projection.name.unwrap().value
              if result_fields.contains(name) ||
                aggregates.any(entry => entry.0 == name) {
                raise Abort(DuplicateOutput)
              }
              aggregates.push(
                (
                  name,
                  lower_aggregate(
                    construction, call, query, input, active_fields, max_work,
                  ),
                ),
              )
              result_fields.push(name)
            }
            None => ()
          }
        }
        entries.push(
          (
            "group",
            construction.object([
              ("by", construction.array(by)),
              ("aggregates", construction.object(aggregates)),
            ]),
          ),
        )
        active_fields = result_fields.copy()
        output = result_fields
        grouped = true
      }
      Having(predicate) => {
        if !grouped {
          raise Abort(UnsupportedHaving)
        }
        let projections = selected_projections(query)
        let value = match
          @expression.append(
            predicate,
            path => {
              having_column(
                path, query, input, active_fields, projections, grouped_keys,
              )
            },
            construction.builder,
            max_work,
          ) {
          Ok(value) => value
          Err(error) => raise Abort(Expression(error))
        }
        entries.push(("filter", value))
      }
      Analytic(projections) => {
        if projections.is_empty() {
          raise Abort(UnsupportedAnalytic)
        }
        let snapshot = active_fields.copy()
        let groups : Array[Array[@query.Projection]] = []
        for projection in projections {
          if projection.analytic is None {
            continue
          }
          let name = projection.name.unwrap().value
          if active_fields.any(field => ascii_upper(field) == ascii_upper(name)) {
            raise Abort(DuplicateOutput)
          }
          let mut found = false
          for group in groups {
            if same_analytic_window(
                group[0].analytic.unwrap().window,
                projection.analytic.unwrap().window,
              ) {
              group.push(projection)
              found = true
              break
            }
          }
          if !found {
            groups.push([projection])
          }
          active_fields.push(name)
        }
        for group in groups {
          let operation = [
            (
              "analytic",
              lower_analytic(
                construction, group, query, input, snapshot, max_work,
              ),
            ),
          ]
          if !entries.is_empty() {
            operation.insert(0, entries[0])
            entries.clear()
          }
          step_entries.push(operation)
        }
        output = active_fields.copy()
        deferred = true
      }
      Select(projections, distinct) if !preserve_identity_select &&
        !distinct &&
        projections.length() == 1 &&
        projections[0].star == Some("*") => {
        if entries.length() == 1 && entries[0].0 == "from" {
          entries.clear()
          first = true
        }
        deferred = true
      }
      Select(projections, distinct) => {
        let names : Array[String] = []
        let derives : Array[(String, @builder.Node)] = []
        let temporary_names : Array[String] = []
        let selected : Array[@builder.Node] = []
        let bindings : Array[(String, String)] = []
        let expressions : Array[(@query.Expression, String)] = []
        for projection in projections {
          match projection.star {
            Some(_) =>
              for field in active_fields {
                names.push(field)
                selected.push(construction.text(field))
                bindings.push((field, field))
              }
            None => {
              let name = output_name(projection, query, input, active_fields)
              names.push(name)
              if projection.aggregate is Some(_) ||
                projection.analytic is Some(_) {
                if (projection.aggregate is Some(_) && !grouped) ||
                  !active_fields.contains(name) {
                  raise Abort(UnsupportedAggregate)
                }
                selected.push(construction.text(name))
                bindings.push((name, name))
                continue
              }
              let expression = projection.expression.unwrap()
              expressions.push((expression, name))
              let mut grouped_slot : String? = None
              for pair in grouped_keys {
                if same_expression(pair.0, expression) {
                  grouped_slot = Some(pair.1)
                }
              }
              let direct = match
                @query.expression_node(
                  expression,
                  @query.expression_root(expression),
                ).unwrap().kind {
                Reference(path) =>
                  match grouped_slot {
                    Some(_) => grouped_slot
                    None => resolve_column(path, query, input, active_fields)
                  }
                _ => None
              }
              let direct = match grouped_slot {
                Some(_) => grouped_slot
                None => direct
              }
              let source = if direct is Some(column) {
                column
              } else {
                let mut suffix = names.length() - 1
                let mut temporary = "aql_query_expr_" + suffix.to_string()
                while active_fields.contains(temporary) ||
                      names.contains(temporary) ||
                      temporary_names.contains(temporary) {
                  suffix += 1
                  temporary = "aql_query_expr_" + suffix.to_string()
                }
                temporary_names.push(temporary)
                derives.push(
                  (
                    temporary,
                    append_expression(
                      construction, expression, query, input, active_fields, max_work,
                    ),
                  ),
                )
                temporary
              }
              selected.push(
                if source == name {
                  construction.text(source)
                } else {
                  construction.object([(name, construction.text(source))])
                },
              )
              bindings.push((name, source))
            }
          }
        }
        for a in 0..<names.length() {
          for b in 0..<a {
            if ascii_upper(names[a]) == ascii_upper(names[b]) {
              raise Abort(DuplicateOutput)
            }
          }
        }
        if !derives.is_empty() {
          let derive_fields : Array[(String, @builder.Node)] = []
          if entries.length() == 1 {
            derive_fields.push(entries[0])
            entries.clear()
          }
          derive_fields.push(("derive", construction.object(derives)))
          step_entries.push(derive_fields)
        }
        entries.push(("select", construction.array(selected)))
        output = names
        selected_expressions = expressions
        add_distinct = distinct
        let needs_input_order = if distinct {
          false
        } else {
          match @query.operation_at(query, i + 1) {
            Some(Order(terms)) =>
              terms.any(term => {
                match
                  @query.expression_node(
                    term.expression,
                    @query.expression_root(term.expression),
                  ).unwrap().kind {
                  Reference(path) =>
                    path.length() != 1 ||
                    !output.any(name => {
                      same_name(path[0], { value: name, quoted: false, })
                    })
                  _ => false
                }
              })
            _ => false
          }
        }
        if needs_input_order {
          if entries.length() == 2 && entries[0].0 == "from" {
            ignore(entries.remove(0))
            first = true
          }
          pending_select = Some(entries)
          pending_bindings = bindings
          deferred = true
        } else {
          active_fields = names.copy()
        }
      }
      Order(terms) => {
        let sort : Array[@builder.Node] = []
        for term in terms {
          let kind = @query.expression_node(
              term.expression,
              @query.expression_root(term.expression),
            ).unwrap().kind
          let name = match kind {
            Reference(path) =>
              if path.length() == 1 {
                let mut selected : String? = None
                for field in output {
                  if same_name(path[0], { value: field, quoted: false, }) {
                    selected = Some(field)
                  }
                }
                match selected {
                  Some(field) =>
                    if pending_select is Some(_) {
                      let mut slot = field
                      for pair in pending_bindings {
                        if pair.0 == field {
                          slot = pair.1
                        }
                      }
                      slot
                    } else {
                      field
                    }
                  None =>
                    if pending_select is Some(_) {
                      match resolve_column(path, query, input, active_fields) {
                        Some(field) => field
                        None => raise Abort(UnsupportedOrdering)
                      }
                    } else {
                      raise Abort(UnsupportedOrdering)
                    }
                }
              } else if pending_select is Some(_) {
                match resolve_column(path, query, input, active_fields) {
                  Some(field) => field
                  None => raise Abort(UnsupportedOrdering)
                }
              } else {
                raise Abort(UnsupportedOrdering)
              }
            _ => {
              let mut matched : String? = None
              for pair in selected_expressions {
                if same_expression(term.expression, pair.0) {
                  if matched is Some(_) {
                    raise Abort(UnsupportedOrdering)
                  }
                  matched = Some(pair.1)
                }
              }
              match matched {
                Some(name) => {
                  let mut slot = name
                  if pending_select is Some(_) {
                    for pair in pending_bindings {
                      if pair.0 == name {
                        slot = pair.1
                      }
                    }
                  }
                  slot
                }
                None => raise Abort(UnsupportedOrdering)
              }
            }
          }
          sort.push(
            construction.object([
              ("field", construction.text(name)),
              ("dir", construction.text(term.direction)),
              ("nulls", construction.text(term.nulls)),
            ]),
          )
        }
        entries.push(("sort", construction.array(sort)))
      }
      Limit(count, offset) =>
        entries.push(
          (
            "take",
            construction.object([
              ("count", construction.add(Number(count.to_double()))),
              ("offset", construction.add(Number(offset.to_double()))),
            ]),
          ),
        )
    }
    if !deferred {
      step_entries.push(entries)
    }
    if add_distinct {
      step_entries.push([
        (
          "distinct",
          construction.array(output.map(name => construction.text(name))),
        ),
      ])
    }
    if operation is Order(_) {
      match pending_select {
        Some(selection) => {
          step_entries.push(selection)
          pending_select = None
          pending_bindings = []
          active_fields = output.copy()
        }
        None => ()
      }
    }
  }
  if step_entries.is_empty() {
    return ([], output)
  }
  // The last step supplies a stable named stage result for ordinary routing.
  // This is a structural step alias, not a SQL range alias.
  step_entries[step_entries.length() - 1].push(
    ("as", construction.text("aql_gen_0")),
  )
  (step_entries.map(entries => construction.object(entries)), output)
}

///|
// Supplied source fragments are admitted projections of a compile context.
// This frontend does not ask a provider for rows or infer schema during check.
pub fn compile(
  query : @query.Query,
  context : Context,
  limits : Limits,
) -> Result[@program.Program, Issue] {
  if limits.max_expression_work < 0 ||
    context.program_id == "" ||
    context.stage_id == "" ||
    context.stage_result == "" ||
    context.result_name == "" ||
    context.captured_stage == Some(context.stage_id) ||
    context.captured_stage == Some("") {
    return Err(InvalidContext)
  }
  let input = selected_input(query, context) catch {
    Abort(issue) => return Err(issue)
  }
  let fields = columns(input) catch { Abort(issue) => return Err(issue) }
  let document = @query.query_document(query)
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let builder = match @builder.create(document, limits.source) {
    Ok(builder) => builder
    Err(issue) => return Err(Construction(issue))
  }
  let construction : Construction = { builder, generated, }
  try {
    let fragment = match input.source {
      Captured(declaration) => declaration
      GeneratedValues(step) => step
    }
    let imported = match @builder.import_cursor(builder, fragment, generated) {
      Ok(node) => node
      Err(issue) => raise Abort(Construction(issue))
    }
    let mut start_at = 0
    let (input_entries, seed_steps, capture_stage) = match input.source {
      Captured(_) =>
        match context.captured_stage {
          Some(stage_id) => {
            let predicate = match @query.operation_at(query, 0) {
              Some(Where(expression)) => {
                start_at = 1
                append_expression(
                  construction,
                  expression,
                  query,
                  input,
                  fields,
                  limits.max_expression_work,
                )
              }
              _ =>
                construction.object([("literal", construction.add(Bool(true)))])
            }
            let capture_filter = construction.object([
              ("from", construction.text(input.name)),
              ("filter", predicate),
            ])
            let capture_step = construction.object([
              (
                "select",
                construction.array(
                  fields.map(field => construction.text(field)),
                ),
              ),
              ("as", construction.text("aql_capture_0")),
            ])
            let capture_result = construction.object([
              ("from", construction.text("aql_capture_0")),
              (
                "fields",
                construction.array(
                  fields.map(field => construction.text(field)),
                ),
              ),
            ])
            let capture = construction.object([
              ("id", construction.text(stage_id)),
              ("inputs", construction.object([(input.name, imported)])),
              ("steps", construction.array([capture_filter, capture_step])),
              ("results", construction.object([("source", capture_result)])),
            ])
            let source_ref = construction.object([
              (
                "result",
                construction.object([
                  ("stage", construction.text(stage_id)),
                  ("result", construction.text("source")),
                ]),
              ),
            ])
            ([(input.name, source_ref)], [], Some(capture))
          }
          None => ([(input.name, imported)], [], None)
        }
      GeneratedValues(_) => {
        if context.captured_stage is Some(_) {
          raise Abort(InvalidContext)
        }
        ([], [imported], None)
      }
    }
    let (steps, output) = compile_steps(
      construction,
      query,
      input,
      fields,
      limits.max_expression_work,
      start_at,
      context.captured_stage is Some(_),
    )
    let all_steps = seed_steps + steps
    let result_source = if steps.is_empty() { input.name } else { "aql_gen_0" }
    let result = construction.object([
      ("from", construction.text(result_source)),
      (
        "fields",
        construction.array(output.map(name => construction.text(name))),
      ),
    ])
    let stage = construction.object([
      ("id", construction.text(context.stage_id)),
      ("inputs", construction.object(input_entries)),
      ("steps", construction.array(all_steps)),
      ("results", construction.object([(context.stage_result, result)])),
    ])
    let stages = match capture_stage {
      Some(capture) => [capture, stage]
      None => [stage]
    }
    let root = construction.object([
      ("version", construction.text("actql/0.1")),
      ("id", construction.text(context.program_id)),
      ("stages", construction.array(stages)),
      (
        "results",
        construction.object([
          (
            context.result_name,
            construction.object([
              (
                "from",
                construction.object([
                  ("stage", construction.text(context.stage_id)),
                  ("result", construction.text(context.stage_result)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    ])
    let source = match @builder.finish(builder, root) {
      Ok(source) => source
      Err(issue) => raise Abort(Construction(issue))
    }
    match @program.admit_generated_source(source, limits.program) {
      Ok(program) => Ok(program)
      Err(issue) => Err(Admission(issue))
    }
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      Err(issue)
    }
  }
}
