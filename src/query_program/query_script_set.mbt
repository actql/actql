///|
// A DATA set is a logical producer composed with the existing relational
// operations. Reuse output alignment and ORDER/LIMIT lowering from root/CTE
// queries; do not introduce Stage Results, acquisition or retained artifacts.
fn lower_script_set_relation(
  construction : Construction,
  query : @query.Query,
  known : Array[Input],
  context : Context,
  sources : ScriptSources,
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
  output : String,
  graphs? : Array[ScriptGraph] = [],
) -> Input raise Abort {
  let first_step = steps.length()
  let first = pipe_physical_name(reserved, "aql_data_set_term_")
  reserved.push(first)
  let left = lower_script_relation_term(
    construction,
    query,
    known,
    context,
    sources,
    limits,
    steps,
    reserved,
    first,
    graphs~,
    set_head=true,
  )
  let sql_inner_count = set_inner_chain_length(query)
  let sql_rights : Array[Input] = []
  let sql_right_starts : Array[Int] = []
  for index in 0..<sql_inner_count {
    let part = @query.set_part_at(query, index).unwrap()
    let term = pipe_physical_name(reserved, "aql_data_set_term_")
    reserved.push(term)
    sql_right_starts.push(steps.length())
    sql_rights.push(
      lower_script_relation(
        construction,
        part.right,
        known,
        context,
        sources,
        limits,
        steps,
        reserved,
        term,
        graphs~,
        positional_set_output=!part.by_name,
      ),
    )
  }
  let sql_inner_fields = if sql_inner_count > 0 {
    Some(
      set_inner_fields(
        left.visible_fields,
        sql_rights.map(input => input.visible_fields),
        @query.set_part_at(query, 0).unwrap(),
      ),
    )
  } else {
    None
  }
  let mut fields = left.visible_fields
  let mut current = left.name
  for index in 0..<@query.set_part_count(query) {
    let part = @query.set_part_at(query, index).unwrap()
    let right_first_step = if index < sql_inner_count {
      sql_right_starts[index]
    } else {
      steps.length()
    }
    let right = if index < sql_inner_count {
      sql_rights[index]
    } else {
      let term = pipe_physical_name(reserved, "aql_data_set_term_")
      reserved.push(term)
      lower_script_relation(
        construction,
        part.right,
        known,
        context,
        sources,
        limits,
        steps,
        reserved,
        term,
        graphs~,
        positional_set_output=!part.by_name,
      )
    }
    let output_fields = if index < sql_inner_count {
      sql_inner_fields.unwrap()
    } else {
      set_output_fields(fields, part, right_fields=right.visible_fields)
    }
    let (left_matched, left_alignment_needed) = set_alignment_fields(
      output_fields,
      fields,
      true,
      allow_subset=part.inner_by_name,
    )
    if left_alignment_needed {
      let aligned = pipe_physical_name(reserved, "aql_data_set_left_")
      reserved.push(aligned)
      steps.push(
        construction.object([
          ("from", construction.text(current)),
          (
            "select",
            set_select_fields(construction, output_fields, left_matched),
          ),
          ("as", construction.text(aligned)),
        ]),
      )
      current = aligned
    }
    fields = output_fields
    let (matched, alignment_needed) = set_alignment_fields(
      fields,
      right.visible_fields,
      part.by_name,
      allow_subset=part.inner_by_name,
    )
    let mut right_name = right.name
    let folded = alignment_needed &&
      !set_operand_retains_result(part.right) &&
      fold_script_set_terminal_select(
        construction,
        steps,
        right_first_step,
        right.name,
        fields,
        matched,
      )
    if alignment_needed && !folded {
      let aligned = pipe_physical_name(reserved, "aql_data_set_aligned_")
      reserved.push(aligned)
      steps.push(
        construction.object([
          ("from", construction.text(right_name)),
          (
            "select",
            construction.array(
              fields.mapi((index, field) => {
                let source = construction.text(matched[index])
                if field == matched[index] {
                  source
                } else {
                  construction.object([(field, source)])
                }
              }),
            ),
          ),
          ("as", construction.text(aligned)),
        ]),
      )
      right_name = aligned
    }
    let combined = pipe_physical_name(reserved, "aql_data_set_combined_")
    reserved.push(combined)
    let (operation, body) = set_operation_body(construction, part, right_name)
    steps.push(
      construction.object([
        ("from", construction.text(current)),
        (operation, body),
        ("as", construction.text(combined)),
      ]),
    )
    current = combined
    if part.kind == "union" && part.duplicates == "distinct" {
      let unique = pipe_physical_name(reserved, "aql_data_set_unique_")
      reserved.push(unique)
      steps.push(
        construction.object([
          ("from", construction.text(current)),
          (
            "distinct",
            construction.array(fields.map(name => construction.text(name))),
          ),
          ("as", construction.text(unique)),
        ]),
      )
      current = unique
    }
  }
  let result = append_set_final_steps(
    construction,
    query,
    limits,
    current,
    fields,
    steps,
    output + "_",
  )
  let rebound = query_has_join_set_operand(query) &&
    !set_operand_retains_result(query) &&
    rebind_script_set_terminal_output(
      construction, steps, first_step, result, output,
    )
  if !rebound {
    steps.push(
      construction.object([
        ("from", construction.text(result)),
        (
          "select",
          construction.array(fields.map(name => construction.text(name))),
        ),
        ("as", construction.text(output)),
      ]),
    )
  }
  {
    relation: [],
    name: output,
    source: StepReference,
    visible_fields: fields,
    graph_bindings: [],
  }
}
