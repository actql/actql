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
) -> Input raise Abort {
  let first = pipe_physical_name(reserved, "aql_data_set_term_")
  reserved.push(first)
  let left = lower_script_relation_term(
    construction, query, known, context, sources, limits, steps, reserved, first,
  )
  let fields = left.visible_fields
  let mut current = left.name
  for index in 0..<@query.set_part_count(query) {
    let part = @query.set_part_at(query, index).unwrap()
    let term = pipe_physical_name(reserved, "aql_data_set_term_")
    reserved.push(term)
    let right = lower_script_relation(
      construction,
      part.right,
      known,
      context,
      sources,
      limits,
      steps,
      reserved,
      term,
    )
    let (matched, alignment_needed) = set_alignment_fields(
      fields,
      right.visible_fields,
      part.by_name,
    )
    let mut right_name = right.name
    if alignment_needed {
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
  {
    relation: [],
    name: output,
    source: StepReference,
    visible_fields: fields,
    graph_bindings: [],
  }
}
