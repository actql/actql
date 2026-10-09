///|
// Carry the actual retained Result schema into a continuation that needs an
// ARRAY/object star. The existing member/type owners inspect the lowered
// stages; these facts never supply key, presence, order or admission evidence.
fn cte_schema_scope(
  query : @query.Query,
  construction : Construction,
  stages : Array[@builder.Node],
  known : Array[Input],
  context : Context,
  limits : Limits,
) -> Context raise Abort {
  let mut needs_schema = selected_projections(query).any(projection => {
    projection.star is Some(_) && projection.expression is Some(_)
  })
  for index in 0..<@query.operation_count(query) {
    if @query.operation_at(query, index) is Some(UnnestSource(_, _, _)) {
      needs_schema = true
    }
  }
  if !needs_schema || !known.any(input => input.source is StageResult(_, _)) {
    return context
  }
  let root = construction.object([("stages", construction.array(stages))])
  let source = member_construct(@builder.snapshot(construction.builder, root))
  let schemas : Map[(String, String), @schema.Schema?] = Map([])
  let _ = resolve_query_members(
    source,
    @query.query_document(query),
    context,
    limits,
    stage_schemas=Some(schemas),
  )
  let mut inputs = context.input_schemas.copy()
  for input in known {
    if input.source is StageResult(stage, result) {
      // A shadowing CTE must replace the original name's schema as well.
      inputs = inputs.filter(entry => entry.0 != input.name)
      if schemas.get((stage, result)).bind(value => value) is Some(rows) {
        inputs.push((input.name, rows))
      }
    }
  }
  { ..context, input_schemas: inputs, }
}
