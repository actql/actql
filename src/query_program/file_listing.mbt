///|
pub enum FileListingIssue {
  InstalledSourceRequired
  MissingCatalog
  MissingProfile
  UnsupportedSelector
  InvalidSelector
  FixedSelectorConflict
  Source(@sourceviews.Issue)
  Resolution(@source_resolution.Issue)
  RequestSlots(@request_slots.Issue)
  Request(@source_resolution.RequestIssue)
  ParameterDeclarations(@stage_parameters.Issue)
  Bindings(@bindings.Issue)
  Identity(@encode.EncodeFailure)
}

///|
fn selected_join_input(
  query : @query.Query,
  part : @query.JoinPart,
  context : Context,
  limits : Limits,
) -> Input raise Abort {
  let input = selected_relation(part.relation, context)
  match part.file_listing {
    None => input
    Some(selector) =>
      lower_file_listing_input(query, selector, input, context, limits)
  }
}

///|
// Static Request data, not an expression evaluated by the Frontend. Request
// parameter typing and concrete value admission remain with the common owner.
fn append_file_selector(
  construction : Construction,
  expression : @query.Expression,
  paths : Bool,
  limits : Limits,
) -> @builder.Node raise Abort {
  let mut index = @query.expression_root(expression)
  let mut work = limits.max_expression_work
  while true {
    if work <= 0 {
      raise Abort(FileListing(InvalidSelector))
    }
    work -= 1
    match @query.expression_node(expression, index).unwrap().kind {
      Parenthesized(child) => index = child
      ParameterReference(name) =>
        return construction.object([
          ("$param", construction.parameter_text(name)),
        ])
      StringLiteral(value) if !paths => return construction.text(value)
      ArrayConstructor(elements, annotation) if paths => {
        if annotation is Some(kind) && kind != @query.String {
          raise Abort(FileListing(InvalidSelector))
        }
        let values = []
        for child in elements {
          if work <= 0 {
            raise Abort(FileListing(InvalidSelector))
          }
          work -= 1
          guard @query.expression_node(expression, child).unwrap().kind
            is StringLiteral(value) else {
            raise Abort(FileListing(InvalidSelector))
          }
          values.push(construction.text(value))
        }
        return construction.array(values)
      }
      _ => raise Abort(FileListing(InvalidSelector))
    }
  } nobreak {
    raise Abort(FileListing(InvalidSelector))
  }
}

