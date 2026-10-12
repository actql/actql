///|
// Check the actual unfinished source without a synthetic Unit or Result. Real
// capture definitions, imports and Catalog/local input ownership are retained;
// the returned Carrier does not close publication or value/profile obligations.
fn MemberResolution::source_prefix_carrier(
  self : MemberResolution,
  stages : Array[@wire.Cursor],
  stage_index : Int,
  steps : Array[@wire.Cursor],
  catalog : @environment.SourceRequestContracts,
  model_tasks : @environment.ModelTasks?,
) -> @carrier.Carrier? raise Abort {
  if self.probe_refused {
    return None
  }
  let at = steps[steps.length() - 1]
  let allowance = self.work
  self.work = 0
  let caps : @builder.Limits = {
    ..self.limits.source,
    source: {
      ..self.limits.source.source,
      max_nodes: self.limits.source.source.max_nodes.min(allowance),
    },
    tree: {
      ..self.limits.source.tree,
      max_nodes: self.limits.source.tree.max_nodes.min(allowance),
    },
  }
  let build = member_construct(@builder.create(self.document, caps))
  let generated = @origin.validate_span(
    self.document,
    @wire.cursor_span(at),
    kind=@origin.Generated,
  ).unwrap()
  let construct = fn(
    result : Result[@builder.Node, @builder.Issue],
  ) -> @builder.Node raise Abort {
    match result {
      Ok(node) => node
      Err(@builder.NodeLimit) if allowance <
        self.limits.source.source.max_nodes.min(
          self.limits.source.tree.max_nodes,
        ) =>
        raise Abort(
          Expression({
            issue: @expression.WorkLimit,
            origin: @builder.origin(self.source, at),
          }),
        )
      Err(issue) => raise Abort(Construction(issue))
    }
  }
  let add = fn(value : @builder.Value) -> @builder.Node raise Abort {
    construct(@builder.add(build, value, generated))
  }
  let object = fn(
    fields : Array[(String, @builder.Node)],
  ) -> @builder.Node raise Abort {
    add(
      @builder.Object(
        fields.map(entry => { key: entry.0, value: entry.1, origin: generated, }),
      ),
    )
  }
  let imported = fn(cursor : @wire.Cursor) -> @builder.Node raise Abort {
    construct(
      @builder.import_source(build, self.source, cursor, replace_text=at => {
        self.replacements.get(
          @wire.tree_index(@builder.cursor(self.source), at).unwrap(),
        )
      }),
    )
  }
  let prefix_steps = steps.map(imported)
  let current = stages[stage_index]
  let stage_fields : Array[@builder.Field] = []
  for index in 0..<@wire.object_length(current).unwrap() {
    let (key, value) = @wire.field_at(current, index).unwrap()
    if ["steps", "results", "effects", "table_inputs"].contains(key) {
      continue
    }
    stage_fields.push({
      key,
      value: imported(value),
      origin: @builder.key_origin(self.source, value).unwrap(),
    })
  }
  stage_fields.push({
    key: "steps",
    value: add(@builder.Array(prefix_steps)),
    origin: generated,
  })
  stage_fields.push({ key: "results", value: object([]), origin: generated, })
  let prefix_stages = []
  for prior in stages[:stage_index] {
    prefix_stages.push(imported(prior))
  }
  prefix_stages.push(add(@builder.Object(stage_fields)))
  let root = @builder.cursor(self.source)
  let root_fields : Array[@builder.Field] = []
  for index in 0..<@wire.object_length(root).unwrap() {
    let (key, value) = @wire.field_at(root, index).unwrap()
    if ["stages", "results"].contains(key) {
      continue
    }
    root_fields.push({
      key,
      value: imported(value),
      origin: @builder.key_origin(self.source, value).unwrap(),
    })
  }
  root_fields.push({
    key: "stages",
    value: add(@builder.Array(prefix_stages)),
    origin: generated,
  })
  root_fields.push({ key: "results", value: object([]), origin: generated, })
  let copy = member_construct(
    @builder.finish(build, add(@builder.Object(root_fields))),
  )
  self.work = allowance - @builder.usage(copy).nodes
  // Admission scans the copied structure before Source declarations are read.
  self.spend(at, @builder.usage(copy).nodes)
  let prefix = match
    @program.admit_generated_prefix(copy, self.limits.program) {
    Ok(value) => value
    Err(issue) => raise Abort(Admission(issue))
  }
  let source = match
    @stage_parameters.prepare_prefix(prefix, {
      max_parameters: self.work,
      max_nodes: self.limits.source.tree.max_nodes.min(self.work),
      max_text_bytes: self.limits.source.tree.max_total_string_bytes.min(
        self.work,
      ),
      max_depth: self.limits.source.tree.max_depth,
    }) {
    Ok(value) => value
    Err(
      @stage_parameters.Declarations(
        @parameters.ParameterIssue(BudgetExceeded, ..)
      )
    ) =>
      raise Abort(
        Expression({
          issue: @expression.WorkLimit,
          origin: @builder.origin(self.source, at),
        }),
      )
    Err(issue) => raise Abort(BindingPreparation(Declarations(issue)))
  }
  let declaration_usage = @parameters.declaration_usage(
    @stage_parameters.declarations(source),
  )
  self.spend(at, declaration_usage.0)
  self.spend(at, declaration_usage.1)
  let (views, locals) = match
    @check_context.prepare_source_registrations(
      source,
      catalog,
      {
        max_work: self.work,
        max_nodes: self.limits.source.tree.max_nodes,
        max_text_bytes: self.limits.source.tree.max_total_string_bytes,
        max_depth: self.limits.source.tree.max_depth,
      },
      max_inputs=self.work,
      max_views=self.work,
      max_order_keys=self.work,
    ) {
    Ok(value) => value
    Err(issue) => raise Abort(BindingPreparation(SourceRegistration(issue)))
  }
  // This owner's reported work includes registration and local-input prefixes;
  // bill that aggregate once, rather than discarding or double-billing it.
  let (checked, used) = match
    @check_context.check_sourceview_program(
      views,
      locals,
      {
        max_stages: self.limits.program.max_stages,
        max_steps: self.limits.source.tree.max_nodes,
        max_results: self.limits.source.tree.max_nodes,
        max_work: self.work,
        max_nodes: self.limits.source.tree.max_nodes,
        max_tokens: self.limits.source.tree.max_nodes,
        max_text_bytes: self.limits.source.tree.max_total_string_bytes,
        max_depth: self.limits.source.tree.max_depth,
      },
      model_tasks~,
    ) {
    Ok(value) => value
    Err(@check_context.SourceViewProgramIssue::BudgetExceeded)
    | Err(
      @check_context.SourceViewProgramIssue::Program(
        @stage_results.LocalProgramIssue::BudgetExceeded
      )
    ) =>
      raise Abort(
        Expression({
          issue: @expression.WorkLimit,
          origin: @builder.origin(self.source, at),
        }),
      )
    Err(issue) => raise Abort(BindingPreparation(SourceProgram(issue)))
  }
  self.spend(at, used.work)
  let topology = @check_context.sourceview_checked_topology(checked)
  let stage = @stage_results.topology_stage_source(
    @stage_results.topology_stage_at(topology, stage_index).unwrap(),
  )
  let pipeline = @pipeline_parameters.pipeline(
    @stage_parameters.collection(stage),
  )
  // Read the actual last prefix step; no structural helper was added.
  @pipeline.carrier_at(
    pipeline,
    @pipeline.Step(@pipeline.step_count(pipeline) - 1),
  )
}
