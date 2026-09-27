///|
pub(all) struct Input {
  relation : Array[@query.NamePart]
  name : String
  declaration : @wire.Cursor
}

///|
pub(all) struct Context {
  program_id : String
  stage_id : String
  stage_result : String
  result_name : String
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
  let declaration = match @wire.open_object(input.declaration) {
    Ok(object) => object
    Err(_) => raise Abort(InvalidContext)
  }
  let schema = match @wire.required(declaration, "schema") {
    Ok(schema) => schema
    Err(_) => raise Abort(InvalidContext)
  }
  match @wire.object_field_names(schema) {
    Ok(fields) => fields
    Err(_) => raise Abort(InvalidContext)
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
) -> (Array[@builder.Node], Array[String]) raise Abort {
  let steps : Array[@builder.Node] = []
  let mut output = fields.copy()
  let mut first = true
  for i in 0..<@query.operation_count(query) {
    let operation = @query.operation_at(query, i).unwrap()
    let entries : Array[(String, @builder.Node)] = []
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
        if distinct {
          raise Abort(UnsupportedProjection)
        }
        let names : Array[String] = []
        let derives : Array[(String, @builder.Node)] = []
        for projection in projections {
          match projection.star {
            Some(_) =>
              for field in fields {
                names.push(field)
              }
            None => {
              let name = output_name(projection, query, input, fields)
              names.push(name)
              let expression = projection.expression.unwrap()
              let direct = match
                @query.expression_node(
                  expression,
                  @query.expression_root(expression),
                ).unwrap().kind {
                Reference(path) =>
                  resolve_column(path, query, input, fields) == Some(name)
                _ => false
              }
              if !direct {
                derives.push(
                  (
                    name,
                    append_expression(
                      construction, expression, query, input, fields, max_work,
                    ),
                  ),
                )
              }
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
          steps.push(construction.object(derive_fields))
        }
        entries.push(
          (
            "select",
            construction.array(names.map(name => construction.text(name))),
          ),
        )
        output = names
      }
      Order(terms) => {
        let sort : Array[@builder.Node] = []
        for term in terms {
          let name = match
            @query.expression_node(
              term.expression,
              @query.expression_root(term.expression),
            ).unwrap().kind {
            Reference(path) if path.length() == 1 => path[0].value
            _ => raise Abort(UnsupportedOrdering)
          }
          if !output.contains(name) {
            raise Abort(UnsupportedOrdering)
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
    if i == @query.operation_count(query) - 1 {
      entries.push(("as", construction.text("aql_gen_0")))
    }
    steps.push(construction.object(entries))
  }
  if steps.is_empty() {
    return (steps, output)
  }
  // The last step supplies a stable named stage result for ordinary routing.
  // This is a structural step alias, not a SQL range alias.
  (steps, output)
}

///|
// The supplied Input declaration is an admitted catalog projection. This
// frontend does not ask a provider for rows or infer schema during checking.
pub fn compile(
  query : @query.Query,
  context : Context,
  limits : Limits,
) -> Result[@program.Program, Issue] {
  if limits.max_expression_work < 0 ||
    context.program_id == "" ||
    context.stage_id == "" ||
    context.stage_result == "" ||
    context.result_name == "" {
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
    let declaration = match
      @builder.import_cursor(builder, input.declaration, generated) {
      Ok(node) => node
      Err(issue) => raise Abort(Construction(issue))
    }
    let (steps, output) = compile_steps(
      construction,
      query,
      input,
      fields,
      limits.max_expression_work,
    )
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
      ("inputs", construction.object([(input.name, declaration)])),
      ("steps", construction.array(steps)),
      ("results", construction.object([(context.stage_result, result)])),
    ])
    let root = construction.object([
      ("version", construction.text("actql/0.1")),
      ("id", construction.text(context.program_id)),
      ("stages", construction.array([stage])),
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