///|
fn lower_file_listing_input(
  query : @query.Query,
  selector : @query.FileListSelector,
  input : Input,
  context : Context,
  limits : Limits,
) -> Input raise Abort {
  guard input.source is Captured(declaration) &&
    @wire.open_object(declaration) is Ok(object) &&
    @wire.lookup(object, "connector") is Some(_) &&
    @wire.lookup(object, "resource") is Some(_) else {
    raise Abort(FileListing(InstalledSourceRequired))
  }
  guard context.source_catalog is Some(catalog) else {
    raise Abort(FileListing(MissingCatalog))
  }
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
    let request : Array[(String, @builder.Node)] = []
    if @wire.lookup(object, "request") is Some(original) {
      guard @wire.object_length(original) is Some(count) else {
        raise Abort(FileListing(InvalidSelector))
      }
      for index in 0..<count {
        let (name, value) = @wire.field_at(original, index).unwrap()
        if name == "paths" || name == "glob" {
          if !@wire.is_null(value) {
            raise Abort(FileListing(FixedSelectorConflict))
          }
        } else {
          request.push((name, import_query_cursor(construction, value)))
        }
      }
    }
    let (paths, glob, selected) = match selector {
      @query.AllFiles => (construction.add(Null), construction.add(Null), "all")
      @query.ExactPaths(expression) =>
        (
          append_file_selector(construction, expression, true, limits),
          construction.add(Null),
          "paths",
        )
      @query.Glob(expression) =>
        (
          construction.add(Null),
          append_file_selector(construction, expression, false, limits),
          "glob",
        )
    }
    request.push(("paths", paths))
    request.push(("glob", glob))
    let entries = []
    for index in 0..<@wire.object_length(declaration).unwrap() {
      let (name, value) = @wire.field_at(declaration, index).unwrap()
      if name != "request" {
        entries.push((name, import_query_cursor(construction, value)))
      }
    }
    entries.push(("request", construction.object(request)))
    let imported = construction.object(entries)
    // The probe supplies only the real published input to the existing Source
    // resolution and Request owners. It never acquires or executes anything.
    let fields = columns(input)
    let stage = construction.object([
      ("id", construction.text(context.stage_id)),
      ("inputs", construction.object([(input.name, imported)])),
      (
        "steps",
        construction.array([
          construction.object([
            ("from", construction.text(input.name)),
            (
              "select",
              construction.array(fields.map(field => construction.text(field))),
            ),
            ("as", construction.text("aql_file_listing_probe")),
          ]),
        ]),
      ),
      (
        "results",
        construction.object([
          (
            context.stage_result,
            construction.object([
              ("from", construction.text("aql_file_listing_probe")),
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
      Err(issue) => raise Abort(FileListing(ParameterDeclarations(issue)))
    }
    let inputs = match
      @sourceviews.collect(staged, {
        max_work: limits.max_expression_work,
        max_order_keys: limits.source.tree.max_nodes,
      }) {
      Ok(value) => value
      Err(issue) => raise Abort(FileListing(Source(issue)))
    }
    let resolved = match
      @source_resolution.resolve(inputs, catalog, {
        max_work: limits.max_expression_work,
        max_inputs: 1,
        max_views: limits.source.tree.max_nodes,
      }) {
      Ok(value) => value
      Err(issue) => raise Abort(FileListing(Resolution(issue)))
    }
    let resolved_input = @source_resolution.at(resolved, 0).unwrap()
    guard @environment.source_request_file_listing(
        @source_resolution.selected_contract(resolved_input),
      )
      is Some(profile) else {
      raise Abort(FileListing(MissingProfile))
    }
    if !@environment.file_listing_accepts(profile, selected) {
      raise Abort(FileListing(UnsupportedSelector))
    }
    let binding = match
      @bindings.prepare(program, {
        max_bindings: limits.source.tree.max_nodes,
        max_work: limits.max_expression_work,
      }) {
      Ok(value) => value
      Err(issue) => raise Abort(FileListing(Bindings(issue)))
    }
    let slots = match
      @request_slots.collect(staged, binding, {
        max_work: limits.max_expression_work,
        max_slots: limits.source.tree.max_nodes,
      }) {
      Ok(value) => value
      Err(issue) => raise Abort(FileListing(RequestSlots(issue)))
    }
    let requests = match
      @source_resolution.prepare_requests(
        resolved,
        slots,
        limits.max_expression_work,
      ) {
      Ok(value) => value
      Err(issue) => raise Abort(FileListing(Request(issue)))
    }
    match
      @source_resolution.check_direct_request(requests, resolved_input, {
        max_work: limits.max_expression_work,
        max_pairs: limits.source.tree.max_nodes,
        values: {
          max_nodes: limits.source.tree.max_nodes,
          max_depth: limits.source.tree.max_depth,
          max_text_bytes: limits.source.tree.max_total_string_bytes,
        },
      }) {
      Ok(_) => ()
      Err(issue) => raise Abort(FileListing(Request(issue)))
    }
    // Stable semantic Request identity separates repeated installed-source
    // bindings without making source offsets or decoded literal spelling keys.
    let digest = try {
      let writer = @encode.hashing_writer(
        limits.source.max_output_bytes,
        limits.source.tree.max_nodes,
        limits.source.tree.max_depth,
      )
      @program.emit_metadata_stripped_program(program, writer)
      @encode.finish_hash(writer)
    } catch {
      issue => raise Abort(FileListing(Identity(issue)))
    }
    let input_source = @source_resolution.declaration(resolved_input).source
    {
      ..input,
      name: input.name + "_files_" + digest,
      source: Captured(input_source),
    }
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      raise Abort(issue)
    }
  }
}
