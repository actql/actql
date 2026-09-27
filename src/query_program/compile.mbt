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
  UnsupportedOrdering
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
// Node indices are local to each parsed expression. Equal syntax trees have
// the same postorder indices; spans and whitespace are deliberately ignored.
fn same_expression(left : @query.Expression, right : @query.Expression) -> Bool {
  let count = @query.expression_node_count(left)
  if count != @query.expression_node_count(right) {
    return false
  }
  for i in 0..<count {
    let a = @query.expression_node(left, i).unwrap().kind
    let b = @query.expression_node(right, i).unwrap().kind
    match (a, b) {
      (Reference(x), Reference(y)) => if !same_path(x, y) { return false }
      (Call(x, ax), Call(y, ay)) =>
        if !same_path(x, y) || ax != ay {
          return false
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
fn compile_steps(
  construction : Construction,
  query : @query.Query,
  input : Input,
  fields : Array[String],
  max_work : Int,
  start_at : Int,
) -> (Array[@builder.Node], Array[String]) raise Abort {
  let step_entries : Array[Array[(String, @builder.Node)]] = []
  let mut output = fields.copy()
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
              construction, predicate, query, input, fields, max_work,
            ),
          ),
        )
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
              for field in fields {
                names.push(field)
                selected.push(construction.text(field))
                bindings.push((field, field))
              }
            None => {
              let name = output_name(projection, query, input, fields)
              names.push(name)
              let expression = projection.expression.unwrap()
              expressions.push((expression, name))
              let direct = match
                @query.expression_node(
                  expression,
                  @query.expression_root(expression),
                ).unwrap().kind {
                Reference(path) => resolve_column(path, query, input, fields)
                _ => None
              }
              let source = if direct is Some(column) {
                column
              } else {
                let mut suffix = names.length() - 1
                let mut temporary = "aql_query_expr_" + suffix.to_string()
                while fields.contains(temporary) ||
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
                      construction, expression, query, input, fields, max_work,
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
                      match resolve_column(path, query, input, fields) {
                        Some(field) => field
                        None => raise Abort(UnsupportedOrdering)
                      }
                    } else {
                      raise Abort(UnsupportedOrdering)
                    }
                }
              } else if pending_select is Some(_) {
                match resolve_column(path, query, input, fields) {
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
