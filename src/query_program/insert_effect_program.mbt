///|
/// One original static Mapping selection and its Common-admitted row mapping.
/// This is construction evidence, not installation custody or write authority.
pub struct ResolvedInsertTarget {
  selection : ResolvedUpdateTarget
  row_fields : @environment.MappingRowFields
}

///|
pub fn resolved_insert_target_selection(
  target : ResolvedInsertTarget,
) -> ResolvedUpdateTarget {
  target.selection
}

///|
pub fn resolved_insert_target_row_fields(
  target : ResolvedInsertTarget,
) -> @environment.MappingRowFields {
  target.row_fields
}

///|
fn insert_capture_work(remaining : Ref[Int], amount : Int) -> Unit raise Abort {
  if amount < 0 || amount > remaining.val {
    raise Abort(UpdateTargetBinding(WorkLimit))
  }
  remaining.val -= amount
}

///|
fn finish_insert_target(
  selection : ResolvedUpdateTarget,
  max_work : Int,
) -> Result[ResolvedInsertTarget, UpdateTargetIssue] {
  match @environment.check_mapping_row_fields(selection.mapping, max_work) {
    Ok(row_fields) => Ok({ selection, row_fields, })
    Err(@environment.MappingRowFieldsIssue::WorkLimit) => Err(WorkLimit)
    Err(_) => Err(InvalidPublication)
  }
}

