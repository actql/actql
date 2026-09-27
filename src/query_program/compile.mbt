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
  StageResult(String, String)
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
  max_join_output_rows : Int64
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
  UnsupportedSet
  UnsupportedJoin
  UnsupportedCte
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
  selected_relation(@query.relation(query), context)
}

///|
fn selected_relation(
  relation : Array[@query.NamePart],
  context : Context,
) -> Input raise Abort {
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
  if input.source is StageResult(_, _) {
    return input.visible_fields.copy()
  }
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
    StageResult(_, _) => raise Abort(InvalidContext)
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
// Pipe's visible names and range aliases refer to immutable physical slots.
// SET and DROP may change visibility without changing an older alias snapshot.
fn pipe_slot(
  path : Array[@query.NamePart],
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
) -> String? {
  if path.length() == 0 || path.length() > 2 {
    return None
  }
  let mut scope = visible
  if path.length() == 2 {
    let mut found = false
    for range in ranges {
      if same_name(path[0], range.0) {
        if found {
          return None
        }
        scope = range.1
        found = true
      }
    }
    if !found {
      return None
    }
  }
  let mut selected : String? = None
  for entry in scope {
    if same_name(path[path.length() - 1], { value: entry.0, quoted: false, }) {
      if selected is Some(_) {
        return None
      }
      selected = Some(entry.1)
    }
  }
  selected
}

///|
fn append_pipe_expression(
  construction : Construction,
  expression : @query.Expression,
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  max_work : Int,
) -> @builder.Node raise Abort {
  match
    @expression.append(
      expression,
      path => pipe_slot(path, visible, ranges),
      construction.builder,
      max_work,
    ) {
    Ok(node) => node
    Err(error) => raise Abort(Expression(error))
  }
}

///|
fn pipe_name_exists(
  entries : Array[(String, String)],
  name : @query.NamePart,
) -> Bool {
  entries.any(entry => same_name(name, { value: entry.0, quoted: false, }))
}

///|
fn pipe_physical_name(physical : Array[String], prefix : String) -> String {
  let mut index = physical.length()
  let mut name = prefix + index.to_string()
  while physical.any(field => ascii_upper(field) == ascii_upper(name)) {
    index += 1
    name = prefix + index.to_string()
  }
  name
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
fn lower_aggregate_resolved(
  construction : Construction,
  call : @query.AggregateCall,
  resolve : (Array[@query.NamePart]) -> String?,
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
          match resolve(path) {
            Some(field) => entries.push(("field", construction.text(field)))
            None => raise Abort(UnknownColumn)
          }
        _ =>
          entries.push(
            (
              "expr",
              match
                @expression.append(
                  argument,
                  resolve,
                  construction.builder,
                  max_work,
                ) {
                Ok(value) => value
                Err(error) => raise Abort(Expression(error))
              },
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
      let field = match resolve(path) {
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
fn lower_aggregate(
  construction : Construction,
  call : @query.AggregateCall,
  query : @query.Query,
  input : Input,
  fields : Array[String],
  max_work : Int,
) -> @builder.Node raise Abort {
  lower_aggregate_resolved(
    construction,
    call,
    path => resolve_column(path, query, input, fields),
    max_work,
  )
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
  final_alias : String,
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
  let mut pipe_visible = fields.map(field => (field, field))
  let initial_range = match @query.relation_alias(query) {
    Some(name) => name
    None => @query.relation(query).last().unwrap()
  }
  let mut pipe_ranges = [(initial_range, pipe_visible.copy())]
  let mut pipe_changed = false
  let mut pipe_selected = false
  for i in start_at..<@query.operation_count(query) {
    let operation = @query.operation_at(query, i).unwrap()
    if pipe_selected && !(operation is Order(_) || operation is Limit(_, _)) {
      raise Abort(UnsupportedProjection)
    }
    let entries : Array[(String, @builder.Node)] = []
    let mut deferred = false
    let mut add_distinct = false
    if first {
      entries.push(("from", construction.text(input.name)))
      first = false
    }
    match operation {
      Where(predicate) if pipe_changed =>
        entries.push(
          (
            "filter",
            append_pipe_expression(
              construction, predicate, pipe_visible, pipe_ranges, max_work,
            ),
          ),
        )
      Where(predicate) =>
        entries.push(
          (
            "filter",
            append_expression(
              construction, predicate, query, input, active_fields, max_work,
            ),
          ),
        )
      Extend(projections) if pipe_changed => {
        let snapshot = pipe_visible.copy()
        let derived : Array[(String, @builder.Node)] = []
        let next = snapshot.copy()
        for projection in projections {
          let name = projection.name.unwrap()
          if pipe_name_exists(next, name) {
            raise Abort(DuplicateOutput)
          }
          let physical = pipe_physical_name(active_fields, "aql_pipe_extend_")
          active_fields.push(physical)
          derived.push(
            (
              physical,
              append_pipe_expression(
                construction,
                projection.expression.unwrap(),
                snapshot,
                pipe_ranges,
                max_work,
              ),
            ),
          )
          next.push((name.value, physical))
        }
        entries.push(("derive", construction.object(derived)))
        pipe_visible = next
        output = next.map(entry => entry.0)
      }
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
          pipe_visible.push((name, name))
        }
      }
      Set(assignments) => {
        let snapshot = pipe_visible.copy()
        let derived : Array[(String, @builder.Node)] = []
        let targets : Array[String] = []
        let replacements : Array[(String, String)] = []
        for assignment in assignments {
          if !pipe_name_exists(snapshot, assignment.0) ||
            targets.any(name => {
              same_name(assignment.0, { value: name, quoted: false, })
            }) {
            raise Abort(UnsupportedProjection)
          }
          let physical = pipe_physical_name(active_fields, "aql_pipe_set_")
          active_fields.push(physical)
          derived.push(
            (
              physical,
              append_pipe_expression(
                construction,
                assignment.1,
                snapshot,
                pipe_ranges,
                max_work,
              ),
            ),
          )
          targets.push(assignment.0.value)
          replacements.push((assignment.0.value, physical))
        }
        let next : Array[(String, String)] = []
        for current in snapshot {
          let mut slot = current.1
          for replacement in replacements {
            if same_name({ value: current.0, quoted: false, }, {
                value: replacement.0,
                quoted: false,
              }) {
              slot = replacement.1
            }
          }
          next.push((current.0, slot))
        }
        entries.push(("derive", construction.object(derived)))
        pipe_visible = next
        output = pipe_visible.map(entry => entry.0)
        pipe_changed = true
      }
      Drop(names) => {
        let next : Array[(String, String)] = []
        for name in names {
          if !pipe_name_exists(pipe_visible, name) ||
            names.filter(other => same_name(name, other)).length() != 1 {
            raise Abort(UnsupportedProjection)
          }
        }
        for current in pipe_visible {
          if !names.any(name => {
              same_name(name, { value: current.0, quoted: false, })
            }) {
            next.push(current)
          }
        }
        pipe_visible = next
        output = next.map(entry => entry.0)
        if next.is_empty() {
          raise Abort(UnsupportedProjection)
        }
        pipe_changed = true
        deferred = true
      }
      Rename(names) => {
        let next : Array[(String, String)] = []
        for current in pipe_visible {
          let mut name = current.0
          for replacement in names {
            if same_name(replacement.0, { value: current.0, quoted: false, }) {
              name = replacement.1.value
            }
          }
          if pipe_name_exists(next, { value: name, quoted: false, }) {
            raise Abort(DuplicateOutput)
          }
          next.push((name, current.1))
        }
        for replacement in names {
          if !pipe_name_exists(pipe_visible, replacement.0) ||
            names.filter(other => same_name(other.0, replacement.0)).length() !=
            1 {
            raise Abort(UnsupportedProjection)
          }
        }
        pipe_visible = next
        output = next.map(entry => entry.0)
        pipe_changed = true
        deferred = true
      }
      Alias(name) => {
        if pipe_ranges.any(range => same_name(range.0, name)) {
          raise Abort(AmbiguousRelation)
        }
        pipe_ranges.push((name, pipe_visible.copy()))
        pipe_changed = true
        deferred = true
      }
      Group(keys, projections) => {
        let scoped = pipe_changed
        if scoped {
          let materialize : Array[(String, @builder.Node)] = []
          if entries.length() == 1 && entries[0].0 == "from" {
            materialize.push(entries[0])
            entries.clear()
          }
          let visible : Array[@builder.Node] = []
          for entry in pipe_visible {
            visible.push(
              if entry.0 == entry.1 {
                construction.text(entry.1)
              } else {
                construction.object([(entry.0, construction.text(entry.1))])
              },
            )
          }
          materialize.push(("select", construction.array(visible)))
          step_entries.push(materialize)
          active_fields = pipe_visible.map(entry => entry.0)
          pipe_visible = active_fields.map(name => (name, name))
          pipe_ranges = []
        }
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
              match
                (if scoped {
                  pipe_slot(path, pipe_visible, pipe_ranges)
                } else {
                  resolve_column(path, query, input, active_fields)
                }) {
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
                  if scoped {
                    append_pipe_expression(
                      construction, expression, pipe_visible, pipe_ranges, max_work,
                    )
                  } else {
                    append_expression(
                      construction, expression, query, input, active_fields, max_work,
                    )
                  },
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
                  if scoped {
                    lower_aggregate_resolved(
                      construction,
                      call,
                      path => pipe_slot(path, pipe_visible, pipe_ranges),
                      max_work,
                    )
                  } else {
                    lower_aggregate(
                      construction, call, query, input, active_fields, max_work,
                    )
                  },
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
        pipe_visible = result_fields.map(name => (name, name))
        if scoped {
          pipe_ranges = []
          pipe_changed = true
        }
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
      Analytic(_) if pipe_changed => raise Abort(UnsupportedAnalytic)
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
      Select(projections, distinct) if pipe_changed => {
        let names : Array[String] = []
        let selected : Array[@builder.Node] = []
        let derives : Array[(String, @builder.Node)] = []
        let bindings : Array[(String, String)] = []
        let expressions : Array[(@query.Expression, String)] = []
        let physical = active_fields.copy()
        for projection in projections {
          match projection.star {
            Some("*") =>
              for visible in pipe_visible {
                names.push(visible.0)
                selected.push(
                  if visible.0 == visible.1 {
                    construction.text(visible.1)
                  } else {
                    construction.object([
                      (visible.0, construction.text(visible.1)),
                    ])
                  },
                )
                bindings.push(visible)
              }
            Some(_) => raise Abort(UnsupportedProjection)
            None => {
              if projection.aggregate is Some(_) ||
                projection.analytic is Some(_) {
                raise Abort(UnsupportedProjection)
              }
              let expression = projection.expression.unwrap()
              let source = match
                @query.expression_node(
                  expression,
                  @query.expression_root(expression),
                ).unwrap().kind {
                Reference(path) =>
                  match pipe_slot(path, pipe_visible, pipe_ranges) {
                    Some(slot) => slot
                    None => raise Abort(UnknownColumn)
                  }
                _ => {
                  let slot = pipe_physical_name(physical, "aql_pipe_expr_")
                  physical.push(slot)
                  derives.push(
                    (
                      slot,
                      append_pipe_expression(
                        construction, expression, pipe_visible, pipe_ranges, max_work,
                      ),
                    ),
                  )
                  slot
                }
              }
              let name = match projection.name {
                Some(name) => name.value
                None =>
                  match
                    @query.expression_node(
                      expression,
                      @query.expression_root(expression),
                    ).unwrap().kind {
                    Reference(path) => path.last().unwrap().value
                    _ => raise Abort(UnsupportedProjection)
                  }
              }
              names.push(name)
              bindings.push((name, source))
              expressions.push((expression, name))
              selected.push(
                if name == source {
                  construction.text(source)
                } else {
                  construction.object([(name, construction.text(source))])
                },
              )
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
          let derive_step : Array[(String, @builder.Node)] = []
          if entries.length() == 1 {
            derive_step.push(entries[0])
            entries.clear()
          }
          derive_step.push(("derive", construction.object(derives)))
          step_entries.push(derive_step)
        }
        entries.push(("select", construction.array(selected)))
        output = names
        selected_expressions = expressions
        if !distinct && @query.operation_at(query, i + 1) is Some(Order(_)) {
          if entries.length() == 2 && entries[0].0 == "from" {
            ignore(entries.remove(0))
            first = true
          }
          pending_select = Some(entries)
          pending_bindings = bindings
          deferred = true
        } else {
          active_fields = names.copy()
          pipe_visible = names.map(name => (name, name))
          pipe_changed = false
        }
        pipe_selected = true
        if distinct {
          add_distinct = true
        }
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
        pipe_visible = names.map(name => (name, name))
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
      Order(terms) if pipe_selected => {
        let sort : Array[@builder.Node] = []
        for term in terms {
          let expression = term.expression
          let mut selected : String? = None
          for pair in selected_expressions {
            if same_expression(expression, pair.0) {
              if selected is Some(_) {
                raise Abort(UnsupportedOrdering)
              }
              selected = Some(pair.1)
            }
          }
          let name = match selected {
            Some(name) => {
              let mut slot = name
              if pending_select is Some(_) {
                for binding in pending_bindings {
                  if binding.0 == name {
                    slot = binding.1
                  }
                }
              }
              slot
            }
            None =>
              match
                @query.expression_node(
                  expression,
                  @query.expression_root(expression),
                ).unwrap().kind {
                Reference(path) if path.length() == 1 => {
                  let mut slot : String? = None
                  for name in output {
                    if same_name(path[0], { value: name, quoted: false, }) {
                      slot = Some(name)
                    }
                  }
                  match slot {
                    Some(name) => {
                      let mut physical = name
                      if pending_select is Some(_) {
                        for binding in pending_bindings {
                          if binding.0 == name {
                            physical = binding.1
                          }
                        }
                      }
                      physical
                    }
                    None =>
                      if pending_select is Some(_) {
                        match pipe_slot(path, pipe_visible, pipe_ranges) {
                          Some(slot) => slot
                          None => raise Abort(UnsupportedOrdering)
                        }
                      } else {
                        raise Abort(UnsupportedOrdering)
                      }
                  }
                }
                Reference(path) if pending_select is Some(_) =>
                  match pipe_slot(path, pipe_visible, pipe_ranges) {
                    Some(slot) => slot
                    None => raise Abort(UnsupportedOrdering)
                  }
                _ => raise Abort(UnsupportedOrdering)
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
      Order(terms) if pipe_changed => {
        let sort : Array[@builder.Node] = []
        for term in terms {
          let name = match
            @query.expression_node(
              term.expression,
              @query.expression_root(term.expression),
            ).unwrap().kind {
            Reference(path) =>
              match pipe_slot(path, pipe_visible, pipe_ranges) {
                Some(slot) => slot
                None => raise Abort(UnsupportedOrdering)
              }
            _ => raise Abort(UnsupportedOrdering)
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
    if deferred && entries.length() == 1 && entries[0].0 == "from" {
      first = true
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
          pipe_visible = output.map(name => (name, name))
          pipe_changed = false
        }
        None => ()
      }
    }
  }
  if pipe_changed {
    let selected : Array[@builder.Node] = []
    for field in pipe_visible {
      selected.push(
        if field.0 == field.1 {
          construction.text(field.1)
        } else {
          construction.object([(field.0, construction.text(field.1))])
        },
      )
    }
    let entries : Array[(String, @builder.Node)] = []
    if first {
      entries.push(("from", construction.text(input.name)))
    }
    entries.push(("select", construction.array(selected)))
    step_entries.push(entries)
    output = pipe_visible.map(field => field.0)
  }
  if step_entries.is_empty() {
    return ([], output)
  }
  // The last step supplies a stable named stage result for ordinary routing.
  // This is a structural step alias, not a SQL range alias.
  step_entries[step_entries.length() - 1].push(
    ("as", construction.text(final_alias)),
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
  if @query.cte_count(query) > 0 {
    return compile_cte_query(query, context, limits)
  }
  if @query.set_part_count(query) > 0 {
    return compile_set_query(query, context, limits)
  }
  if @query.join_part_count(query) > 0 {
    return compile_join_query(query, context, limits)
  }
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
      StageResult(_, _) => raise Abort(InvalidContext)
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
      StageResult(_, _) => raise Abort(InvalidContext)
    }
    let (steps, output) = compile_steps(
      construction,
      query,
      input,
      fields,
      limits.max_expression_work,
      start_at,
      context.captured_stage is Some(_),
      "aql_gen_0",
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

///|
// A CTE is a checked Stage Result binding. The body is built once, then the
// consumer refers to that Result; text substitution would duplicate acquisition.
fn compile_cte_query(
  query : @query.Query,
  context : Context,
  limits : Limits,
) -> Result[@program.Program, Issue] {
  if @query.cte_count(query) < 1 ||
    @query.set_part_count(query) != 0 ||
    @query.join_part_count(query) > 1 ||
    context.program_id == "" ||
    context.stage_id == "" ||
    context.stage_result == "" ||
    context.result_name == "" {
    return Err(UnsupportedCte)
  }
  if @query.relation(query).length() != 1 {
    return Err(UnsupportedCte)
  }
  let used = Array::make(@query.cte_count(query), false)
  let joined_relation = if @query.join_part_count(query) == 1 {
    Some(@query.join_part_at(query, 0).unwrap().relation)
  } else {
    None
  }
  for index in 0..<@query.cte_count(query) {
    let cte = @query.cte_at(query, index).unwrap()
    for earlier in 0..<index {
      if same_name(cte.name, @query.cte_at(query, earlier).unwrap().name) {
        return Err(UnsupportedCte)
      }
    }
    let body = cte.query
    if @query.cte_count(body) != 0 ||
      @query.set_part_count(body) != 0 ||
      @query.join_part_count(body) > 1 {
      return Err(UnsupportedCte)
    }
    let body_relation = @query.relation(body)
    for future in index..<@query.cte_count(query) {
      if same_path(body_relation, [@query.cte_at(query, future).unwrap().name]) {
        return Err(UnsupportedCte)
      }
    }
    let mut known_relation = context.inputs.any(input => {
      same_path(body_relation, input.relation)
    })
    for earlier in 0..<index {
      if same_path(body_relation, [@query.cte_at(query, earlier).unwrap().name]) {
        known_relation = true
      }
    }
    if !known_relation {
      return Err(UnknownRelation)
    }
    if @query.join_part_count(body) == 1 {
      let right = @query.join_part_at(body, 0).unwrap().relation
      let mut known_right = false
      for earlier in 0..<index {
        if same_path(right, [@query.cte_at(query, earlier).unwrap().name]) {
          known_right = true
        }
      }
      if !known_right {
        return Err(UnsupportedCte)
      }
    }
    let joined = match joined_relation {
      Some(path) => same_path(path, [cte.name])
      None => false
    }
    if same_path(@query.relation(query), [cte.name]) || joined {
      used[index] = true
    }
  }
  if !used.any(value => value) {
    return Err(UnsupportedCte)
  }
  let mut index = @query.cte_count(query) - 1
  while index >= 0 {
    if used[index] {
      let relation = @query.relation(@query.cte_at(query, index).unwrap().query)
      let right = if @query.join_part_count(
          @query.cte_at(query, index).unwrap().query,
        ) ==
        1 {
        Some(
          @query.join_part_at(@query.cte_at(query, index).unwrap().query, 0).unwrap().relation,
        )
      } else {
        None
      }
      for earlier in 0..<index {
        let name = [@query.cte_at(query, earlier).unwrap().name]
        if same_path(relation, name) ||
          (right is Some(right_relation) && same_path(right_relation, name)) {
          used[earlier] = true
        }
      }
    }
    index -= 1
  }
  // An unused declaration still needs full semantic checking. Until the
  // frontend can check it without scheduling its acquisition, reject it.
  if used.any(value => !value) {
    return Err(UnsupportedCte)
  }
  let document = @query.query_document(query)
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let builder = match @builder.create(document, limits.source) {
    Ok(value) => value
    Err(issue) => return Err(Construction(issue))
  }
  let construction : Construction = { builder, generated, }
  try {
    let stages : Array[@builder.Node] = []
    let used_stage_names : Array[String] = []
    let mut known = context.inputs.copy()
    let cte_inputs : Array[Input] = []
    let mut captured_owner = false
    for index in 0..<@query.cte_count(query) {
      let cte = @query.cte_at(query, index).unwrap()
      let body_relation = @query.relation(cte.query)
      let captures_source = context.inputs.any(input => {
        same_path(body_relation, input.relation) && input.source is Captured(_)
      })
      if captures_source && captured_owner {
        raise Abort(UnsupportedCte)
      }
      if captures_source {
        captured_owner = true
      }
      let stage_name = if captures_source {
        context.captured_stage.unwrap_or("aql_cte_" + index.to_string())
      } else {
        "aql_cte_" + index.to_string()
      }
      if stage_name == context.stage_id || used_stage_names.contains(stage_name) {
        raise Abort(InvalidContext)
      }
      used_stage_names.push(stage_name)
      let (stage, binding) = compile_cte_stage(
        construction, cte, known, context, limits, stage_name,
      )
      stages.push(stage)
      known = known.filter(input => !same_path(input.relation, [cte.name]))
      known.push(binding)
      cte_inputs.push(binding)
    }
    let mut cte_input : Input? = None
    for input in cte_inputs {
      if same_path(input.relation, @query.relation(query)) {
        cte_input = Some(input)
      }
    }
    guard cte_input is Some(cte_input) else { raise Abort(UnsupportedCte) }
    let body_output = cte_input.visible_fields
    guard cte_input.source is StageResult(stage_name, result_name) else {
      raise Abort(UnsupportedCte)
    }
    let cte_ref = construction.object([
      (
        "result",
        construction.object([
          ("stage", construction.text(stage_name)),
          ("result", construction.text(result_name)),
        ]),
      ),
    ])
    let (outer_steps, output, outer_inputs, outer_from) = if @query.join_part_count(
        query,
      ) ==
      1 {
      let part = @query.join_part_at(query, 0).unwrap()
      let mut right_input : Input? = None
      for input in cte_inputs {
        if same_path(input.relation, part.relation) {
          right_input = Some(input)
        }
      }
      guard right_input is Some(right_input) &&
        right_input.source is StageResult(right_stage, right_result) else {
        raise Abort(UnsupportedCte)
      }
      let right_ref = construction.object([
        (
          "result",
          construction.object([
            ("stage", construction.text(right_stage)),
            ("result", construction.text(right_result)),
          ]),
        ),
      ])
      let (steps, fields) = compile_cte_join_steps(
        construction,
        query,
        @query.relation(query)[0],
        body_output,
        part.relation[0],
        right_input.visible_fields,
        limits,
      )
      (steps, fields, [("l", cte_ref), ("r", right_ref)], "aql_join_output")
    } else {
      let (steps, fields) = compile_steps(
        construction,
        query,
        cte_input,
        body_output,
        limits.max_expression_work,
        0,
        false,
        "aql_gen_0",
      )
      let from = if steps.is_empty() { cte_input.name } else { "aql_gen_0" }
      (steps, fields, [(cte_input.name, cte_ref)], from)
    }
    let stage = construction.object([
      ("id", construction.text(context.stage_id)),
      ("inputs", construction.object(outer_inputs)),
      ("steps", construction.array(outer_steps)),
      (
        "results",
        construction.object([
          (
            context.stage_result,
            construction.object([
              ("from", construction.text(outer_from)),
              (
                "fields",
                construction.array(
                  output.map(field => construction.text(field)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    ])
    stages.push(stage)
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
      Ok(value) => value
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

///|
fn compile_cte_stage(
  construction : Construction,
  cte : @query.CtePart,
  known : Array[Input],
  context : Context,
  limits : Limits,
  stage_name : String,
) -> (@builder.Node, Input) raise Abort {
  let body = cte.query
  if @query.set_part_count(body) != 0 ||
    @query.join_part_count(body) > 1 ||
    @query.cte_count(body) != 0 {
    raise Abort(UnsupportedCte)
  }
  if @query.join_part_count(body) == 1 {
    let left = selected_input(body, { ..context, inputs: known, })
    let right_relation = @query.join_part_at(body, 0).unwrap().relation
    let mut right : Input? = None
    for input in known {
      if same_path(input.relation, right_relation) {
        right = Some(input)
      }
    }
    guard right is Some(right_input) &&
      left.source is StageResult(left_stage, left_result) &&
      right_input.source is StageResult(right_stage, right_result) else {
      raise Abort(UnsupportedCte)
    }
    let stage_ref = fn(producer : String, result : String) raise Abort {
      construction.object([
        (
          "result",
          construction.object([
            ("stage", construction.text(producer)),
            ("result", construction.text(result)),
          ]),
        ),
      ])
    }
    let (steps, output) = compile_cte_join_steps(
      construction,
      body,
      @query.relation(body)[0],
      columns(left),
      right_relation[0],
      columns(right_input),
      limits,
    )
    let stage = construction.object([
      ("id", construction.text(stage_name)),
      (
        "inputs",
        construction.object([
          ("l", stage_ref(left_stage, left_result)),
          ("r", stage_ref(right_stage, right_result)),
        ]),
      ),
      ("steps", construction.array(steps)),
      (
        "results",
        construction.object([
          (
            "rows",
            construction.object([
              ("from", construction.text("aql_join_output")),
              (
                "fields",
                construction.array(
                  output.map(field => construction.text(field)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    ])
    return (
      stage,
      {
        relation: [cte.name],
        name: cte.name.value,
        source: StageResult(stage_name, "rows"),
        visible_fields: output,
      },
    )
  }
  let input = selected_input(body, { ..context, inputs: known, })
  let fields = columns(input)
  let (cte_inputs, seed) = match input.source {
    Captured(declaration) => {
      let imported = match
        @builder.import_cursor(
          construction.builder,
          declaration,
          construction.generated,
        ) {
        Ok(node) => node
        Err(issue) => raise Abort(Construction(issue))
      }
      ([(input.name, imported)], [])
    }
    GeneratedValues(step) => {
      if context.captured_stage is Some(_) {
        raise Abort(InvalidContext)
      }
      let imported = match
        @builder.import_cursor(
          construction.builder,
          step,
          construction.generated,
        ) {
        Ok(node) => node
        Err(issue) => raise Abort(Construction(issue))
      }
      ([], [imported])
    }
    StageResult(producer, result) => {
      let source_ref = construction.object([
        (
          "result",
          construction.object([
            ("stage", construction.text(producer)),
            ("result", construction.text(result)),
          ]),
        ),
      ])
      ([(input.name, source_ref)], [])
    }
  }
  let final_alias = "aql_cte_final"
  let (body_steps, body_output) = compile_steps(
    construction,
    body,
    input,
    fields,
    limits.max_expression_work,
    0,
    input.source is Captured(_),
    final_alias,
  )
  let body_from = if body_steps.is_empty() { input.name } else { final_alias }
  let stage = construction.object([
    ("id", construction.text(stage_name)),
    ("inputs", construction.object(cte_inputs)),
    ("steps", construction.array(seed + body_steps)),
    (
      "results",
      construction.object([
        (
          "rows",
          construction.object([
            ("from", construction.text(body_from)),
            (
              "fields",
              construction.array(
                body_output.map(field => construction.text(field)),
              ),
            ),
          ]),
        ),
      ]),
    ),
  ])
  (
    stage,
    {
      relation: [cte.name],
      name: cte.name.value,
      source: StageResult(stage_name, "rows"),
      visible_fields: body_output,
    },
  )
}

///|
fn compile_cte_join_steps(
  construction : Construction,
  query : @query.Query,
  left_name : @query.NamePart,
  left_fields : Array[String],
  right_name : @query.NamePart,
  right_fields : Array[String],
  limits : Limits,
) -> (Array[@builder.Node], Array[String]) raise Abort {
  if @query.operation_count(query) != 1 ||
    limits.max_join_output_rows < 1L ||
    limits.max_join_output_rows > 9007199254740991L {
    raise Abort(UnsupportedCte)
  }
  let part = @query.join_part_at(query, 0).unwrap()
  let left_qualifier = @query.relation_alias(query).unwrap_or(left_name)
  let right_qualifier = part.source_alias.unwrap_or(right_name)
  if same_name(left_qualifier, right_qualifier) {
    raise Abort(AmbiguousRelation)
  }
  let keys = join_keys(
    part, left_qualifier, right_qualifier, left_fields, right_fields,
  )
  guard @query.operation_at(query, 0) is Some(Select(projections, false)) else {
    raise Abort(UnsupportedCte)
  }
  let select : Array[(String, @builder.Node)] = []
  let output : Array[String] = []
  for projection in projections {
    guard projection.expression is Some(expression) &&
      projection.aggregate is None &&
      projection.analytic is None &&
      @query.expression_node(expression, @query.expression_root(expression))
      is Some({ kind: Reference(path), .. }) else {
      raise Abort(UnsupportedCte)
    }
    let name = projection.name
      .map(value => value.value)
      .unwrap_or(path.last().unwrap().value)
    if output.any(field => ascii_upper(field) == ascii_upper(name)) {
      raise Abort(DuplicateOutput)
    }
    output.push(name)
  }
  if output.is_empty() {
    raise Abort(UnsupportedCte)
  }
  let reserved = left_fields + right_fields
  for name in output {
    reserved.push(name)
  }
  let merged : Array[(String, String, String)] = []
  for index in 0..<projections.length() {
    let projection = projections[index]
    let expression = projection.expression.unwrap()
    guard @query.expression_node(expression, @query.expression_root(expression))
      is Some({ kind: Reference(path), .. }) else {
      raise Abort(UnsupportedCte)
    }
    let name = output[index]
    if part.kind == "full" &&
      path.length() == 1 &&
      part.using_columns.any(key => same_name(key, path[0])) {
      let left = join_field(
        [left_qualifier, path[0]],
        left_qualifier,
        right_qualifier,
        left_fields,
        right_fields,
      )
      let right = join_field(
        [right_qualifier, path[0]],
        left_qualifier,
        right_qualifier,
        left_fields,
        right_fields,
      )
      let left_slot = pipe_physical_name(reserved, "aql_join_left_key_")
      reserved.push(left_slot)
      let right_slot = pipe_physical_name(reserved, "aql_join_right_key_")
      reserved.push(right_slot)
      select.push((left_slot, construction.text(left.0 + "." + left.1)))
      select.push((right_slot, construction.text(right.0 + "." + right.1)))
      merged.push((name, left_slot, right_slot))
    } else {
      let resolved = join_projection_field(
        path, part, left_qualifier, right_qualifier, left_fields, right_fields,
      )
      select.push((name, construction.text(resolved.0 + "." + resolved.1)))
    }
  }
  let operation = if part.kind == "cross" {
    (
      "cross_join",
      construction.object([
        ("with", construction.text("r")),
        (
          "max_output_rows",
          construction.add(Number(limits.max_join_output_rows.to_double())),
        ),
        ("select", construction.object(select)),
      ]),
    )
  } else {
    (
      "join",
      construction.object([
        ("with", construction.text("r")),
        ("kind", construction.text(part.kind)),
        (
          "on",
          construction.array(
            keys.map(pair => {
              construction.object([
                ("left", construction.text(pair.0)),
                ("right", construction.text(pair.1)),
              ])
            }),
          ),
        ),
        (
          "max_output_rows",
          construction.add(Number(limits.max_join_output_rows.to_double())),
        ),
        ("select", construction.object(select)),
      ]),
    )
  }
  let steps : Array[@builder.Node] = []
  steps.push(
    construction.object([
      ("from", construction.text("l")),
      operation,
      (
        "as",
        construction.text(
          if merged.is_empty() {
            "aql_join_output"
          } else {
            "aql_join_raw"
          },
        ),
      ),
    ]),
  )
  if !merged.is_empty() {
    steps.push(
      construction.object([
        ("from", construction.text("aql_join_raw")),
        (
          "derive",
          construction.object(
            merged.map(entry => {
              (
                entry.0,
                construction.object([
                  (
                    "coalesce",
                    construction.array([
                      construction.object([
                        ("field", construction.text(entry.1)),
                      ]),
                      construction.object([
                        ("field", construction.text(entry.2)),
                      ]),
                    ]),
                  ),
                ]),
              )
            }),
          ),
        ),
        ("as", construction.text("aql_join_merged")),
      ]),
    )
    steps.push(
      construction.object([
        ("from", construction.text("aql_join_merged")),
        (
          "select",
          construction.array(output.map(name => construction.text(name))),
        ),
        ("as", construction.text("aql_join_output")),
      ]),
    )
  }
  (steps, output)
}

///|
// Set operands remain checked Program steps. Position matching is expressed
// as an ordinary simultaneous projection before the existing row-set kernel.
fn compile_set_query(
  query : @query.Query,
  context : Context,
  limits : Limits,
) -> Result[@program.Program, Issue] {
  if limits.max_expression_work < 0 ||
    context.program_id == "" ||
    context.stage_id == "" ||
    context.stage_result == "" ||
    context.result_name == "" ||
    context.captured_stage is Some(_) {
    return Err(InvalidContext)
  }
  let document = @query.query_document(query)
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let builder = match @builder.create(document, limits.source) {
    Ok(builder) => builder
    Err(issue) => return Err(Construction(issue))
  }
  let construction : Construction = { builder, generated, }
  try {
    let terms : Array[@query.Query] = [query]
    for index in 0..<@query.set_part_count(query) {
      terms.push(@query.set_part_at(query, index).unwrap().right)
    }
    let stages : Array[@builder.Node] = []
    let sources : Array[String] = []
    let outputs : Array[Array[String]] = []
    for index in 0..<terms.length() {
      let term = terms[index]
      if @query.join_part_count(term) > 0 {
        raise Abort(UnsupportedJoin)
      }
      let input = selected_input(term, context)
      let fields = columns(input)
      let fragment = match input.source {
        GeneratedValues(step) => step
        Captured(_) | StageResult(_, _) => raise Abort(UnsupportedSet)
      }
      let seed = match @builder.import_cursor(builder, fragment, generated) {
        Ok(node) => node
        Err(issue) => raise Abort(Construction(issue))
      }
      let seed_stage = "aql_set_seed_" + index.to_string()
      stages.push(
        construction.object([
          ("id", construction.text(seed_stage)),
          ("inputs", construction.object([])),
          ("steps", construction.array([seed])),
          (
            "results",
            construction.object([
              (
                seed_stage,
                construction.object([
                  ("from", construction.text(input.name)),
                  (
                    "fields",
                    construction.array(
                      fields.map(name => construction.text(name)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      )
      let term_stage = "aql_set_term_" + index.to_string()
      if context.inputs.any(other => other.name == term_stage) {
        raise Abort(InvalidContext)
      }
      let term_name = "aql_set_output_" + index.to_string()
      let (body, output) = compile_steps(
        construction,
        term,
        input,
        fields,
        limits.max_expression_work,
        0,
        false,
        term_name,
      )
      let term_steps : Array[@builder.Node] = []
      for step in body {
        term_steps.push(step)
      }
      if term_steps.is_empty() {
        term_steps.push(
          construction.object([
            ("from", construction.text(input.name)),
            (
              "select",
              construction.array(fields.map(name => construction.text(name))),
            ),
            ("as", construction.text(term_name)),
          ]),
        )
      }
      stages.push(
        construction.object([
          ("id", construction.text(term_stage)),
          (
            "inputs",
            construction.object([
              (
                input.name,
                construction.object([
                  (
                    "result",
                    construction.object([
                      ("stage", construction.text(seed_stage)),
                      ("result", construction.text(seed_stage)),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
          ("steps", construction.array(term_steps)),
          (
            "results",
            construction.object([
              (
                term_stage,
                construction.object([
                  ("from", construction.text(term_name)),
                  (
                    "fields",
                    construction.array(
                      output.map(name => construction.text(name)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      )
      sources.push(term_stage)
      outputs.push(output)
    }
    let left_fields = outputs[0]
    let mut current_stage = sources[0]
    for index in 0..<@query.set_part_count(query) {
      let part = @query.set_part_at(query, index).unwrap()
      let right_fields = outputs[index + 1]
      if right_fields.length() != left_fields.length() {
        raise Abort(UnsupportedSet)
      }
      let aligned : Array[(String, @builder.Node)] = []
      let mut alignment_needed = false
      let matched : Array[String] = []
      for field in left_fields {
        let source = if part.by_name {
          let mut selected : String? = None
          for candidate in right_fields {
            if same_name({ value: field, quoted: false, }, {
                value: candidate,
                quoted: false,
              }) {
              if selected is Some(_) {
                raise Abort(UnsupportedSet)
              }
              selected = Some(candidate)
            }
          }
          match selected {
            Some(name) => name
            None => raise Abort(UnsupportedSet)
          }
        } else {
          right_fields[aligned.length()]
        }
        matched.push(source)
        if source != field || right_fields[aligned.length()] != field {
          alignment_needed = true
        }
        aligned.push((field, construction.text(source)))
      }
      if matched.length() != right_fields.length() {
        raise Abort(UnsupportedSet)
      }
      let mut right_stage = sources[index + 1]
      if alignment_needed {
        let aligned_name = "aql_set_aligned_" + index.to_string()
        stages.push(
          construction.object([
            ("id", construction.text(aligned_name)),
            (
              "inputs",
              construction.object([
                (
                  "r",
                  construction.object([
                    (
                      "result",
                      construction.object([
                        ("stage", construction.text(right_stage)),
                        ("result", construction.text(right_stage)),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
            (
              "steps",
              construction.array([
                construction.object([
                  ("from", construction.text("r")),
                  (
                    "select",
                    construction.array(
                      aligned.mapi((index, entry) => {
                        if entry.0 == matched[index] {
                          entry.1
                        } else {
                          construction.object([(entry.0, entry.1)])
                        }
                      }),
                    ),
                  ),
                  ("as", construction.text("aligned_rows")),
                ]),
              ]),
            ),
            (
              "results",
              construction.object([
                (
                  aligned_name,
                  construction.object([
                    ("from", construction.text("aligned_rows")),
                    (
                      "fields",
                      construction.array(
                        left_fields.map(name => construction.text(name)),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        )
        right_stage = aligned_name
      }
      let combined = "aql_set_combined_" + index.to_string()
      let operation = match part.kind {
        "union" => "append"
        "intersect" => "intersect"
        "except" => "except"
        _ => raise Abort(UnsupportedSet)
      }
      let body = if part.kind == "union" {
        construction.object([("with", construction.text("r"))])
      } else {
        construction.object([
          ("with", construction.text("r")),
          ("duplicates", construction.text(part.duplicates)),
        ])
      }
      let merge_stage = "aql_set_merge_" + index.to_string()
      stages.push(
        construction.object([
          ("id", construction.text(merge_stage)),
          (
            "inputs",
            construction.object([
              (
                "l",
                construction.object([
                  (
                    "result",
                    construction.object([
                      ("stage", construction.text(current_stage)),
                      ("result", construction.text(current_stage)),
                    ]),
                  ),
                ]),
              ),
              (
                "r",
                construction.object([
                  (
                    "result",
                    construction.object([
                      ("stage", construction.text(right_stage)),
                      ("result", construction.text(right_stage)),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
          (
            "steps",
            construction.array([
              construction.object([
                ("from", construction.text("l")),
                (operation, body),
                ("as", construction.text(combined)),
              ]),
            ]),
          ),
          (
            "results",
            construction.object([
              (
                merge_stage,
                construction.object([
                  ("from", construction.text(combined)),
                  (
                    "fields",
                    construction.array(
                      left_fields.map(name => construction.text(name)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      )
      current_stage = merge_stage
      if part.kind == "union" && part.duplicates == "distinct" {
        let unique_stage = "aql_set_unique_" + index.to_string()
        stages.push(
          construction.object([
            ("id", construction.text(unique_stage)),
            (
              "inputs",
              construction.object([
                (
                  "rows",
                  construction.object([
                    (
                      "result",
                      construction.object([
                        ("stage", construction.text(current_stage)),
                        ("result", construction.text(current_stage)),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
            (
              "steps",
              construction.array([
                construction.object([
                  ("from", construction.text("rows")),
                  (
                    "distinct",
                    construction.array(
                      left_fields.map(name => construction.text(name)),
                    ),
                  ),
                  ("as", construction.text("unique_rows")),
                ]),
              ]),
            ),
            (
              "results",
              construction.object([
                (
                  unique_stage,
                  construction.object([
                    ("from", construction.text("unique_rows")),
                    (
                      "fields",
                      construction.array(
                        left_fields.map(name => construction.text(name)),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        )
        current_stage = unique_stage
      }
    }
    let steps : Array[@builder.Node] = []
    let mut current = "set_rows"
    for index in 0..<@query.final_operation_count(query) {
      let operation = @query.final_operation_at(query, index).unwrap()
      let final_name = "aql_set_final_" + index.to_string()
      match operation {
        Order(terms) => {
          let sort : Array[@builder.Node] = []
          for term in terms {
            let root = @query.expression_node(
              term.expression,
              @query.expression_root(term.expression),
            ).unwrap()
            guard root.kind is Reference(path) && path.length() == 1 else {
              raise Abort(UnsupportedOrdering)
            }
            let mut selected : String? = None
            for field in left_fields {
              if same_name(path[0], { value: field, quoted: false, }) {
                selected = Some(field)
              }
            }
            let field = match selected {
              Some(field) => field
              None => raise Abort(UnsupportedOrdering)
            }
            sort.push(
              construction.object([
                ("field", construction.text(field)),
                ("dir", construction.text(term.direction)),
                ("nulls", construction.text(term.nulls)),
              ]),
            )
          }
          steps.push(
            construction.object([
              ("from", construction.text(current)),
              ("sort", construction.array(sort)),
              ("as", construction.text(final_name)),
            ]),
          )
        }
        Limit(count, offset) =>
          steps.push(
            construction.object([
              ("from", construction.text(current)),
              (
                "take",
                construction.object([
                  ("count", construction.add(Number(count.to_double()))),
                  ("offset", construction.add(Number(offset.to_double()))),
                ]),
              ),
              ("as", construction.text(final_name)),
            ]),
          )
        _ => raise Abort(UnsupportedSet)
      }
      current = final_name
    }
    if steps.is_empty() {
      current = "aql_set_final_0"
      steps.push(
        construction.object([
          ("from", construction.text("set_rows")),
          (
            "select",
            construction.array(left_fields.map(name => construction.text(name))),
          ),
          ("as", construction.text(current)),
        ]),
      )
    }
    let result = construction.object([
      ("from", construction.text(current)),
      (
        "fields",
        construction.array(left_fields.map(name => construction.text(name))),
      ),
    ])
    let stage = construction.object([
      ("id", construction.text(context.stage_id)),
      (
        "inputs",
        construction.object([
          (
            "set_rows",
            construction.object([
              (
                "result",
                construction.object([
                  ("stage", construction.text(current_stage)),
                  ("result", construction.text(current_stage)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
      ("steps", construction.array(steps)),
      ("results", construction.object([(context.stage_result, result)])),
    ])
    stages.push(stage)
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

///|
fn join_field(
  path : Array[@query.NamePart],
  left_qualifier : @query.NamePart,
  right_qualifier : @query.NamePart,
  left_fields : Array[String],
  right_fields : Array[String],
) -> (String, String) raise Abort {
  if path.is_empty() || path.length() > 2 {
    raise Abort(UnknownColumn)
  }
  let mut left = path.length() == 1 || same_name(path[0], left_qualifier)
  let mut right = path.length() == 1 || same_name(path[0], right_qualifier)
  if path.length() == 2 && left && right {
    raise Abort(AmbiguousRelation)
  }
  let name = path[path.length() - 1]
  let mut field : String? = None
  if left {
    for candidate in left_fields {
      if same_name(name, { value: candidate, quoted: false, }) {
        if field is Some(_) {
          raise Abort(UnknownColumn)
        }
        field = Some(candidate)
      }
    }
    if field is None {
      left = false
    }
  }
  let left_field = field
  field = None
  if right {
    for candidate in right_fields {
      if same_name(name, { value: candidate, quoted: false, }) {
        if field is Some(_) {
          raise Abort(UnknownColumn)
        }
        field = Some(candidate)
      }
    }
    if field is None {
      right = false
    }
  }
  if left && right {
    raise Abort(UnknownColumn)
  }
  if left {
    return ("left", left_field.unwrap())
  }
  if right {
    return ("right", field.unwrap())
  }
  raise Abort(UnknownColumn)
}

///|
fn join_projection_field(
  path : Array[@query.NamePart],
  part : @query.JoinPart,
  left_qualifier : @query.NamePart,
  right_qualifier : @query.NamePart,
  left_fields : Array[String],
  right_fields : Array[String],
) -> (String, String) raise Abort {
  if path.length() == 1 {
    for using_name in part.using_columns {
      if same_name(path[0], using_name) {
        if part.kind == "full" {
          raise Abort(UnsupportedJoin)
        }
        // INNER and LEFT USING expose one key while retaining qualified
        // access to both originals. FULL requires a coalesced output key.
        return join_field(
          [left_qualifier, using_name],
          left_qualifier,
          right_qualifier,
          left_fields,
          right_fields,
        )
      }
    }
  }
  join_field(path, left_qualifier, right_qualifier, left_fields, right_fields)
}

///|
fn join_keys(
  part : @query.JoinPart,
  left_qualifier : @query.NamePart,
  right_qualifier : @query.NamePart,
  left_fields : Array[String],
  right_fields : Array[String],
) -> Array[(String, String)] raise Abort {
  let pairs : Array[(String, String)] = []
  if part.on is Some(expression) {
    let pending = [@query.expression_root(expression)]
    while pending.pop() is Some(index) {
      let node = @query.expression_node(expression, index).unwrap()
      match node.kind {
        Parenthesized(child) => pending.push(child)
        Binary("AND", left, right) => {
          pending.push(right)
          pending.push(left)
        }
        Binary("=", left, right) => {
          guard @query.expression_node(expression, left).unwrap().kind
            is Reference(left_path) &&
            @query.expression_node(expression, right).unwrap().kind
            is Reference(right_path) else {
            raise Abort(UnsupportedJoin)
          }
          let a = join_field(
            left_path, left_qualifier, right_qualifier, left_fields, right_fields,
          )
          let b = join_field(
            right_path, left_qualifier, right_qualifier, left_fields, right_fields,
          )
          if a.0 == "left" && b.0 == "right" {
            pairs.push((a.1, b.1))
          } else if a.0 == "right" && b.0 == "left" {
            pairs.push((b.1, a.1))
          } else {
            raise Abort(UnsupportedJoin)
          }
        }
        _ => raise Abort(UnsupportedJoin)
      }
    }
  } else {
    for name in part.using_columns {
      let left = join_field(
        [left_qualifier, name],
        left_qualifier,
        right_qualifier,
        left_fields,
        right_fields,
      )
      let right = join_field(
        [right_qualifier, name],
        left_qualifier,
        right_qualifier,
        left_fields,
        right_fields,
      )
      pairs.push((left.1, right.1))
    }
  }
  if pairs.is_empty() && part.kind != "cross" {
    raise Abort(UnsupportedJoin)
  }
  pairs
}

///|
fn join_values_rows(input : Input) -> Int raise Abort {
  guard input.source is GeneratedValues(step) else {
    raise Abort(UnsupportedJoin)
  }
  let step = match @wire.open_object(step) {
    Ok(value) => value
    Err(_) => raise Abort(InvalidContext)
  }
  let values = match @wire.lookup(step, "values") {
    Some(value) => value
    None => raise Abort(InvalidContext)
  }
  let values = match @wire.open_object(values) {
    Ok(value) => value
    Err(_) => raise Abort(InvalidContext)
  }
  let rows = match @wire.lookup(values, "rows") {
    Some(value) => value
    None => raise Abort(InvalidContext)
  }
  match @wire.elements(rows) {
    Ok(value) => value.length()
    Err(_) => raise Abort(InvalidContext)
  }
}

///|
fn join_seed_stage(
  construction : Construction,
  input : Input,
  fields : Array[String],
  stage_name : String,
) -> @builder.Node raise Abort {
  guard input.source is GeneratedValues(step) else {
    raise Abort(UnsupportedJoin)
  }
  let seed = match
    @builder.import_cursor(construction.builder, step, construction.generated) {
    Ok(value) => value
    Err(issue) => raise Abort(Construction(issue))
  }
  construction.object([
    ("id", construction.text(stage_name)),
    ("inputs", construction.object([])),
    ("steps", construction.array([seed])),
    (
      "results",
      construction.object([
        (
          stage_name,
          construction.object([
            ("from", construction.text(input.name)),
            (
              "fields",
              construction.array(fields.map(field => construction.text(field))),
            ),
          ]),
        ),
      ]),
    ),
  ])
}

///|
fn compile_join_query(
  query : @query.Query,
  context : Context,
  limits : Limits,
) -> Result[@program.Program, Issue] {
  if @query.join_part_count(query) != 1 ||
    @query.operation_count(query) != 1 ||
    context.captured_stage is Some(_) ||
    context.program_id == "" ||
    context.stage_id == "" ||
    context.stage_result == "" ||
    context.result_name == "" {
    return Err(UnsupportedJoin)
  }
  let document = @query.query_document(query)
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let builder = match @builder.create(document, limits.source) {
    Ok(value) => value
    Err(issue) => return Err(Construction(issue))
  }
  let construction : Construction = { builder, generated, }
  try {
    let part = @query.join_part_at(query, 0).unwrap()
    // A FULL JOIN requires stable row identity on both sides. Generated
    // Values stages do not currently carry that proof across stage Results.
    if part.kind == "full" {
      raise Abort(UnsupportedJoin)
    }
    let left = selected_input(query, context)
    let right = selected_relation(part.relation, context)
    let left_fields = columns(left)
    let right_fields = columns(right)
    let left_qualifier = @query.relation_alias(query).unwrap_or(
      @query.relation(query).last().unwrap(),
    )
    let right_qualifier = part.source_alias.unwrap_or(
      part.relation.last().unwrap(),
    )
    if same_name(left_qualifier, right_qualifier) {
      raise Abort(AmbiguousRelation)
    }
    let keys = join_keys(
      part, left_qualifier, right_qualifier, left_fields, right_fields,
    )
    guard @query.operation_at(query, 0) is Some(Select(projections, false)) else {
      raise Abort(UnsupportedJoin)
    }
    let select : Array[(String, @builder.Node)] = []
    let output : Array[String] = []
    for projection in projections {
      guard projection.expression is Some(expression) &&
        projection.aggregate is None &&
        projection.analytic is None &&
        @query.expression_node(expression, @query.expression_root(expression))
        is Some({ kind: Reference(path), .. }) else {
        raise Abort(UnsupportedJoin)
      }
      let resolved = join_projection_field(
        path, part, left_qualifier, right_qualifier, left_fields, right_fields,
      )
      let name = projection.name
        .map(value => value.value)
        .unwrap_or(path.last().unwrap().value)
      if output.any(field => ascii_upper(field) == ascii_upper(name)) {
        raise Abort(DuplicateOutput)
      }
      output.push(name)
      select.push((name, construction.text(resolved.0 + "." + resolved.1)))
    }
    if output.is_empty() {
      raise Abort(UnsupportedJoin)
    }
    let left_rows = join_values_rows(left).to_int64()
    let right_rows = join_values_rows(right).to_int64()
    let factor = if part.kind == "inner" || part.kind == "cross" {
      right_rows
    } else if right_rows == 0L {
      1L
    } else {
      right_rows
    }
    let extra = if part.kind == "full" { right_rows } else { 0L }
    if extra > 9007199254740991L ||
      (factor != 0L && left_rows > (9007199254740991L - extra) / factor) {
      raise Abort(UnsupportedJoin)
    }
    let raw_bound = left_rows * factor + extra
    let bound = if raw_bound == 0L { 1L } else { raw_bound }
    if limits.max_join_output_rows < 1L || bound > limits.max_join_output_rows {
      raise Abort(UnsupportedJoin)
    }
    let left_stage = "aql_join_left"
    let right_stage = "aql_join_right"
    let operation = if part.kind == "cross" {
      (
        "cross_join",
        construction.object([
          ("with", construction.text("r")),
          ("max_output_rows", construction.add(Number(bound.to_double()))),
          ("select", construction.object(select)),
        ]),
      )
    } else {
      (
        "join",
        construction.object([
          ("with", construction.text("r")),
          ("kind", construction.text(part.kind)),
          (
            "on",
            construction.array(
              keys.map(pair => {
                construction.object([
                  ("left", construction.text(pair.0)),
                  ("right", construction.text(pair.1)),
                ])
              }),
            ),
          ),
          ("max_output_rows", construction.add(Number(bound.to_double()))),
          ("select", construction.object(select)),
        ]),
      )
    }
    let joined = "aql_join_output"
    let stage = construction.object([
      ("id", construction.text(context.stage_id)),
      (
        "inputs",
        construction.object([
          (
            "l",
            construction.object([
              (
                "result",
                construction.object([
                  ("stage", construction.text(left_stage)),
                  ("result", construction.text(left_stage)),
                ]),
              ),
            ]),
          ),
          (
            "r",
            construction.object([
              (
                "result",
                construction.object([
                  ("stage", construction.text(right_stage)),
                  ("result", construction.text(right_stage)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
      (
        "steps",
        construction.array([
          construction.object([
            ("from", construction.text("l")),
            operation,
            ("as", construction.text(joined)),
          ]),
        ]),
      ),
      (
        "results",
        construction.object([
          (
            context.stage_result,
            construction.object([
              ("from", construction.text(joined)),
              (
                "fields",
                construction.array(output.map(name => construction.text(name))),
              ),
            ]),
          ),
        ]),
      ),
    ])
    let root = construction.object([
      ("version", construction.text("actql/0.1")),
      ("id", construction.text(context.program_id)),
      (
        "stages",
        construction.array([
          join_seed_stage(construction, left, left_fields, left_stage),
          join_seed_stage(construction, right, right_fields, right_stage),
          stage,
        ]),
      ),
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
      Ok(value) => value
      Err(issue) => raise Abort(Construction(issue))
    }
    @program.admit_generated_source(source, limits.program).map_err(issue => {
      Admission(issue)
    })
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      Err(issue)
    }
  }
}
