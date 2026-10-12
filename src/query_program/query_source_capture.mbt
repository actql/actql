///|
// Capture only an independent original request. A keyed template keeps its
// logical JoinRight occurrence; the same Common acquisition Owner classifies
// coverage and later checks every actual consumer. This probe acquires no rows,
// binds no values and grants no authority or complete-Program acceptance.
fn right_source_capture_allowed(
  query : @query.Query,
  input : Input,
  context : Context,
  limits : Limits,
) -> Bool raise Abort {
  if context.captured_stage is None {
    return false
  }
  guard input.source is Captured(declaration) else { return true }
  let document = @query.query_document(query)
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let parameter_names = query_parameter_names(
    context.parameter_declarations,
    limits.max_expression_work,
  )
  let builder = match @builder.create(document, limits.source) {
    Ok(builder) => builder
    Err(issue) => raise Abort(Construction(issue))
  }
  let construction : Construction = {
    builder,
    generated,
    model_tasks: context.model_tasks,
    parameter_names,
  }
  try {
    let fields = columns(input)
    let stage = construction.object([
      ("id", construction.text(context.stage_id)),
      (
        "inputs",
        construction.object([
          (input.name, import_query_cursor(construction, declaration)),
        ]),
      ),
      ("steps", construction.array([])),
      (
        "results",
        construction.object([
          (
            context.stage_result,
            construction.object([
              ("from", construction.text(input.name)),
              (
                "fields",
                construction.array(
                  fields.map(field => construction.text(field)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    ])
    let root = program_root(construction, context, [stage])
    let source = match @builder.finish(builder, root) {
      Ok(source) => source
      Err(issue) => raise Abort(Construction(issue))
    }
    let program = match
      @program.admit_generated_source(source, limits.program) {
      Ok(program) => program
      Err(issue) => raise Abort(Admission(issue))
    }
    let staged = match
      @stage_parameters.prepare(program, {
        max_parameters: limits.source.tree.max_nodes,
        max_nodes: limits.source.tree.max_nodes,
        max_depth: limits.source.tree.max_depth,
        max_text_bytes: limits.source.tree.max_total_string_bytes,
      }) {
      Ok(value) => value
      Err(issue) => raise Abort(BindingPreparation(Declarations(issue)))
    }
    let inputs = match
      @sourceviews.collect(staged, {
        max_work: limits.max_expression_work,
        max_order_keys: limits.source.tree.max_nodes,
      }) {
      Ok(value) => value
      Err(issue) => raise Abort(BindingPreparation(SourceDeclarations(issue)))
    }
    // Inline structural Relation declarations are not SourceView requests.
    guard @sourceviews.at(inputs, 0) is Some(declared) else { return true }
    guard context.source_catalog is Some(catalog) else {
      raise Abort(BindingPreparation(MissingSourceCatalog(declared)))
    }
    let resolved = match
      @source_resolution.resolve(inputs, catalog, {
        max_work: limits.max_expression_work,
        max_inputs: 1,
        max_views: limits.source.tree.max_nodes,
      }) {
      Ok(value) => value
      Err(issue) => raise Abort(BindingPreparation(SourceSelection(issue)))
    }
    let binding = match
      @bindings.prepare(program, {
        max_bindings: limits.source.tree.max_nodes,
        max_work: limits.max_expression_work,
      }) {
      Ok(value) => value
      Err(issue) =>
        raise Abort(BindingPreparation(SourceRequestBindings(issue)))
    }
    let slots = match
      @request_slots.collect(staged, binding, {
        max_work: limits.max_expression_work,
        max_slots: limits.source.tree.max_nodes,
      }) {
      Ok(value) => value
      Err(issue) => raise Abort(BindingPreparation(SourceRequestSlots(issue)))
    }
    let requests = match
      @source_resolution.prepare_requests(
        resolved,
        slots,
        limits.max_expression_work,
      ) {
      Ok(value) => value
      Err(issue) => raise Abort(BindingPreparation(SourceRequest(issue)))
    }
    let form = match
      @source_resolution.check_request_form(
        requests,
        @source_resolution.at(resolved, 0).unwrap(),
        limits.max_expression_work,
      ) {
      Ok(value) => value
      Err(issue) => raise Abort(BindingPreparation(SourceRequestForm(issue)))
    }
    @source_resolution.request_form(form) is @source_resolution.DirectForm
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      raise Abort(issue)
    }
  }
}
