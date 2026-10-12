///|
// Frontend name binding only. Common type probes supply receiver/output types;
// they are not key, presence, capacity, acquisition or execution admission.
priv struct MemberResolution {
  source : @builder.Source
  document : @origin.Document
  limits : Limits
  mut work : Int
  mut output_work : Int
  mut probe_refused : Bool
  replacements : Map[Int, String]
}

///|
// A refused common probe reports no usage. Its complete remaining allowance
// is therefore retained as a reservation, and no further probe is attempted.
// Final ordinary checking still owns the semantic refusal and its diagnosis.
fn MemberResolution::defer_refusal(self : MemberResolution) -> Unit {
  self.probe_refused = true
  self.work = 0
}

///|
fn MemberResolution::replace_member(
  self : MemberResolution,
  at : @wire.Cursor,
  actual : String,
) -> Unit raise Abort {
  if self.replacements.is_empty() {
    // Text replacement cannot change the node count. Hold this exact copy
    // allowance before lending the remaining budget to another type probe.
    let nodes = @builder.usage(self.source).nodes
    self.spend(at, nodes)
    self.output_work = nodes
  }
  self.replacements[@wire.tree_index(@builder.cursor(self.source), at).unwrap()] = actual
}

///|
fn MemberResolution::finish(
  self : MemberResolution,
) -> @builder.Source raise Abort {
  if self.replacements.is_empty() {
    return self.source
  }
  // Return only the already-held allowance. This is not a budget increase
  // or a continuation of checking after the refused probe.
  self.work += self.output_work
  self.output_work = 0
  self.copy(@builder.cursor(self.source))
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
fn member_copy_limits(
  limits : @builder.Limits,
  allowance : Int,
) -> @builder.Limits {
  {
    ..limits,
    source: {
      ..limits.source,
      max_nodes: limits.source.max_nodes.min(allowance),
    },
    tree: { ..limits.tree, max_nodes: limits.tree.max_nodes.min(allowance), },
  }
}

///|
fn[A] member_copy_construct(
  result : Result[A, @builder.Issue],
  self : MemberResolution,
  at : @wire.Cursor,
  allowance : Int,
) -> A raise Abort {
  match result {
    Ok(value) => value
    Err(@builder.NodeLimit) if allowance <
      self.limits.source.source.max_nodes.min(self.limits.source.tree.max_nodes) =>
      raise Abort(
        Expression({
          issue: @expression.WorkLimit,
          origin: @builder.origin(self.source, at),
        }),
      )
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
  // Lend only the remaining node allowance to the common importer. Its
  // scheduling guard refuses before building an over-budget child tree.
  let allowance = self.work
  self.work = 0
  let copy_limits = member_copy_limits(self.limits.source, allowance)
  let builder = member_construct(@builder.create(self.document, copy_limits))
  let root = member_copy_construct(
    @builder.import_source(builder, self.source, cursor, replace_text=at => {
      self.replacements.get(
        @wire.tree_index(@builder.cursor(self.source), at).unwrap(),
      )
    }),
    self,
    cursor,
    allowance,
  )
  let result = member_construct(@builder.finish(builder, root))
  // Return only unused lent work; failed imports retain their reservation.
  self.work = allowance - @builder.usage(result).nodes
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
fn MemberResolution::has_authored_member(
  self : MemberResolution,
) -> Bool raise Abort {
  let source = self.source
  self.spend(@builder.cursor(source), 1)
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
      ArrayValue(items) => {
        self.spend(cursor, items.length())
        for item in items {
          pending.push(item)
        }
      }
      ObjectValue(_) => {
        self.spend(cursor, @wire.object_length(cursor).unwrap())
        for index in 0..<@wire.object_length(cursor).unwrap() {
          pending.push(@wire.field_at(cursor, index).unwrap().1)
        }
      }
      _ => ()
    }
  }
  false
}

///|
fn MemberResolution::environment(
  self : MemberResolution,
  at : @wire.Cursor,
  rows : @schema.Schema?,
  declarations : @parameters.Declarations?,
) -> @typing.Environment raise Abort {
  let left = []
  let right = []
  if rows is Some(rows) {
    // Account for every field before allocating the projection arrays, and
    // for its admitted name before handing it to common construction.
    self.spend(at, @schema.field_count(rows))
    for index in 0..<@schema.field_count(rows) {
      let field = @schema.field_at(rows, index).unwrap()
      let name = match field.name {
        @schema.Unqualified(name) | @schema.Qualified(_, name) => name
      }
      self.spend(at, name.length())
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
  retain_refusal? : (@typing.Issue) -> Unit = _ => (),
) -> Unit raise Abort {
  // Literal data is not expression structure. All other forms already came
  // from the query lowerer, and the common expression admission still checks
  // each receiver before any field name is selected.
  let work = [(root, false)]
  while work.pop() is Some((cursor, visited)) {
    if self.probe_refused {
      return
    }
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
    let admitted = match
      @expression_syntax.admit(@builder.cursor(normalized), {
        max_nodes: self.limits.source.tree.max_nodes.min(self.work),
        max_depth: self.limits.source.tree.max_depth,
        max_text_bytes: self.limits.source.tree.max_total_string_bytes,
        max_tokens: self.limits.source.tree.max_nodes.min(self.work),
        tree: self.limits.source.tree,
      }) {
      Ok(admitted) => admitted
      Err({ kind: BudgetExceeded, .. }) =>
        raise Abort(
          Expression({
            issue: @expression.WorkLimit,
            origin: @builder.origin(self.source, receiver),
          }),
        )
      Err(_) => {
        self.defer_refusal()
        return
      }
    }
    self.spend(receiver, @expression_syntax.usage(admitted).nodes)
    if rows is None && @expression_syntax.relation_reference_count(admitted) > 0 {
      // Missing producer facts are not proof of an invalid receiver. Leave
      // these members to ordinary checking, and retain independent bindings.
      continue
    }
    let typed = match
      @typing.check(admitted, self.environment(receiver, rows, declarations), {
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
      Err(issue) => {
        retain_refusal(issue)
        self.defer_refusal()
        return
      }
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
      self.replace_member(at, actual)
    }
  }
}

///|
fn member_rows(value : @carrier.Carrier) -> @schema.Schema? {
  @carrier.relation_rows(value).bind(@carrier.complete_schema)
}

///|
// Retain typed Carrier kinds across ToVectors/NEAREST. A schema alone cannot
// represent their producer roles. This is structural information only: pending
// key, profile, capacity and data-validation obligations remain with checking.
fn MemberResolution::relation_carrier(
  self : MemberResolution,
  at : @wire.Cursor,
  schema : @schema.Schema?,
) -> @carrier.Carrier? raise Abort {
  guard schema is Some(schema) else { return None }
  self.spend(at, @schema.field_count(schema))
  Some(@carrier.relation(@carrier.typed_rows(schema)))
}

///|
// Graph construction needs admitted producer definitions to issue its domain.
// Check the resolved prefix through the existing pipeline owner rather
// than manufacturing a domain or extracting a property schema by hand.
fn MemberResolution::prefix_carrier(
  self : MemberResolution,
  steps : Array[@wire.Cursor],
  declarations : @parameters.Declarations?,
  inputs? : Array[(String, @carrier.Carrier)] = [],
  model_tasks? : @environment.ModelTasks? = None,
) -> @carrier.Carrier? raise Abort {
  if self.probe_refused {
    return None
  }
  let at = steps[steps.length() - 1]
  // Hold the remaining copy allowance before importing a prefix. The common
  // importer refuses an over-budget subtree before scheduling its children.
  let allowance = self.work
  self.work = 0
  let builder = member_construct(
    @builder.create(
      self.document,
      member_copy_limits(self.limits.source, allowance),
    ),
  )
  let items = []
  for step in steps {
    items.push(
      member_copy_construct(
        @builder.import_source(builder, self.source, step, replace_text=at => {
          self.replacements.get(
            @wire.tree_index(@builder.cursor(self.source), at).unwrap(),
          )
        }),
        self,
        at,
        allowance,
      ),
    )
  }
  let root = member_copy_construct(
    @builder.add(
      builder,
      @builder.Array(items),
      @builder.origin(self.source, at).unwrap(),
    ),
    self,
    at,
    allowance,
  )
  let copy = member_construct(@builder.finish(builder, root))
  self.work = allowance - @builder.usage(copy).nodes
  match
    @pipeline.check_carriers(
      @builder.cursor(copy),
      inputs,
      declarations,
      None,
      {
        max_steps: self.limits.source.tree.max_nodes,
        max_work: self.work,
        max_nodes: self.limits.source.tree.max_nodes,
        max_tokens: self.limits.source.tree.max_nodes,
        max_text_bytes: self.limits.source.tree.max_total_string_bytes,
        max_depth: self.limits.source.tree.max_depth,
      },
      model_tasks~,
    ) {
    Ok(checked) => {
      self.spend(at, @pipeline.usage(checked).work)
      @pipeline.output_carrier(checked)
    }
    Err({ kind: BudgetExceeded, .. }) =>
      raise Abort(
        Expression({
          issue: @expression.WorkLimit,
          origin: @builder.origin(self.source, at),
        }),
      )
    Err(_) => {
      self.defer_refusal()
      None
    }
  }
}

///|
fn MemberResolution::operation_carrier(
  self : MemberResolution,
  tag : String,
  body : @wire.Cursor,
  input : @carrier.Carrier?,
  names : Map[String, @carrier.Carrier?],
  declarations : @parameters.Declarations?,
) -> @carrier.Carrier? raise Abort {
  if self.probe_refused {
    return None
  }
  if ["to_vectors", "normalize_vectors", "score_vectors", "nearest"].contains(
      tag,
    ) {
    guard input is Some(input) else { return None }
    let queries = if tag == "nearest" {
      member_text(body, "queries").bind(name => {
        names.get(name).bind(value => value)
      })
    } else {
      None
    }
    if tag == "nearest" && queries is None {
      return None
    }
    let copy = self.copy(body)
    let limits : @vector.Limits = {
      max_work: self.work,
      max_nodes: self.limits.source.tree.max_nodes,
      max_depth: self.limits.source.tree.max_depth,
      max_text_bytes: self.limits.source.tree.max_total_string_bytes,
    }
    let checked = if tag == "nearest" {
      @vector.check_nearest(
        @builder.cursor(copy),
        input,
        queries.unwrap(),
        limits,
      ).map(checked => {
        (@vector.nearest_output(checked), @vector.nearest_usage(checked).work)
      })
    } else {
      let operation : @vector.Operation = match tag {
        "to_vectors" => ToVectors
        "normalize_vectors" => NormalizeVectors
        _ => ScoreVectors
      }
      @vector.check(
        operation,
        @builder.cursor(copy),
        input,
        declarations,
        limits,
      ).map(checked => (@vector.output(checked), @vector.usage(checked).work))
    }
    return match checked {
      Ok((output, work)) => {
        self.spend(body, work)
        Some(output)
      }
      Err({ kind: BudgetExceeded, .. }) =>
        raise Abort(
          Expression({
            issue: @expression.WorkLimit,
            origin: @builder.origin(self.source, body),
          }),
        )
      Err(_) => {
        self.defer_refusal()
        None
      }
    }
  }
  self.relation_carrier(
    body,
    self.operation_schema(
      tag,
      body,
      input.bind(member_rows),
      names,
      declarations,
    ),
  )
}

///|
fn MemberResolution::operation_schema(
  self : MemberResolution,
  tag : String,
  body : @wire.Cursor,
  rows : @schema.Schema?,
  names : Map[String, @carrier.Carrier?],
  declarations : @parameters.Declarations?,
) -> @schema.Schema? raise Abort {
  if self.probe_refused {
    return None
  }
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
      Err(_) => {
        self.defer_refusal()
        None
      }
    }
  }
  guard rows is Some(rows) else { return None }
  let copy = self.copy(body)
  let cursor = @builder.cursor(copy)
  if tag == "join" || tag == "cross_join" {
    guard member_text(body, "with").bind(name => {
        names.get(name).bind(value => value).bind(member_rows)
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
        Err(_) => self.defer_refusal()
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
        Err(_) => self.defer_refusal()
      }
    }
    return None
  }
  if tag == "append" {
    guard member_text(body, "with").bind(name => {
        names.get(name).bind(value => value).bind(member_rows)
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
      Err(_) => self.defer_refusal()
    }
    return None
  }
  if tag == "intersect" || tag == "except" {
    guard member_text(body, "with").bind(name => {
        names.get(name).bind(value => value).bind(member_rows)
      })
      is Some(right) else {
      return None
    }
    let operation : @set_shape.Operation = if tag == "intersect" {
      Intersect
    } else {
      Except
    }
    match
      @set_shape.check(operation, cursor, rows, right, {
        max_work: self.work,
        max_text_bytes: self.limits.source.tree.max_total_string_bytes,
        max_nodes: self.limits.source.tree.max_nodes,
        max_depth: self.limits.source.tree.max_depth,
      }) {
      Ok(checked) => {
        self.spend(body, @set_shape.usage(checked).work)
        return Some(@set_shape.output_schema(checked))
      }
      Err({ kind: BudgetExceeded, .. }) =>
        raise Abort(
          Expression({
            issue: @expression.WorkLimit,
            origin: @builder.origin(self.source, body),
          }),
        )
      Err(_) => self.defer_refusal()
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
    Err(_) => {
      self.defer_refusal()
      None
    }
  }
}

///|
// Local Relation declarations use the ordinary authored-input owner. Published
// Source View types instead come from the generation-bound Context attachment.
// These types never authorize acquisition or prove input rows/key uniqueness.
fn MemberResolution::input_schema(
  self : MemberResolution,
  cursor : @wire.Cursor,
) -> @schema.Schema? raise Abort {
  if self.probe_refused || member_text(cursor, "carrier") != Some("relation") {
    return None
  }
  match
    @local_input.read(cursor, {
      max_nodes: self.limits.source.tree.max_nodes.min(self.work),
      max_depth: self.limits.source.tree.max_depth,
      max_text_bytes: self.limits.source.tree.max_total_string_bytes,
    }) {
    Ok(checked) => {
      self.spend(cursor, @local_input.usage(checked).nodes)
      @carrier.relation_rows(@local_input.carrier(checked)).bind(
        @carrier.complete_schema,
      )
    }
    Err(BudgetExceeded) | Err(Contract(ContractIssue(BudgetExceeded, ..))) =>
      raise Abort(
        Expression({
          issue: @expression.WorkLimit,
          origin: @builder.origin(self.source, cursor),
        }),
      )
    Err(_) => {
      self.defer_refusal()
      None
    }
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
  stage_schemas? : Map[(String, String), @schema.Schema?]? = None,
) -> @builder.Source raise Abort {
  let resolution : MemberResolution = {
    source,
    document,
    limits,
    work: limits.max_expression_work,
    output_work: 0,
    probe_refused: false,
    replacements: Map([]),
  }
  if stage_schemas is None && !resolution.has_authored_member() {
    return source
  }
  let root = @builder.cursor(source)
  let stages = member_lookup(root, "stages")
    .bind(cursor => member_success(@wire.elements(cursor)))
    .unwrap()
  let results : Map[(String, String), @schema.Schema?] = stage_schemas.unwrap_or(
    Map([]),
  )
  let originals : Map[String, @carrier.Carrier?] = Map([])
  for (name, schema) in context.input_schemas {
    originals[name] = resolution.relation_carrier(root, Some(schema))
  }
  for input in context.inputs {
    if originals.contains(input.name) {
      continue
    }
    originals[input.name] = match input.source {
      Captured(cursor) =>
        resolution.relation_carrier(cursor, resolution.input_schema(cursor))
      _ => None
    }
  }
  for stage_index, stage in stages {
    if resolution.probe_refused {
      break
    }
    resolution.spend(stage, 1)
    let names : Map[String, @carrier.Carrier?] = Map([])
    let inputs = member_lookup(stage, "inputs").unwrap()
    for index in 0..<@wire.object_length(inputs).unwrap() {
      let (name, declaration) = @wire.field_at(inputs, index).unwrap()
      let rows = if member_lookup(declaration, "result") is Some(reference) {
        match
          (member_text(reference, "stage"), member_text(reference, "result")) {
          (Some(stage), Some(result)) =>
            resolution.relation_carrier(
              declaration,
              results.get((stage, result)).bind(value => value),
            )
          _ => None
        }
      } else {
        originals.get(name).bind(value => value)
      }
      names[name] = rows
    }
    // These schema Carriers supply type facts only. Key assertions in the
    // resolved prefix are checked by the common pipeline, never inferred from
    // ITEM KEY or copied from a differently bound value.
    let prefix_inputs = []
    for (name, carrier) in names {
      if carrier is Some(carrier) {
        prefix_inputs.push((name, carrier))
      }
    }
    let mut current = if names.length() == 1 {
      names.values().to_array()[0]
    } else {
      None
    }
    let prefix = []
    for step in @wire.elements(member_lookup(stage, "steps").unwrap()).unwrap() {
      if resolution.probe_refused {
        break
      }
      resolution.spend(step, 1)
      prefix.push(step)
      if member_text(step, "from") is Some(name) {
        current = names.get(name).bind(value => value)
      }
      let mut output : @carrier.Carrier? = None
      for index in 0..<@wire.object_length(step).unwrap() {
        let (tag, body) = @wire.field_at(step, index).unwrap()
        if ["from", "as", "meta"].contains(tag) {
          continue
        }
        if tag != "values" {
          resolution.expression(
            body,
            current.bind(member_rows),
            context.parameter_declarations,
          )
        }
        if context.source_catalog is Some(catalog) &&
          (
            tag == "graph" ||
            tag == "infer" ||
            (
              current is Some(value) &&
              @carrier.kind(value) == @carrier.GraphKind
            )
          ) {
          output = resolution.source_prefix_carrier(
            stages,
            stage_index,
            prefix,
            catalog,
            context.model_tasks,
          )
        } else if tag == "infer" &&
          context.model_tasks is Some(_) &&
          prefix_inputs.length() == @wire.object_length(inputs).unwrap() {
          output = resolution.prefix_carrier(
            prefix,
            context.parameter_declarations,
            inputs=prefix_inputs,
            model_tasks=context.model_tasks,
          )
        } else if @wire.object_length(inputs) == Some(0) &&
          (
            tag == "graph" ||
            (
              current is Some(value) &&
              @carrier.kind(value) == @carrier.GraphKind
            )
          ) {
          output = resolution.prefix_carrier(
            prefix,
            context.parameter_declarations,
            model_tasks=context.model_tasks,
          )
        } else {
          output = resolution.operation_carrier(
            tag,
            body,
            current,
            names,
            context.parameter_declarations,
          )
        }
      }
      current = output
      if member_text(step, "as") is Some(name) {
        names[name] = current
      }
    }
    if resolution.probe_refused {
      break
    }
    let stage_id = member_text(stage, "id").unwrap()
    let stage_results = member_lookup(stage, "results").unwrap()
    for index in 0..<@wire.object_length(stage_results).unwrap() {
      let (name, body) = @wire.field_at(stage_results, index).unwrap()
      let rows = member_text(body, "from").bind(name => {
        names.get(name).bind(value => value).bind(member_rows)
      })
      results[(stage_id, name)] = resolution.result_schema(body, rows)
    }
  }
  resolution.finish()
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