///|
pub fn resolve_insert_effect_target_binding(
  publication : UpdateTargetPublication,
  name : Array[@query.NamePart],
  explicit_mapping : @query.NamePart?,
  max_work : Int,
) -> Result[ResolvedInsertTarget, UpdateTargetIssue] {
  if max_work < 0 {
    return Err(WorkLimit)
  }
  let selection_work = max_work / 2
  let (candidates, remaining) = match
    record_effect_candidates(publication, "create", "none", selection_work) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let selected = match
    resolve_effect_target_candidates(
      publication, candidates, name, explicit_mapping, remaining,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  finish_insert_target(selected, max_work - selection_work)
}

///|
pub fn resolve_concrete_insert_effect_target_binding(
  publication : UpdateTargetPublication,
  target : String,
  mapping_reference : String,
  max_work : Int,
) -> Result[ResolvedInsertTarget, UpdateTargetIssue] {
  if max_work < 0 {
    return Err(WorkLimit)
  }
  let selection_work = max_work / 2
  let (candidates, remaining) = match
    record_effect_candidates(publication, "create", "none", selection_work) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let selected = match
    resolve_concrete_effect_target_candidates(
      publication, candidates, target, mapping_reference, remaining,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  finish_insert_target(selected, max_work - selection_work)
}

///|
fn resolve_insert_effect_target(
  clause : @query.InsertEffectClause,
  publication : UpdateTargetPublication?,
  max_work : Int,
) -> ResolvedInsertTarget raise Abort {
  guard publication is Some(publication) else {
    raise Abort(UpdateTargetBinding(UnresolvedTarget))
  }
  let selected = match clause.target {
    ConcreteTarget(target) => {
      guard clause.mapping is Some(mapping) else {
        raise Abort(UnsupportedEffect)
      }
      resolve_concrete_insert_effect_target_binding(
        publication,
        target,
        mapping.value,
        max_work,
      )
    }
    LogicalTarget(name) =>
      resolve_insert_effect_target_binding(
        publication,
        name,
        clause.mapping,
        max_work,
      )
  }
  match selected {
    Ok(value) => value
    Err(issue) => raise Abort(UpdateTargetBinding(issue))
  }
}

///|
// Every captured column is an actual authored payload value. Literal-only
// VALUES use ordinary derive outputs, preserving input multiplicity without
// an artificial marker, extra Values source or empty Result projection.
fn lower_insert_capture(
  construction : Construction,
  clause : @query.InsertEffectClause,
  target : ResolvedInsertTarget,
  producer : String,
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  physical : Array[String],
  max_work : Int,
  reserved_bindings? : Array[String] = [],
  expression_columns? : Array[(String, String)]? = None,
  value_ranges? : Array[@query.NamePart] = [],
) -> (RetainedResult, Array[Array[(String, @builder.Node)]]) raise Abort {
  guard !clause.fields.is_empty() else { raise Abort(InvalidQuery) }
  if clause.values is Some(values) && values.length() != clause.fields.length() {
    raise Abort(InvalidQuery)
  }
  let expression_visible = expression_columns.unwrap_or(visible)
  let resolve = path => {
    pipe_expression_slot(path, expression_visible, ranges, value_ranges~)
  }
  let fields : Array[String] = []
  let projection : Array[@builder.Node] = []
  let captured : Array[(String, String)] = []
  let derives : Array[(String, @builder.Node)] = []
  let rows = target.row_fields
  let row_count = @environment.mapping_row_fields_count(rows)
  let remaining = Ref(max_work)
  insert_capture_work(remaining, row_count)
  insert_capture_work(remaining, clause.fields.length())
  // create.from consumes the original row_mapping, not an independent payload.
  // Keep the entire declared correspondence and never replace its contract.
  let declared = @environment.mapping_row_fields_names(rows)
  if declared.length() != clause.fields.length() {
    raise Abort(UnsupportedEffect)
  }
  for name in declared {
    insert_capture_work(remaining, clause.fields.length())
    if !clause.fields.any(field => field.value == name) {
      raise Abort(UnsupportedEffect)
    }
  }
  let reserved = physical + declared
  for index in 0..<clause.fields.length() {
    let field = clause.fields[index]
    insert_capture_work(remaining, row_count)
    let matches = Array::makei(row_count, i => {
      @environment.mapping_row_fields_source_at(rows, i).unwrap()
    }).filter(entry => entry.0 == field.value)
    guard matches.length() == 1 && matches[0].1 is Some(source_name) else {
      raise Abort(UnsupportedEffect)
    }
    let slot = match clause.values {
      None =>
        match resolve([field]) {
          Some(slot) => slot
          None => raise Abort(UnknownColumn)
        }
      Some(values) => {
        let expression = values[index]
        let mut root = @query.expression_node(
          expression,
          @query.expression_root(expression),
        ).unwrap()
        while root.kind is Parenthesized(child) {
          root = @query.expression_node(expression, child).unwrap()
        }
        let direct = match root.kind {
          Reference(path) => resolve(path)
          _ => None
        }
        match direct {
          Some(slot) => slot
          None => {
            let slot = pipe_physical_name(reserved, "aql_insert_value_")
            reserved.push(slot)
            derives.push(
              (
                slot,
                append_pipe_expression(
                  construction,
                  expression,
                  expression_visible,
                  ranges,
                  max_work,
                  value_ranges~,
                ),
              ),
            )
            slot
          }
        }
      }
    }
    insert_capture_work(remaining, captured.length())
    let previous = captured.filter(entry => entry.0 == source_name)
    if previous.get(0) is Some(entry) {
      // A shared original source column must denote the same resolved input.
      // Different expressions cannot overwrite one another through an alias.
      if entry.1 != slot {
        raise Abort(UnsupportedEffect)
      }
    } else {
      captured.push((source_name, slot))
      fields.push(source_name)
      projection.push(
        if source_name == slot {
          construction.text(slot)
        } else {
          construction.object([(source_name, construction.text(slot))])
        },
      )
    }
  }
  let steps : Array[Array[(String, @builder.Node)]] = []
  let start = [("from", construction.text(producer))]
  if !derives.is_empty() {
    start.push(("derive", construction.object(derives)))
    steps.push(start)
  }
  let selected = if derives.is_empty() { start } else { [] }
  selected.push(("select", construction.array(projection)))
  let capture = pipe_physical_name(
    reserved_bindings + [producer],
    "aql_insert_capture_",
  )
  reserved_bindings.push(capture)
  selected.push(("as", construction.text(capture)))
  steps.push(selected)
  (
    {
      name: "",
      port: "aql_private_insert",
      from: capture,
      fields,
      terminal: false,
      carrier_complete: false,
      update: None,
      store: false,
      insert: true,
      command: None,
    },
    steps,
  )
}

///|
fn lower_insert_effect(
  construction : Construction,
  clause : @query.InsertEffectClause,
  target : ResolvedInsertTarget,
  default_port : String,
  retained : Array[RetainedResult],
) -> @builder.Node raise Abort {
  let captures = retained.filter(result => result.insert)
  guard captures.length() == 1 else { raise Abort(UnsupportedEffect) }
  let capture = captures[0]
  let name = clause.name.map(part => part.value).unwrap_or("aql_create_effect")
  guard name != "" else { raise Abort(UnsupportedEffect) }
  let (target_ref, mapping_ref) = resolved_update_target(target.selection)
  construction.object([
    (
      name,
      construction.object([
        (
          "create",
          construction.object([
            ("target", construction.text(target_ref)),
            ("mapping", construction.text(mapping_ref)),
            (
              "from",
              construction.object([
                (
                  "result",
                  construction.text(
                    retained_result_port(default_port, capture.port),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    ),
  ])
}
