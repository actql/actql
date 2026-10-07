///|
// Frontend name binding only. Common type probes supply receiver/output types;
// they are not key, presence, capacity, acquisition or execution admission.
priv struct MemberResolution {
  source : @builder.Source
  document : @origin.Document
  limits : Limits
  mut work : Int
  replacements : Map[Int, String]
}

///|
fn MemberResolution::spend(
  self : MemberResolution,
  cursor : @wire.Cursor,
  used : Int,
) -> Unit raise Abort {
  if used < 0 || used > self.work {
    raise Abort(
      Expression({
        issue: @expression.WorkLimit,
        origin: @builder.origin(self.source, cursor),
      }),
    )
  }
  self.work -= used
}

///|
fn[A, E] member_success(result : Result[A, E]) -> A? {
  match result {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
fn[A] member_construct(result : Result[A, @builder.Issue]) -> A raise Abort {
  match result {
    Ok(value) => value
    Err(issue) => raise Abort(Construction(issue))
  }
}

///|
fn member_lookup(cursor : @wire.Cursor, name : String) -> @wire.Cursor? {
  member_success(@wire.open_object(cursor)).bind(object => {
    @wire.lookup(object, name)
  })
}

///|
fn member_text(cursor : @wire.Cursor, name : String) -> String? {
  member_lookup(cursor, name).bind(value => member_success(@wire.text(value)))
}

///|
// Preserve authored locations and imported/generated boundaries on the copy.
fn MemberResolution::copy(
  self : MemberResolution,
  cursor : @wire.Cursor,
) -> @builder.Source raise Abort {
  let builder = member_construct(
    @builder.create(self.document, self.limits.source),
  )
  let root = member_construct(
    @builder.import_source(builder, self.source, cursor, replace_text=at => {
      self.replacements.get(
        @wire.tree_index(@builder.cursor(self.source), at).unwrap(),
      )
    }),
  )
  let result = member_construct(@builder.finish(builder, root))
  self.spend(cursor, @builder.usage(result).nodes)
  result
}

///|
// Scan only admitted source structure; literal contents cannot become syntax.
fn member_is_literal(source : @builder.Source, cursor : @wire.Cursor) -> Bool {
  @wire.object_length(cursor) == Some(1) &&
  @builder.origin(source, cursor) is Some(origin) &&
  @origin.kind(origin) == @origin.Authored &&
  (
    member_lookup(cursor, "literal") is Some(_) ||
    member_lookup(cursor, "typed_literal") is Some(_)
  )
}

///|
fn has_authored_member(source : @builder.Source) -> Bool {
  let pending = [@builder.cursor(source)]
  while pending.pop() is Some(cursor) {
    if member_is_literal(source, cursor) {
      continue
    }
    if @wire.object_length(cursor) == Some(1) &&
      member_lookup(cursor, "property") is Some(body) &&
      member_lookup(body, "name") is Some(name) &&
      @builder.origin(source, name) is Some(origin) &&
      @origin.kind(origin) == @origin.Authored {
      return true
    }
    match @wire.view(cursor) {
      ArrayValue(items) =>
        for item in items {
          pending.push(item)
        }
      ObjectValue(_) =>
        for index in 0..<@wire.object_length(cursor).unwrap() {
          pending.push(@wire.field_at(cursor, index).unwrap().1)
        }
      _ => ()
    }
  }
  false
}

///|
fn member_environment(
  rows : @schema.Schema?,
  declarations : @parameters.Declarations?,
) -> @typing.Environment {
  let left = []
  let right = []
  if rows is Some(rows) {
    for field in @schema.fields(rows) {
      match field.name {
        @schema.Qualified(@schema.Left, name) =>
          left.push((name, field.contract))
        @schema.Qualified(@schema.Right, name) =>
          right.push((name, field.contract))
        _ => ()
      }
    }
  }
  let object = fn(
    fields : Array[(String, @contract.Contract)],
  ) -> @contract.Contract? {
    if fields.is_empty() {
      None
    } else {
      member_success(
        @contract.object_contract(
          fields,
          nullable=false,
          max_fields=8192,
          max_name_bytes=65536,
        ),
      )
    }
  }
  {
    fields: rows.bind(@schema.as_object),
    left: object(left),
    right: object(right),
    parameters: declarations,
  }
}

///|
fn MemberResolution::expression(
  self : MemberResolution,
  root : @wire.Cursor,
  rows : @schema.Schema?,
  declarations : @parameters.Declarations?,
) -> Unit raise Abort {
  // Literal data is not expression structure. All other forms already came
  // from the query lowerer, and the common expression admission still checks
  // each receiver before any field name is selected.
  let work = [(root, false)]
  while work.pop() is Some((cursor, visited)) {
    self.spend(cursor, 1)
    if !visited {
      if member_is_literal(self.source, cursor) {
        continue
      }
      work.push((cursor, true))
      match @wire.view(cursor) {
        ArrayValue(items) =>
          for item in items {
            work.push((item, false))
          }
        ObjectValue(_) =>
          for index in 0..<@wire.object_length(cursor).unwrap() {
            work.push((@wire.field_at(cursor, index).unwrap().1, false))
          }
        _ => ()
      }
      continue
    }
    guard @wire.object_length(cursor) == Some(1) &&
      member_lookup(cursor, "property") is Some(body) else {
      continue
    }
    guard member_lookup(body, "name") is Some(at) &&
      member_lookup(body, "value") is Some(receiver) &&
      @wire.text(at) is Ok(authored) else {
      continue
    }
    guard @builder.origin(self.source, at) is Some(origin) &&
      @origin.kind(origin) == @origin.Authored else {
      continue
    }
    let normalized = self.copy(receiver)
    let admitted = member_success(
      @expression_syntax.admit(@builder.cursor(normalized), {
        max_nodes: self.limits.source.tree.max_nodes,
        max_depth: self.limits.source.tree.max_depth,
        max_text_bytes: self.limits.source.tree.max_total_string_bytes,
        max_tokens: self.limits.source.tree.max_nodes,
        tree: self.limits.source.tree,
      }),
    )
    guard admitted is Some(admitted) else { continue }
    let typed = match
      @typing.check(admitted, member_environment(rows, declarations), {
        max_nodes: self.limits.source.tree.max_nodes,
        max_depth: self.limits.source.tree.max_depth,
        max_work: self.work,
        max_text_bytes: self.limits.source.tree.max_total_string_bytes,
      }) {
      Ok(typed) => {
        self.spend(receiver, @typing.usage(typed).work)
        typed
      }
      Err({ kind: BudgetExceeded, .. }) =>
        raise Abort(
          Expression({
            issue: @expression.WorkLimit,
            origin: @builder.origin(self.source, receiver),
          }),
        )
      // Unknown or invalid receivers retain ordinary checking's rejection.
      // No row sampling, guessed field type or input-scope fallback is used.
      Err(_) => continue
    }
    guard @typing.result_type(typed).shape is @contract.Object(fields) else {
      continue
    }
    let mut resolved : String? = None
    for index in 0..<@contract.field_count(fields) {
      let field = @contract.field_at(fields, index).unwrap()
      self.spend(at, 1 + authored.length() + field.name.length())
      if ascii_upper(authored) == ascii_upper(field.name) {
        if resolved is Some(_) {
          raise Abort(AmbiguousColumn)
        }
        resolved = Some(field.name)
      }
    }
    if resolved is Some(actual) && actual != authored {
      self.replacements[@wire.tree_index(@builder.cursor(self.source), at).unwrap()] = actual
    }
  }
}

///|
fn MemberResolution::schema(
  self : MemberResolution,
  cursor : @wire.Cursor,
) -> @schema.Schema? raise Abort {
  match
    @environment.read_relation_schema_fields(
      cursor,
      self.limits.source.tree.max_total_string_bytes,
      self.limits.source.tree.max_nodes,
      self.limits.source.tree.max_depth,
      self.work,
    ) {
    Ok((rows, used)) => {
      self.spend(cursor, used)
      Some(rows)
    }
    Err({ kind: WorkLimit, .. }) =>
      raise Abort(
        Expression({
          issue: @expression.WorkLimit,
          origin: @builder.origin(self.source, cursor),
        }),
      )
    Err(_) => None
  }
}

///|
fn MemberResolution::operation_schema(
  self : MemberResolution,
  tag : String,
  body : @wire.Cursor,
  rows : @schema.Schema?,
  names : Map[String, @schema.Schema?],
  declarations : @parameters.Declarations?,
) -> @schema.Schema? raise Abort {
  if tag == "values" {
    return match
      @values.check(body, declarations, {
        max_rows: self.limits.source.tree.max_nodes,
        max_work: self.work,
        max_nodes: self.limits.source.tree.max_nodes,
        max_text_bytes: self.limits.source.tree.max_total_string_bytes,
        max_depth: self.limits.source.tree.max_depth,
      }) {
      Ok(checked) => {
        self.spend(body, @values.usage(checked).work)
        Some(@values.output_schema(checked))
      }
      Err({ kind: BudgetExceeded, .. }) =>
        raise Abort(
          Expression({
            issue: @expression.WorkLimit,
            origin: @builder.origin(self.source, body),
          }),
        )
      Err(_) => None
    }
  }
  guard rows is Some(rows) else { return None }
  let copy = self.copy(body)
  let cursor = @builder.cursor(copy)
  if tag == "join" || tag == "cross_join" {
    guard member_text(body, "with").bind(name => {
        names.get(name).bind(value => value)
      })
      is Some(right) else {
      return None
    }
    let limits : @join_shape.Limits = {
      max_work: self.work,
      max_text_bytes: self.limits.source.tree.max_total_string_bytes,
      max_nodes: self.limits.source.tree.max_nodes,
      max_depth: self.limits.source.tree.max_depth,
    }
    if tag == "join" {
      match @join_shape.check(cursor, rows, right, declarations, limits) {
        Ok(checked) => {
          self.spend(body, @join_shape.usage(checked).work)
          return Some(@join_shape.output_schema(checked))
        }
        Err({ kind: BudgetExceeded, .. }) =>
          raise Abort(
            Expression({
              issue: @expression.WorkLimit,
              origin: @builder.origin(self.source, body),
            }),
          )
        Err(_) => ()
      }
    } else {
      match @join_shape.check_cross(cursor, rows, right, declarations, limits) {
        Ok(checked) => {
          self.spend(body, @join_shape.cross_usage(checked).work)
          return Some(@join_shape.cross_output_schema(checked))
        }
        Err({ kind: BudgetExceeded, .. }) =>
          raise Abort(
            Expression({
              issue: @expression.WorkLimit,
              origin: @builder.origin(self.source, body),
            }),
          )
        Err(_) => ()
      }
    }
    return None
  }
  if tag == "append" {
    guard member_text(body, "with").bind(name => {
        names.get(name).bind(value => value)
      })
      is Some(right) else {
      return None
    }
    match
      @append_shape.check(cursor, rows, right, {
        max_work: self.work,
        max_text_bytes: self.limits.source.tree.max_total_string_bytes,
        max_nodes: self.limits.source.tree.max_nodes,
        max_depth: self.limits.source.tree.max_depth,
      }) {
      Ok(checked) => {
        self.spend(body, @append_shape.usage(checked).work)
        return Some(@append_shape.output_schema(checked))
      }
      Err({ kind: BudgetExceeded, .. }) =>
        raise Abort(
          Expression({
            issue: @expression.WorkLimit,
            origin: @builder.origin(self.source, body),
          }),
        )
      Err(_) => ()
    }
    return None
  }
  let operation : @relation.Operation = match tag {
    "derive" => Derive
    "filter" => Filter
    "select" => Select
    "rename" => Rename
    "drop" => Drop
    "sort" => Sort
    "take" => Take
    "distinct" => Distinct
    "unnest" => Unnest
    "assert_rows" => AssertRows
    "group" => Group
    "analytic" => Analytic
    _ => return None
  }
  match
    @relation.check(operation, cursor, rows, declarations, {
      max_work: self.work,
      max_text_bytes: self.limits.source.tree.max_total_string_bytes,
      max_nodes: self.limits.source.tree.max_nodes,
      max_tokens: self.limits.source.tree.max_nodes,
      max_depth: self.limits.source.tree.max_depth,
    }) {
    Ok(checked) => {
      self.spend(body, @relation.work_used(checked))
      Some(@relation.output_schema(checked))
    }
    Err({ kind: BudgetExceeded, .. }) =>
      raise Abort(
        Expression({
          issue: @expression.WorkLimit,
          origin: @builder.origin(self.source, body),
        }),
      )
    Err(_) => None
  }
}

///|
fn MemberResolution::result_schema(
  self : MemberResolution,
  body : @wire.Cursor,
  rows : @schema.Schema?,
) -> @schema.Schema? raise Abort {
  guard rows is Some(rows) &&
    member_lookup(body, "fields") is Some(fields) &&
    @wire.elements(fields) is Ok(fields) else {
    return None
  }
  let selected = []
  for cursor in fields {
    self.spend(cursor, 1)
    guard @wire.text(cursor) is Ok(name) &&
      @schema.lookup_reference(rows, name) is Some(field) else {
      return None
    }
    selected.push((field.name, field.contract, field.presence))
  }
  member_success(
    @schema.from_presence_fields(
      selected,
      max_fields=self.limits.source.tree.max_nodes,
      max_name_bytes=self.limits.source.tree.max_total_string_bytes,
    ),
  )
}

///|
// Bind member names only after the complete query lowerer has decided the
// actual input/alias/qualified slot. No SELECT expression is re-evaluated.
fn resolve_query_members(
  source : @builder.Source,
  document : @origin.Document,
  context : Context,
  limits : Limits,
) -> @builder.Source raise Abort {
  if !has_authored_member(source) {
    return source
  }
  let resolution : MemberResolution = {
    source,
    document,
    limits,
    work: limits.max_expression_work,
    replacements: Map([]),
  }
  let root = @builder.cursor(source)
  let stages = member_lookup(root, "stages")
    .bind(cursor => member_success(@wire.elements(cursor)))
    .unwrap()
  let results : Map[(String, String), @schema.Schema?] = Map([])
  let originals : Map[String, @schema.Schema?] = Map([])
  for (name, schema) in context.input_schemas {
    originals[name] = Some(schema)
  }
  for input in context.inputs {
    if originals.contains(input.name) {
      continue
    }
    let schema = match input.source {
      Captured(cursor) => member_lookup(cursor, "schema")
      GeneratedValues(_) => None
      _ => None
    }
    originals[input.name] = schema.bind(cursor => resolution.schema(cursor))
  }
  for stage in stages {
    resolution.spend(stage, 1)
    let names : Map[String, @schema.Schema?] = Map([])
    let inputs = member_lookup(stage, "inputs").unwrap()
    for index in 0..<@wire.object_length(inputs).unwrap() {
      let (name, declaration) = @wire.field_at(inputs, index).unwrap()
      let rows = if member_lookup(declaration, "result") is Some(reference) {
        match
          (member_text(reference, "stage"), member_text(reference, "result")) {
          (Some(stage), Some(result)) =>
            results.get((stage, result)).bind(value => value)
          _ => None
        }
      } else {
        originals.get(name).bind(value => value)
      }
      names[name] = rows
    }
    let mut current = if names.length() == 1 {
      names.values().to_array()[0]
    } else {
      None
    }
    for step in @wire.elements(member_lookup(stage, "steps").unwrap()).unwrap() {
      resolution.spend(step, 1)
      if member_text(step, "from") is Some(name) {
        current = names.get(name).bind(value => value)
      }
      let mut output : @schema.Schema? = None
      for index in 0..<@wire.object_length(step).unwrap() {
        let (tag, body) = @wire.field_at(step, index).unwrap()
        if ["from", "as", "meta"].contains(tag) {
          continue
        }
        if tag != "values" {
          resolution.expression(body, current, context.parameter_declarations)
        }
        output = resolution.operation_schema(
          tag,
          body,
          current,
          names,
          context.parameter_declarations,
        )
      }
      current = output
      if member_text(step, "as") is Some(name) {
        names[name] = current
      }
    }
    let stage_id = member_text(stage, "id").unwrap()
    let stage_results = member_lookup(stage, "results").unwrap()
    for index in 0..<@wire.object_length(stage_results).unwrap() {
      let (name, body) = @wire.field_at(stage_results, index).unwrap()
      let rows = member_text(body, "from").bind(name => {
        names.get(name).bind(value => value)
      })
      results[(stage_id, name)] = resolution.result_schema(body, rows)
    }
  }
  if resolution.replacements.is_empty() {
    source
  } else {
    resolution.copy(root)
  }
}

///|
fn admit_query_source(
  source : @builder.Source,
  document : @origin.Document,
  context : Context,
  limits : Limits,
) -> Result[@program.Program, Issue] {
  let source = resolve_query_members(source, document, context, limits) catch {
    Abort(issue) => return Err(issue)
  }
  @program.admit_generated_source(source, limits.program).map_err(issue => {
    Admission(issue)
  })
}
