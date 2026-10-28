///|
/// Original core semantic boundaries, not a Resource grant or another checker.
priv enum PipelineCoreReadPhase {
  Inputs
  Parameters
  ImportedEvidence
  DeltaContracts
  Steps
  FinalEvidence
  Complete
  Failed
  Taken
  Cleared
} derive(Eq)

///|
/// Actual original input loop positions. These retain only borrowed inputs and
/// original counters; they grant no resource, key or semantic acceptance.
priv enum PipelineCoreInputStep {
  Name
  SourceFields
  SourceBinding
  Duplicate
  CarrierStart
  Carrier
  Keys
  KeyField
  KeyAlias
  Register
}

///|
priv enum PipelineCoreParameterStep {
  Count
  Name
  Contract
  Select
  Arrays
}

///|
priv enum PipelineCoreImportedStep {
  LiteralInputs
  LiteralDomain
  LiteralRead
  LiteralSteps
  DeltaStart
  DeltaInput
  DeltaField
  DeltaCarrier
  DeltaRegister
  DeltaAppend
  DeltaSteps
}

///|
priv enum PipelineCoreDeltaBindingStep {
  Count
  Name
  Target
  Field
  Carrier
  Register
} derive(Eq)

///|
priv struct PipelineCoreBody {
  source : @decode.Cursor
  inputs : Array[(String, @carrier.Carrier)]
  parameters : @parameter.Declarations?
  from : @decode.Cursor?
  limits : Limits
  calendar_profile : @calendar_profile.Profile?
  text_rank_profile : @text_rank_profile.Profile?
  delta_contracts : Array[
    (String, @schema.FieldName, @graph_contract.CheckedContract),
  ]
  keyed_inputs : Array[@evidence.KeySet?]
  ranked_inputs : Array[@vector.RankingInput?]
  produced_inputs : Array[ProducedInput?]
  input_contracts : Array[InputContract]
  model_tasks : @model_environment.ModelTasks?
  b : Budget
  bodies : Array[@decode.Cursor]
  names : Map[String, Target]
  mut current : Target?
  mut steps : Array[CheckedStep]?
  mut ranked_steps : Array[@vector.RankingInput]?
  mut keyed_steps : Array[@evidence.KeySet?]?
  mut literal_inputs : Array[@evidence.LiteralDomains?]?
  mut literal_steps : Array[@evidence.LiteralDomains?]?
  mut delta_inputs : Array[DeltaEvidence]?
  mut delta_steps : Array[DeltaEvidence]?
  mut phase : PipelineCoreReadPhase
  mut input_step : PipelineCoreInputStep
  mut input_index : Int
  mut source_count : Int
  mut source_index : Int
  mut key_count : Int
  mut key_index : Int
  mut field_count : Int
  mut field_index : Int
  mut alias_count : Int
  mut alias_index : Int
  mut carrier_read : CarrierPreflightRead?
  mut parameter_step : PipelineCoreParameterStep
  mut parameter_index : Int
  mut parameter_read : ContractPreflightRead?
  mut imported_step : PipelineCoreImportedStep
  mut imported_index : Int
  mut literal_read : @evidence.LiteralDomainsRead?
  mut delta_iterator : Iter[(String, @graph_contract.CheckedContract)]?
  mut delta_field : (String, @graph_contract.CheckedContract)?
  mut delta_pending : DeltaEvidence?
  mut delta_completed_storage : @shape.CollectionConstructionExtent
  mut delta_binding_step : PipelineCoreDeltaBindingStep
  mut delta_binding_index : Int
  mut delta_binding_count : Int
  mut delta_binding_target : Int
  mut delta_binding : (
    String,
    @schema.FieldName,
    @graph_contract.CheckedContract,
  )?
  mut delta_binding_key : String?
  mut delta_binding_old : @shape.CollectionConstructionExtent?
  mut delta_bound_name_headers : Int64
  mut delta_bound_name_units : Int64
}

///|
priv enum PipelineCoreState {
  Reading(PipelineCoreBody)
  Completed(CheckedPipeline)
  Rejected(PipelineCoreBody, Issue)
  Taken
  Cleared
}

///|
/// Retains the actual original typed inputs, work budget, names and intermediate
/// evidence. Synchronous and staged consumers drive this SAME semantic body.
priv struct PipelineCoreRead {
  mut state : PipelineCoreState
}

///|
fn begin_pipeline_core_read(
  source : @decode.Cursor,
  supplied_inputs : Array[(String, @carrier.Carrier)],
  parameters : @parameter.Declarations?,
  from : @decode.Cursor?,
  limits : Limits,
  calendar_profile : @calendar_profile.Profile?,
  text_rank_profile : @text_rank_profile.Profile?,
  delta_contracts : Array[
    (String, @schema.FieldName, @graph_contract.CheckedContract),
  ],
  keyed_inputs : Array[@evidence.KeySet?],
  ranked_inputs : Array[@vector.RankingInput?],
  produced_inputs : Array[ProducedInput?],
  input_contracts : Array[InputContract],
  model_tasks : @model_environment.ModelTasks?,
) -> Result[PipelineCoreRead, Issue] {
  begin_pipeline_core_read_owned(
    source, supplied_inputs, parameters, from, limits, calendar_profile, text_rank_profile,
    delta_contracts, keyed_inputs, ranked_inputs, produced_inputs, input_contracts,
    model_tasks,
  ) catch {
    Stop(issue) => Err(issue)
  }
}

///|
fn begin_pipeline_core_read_owned(
  source : @decode.Cursor,
  supplied_inputs : Array[(String, @carrier.Carrier)],
  parameters : @parameter.Declarations?,
  from : @decode.Cursor?,
  limits : Limits,
  calendar_profile : @calendar_profile.Profile?,
  text_rank_profile : @text_rank_profile.Profile?,
  delta_contracts : Array[
    (String, @schema.FieldName, @graph_contract.CheckedContract),
  ],
  keyed_inputs : Array[@evidence.KeySet?],
  ranked_inputs : Array[@vector.RankingInput?],
  produced_inputs : Array[ProducedInput?],
  input_contracts : Array[InputContract],
  model_tasks : @model_environment.ModelTasks?,
) -> Result[PipelineCoreRead, Issue] raise Stop {
  if limits.max_steps < 0 ||
    limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_tokens < 0 ||
    limits.max_depth < 0 {
    fail(source, InvalidLimits)
  }
  let b : Budget = {
    limits,
    work: limits.max_work,
    text: limits.max_text_bytes,
    nodes: limits.max_nodes,
    tokens: limits.max_tokens,
  }
  let bodies = match @decode.elements(source) {
    Ok(v) => v
    Err(_) => fail(source, InvalidBody)
  }
  if bodies.length() > limits.max_steps {
    fail(source, BudgetExceeded)
  }
  spend(b, source, supplied_inputs.length())
  let inputs = supplied_inputs.copy()
  let names : Map[String, Target] = Map([])
  Ok({
    state: Reading({
      source,
      inputs,
      parameters,
      from,
      limits,
      calendar_profile,
      text_rank_profile,
      delta_contracts,
      keyed_inputs,
      ranked_inputs,
      produced_inputs,
      input_contracts,
      model_tasks,
      b,
      bodies,
      names,
      current: None,
      steps: None,
      ranked_steps: None,
      keyed_steps: None,
      literal_inputs: None,
      literal_steps: None,
      delta_inputs: None,
      delta_steps: None,
      phase: Inputs,
      input_step: Name,
      input_index: 0,
      source_count: 0,
      source_index: 0,
      key_count: 0,
      key_index: 0,
      field_count: 0,
      field_index: 0,
      alias_count: 0,
      alias_index: 0,
      carrier_read: None,
      parameter_step: Count,
      parameter_index: 0,
      parameter_read: None,
      imported_step: LiteralInputs,
      imported_index: 0,
      literal_read: None,
      delta_iterator: None,
      delta_field: None,
      delta_pending: None,
      delta_completed_storage: pipeline_core_zero_extent,
      delta_binding_step: Count,
      delta_binding_index: 0,
      delta_binding_count: 0,
      delta_binding_target: 0,
      delta_binding: None,
      delta_binding_key: None,
      delta_binding_old: None,
      delta_bound_name_headers: 0L,
      delta_bound_name_units: 0L,
    }),
  })
}

///|
fn pipeline_core_read_phase(
  original : PipelineCoreRead,
) -> PipelineCoreReadPhase {
  match original.state {
    Reading(body) => body.phase
    Completed(_) => Complete
    Rejected(_, _) => Failed
    Taken => Taken
    Cleared => Cleared
  }
}

///|
fn advance_pipeline_core_read(
  original : PipelineCoreRead,
) -> PipelineCoreReadPhase {
  guard original.state is Reading(body) else {
    return pipeline_core_read_phase(original)
  }
  let next = advance_pipeline_core_read_owned(body) catch {
    Stop(issue) => Err(issue)
  }
  match next {
    Err(issue) => original.state = Rejected(body, issue)
    Ok(Some(checked)) => original.state = Completed(checked)
    Ok(None) => ()
  }
  pipeline_core_read_phase(original)
}

///|
fn take_pipeline_core_read(
  original : PipelineCoreRead,
) -> Result[CheckedPipeline, Issue]? {
  match original.state {
    Completed(checked) => {
      original.state = Taken
      Some(Ok(checked))
    }
    Rejected(_, issue) => {
      original.state = Taken
      Some(Err(issue))
    }
    _ => None
  }
}

///|
fn clear_pipeline_core_read(original : PipelineCoreRead) -> Unit {
  if !(original.state is Taken) {
    match original.state {
      Reading(body) | Rejected(body, _) => {
        if body.carrier_read is Some(read) {
          clear_carrier_preflight_read(read)
        }
        body.carrier_read = None
        if body.parameter_read is Some(read) {
          clear_contract_preflight_read(read)
        }
        body.parameter_read = None
        if body.literal_read is Some(read) {
          @evidence.clear_literal_domains_read(read)
        }
        body.literal_read = None
        body.delta_iterator = None
        body.delta_field = None
        body.delta_pending = None
        body.delta_binding = None
        body.delta_binding_key = None
        body.delta_binding_old = None
        body.phase = Cleared
      }
      _ => ()
    }
    original.state = Cleared
  }
}

///|
fn advance_pipeline_core_read_owned(
  original : PipelineCoreBody,
) -> Result[CheckedPipeline?, Issue] raise Stop {
  let source = original.source
  let inputs = original.inputs
  let parameters = original.parameters
  let from = original.from
  let limits = original.limits
  let calendar_profile = original.calendar_profile
  let text_rank_profile = original.text_rank_profile
  let keyed_inputs = original.keyed_inputs
  let ranked_inputs = original.ranked_inputs
  let produced_inputs = original.produced_inputs
  let input_contracts = original.input_contracts
  let model_tasks = original.model_tasks
  let b = original.b
  let bodies = original.bodies
  let names = original.names
  match original.phase {
    Inputs => advance_pipeline_core_inputs(original)
    Parameters => advance_pipeline_core_parameters(original)
    ImportedEvidence => advance_pipeline_core_imported(original)
    DeltaContracts => advance_pipeline_core_delta_bindings(original)
    Steps => {
      let steps = original.steps.unwrap()
      let ranked_steps = original.ranked_steps.unwrap()
      let keyed_steps = original.keyed_steps.unwrap()
      let literal_inputs = original.literal_inputs.unwrap()
      let literal_steps = original.literal_steps.unwrap()
      let delta_inputs = original.delta_inputs.unwrap()
      let delta_steps = original.delta_steps.unwrap()
      let mut current = original.current
      for body in bodies {
        sync_delta(b, body, delta_inputs, steps, delta_steps)
        sync_keys(
          b, keyed_inputs, steps, keyed_steps, literal_inputs, literal_steps,
        )
        sync_rankings(b, inputs, ranked_inputs, steps, ranked_steps)
        spend(b, body, 1)
        if b.nodes == 0 {
          fail(body, BudgetExceeded)
        }
        b.nodes -= 1
        let object = match @decode.open_object(body) {
          Ok(v) => v
          Err(_) => fail(body, InvalidBody)
        }
        let keys = @decode.object_field_names(body).unwrap()
        spend(b, body, keys.length())
        let mut operation_name : String? = None
        for key in keys {
          charge(b, body, key)
          if key != "from" && key != "as" && key != "meta" {
            if operation_name is Some(_) {
              fail(body, InvalidBody)
            }
            operation_name = Some(key)
          }
        }
        let key = match operation_name {
          Some(v) => v
          None => fail(body, InvalidBody)
        }
        if key == "graph" {
          let at = @decode.lookup(object, key).unwrap()
          if @decode.open_object(at) is Ok(config) &&
            @decode.lookup(config, "version") is None {
            fail(at, Graph(@graph.UnsupportedGraphOperation))
          }
          let step = check_graph_step(
            body, at, object, names, inputs, input_contracts, produced_inputs, steps,
            b,
          )
          let target = Step(steps.length())
          names[step.binding_name.unwrap()] = target
          steps.push(step)
          current = Some(target)
          continue
        }
        if key == "values" {
          if @decode.lookup(object, "from") is Some(s) {
            fail(s, GeneratorFrom)
          }
          let alias_source = match @decode.lookup(object, "as") {
            Some(s) => s
            None => fail(body, GeneratorRequiresAlias)
          }
          let binding = read_name(b, alias_source)
          if names.contains(binding) {
            fail(alias_source, DuplicateName(binding))
          }
          let meta = @decode.lookup(object, "meta")
          if meta is Some(s) {
            metadata(b, s)
          }
          let checked = match
            @values.check(@decode.lookup(object, key).unwrap(), parameters, {
              max_rows: b.nodes,
              max_work: b.work,
              max_nodes: b.nodes,
              max_text_bytes: b.text,
              max_depth: limits.max_depth,
            }) {
            Ok(v) => v
            Err(issue) =>
              raise Stop({
                kind: Values(issue.kind),
                source: issue.source,
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let used = @values.usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: None,
            binding_name: Some(binding),
            metadata: meta,
            operation: Values(checked),
            output: @carrier.relation(
              @carrier.typed_rows(@values.output_schema(checked)),
            ),
            connections: { entries: [], },
            filter_refinement: None,
            window: None,
          })
          names[binding] = target
          current = Some(target)
          continue
        }
        if key == "calendar_bucket" || key == "calendar_series" {
          let generator = key == "calendar_series"
          let main = if generator {
            if @decode.lookup(object, "from") is Some(s) {
              fail(s, GeneratorFrom)
            }
            None
          } else {
            Some(
              match @decode.lookup(object, "from") {
                Some(s) => resolve_target(b, s, names)
                None =>
                  match current {
                    Some(t) => t
                    None => fail(body, MissingCurrent)
                  }
              },
            )
          }
          let binding_name = match @decode.lookup(object, "as") {
            Some(s) => {
              let name = read_name(b, s)
              if names.contains(name) {
                fail(s, DuplicateName(name))
              }
              Some(name)
            }
            None =>
              if generator {
                fail(body, GeneratorRequiresAlias)
              } else {
                None
              }
          }
          let meta = @decode.lookup(object, "meta")
          if meta is Some(s) {
            metadata(b, s)
          }
          let operation_body = @decode.lookup(object, key).unwrap()
          let checked = match
            @calendar.check(
              if generator {
                Series
              } else {
                Bucket
              },
              operation_body,
              main.map(t => carrier(t, inputs, steps)),
              parameters,
              calendar_profile,
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_text_bytes: b.text,
                max_depth: limits.max_depth,
              },
            ) {
            Ok(v) => v
            Err(e) =>
              raise Stop({
                kind: Calendar(e.kind),
                source: operation_body,
                path: e.path.copy(),
                span: e.span,
                range: None,
              })
          }
          let u = @calendar.usage(checked)
          b.work -= u.work
          b.nodes -= u.nodes
          b.text -= u.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: main,
            binding_name,
            metadata: meta,
            operation: Calendar(checked),
            output: @calendar.output(checked),
            connections: {
              entries: match main {
                None => []
                Some(t) => [{ role: Primary, target: t, }]
              },
            },
            filter_refinement: None,
            window: match main {
              None => None
              Some(Step(i)) => steps[i].window
              Some(Input(_)) => None
            },
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "mean_graphs" {
          if @decode.lookup(object, "from") is Some(s) {
            fail(s, GeneratorFrom)
          }
          let alias_source = match @decode.lookup(object, "as") {
            Some(s) => s
            None => fail(body, GeneratorRequiresAlias)
          }
          let binding = read_name(b, alias_source)
          if names.contains(binding) {
            fail(alias_source, DuplicateName(binding))
          }
          if @decode.lookup(object, "meta") is Some(s) {
            metadata(b, s)
          }
          let at = @decode.lookup(object, key).unwrap()
          match
            @graph.check_mean_options(at, {
              max_work: b.work,
              max_nodes: b.nodes,
              max_text_bytes: b.text,
              max_depth: limits.max_depth,
            }) {
            Ok(_) => ()
            Err(e) =>
              raise Stop({
                kind: Graph(e.kind),
                source: at,
                path: e.path.copy(),
                span: e.span,
                range: None,
              })
          }
          let operands = []
          let carriers = []
          let authored = @decode.elements(
            @decode.lookup(@decode.open_object(at).unwrap(), "with").unwrap(),
          ).unwrap()
          for peer in authored {
            let target = resolve_target(b, peer, names)
            operands.push(target)
            carriers.push(carrier(target, inputs, steps))
          }
          // Typed mean owns alignment and all obligations. The ordered sample
          // list never acquires an implicit current input or pairwise union.
          let checked = match
            @graph.check_mean(at, carriers, {
              max_work: b.work,
              max_nodes: b.nodes,
              max_text_bytes: b.text,
              max_depth: limits.max_depth,
            }) {
            Ok(checked) => checked
            Err(e) =>
              raise Stop({
                kind: Graph(e.kind),
                source: at,
                path: e.path.copy(),
                span: e.span,
                range: None,
              })
          }
          let used = @graph.mean_usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: None,
            binding_name: Some(binding),
            metadata: @decode.lookup(object, "meta"),
            operation: GraphMean(inputs=operands, checked~),
            output: @graph.mean_output(checked),
            connections: {
              entries: operands.mapi((index, target) => {
                role: Sample(index),
                target,
              }),
            },
            filter_refinement: None,
            window: None,
          })
          names[binding] = target
          current = Some(target)
          continue
        }
        if key == "time_series" {
          if @decode.lookup(object, "from") is Some(s) {
            fail(s, GeneratorFrom)
          }
          let alias_source = match @decode.lookup(object, "as") {
            Some(s) => s
            None => fail(body, GeneratorRequiresAlias)
          }
          let binding = read_name(b, alias_source)
          if names.contains(binding) {
            fail(alias_source, DuplicateName(binding))
          }
          let meta = @decode.lookup(object, "meta")
          if meta is Some(s) {
            metadata(b, s)
          }
          let checked = match
            @series.check(@decode.lookup(object, key).unwrap(), parameters, {
              max_work: b.work,
              max_nodes: b.nodes,
              max_text_bytes: b.text,
              max_depth: limits.max_depth,
            }) {
            Ok(v) => v
            Err(issue) =>
              raise Stop({
                kind: TimeSeries(issue.kind),
                source: @decode.lookup(object, key).unwrap(),
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let used = @series.usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: None,
            binding_name: Some(binding),
            metadata: meta,
            operation: TimeSeries(checked),
            output: @series.output(checked),
            connections: { entries: [], },
            filter_refinement: None,
            window: None,
          })
          names[binding] = target
          current = Some(target)
          continue
        }
        let op : @relation.Operation? = match key {
          "derive" => Some(Derive)
          "filter" => Some(Filter)
          "select" => Some(Select)
          "rename" => Some(Rename)
          "drop" => Some(Drop)
          "sort" => Some(Sort)
          "take" => Some(Take)
          "distinct" => Some(Distinct)
          "dedupe_rows" => Some(DedupeRows)
          "json_pick" => Some(JsonPick)
          "unnest" => Some(Unnest)
          "assert_rows" => Some(AssertRows)
          "unpivot" => Some(Unpivot)
          "group" => Some(Group)
          "window_group" => Some(Group)
          "pivot" => Some(Pivot)
          "analytic" => Some(Analytic)
          "top_k" => Some(TopK)
          "top_k_by" => Some(TopKBy)
          "lag" => Some(Lag)
          "watermark_rows" => Some(WatermarkRows)
          "join"
          | "append"
          | "nest"
          | "except"
          | "intersect"
          | "cross_join"
          | "interval_join"
          | "asof_join"
          | "sequence"
          | "row_window"
          | "events"
          | "watermark_events"
          | "to_events"
          | "dedupe_events"
          | "session"
          | "normalize_graph"
          | "normalize_vectors"
          | "to_vectors"
          | "score_vectors"
          | "nearest"
          | "pool_vectors"
          | "merge_rankings"
          | "text_rank"
          | "degree"
          | "components"
          | "graph_bounds"
          | "graphs_equal"
          | "graph_diff"
          | "match_nodes"
          | "match_edges"
          | "reach"
          | "subgraph"
          | "traverse"
          | "shortest_path"
          | "graft_graph"
          | "union_graphs"
          | "subtract_graphs"
          | "apply_graph_delta"
          | "vectors"
          | "node_rows"
          | "edge_rows"
          | "window_events" => None
          "infer" | "serialize" => None
          _ =>
            fail(
              @decode.lookup(object, key).unwrap(),
              UnsupportedOperation(key),
            )
        }
        let selected = match @decode.lookup(object, "from") {
          Some(cursor) => {
            let key = read_name(b, cursor)
            match names.get(key) {
              Some(v) => Some(v)
              None => fail(cursor, UnknownName(key))
            }
          }
          None => current
        }
        let operation_body = @decode.lookup(object, key).unwrap()
        let join_object = if key == "join" {
          match @decode.open_object(operation_body) {
            Ok(v) => Some(v)
            Err(_) => fail(operation_body, InvalidBody)
          }
        } else {
          None
        }
        let input = match join_object {
          Some(obj) =>
            match @decode.lookup(obj, "left") {
              Some(s) => resolve_target(b, s, names)
              None =>
                match selected {
                  Some(v) => v
                  None => fail(body, MissingCurrent)
                }
            }
          None =>
            match selected {
              Some(v) => v
              None => fail(body, MissingCurrent)
            }
        }
        let binding_name = match @decode.lookup(object, "as") {
          Some(cursor) => {
            let key = read_name(b, cursor)
            if names.contains(key) {
              fail(cursor, DuplicateName(key))
            }
            Some(key)
          }
          None => None
        }
        let meta = @decode.lookup(object, "meta")
        if meta is Some(cursor) {
          metadata(b, cursor)
        }
        // Projection and the implemented filter/derive/sort/take kernels preserve
        // conditional rows without making conditional fields ordinary values.
        // Distinct's own checker permits only a guaranteed-key projection here.
        // This checked boundary also covers consumers using Knowledge directly,
        // rather than letting them infer dense rows from known field types.
        if key != "select" &&
          key != "drop" &&
          key != "filter" &&
          key != "derive" &&
          key != "sort" &&
          key != "take" &&
          key != "distinct" &&
          key != "group" &&
          key != "serialize" {
          if carrier(input, inputs, steps) is @carrier.Relation(rows) {
            if !@carrier.all_fields_required(rows) {
              fail(
                operation_body,
                Operation(@relation.ConditionalInputNotImplemented),
              )
            }
          }
        }
        if key == "serialize" {
          let checked = check_serialization(
            b,
            operation_body,
            schema(operation_body, input, inputs, steps, allow_conditional=true),
            parameters,
          )
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: Serialize(checked),
            output: @carrier.relation(@carrier.typed_rows(checked.output)),
            connections: { entries: [{ role: Primary, target: input, }], },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "infer" {
          if binding_name is None {
            fail(body, InferRequiresAlias)
          }
          let tasks = match model_tasks {
            Some(tasks) => tasks
            None => fail(operation_body, MissingModelTasks)
          }
          let checked = match
            @evidence.check_infer(
              operation_body,
              carrier(input, inputs, steps),
              key_at(input, keyed_inputs, keyed_steps),
              tasks,
              parameters,
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
                max_text_bytes: b.text,
                max_tokens: b.tokens,
                max_key_fields: b.nodes.min(b.work),
                max_input_roles: b.nodes.min(b.work),
              },
            ) {
            Ok(checked) => checked
            Err(issue) => fail(issue.source, Infer(issue.kind))
          }
          let used = @evidence.infer_usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          b.tokens -= used.tokens
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: Infer(checked),
            output: @carrier.relation(
              @carrier.typed_rows(@evidence.infer_output_schema(checked)),
            ),
            connections: { entries: [{ role: Primary, target: input, }], },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "sequence" {
          let checked = match
            @relation.check_sequence(
              operation_body,
              carrier(input, inputs, steps),
              parameters,
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_text_bytes: b.text,
                max_tokens: b.tokens,
                max_depth: limits.max_depth,
              },
            ) {
            Ok(v) => v
            Err(e) =>
              raise Stop({
                kind: Operation(e.kind),
                source: e.source,
                path: e.path.copy(),
                span: e.span,
                range: e.range,
              })
          }
          let used = @relation.sequence_usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          b.tokens -= used.tokens
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: Sequence(checked),
            output: @carrier.relation(
              @carrier.typed_rows(@relation.sequence_output(checked)),
            ),
            connections: { entries: [{ role: Primary, target: input, }], },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "asof_join" {
          let obj = match @decode.open_object(operation_body) {
            Ok(v) => v
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right_source = match @decode.required(obj, "with") {
            Ok(v) => v
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right = resolve_target(b, right_source, names)
          let checked = match
            @join.check_asof_sources(
              operation_body,
              asof_input_source(input, inputs, steps, keyed_inputs, keyed_steps),
              asof_input_source(right, inputs, steps, keyed_inputs, keyed_steps),
              parameters,
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_text_bytes: b.text,
                max_depth: limits.max_depth,
              },
            ) {
            Ok(v) => v
            Err(e) =>
              raise Stop({
                kind: Join(e.kind),
                source: e.source,
                path: e.path.copy(),
                span: e.span,
                range: None,
              })
          }
          let used = @join.asof_usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: AsOfJoin(right~, checked~),
            output: @carrier.relation(
              @carrier.typed_rows(@join.asof_output_schema(checked)),
            ),
            connections: {
              entries: [
                { role: Left, target: input, },
                { role: Right, target: right, },
              ],
            },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "graphs_equal" {
          let object = match @decode.closed_object(operation_body, ["with"]) {
            Ok(object) => object
            Err(_) => fail(operation_body, InvalidBody)
          }
          let with_at = match @decode.required(object, "with") {
            Ok(at) => at
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right = resolve_target(b, with_at, names)
          let checked = match
            @graph.check_graph_equality(
              operation_body,
              carrier(input, inputs, steps),
              carrier(right, inputs, steps),
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
                max_text_bytes: b.text,
              },
            ) {
            Ok(value) => value
            Err(issue) =>
              raise Stop({
                kind: Graph(issue.kind),
                source: operation_body,
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let used = @graph.graph_equality_usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: GraphEquality(right~, checked~),
            output: @graph.graph_equality_output(checked),
            connections: {
              entries: [
                { role: Left, target: input, },
                { role: Right, target: right, },
              ],
            },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "graph_diff" || key == "apply_graph_delta" {
          let object = match
            @decode.closed_object(
              operation_body,
              if key == "graph_diff" {
                ["with"]
              } else {
                ["with", "field"]
              },
            ) {
            Ok(object) => object
            Err(_) => fail(operation_body, InvalidBody)
          }
          let with_at = match @decode.required(object, "with") {
            Ok(at) => at
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right = resolve_target(b, with_at, names)
          let graph_limits : @graph.Limits = {
            max_work: b.work,
            max_nodes: b.nodes,
            max_depth: limits.max_depth,
            max_text_bytes: b.text,
          }
          let result = if key == "graph_diff" {
            @graph.check_graph_diff(
              operation_body,
              carrier(input, inputs, steps),
              carrier(right, inputs, steps),
              graph_limits,
            )
          } else {
            let field = match @decode.required(object, "field") {
              Ok(field) => field
              Err(_) => fail(operation_body, InvalidBody)
            }
            let field_name = read_name(b, field)
            let expectation = delta_at(right, delta_inputs, delta_steps).fields.get(
              field_name,
            )
            // Read-name charges precede the nested checker; do not grant it the
            // earlier, larger budget after spending on this occurrence.
            @graph.check_apply_graph_delta(
              operation_body,
              carrier(input, inputs, steps),
              carrier(right, inputs, steps),
              expectation,
              { ..graph_limits, max_work: b.work, max_text_bytes: b.text, },
            )
          }
          let checked = match result {
            Ok(checked) => checked
            Err(issue) =>
              raise Stop({
                kind: Graph(issue.kind),
                source: operation_body,
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let used = @graph.delta_usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: GraphDelta(right~, checked~),
            output: @graph.delta_output(checked),
            connections: {
              entries: [
                { role: Left, target: input, },
                { role: Right, target: right, },
              ],
            },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "union_graphs" || key == "graft_graph" {
          let object = match
            @decode.closed_object(
              operation_body,
              if key == "graft_graph" {
                ["with"]
              } else {
                ["with", "merge"]
              },
            ) {
            Ok(object) => object
            Err(_) => fail(operation_body, InvalidBody)
          }
          let at = match @decode.required(object, "with") {
            Ok(at) => at
            Err(_) => fail(operation_body, InvalidBody)
          }
          let peers = if @decode.array_length(at) is Some(count) {
            if count == 0 || key == "graft_graph" {
              fail(at, InvalidBody)
            }
            spend(b, at, count)
            @decode.elements(at).unwrap()
          } else {
            [at]
          }
          let operands = [input]
          let carriers = [carrier(input, inputs, steps)]
          for peer in peers {
            let target = resolve_target(b, peer, names)
            operands.push(target)
            carriers.push(carrier(target, inputs, steps))
          }
          let graph_limits : @graph.Limits = {
            max_work: b.work,
            max_nodes: b.nodes,
            max_text_bytes: b.text,
            max_depth: limits.max_depth,
          }
          let checked = match
            (if key == "graft_graph" {
              @graph.check_graft(operation_body, carriers, graph_limits)
            } else {
              @graph.check_union(operation_body, carriers, graph_limits)
            }) {
            Ok(checked) => checked
            Err(issue) =>
              raise Stop({
                kind: Graph(issue.kind),
                source: operation_body,
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let used = @graph.union_usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: GraphUnion(inputs=operands, checked~),
            output: @graph.union_output(checked),
            connections: {
              entries: operands.mapi((index, target) => {
                role: if index == 0 {
                  Primary
                } else {
                  Sample(index)
                },
                target,
              }),
            },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "subtract_graphs" {
          let object = match
            @decode.closed_object(operation_body, ["with", "merge"]) {
            Ok(object) => object
            Err(_) => fail(operation_body, InvalidBody)
          }
          let at = match @decode.required(object, "with") {
            Ok(at) => at
            Err(_) => fail(operation_body, InvalidBody)
          }
          let right = resolve_target(b, at, names)
          let checked = match
            @graph.check_subtraction(
              operation_body,
              carrier(input, inputs, steps),
              carrier(right, inputs, steps),
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_text_bytes: b.text,
                max_depth: limits.max_depth,
              },
            ) {
            Ok(checked) => checked
            Err(issue) =>
              raise Stop({
                kind: Graph(issue.kind),
                source: operation_body,
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let used = @graph.subtraction_usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: GraphSubtraction(right~, checked~),
            output: @graph.subtraction_output(checked),
            connections: {
              entries: [
                { role: Left, target: input, },
                { role: Right, target: right, },
              ],
            },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "shortest_path" {
          let root = match
            @decode.closed_object(operation_body, [
              "source", "target", "selection", "direction", "max_hops", "weight",
              "edge_types", "max_output_rows",
            ]) {
            Ok(o) => o
            Err(_) => fail(operation_body, InvalidBody)
          }
          let selectors : Array[Target?] = []
          for name in ["source", "target"] {
            let at = match @decode.required(root, name) {
              Ok(c) => c
              Err(_) => fail(operation_body, InvalidBody)
            }
            selectors.push(
              match @decode.open_object(at) {
                Ok(o) =>
                  @decode.lookup(o, "from").map(c => resolve_target(b, c, names))
                Err(_) => None
              },
            )
          }
          let shortest = match
            @graph.check_shortest(
              operation_body,
              carrier(input, inputs, steps),
              selectors[0].map(t => carrier(t, inputs, steps)),
              selectors[1].map(t => carrier(t, inputs, steps)),
              parameters,
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
                max_text_bytes: b.text,
                max_tokens: b.tokens,
              },
            ) {
            Ok(value) => value
            Err(issue) => {
              let diagnostic = @graph.match_diagnostic(issue, operation_body)
              raise Stop({
                kind: GraphMatch(diagnostic.kind),
                source: operation_body,
                path: diagnostic.path.copy(),
                span: diagnostic.span,
                range: diagnostic.range,
              })
            }
          }
          let used = @graph.shortest_usage(shortest)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          b.tokens -= used.tokens
          let entries = [{ role: Primary, target: input, }]
          if selectors[0] is Some(target) {
            entries.push({ role: Right, target, })
          }
          if selectors[1] is Some(target) {
            // Preserve this occurrence even when both selectors read one producer.
            entries.push({ role: Sample(0), target, })
          }
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: Traverse(
              selector=selectors[0],
              checked=@graph.shortest_traversal(shortest),
            ),
            output: @graph.shortest_output(shortest),
            connections: { entries, },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "subgraph" {
          let root = match
            @decode.closed_object(operation_body, ["nodes", "edges"]) {
            Ok(value) => value
            Err(_) => fail(operation_body, InvalidBody)
          }
          let at = match @decode.required(root, "nodes") {
            Ok(value) => value
            Err(_) => fail(operation_body, InvalidBody)
          }
          let selector = match
            @decode.closed_object(at, ["ids", "from", "id", "where"]) {
            Ok(value) => value
            Err(_) => fail(at, InvalidBody)
          }
          let selected = @decode.lookup(selector, "from").map(reference => {
            resolve_target(b, reference, names)
          })
          let checked = match
            @graph.check_subgraph(
              operation_body,
              carrier(input, inputs, steps),
              selected.map(target => carrier(target, inputs, steps)),
              parameters,
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
                max_text_bytes: b.text,
                max_tokens: b.tokens,
              },
            ) {
            Ok(value) => value
            Err(issue) => {
              let diagnostic = @graph.match_diagnostic(issue, operation_body)
              raise Stop({
                kind: GraphMatch(diagnostic.kind),
                source: match issue {
                  MatchStructure(cause) =>
                    cause.source.unwrap_or(operation_body)
                  _ => operation_body
                },
                path: diagnostic.path.copy(),
                span: diagnostic.span,
                range: diagnostic.range,
              })
            }
          }
          let used = @graph.subgraph_usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          b.tokens -= used.tokens
          let entries = [{ role: Primary, target: input, }]
          if selected is Some(target) {
            entries.push({ role: Right, target, })
          }
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: Subgraph(selector=selected, checked~),
            output: @graph.subgraph_output(checked),
            connections: { entries, },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "traverse" || key == "reach" {
          let root = match
            @decode.closed_object(
              operation_body,
              if key == "reach" {
                ["start", "direction", "max_depth"]
              } else {
                [
                  "start", "hops", "direction", "edge_types", "min_hops", "max_hops",
                  "emit", "max_output_rows", "path_mode", "edge_where", "node_where",
                ]
              },
            ) {
            Ok(o) => o
            Err(_) => fail(operation_body, InvalidBody)
          }
          let at = match @decode.required(root, "start") {
            Ok(c) => c
            Err(_) => fail(operation_body, InvalidBody)
          }
          let selector_body = match @decode.open_object(at) {
            Ok(o) => Some(o)
            Err(_) if key == "reach" => None
            Err(_) => fail(at, InvalidBody)
          }
          let selector = selector_body
            .bind(body => @decode.lookup(body, "from"))
            .map(at => resolve_target(b, at, names))
          let caps : @graph.PredicateLimits = {
            max_work: b.work,
            max_nodes: b.nodes,
            max_depth: limits.max_depth,
            max_text_bytes: b.text,
            max_tokens: b.tokens,
          }
          let checked = (if key == "reach" {
            @graph.check_reach
          } else {
            @graph.check_traverse
          })(
            operation_body,
            carrier(input, inputs, steps),
            selector.map(t => carrier(t, inputs, steps)),
            parameters,
            caps,
          ).map(c => {
            (
              Traverse(selector~, checked=c),
              @graph.traverse_output(c),
              @graph.traverse_usage(c),
            )
          })
          let (operation, output, used) = match checked {
            Ok(c) => c
            Err(e) => {
              let d = @graph.match_diagnostic(e, operation_body)
              raise Stop({
                kind: GraphMatch(d.kind),
                source: operation_body,
                path: d.path.copy(),
                span: d.span,
                range: d.range,
              })
            }
          }
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          b.tokens -= used.tokens
          let entries = [{ role: Primary, target: input, }]
          if selector is Some(t) {
            entries.push({ role: Right, target: t, })
          }
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation,
            output,
            connections: { entries, },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "match_nodes" || key == "match_edges" {
          let checked = match
            @graph.check_match(
              if key == "match_nodes" {
                @graph.Nodes
              } else {
                @graph.Edges
              },
              operation_body,
              carrier(input, inputs, steps),
              parameters,
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
                max_text_bytes: b.text,
                max_tokens: b.tokens,
              },
            ) {
            Ok(c) => c
            Err(e) => {
              let d = @graph.match_diagnostic(e, operation_body)
              raise Stop({
                kind: GraphMatch(d.kind),
                source: operation_body,
                path: d.path.copy(),
                span: d.span,
                range: d.range,
              })
            }
          }
          let used = @graph.match_usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          b.tokens -= used.tokens
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: GraphMatch(checked),
            output: @graph.match_output(checked),
            connections: { entries: [{ role: Primary, target: input, }], },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "degree" || key == "graph_bounds" {
          let graph = carrier(input, inputs, steps)
          let (operation, output, used) = if key == "degree" {
            let checked = match
              @graph.check_degree(operation_body, graph, {
                max_work: b.work,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
                max_text_bytes: b.text,
              }) {
              Ok(value) => value
              Err(issue) =>
                raise Stop({
                  kind: Graph(issue.kind),
                  source: operation_body,
                  path: issue.path.copy(),
                  span: issue.span,
                  range: None,
                })
            }
            (
              GraphDegree(checked),
              @graph.degree_output(checked),
              @graph.degree_usage(checked),
            )
          } else {
            let checked = match
              @graph.check_graph_bounds(operation_body, graph, parameters, {
                max_work: b.work,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
                max_text_bytes: b.text,
              }) {
              Ok(value) => value
              Err(issue) =>
                raise Stop({
                  kind: Graph(issue.kind),
                  source: operation_body,
                  path: issue.path.copy(),
                  span: issue.span,
                  range: None,
                })
            }
            (
              GraphBounds(checked),
              @graph.graph_bounds_output(checked),
              @graph.graph_bounds_usage(checked),
            )
          }
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation,
            output,
            connections: { entries: [{ role: Primary, target: input, }], },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "normalize_graph" {
          let checked = match
            @graph.check_normalize(
              operation_body,
              carrier(input, inputs, steps),
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
                max_text_bytes: b.text,
              },
            ) {
            Ok(value) => value
            Err(issue) =>
              raise Stop({
                kind: Graph(issue.kind),
                source: operation_body,
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let used = @graph.normalize_usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: GraphNormalize(checked),
            output: @graph.normalize_output(checked),
            connections: { entries: [{ role: Primary, target: input, }], },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "components" {
          let checked = match
            @graph.check_components(
              operation_body,
              carrier(input, inputs, steps),
              parameters,
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
                max_text_bytes: b.text,
              },
            ) {
            Ok(value) => value
            Err(issue) =>
              raise Stop({
                kind: Graph(issue.kind),
                source: issue.source.unwrap_or(operation_body),
                path: issue.path.copy(),
                span: issue.span,
                range: None,
              })
          }
          let used = @graph.components_usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: GraphComponents(checked),
            output: @graph.components_output(checked),
            connections: { entries: [{ role: Primary, target: input, }], },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "text_rank" {
          let options = vector_result(
            operation_body,
            @vector.read_text_rank_options(operation_body, {
              max_work: b.work,
              max_nodes: b.nodes,
              max_depth: limits.max_depth,
              max_text_bytes: b.text,
            }),
          )
          let u = @vector.text_rank_options_usage(options)
          b.work -= u.work
          b.nodes -= u.nodes
          b.text -= u.text_bytes
          let root = @decode.open_object(operation_body).unwrap()
          let queries = resolve_target(
            b,
            @decode.required(root, "queries").unwrap(),
            names,
          )
          let checked = vector_result(
            operation_body,
            @vector.check_text_rank_inputs(
              options,
              carrier(input, inputs, steps),
              carrier(queries, inputs, steps),
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
                max_text_bytes: b.text,
              },
              profile=text_rank_profile,
            ),
          )
          let u = @vector.text_rank_usage(checked)
          b.work -= u.work
          b.nodes -= u.nodes
          b.text -= u.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: TextRank(queries~, checked~),
            output: @vector.text_rank_output(checked),
            connections: {
              entries: [
                { role: Left, target: input, },
                { role: Right, target: queries, },
              ],
            },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "merge_rankings" {
          let options = vector_result(
            operation_body,
            @vector.read_ranking_options(operation_body, {
              max_work: b.work,
              max_nodes: b.nodes,
              max_depth: limits.max_depth,
              max_text_bytes: b.text,
            }),
          )
          let u = @vector.ranking_options_usage(options)
          b.work -= u.work
          b.nodes -= u.nodes
          b.text -= u.text_bytes
          let root = @decode.open_object(operation_body).unwrap()
          let at = @decode.required(root, "with").unwrap()
          let targets = [input]
          match @decode.view(at) {
            ArrayValue(items) => {
              spend(b, at, items.length())
              for item in items {
                targets.push(resolve_target(b, item, names))
              }
            }
            _ => targets.push(resolve_target(b, at, names))
          }
          spend(b, operation_body, targets.length())
          let ranking_inputs = targets.map(t => {
            ranking_at(t, inputs, ranked_inputs, ranked_steps)
          })
          let checked = vector_result(
            operation_body,
            @vector.check_ranking_fusion(options, ranking_inputs, {
              max_work: b.work,
              max_nodes: b.nodes,
              max_depth: limits.max_depth,
              max_text_bytes: b.text,
            }),
          )
          let u = @vector.merged_ranking_usage(checked)
          b.work -= u.work
          b.nodes -= u.nodes
          b.text -= u.text_bytes
          let edges : Array[InputOccurrence] = []
          for i in 0..<targets.length() {
            edges.push({ role: Sample(i), target: targets[i], })
          }
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: Ranking(checked),
            output: @vector.merged_ranking_output(checked),
            connections: { entries: edges, },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "pool_vectors" {
          let caps : @vector.Limits = {
            max_work: b.work,
            max_nodes: b.nodes,
            max_depth: limits.max_depth,
            max_text_bytes: b.text,
          }
          let result = match carrier(input, inputs, steps) {
            @carrier.Relation(_) => {
              let declaration = key_at(input, keyed_inputs, keyed_steps)
              guard declaration is Some(declaration) else {
                fail(operation_body, MissingKeyEvidence)
              }
              @vector.check_pool_keys(operation_body, declaration, caps)
            }
            other => @vector.check_pool_vectors(operation_body, other, caps)
          }
          let checked = match result {
            Ok(c) => c
            Err(e) =>
              raise Stop({
                kind: Vector(e.kind),
                source: operation_body,
                path: e.path.copy(),
                span: e.span,
                range: None,
              })
          }
          let u = @vector.pooled_usage(checked)
          b.work -= u.work
          b.nodes -= u.nodes
          b.text -= u.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: Pool(checked),
            output: @vector.pooled_output(checked),
            connections: { entries: [{ role: Primary, target: input, }], },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "nearest" {
          let root = match
            @decode.closed_object(operation_body, [
              "queries", "candidate_id", "candidate_vector", "query_id", "query_vector",
              "metric", "k",
            ]) {
            Ok(o) => o
            Err(_) => fail(operation_body, InvalidBody)
          }
          let query_source = match @decode.required(root, "queries") {
            Ok(s) => s
            Err(_) => fail(operation_body, InvalidBody)
          }
          let queries = resolve_target(b, query_source, names)
          let checked = match
            @vector.check_nearest_sources(
              operation_body,
              nearest_input_source(
                input, inputs, steps, keyed_inputs, keyed_steps,
              ),
              nearest_input_source(
                queries, inputs, steps, keyed_inputs, keyed_steps,
              ),
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
                max_text_bytes: b.text,
              },
            ) {
            Ok(c) => c
            Err(e) =>
              raise Stop({
                kind: Vector(e.kind),
                source: operation_body,
                path: e.path.copy(),
                span: e.span,
                range: None,
              })
          }
          let u = @vector.nearest_usage(checked)
          b.work -= u.work
          b.nodes -= u.nodes
          b.text -= u.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: Nearest(queries~, checked~),
            output: @vector.nearest_output(checked),
            connections: {
              entries: [
                { role: Left, target: input, },
                { role: Right, target: queries, },
              ],
            },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "normalize_vectors" ||
          key == "score_vectors" ||
          key == "to_vectors" {
          let operation = match key {
            "to_vectors" => @vector.ToVectors
            "normalize_vectors" => @vector.NormalizeVectors
            _ => @vector.ScoreVectors
          }
          let checked = match
            @vector.check(
              operation,
              operation_body,
              carrier(input, inputs, steps),
              parameters,
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_depth: limits.max_depth,
                max_text_bytes: b.text,
              },
            ) {
            Ok(value) => value
            Err(e) =>
              raise Stop({
                kind: Vector(e.kind),
                source: operation_body,
                path: e.path.copy(),
                span: e.span,
                range: None,
              })
          }
          let used = @vector.usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: Vector(checked),
            output: @vector.output(checked),
            connections: { entries: [{ role: Primary, target: input, }], },
            filter_refinement: None,
            window: None,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "watermark_events" ||
          key == "to_events" ||
          key == "dedupe_events" ||
          key == "session" {
          let check_event = match key {
            "session" =>
              fn(source, input, caps) {
                @event.check_session(source, input, parameters, caps)
              }
            "to_events" => @event.check_bridge
            "dedupe_events" => @event.check_dedupe
            _ =>
              fn(source, input, caps) {
                @event.check_watermark(source, input, caps, parameters~)
              }
          }
          let checked = match
            check_event(operation_body, carrier(input, inputs, steps), {
              max_work: b.work,
              max_nodes: b.nodes,
              max_depth: limits.max_depth,
              max_text_bytes: b.text,
            }) {
            Ok(value) => value
            Err(e) =>
              raise Stop({
                kind: Event(e.kind),
                source: operation_body,
                path: e.path.copy(),
                span: e.span,
                range: None,
              })
          }
          let used = @event.usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let target = Step(steps.length())
          let operation : CheckedOperation = Event(checked)
          let window = transfer_window(
            b, operation_body, input, steps, operation, produced_inputs,
          )
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation,
            output: @event.output(checked),
            connections: { entries: [{ role: Primary, target: input, }], },
            filter_refinement: None,
            window,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "events" ||
          key == "vectors" ||
          key == "node_rows" ||
          key == "edge_rows" {
          let projection = match key {
            "events" => @projection.Events
            "node_rows" => @projection.NodeRows
            "edge_rows" => @projection.EdgeRows
            _ => @projection.Vectors
          }
          let checked = match
            @projection.check(
              projection,
              operation_body,
              carrier(input, inputs, steps),
              {
                max_work: b.work,
                max_nodes: b.nodes,
                max_text_bytes: b.text,
                max_depth: limits.max_depth,
              },
            ) {
            Ok(value) => value
            Err(e) =>
              raise Stop({
                kind: Projection(e.kind),
                source: operation_body,
                path: e.path.copy(),
                span: e.span,
                range: None,
              })
          }
          let used = @projection.usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let operation : CheckedOperation = Projection(checked)
          let window = transfer_window(
            b, operation_body, input, steps, operation, produced_inputs,
          )
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation,
            output: @projection.output(checked),
            connections: { entries: [{ role: Primary, target: input, }], },
            filter_refinement: None,
            window,
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        if key == "row_window" || key == "window_events" {
          let input_carrier = carrier(input, inputs, steps)
          let expected = if key == "row_window" {
            @carrier.RelationKind
          } else {
            @carrier.EventsKind
          }
          if @carrier.kind(input_carrier) != expected {
            fail(operation_body, WrongCarrier(@carrier.kind(input_carrier)))
          }
          let checked = match
            @window.check(operation_body, input_carrier, parameters, {
              max_work: b.work,
              max_nodes: b.nodes,
              max_text_bytes: b.text,
              max_depth: limits.max_depth,
            }) {
            Ok(v) => v
            Err(e) =>
              raise Stop({
                kind: Window(e.kind),
                source: operation_body,
                path: e.path.copy(),
                span: e.span,
                range: None,
              })
          }
          let used = @window.check_usage(checked)
          b.work -= used.work
          b.nodes -= used.nodes
          b.text -= used.text_bytes
          let (start, end) = @window.boundary_fields(
            @window.window_roles(checked),
          )
          let target = Step(steps.length())
          steps.push({
            source: body,
            input: Some(input),
            binding_name,
            metadata: meta,
            operation: Window(checked),
            output: @window.output(checked),
            connections: { entries: [{ role: Primary, target: input, }], },
            filter_refinement: None,
            window: Some({ starts: [start], ends: [end], }),
          })
          if binding_name is Some(name) {
            names[name] = target
          }
          current = Some(target)
          continue
        }
        let mut filter_refinement : @evidence.RefinedFilter? = None
        let (checked, output) = match op {
          Some(op) => {
            let input_schema = schema(
              operation_body,
              input,
              inputs,
              steps,
              allow_conditional=key == "select" ||
                key == "drop" ||
                key == "filter" ||
                key == "derive" ||
                key == "sort" ||
                key == "take" ||
                key == "distinct" ||
                key == "group",
            )
            let operation_limits : @relation.Limits = {
              max_work: b.work,
              max_text_bytes: b.text,
              max_nodes: b.nodes,
              max_tokens: b.tokens,
              max_depth: limits.max_depth,
            }
            let result = if key == "window_group" {
              let evidence = window_at(input, steps, produced_inputs)
              let roles = match evidence {
                Some(v) => v
                None => fail(operation_body, MissingWindowEvidence)
              }
              @relation.check_group_with_prefix(
                operation_body,
                input_schema,
                [roles.starts[0], roles.ends[0]],
                parameters,
                operation_limits,
              )
            } else {
              @relation.check(
                op, operation_body, input_schema, parameters, operation_limits,
              )
            }
            let checked = match result {
              Ok(v) => v
              Err(issue) =>
                raise Stop({
                  kind: Operation(issue.kind),
                  source: issue.source,
                  path: issue.path.copy(),
                  span: issue.span,
                  range: issue.range,
                })
            }
            b.work -= @relation.work_used(checked)
            b.text -= @relation.text_bytes_used(checked)
            b.nodes -= @relation.nodes_used(checked)
            b.tokens -= @relation.tokens_used(checked)
            if op is Filter {
              filter_refinement = infer_filter_refinement(
                b, source, steps, checked,
              )
            }
            (
              if key == "window_group" {
                WindowGroup(checked)
              } else {
                Unary(checked)
              },
              match filter_refinement {
                Some(proof) => @evidence.refined_filter_output(proof)
                None => @relation.output_schema(checked)
              },
            )
          }
          None =>
            if key == "interval_join" {
              let obj = match @decode.open_object(operation_body) {
                Ok(v) => v
                Err(_) => fail(operation_body, InvalidBody)
              }
              let right_source = match @decode.required(obj, "with") {
                Ok(v) => v
                Err(_) => fail(operation_body, InvalidBody)
              }
              let right = resolve_target(b, right_source, names)
              let checked = match
                @join.check_interval(
                  operation_body,
                  schema(operation_body, input, inputs, steps),
                  schema(right_source, right, inputs, steps),
                  parameters,
                  {
                    max_work: b.work,
                    max_text_bytes: b.text,
                    max_nodes: b.nodes,
                    max_depth: limits.max_depth,
                  },
                ) {
                Ok(v) => v
                Err(issue) =>
                  raise Stop({
                    kind: Join(issue.kind),
                    source: issue.source,
                    path: issue.path.copy(),
                    span: issue.span,
                    range: None,
                  })
              }
              let used = @join.interval_usage(checked)
              b.work -= used.work
              b.text -= used.text_bytes
              b.nodes -= used.nodes
              (
                IntervalJoin(right~, checked~),
                @join.interval_output_schema(checked),
              )
            } else if key == "cross_join" {
              let obj = match @decode.open_object(operation_body) {
                Ok(v) => v
                Err(_) => fail(operation_body, InvalidBody)
              }
              let right_source = match @decode.required(obj, "with") {
                Ok(v) => v
                Err(_) => fail(operation_body, InvalidBody)
              }
              let right = resolve_target(b, right_source, names)
              let checked = match
                @join.check_cross(
                  operation_body,
                  schema(operation_body, input, inputs, steps),
                  schema(right_source, right, inputs, steps),
                  parameters,
                  {
                    max_work: b.work,
                    max_text_bytes: b.text,
                    max_nodes: b.nodes,
                    max_depth: limits.max_depth,
                  },
                ) {
                Ok(v) => v
                Err(issue) =>
                  raise Stop({
                    kind: Join(issue.kind),
                    source: issue.source,
                    path: issue.path.copy(),
                    span: issue.span,
                    range: None,
                  })
              }
              let used = @join.cross_usage(checked)
              b.work -= used.work
              b.text -= used.text_bytes
              b.nodes -= used.nodes
              (CrossJoin(right~, checked~), @join.cross_output_schema(checked))
            } else if key == "except" || key == "intersect" {
              let obj = match @decode.open_object(operation_body) {
                Ok(v) => v
                Err(_) => fail(operation_body, InvalidBody)
              }
              let right_source = match @decode.required(obj, "with") {
                Ok(v) => v
                Err(_) => fail(operation_body, InvalidBody)
              }
              let right = resolve_target(b, right_source, names)
              let checked = match
                @set.check(
                  if key == "except" {
                    Except
                  } else {
                    Intersect
                  },
                  operation_body,
                  schema(operation_body, input, inputs, steps),
                  schema(right_source, right, inputs, steps),
                  {
                    max_work: b.work,
                    max_text_bytes: b.text,
                    max_nodes: b.nodes,
                    max_depth: limits.max_depth,
                  },
                ) {
                Ok(v) => v
                Err(issue) =>
                  raise Stop({
                    kind: Set(issue.kind),
                    source: issue.source,
                    path: issue.path.copy(),
                    span: issue.span,
                    range: None,
                  })
              }
              let used = @set.usage(checked)
              b.work -= used.work
              b.text -= used.text_bytes
              b.nodes -= used.nodes
              (Set(right~, checked~), @set.output_schema(checked))
            } else if key == "nest" {
              let obj = match @decode.open_object(operation_body) {
                Ok(v) => v
                Err(_) => fail(operation_body, InvalidBody)
              }
              let right_source = match @decode.required(obj, "with") {
                Ok(v) => v
                Err(_) => fail(operation_body, InvalidBody)
              }
              let right = resolve_target(b, right_source, names)
              let checked = match
                @nest.check(
                  operation_body,
                  schema(operation_body, input, inputs, steps),
                  schema(right_source, right, inputs, steps),
                  parameters,
                  {
                    max_work: b.work,
                    max_text_bytes: b.text,
                    max_nodes: b.nodes,
                    max_depth: limits.max_depth,
                  },
                ) {
                Ok(v) => v
                Err(issue) =>
                  raise Stop({
                    kind: Nest(issue.kind),
                    source: issue.source,
                    path: issue.path.copy(),
                    span: issue.span,
                    range: None,
                  })
              }
              let usage = @nest.usage(checked)
              b.work -= usage.work
              b.text -= usage.text_bytes
              b.nodes -= usage.nodes
              (Nest(right~, checked~), @nest.output_schema(checked))
            } else if key == "append" {
              let obj = match @decode.open_object(operation_body) {
                Ok(v) => v
                Err(_) => fail(operation_body, InvalidBody)
              }
              let right_source = match @decode.required(obj, "with") {
                Ok(v) => v
                Err(_) => fail(operation_body, InvalidBody)
              }
              let right = resolve_target(b, right_source, names)
              let checked = match
                @append.check(
                  operation_body,
                  schema(operation_body, input, inputs, steps),
                  schema(right_source, right, inputs, steps),
                  {
                    max_work: b.work,
                    max_text_bytes: b.text,
                    max_nodes: b.nodes,
                    max_depth: limits.max_depth,
                  },
                ) {
                Ok(v) => v
                Err(issue) =>
                  raise Stop({
                    kind: Append(issue.kind),
                    source: issue.source,
                    path: issue.path.copy(),
                    span: issue.span,
                    range: None,
                  })
              }
              let usage = @append.usage(checked)
              b.work -= usage.work
              b.text -= usage.text_bytes
              b.nodes -= usage.nodes
              (Append(right~, checked~), @append.output_schema(checked))
            } else {
              let obj = join_object.unwrap()
              let right_source = match @decode.required(obj, "with") {
                Ok(v) => v
                Err(_) => fail(operation_body, InvalidBody)
              }
              let right = resolve_target(b, right_source, names)
              let checked = match
                @join.check(
                  operation_body,
                  schema(operation_body, input, inputs, steps),
                  schema(right_source, right, inputs, steps),
                  parameters,
                  {
                    max_work: b.work,
                    max_text_bytes: b.text,
                    max_nodes: b.nodes,
                    max_depth: limits.max_depth,
                  },
                ) {
                Ok(v) => v
                Err(issue) =>
                  raise Stop({
                    kind: Join(issue.kind),
                    source: issue.source,
                    path: issue.path.copy(),
                    span: issue.span,
                    range: None,
                  })
              }
              let usage = @join.usage(checked)
              b.work -= usage.work
              b.text -= usage.text_bytes
              b.nodes -= usage.nodes
              (Join(right~, checked~), @join.output_schema(checked))
            }
        }
        let target = Step(steps.length())
        let connections : Connections = {
          entries: match checked {
            GraphConstruction(inputs~, ..)
            | GraphUnion(inputs~, ..)
            | GraphMean(inputs~, ..) =>
              inputs.mapi((index, target) => { role: Sample(index), target, })
            Values(_) | TimeSeries(_) => []
            Calendar(_) | Pool(_) | Ranking(_) =>
              [{ role: Primary, target: input, }]
            Subgraph(selector~, ..) | Traverse(selector~, ..) => {
              let entries = [{ role: Primary, target: input, }]
              if selector is Some(t) {
                entries.push({ role: Right, target: t, })
              }
              entries
            }
            Unary(_)
            | Serialize(_)
            | Infer(_)
            | Window(_)
            | WindowGroup(_)
            | GraphNormalize(_)
            | Projection(_)
            | GraphMatch(_)
            | GraphBounds(_)
            | GraphDegree(_)
            | GraphEquality(..)
            | GraphComponents(_)
            | Event(_)
            | Sequence(_)
            | Vector(_) => [{ role: Primary, target: input, }]
            Nearest(queries~, ..) | TextRank(queries~, ..) =>
              [
                { role: Left, target: input, },
                { role: Right, target: queries, },
              ]
            Join(right~, ..)
            | Append(right~, ..)
            | Nest(right~, ..)
            | Set(right~, ..)
            | CrossJoin(right~, ..)
            | IntervalJoin(right~, ..)
            | AsOfJoin(right~, ..) =>
              [{ role: Left, target: input, }, { role: Right, target: right, }]
            GraphDelta(right~, ..) | GraphSubtraction(right~, ..) =>
              [{ role: Left, target: input, }, { role: Right, target: right, }]
          },
        }
        steps.push({
          source: body,
          input: Some(input),
          binding_name,
          metadata: meta,
          operation: checked,
          output: @carrier.relation(@carrier.typed_rows(output)),
          connections,
          filter_refinement,
          window: transfer_window(
            b, operation_body, input, steps, checked, produced_inputs,
          ),
        })
        if binding_name is Some(key) {
          names[key] = target
        }
        current = Some(target)
      }
      original.current = current
      original.phase = FinalEvidence
    }
    FinalEvidence => {
      let steps = original.steps.unwrap()
      let ranked_steps = original.ranked_steps.unwrap()
      let keyed_steps = original.keyed_steps.unwrap()
      let literal_inputs = original.literal_inputs.unwrap()
      let literal_steps = original.literal_steps.unwrap()
      let delta_inputs = original.delta_inputs.unwrap()
      let delta_steps = original.delta_steps.unwrap()
      let current = original.current
      sync_delta(b, source, delta_inputs, steps, delta_steps)
      sync_keys(
        b, keyed_inputs, steps, keyed_steps, literal_inputs, literal_steps,
      )
      sync_rankings(b, inputs, ranked_inputs, steps, ranked_steps)
      let join_evidence = derive_join_evidence(
        b, steps, keyed_inputs, keyed_steps,
      )
      spend(b, source, produced_inputs.length())
      spend(b, source, produced_inputs.length())
      let (row_counts, graph_counts) = derive_row_counts(
        b, steps, join_evidence, produced_inputs,
      )
      spend(b, source, produced_inputs.length())
      let input_orders = imported_orders(produced_inputs)
      let (
        logical_orders,
        lag_orders,
        analytic_orders,
        serialization_completions,
      ) = derive_logical_orders(
        b, steps, keyed_inputs, keyed_steps, input_orders, join_evidence,
      )
      return Ok(
        Some({
          input_orders,
          input_contracts,
          produced_inputs,
          logical_orders,
          serialization_completions,
          lag_orders,
          analytic_orders,
          graph_counts,
          join_evidence,
          row_counts,
          ranked_inputs,
          ranked_steps,
          keyed_inputs,
          keyed_steps,
          literal_inputs,
          literal_steps,
          delta_inputs,
          delta_steps,
          source,
          inputs,
          steps,
          names,
          current,
          output: current.map(target => carrier(target, inputs, steps)),
          initial_from: from,
          parameters,
          usage: {
            work: limits.max_work - b.work,
            text_bytes: limits.max_text_bytes - b.text,
            nodes: limits.max_nodes - b.nodes,
            tokens: limits.max_tokens - b.tokens,
          },
        }),
      )
    }
    _ => return Ok(None)
  }
  Ok(None)
}

///|
fn pipeline_core_read_consumed_work(
  read : PipelineCoreRead,
  prefix? : Int = 0,
) -> Int? {
  match read.state {
    Reading(body) => pipeline_core_body_consumed_work(body, prefix)
    Rejected(body, _) =>
      if body.phase == Inputs ||
        body.phase == Parameters ||
        body.phase == ImportedEvidence ||
        body.phase == DeltaContracts {
        pipeline_core_body_consumed_work(body, prefix)
      } else {
        None
      }
    Completed(checked) => Some(prefix + checked.usage.work)
    _ => None
  }
}

///|
fn pipeline_core_body_consumed_work(
  body : PipelineCoreBody,
  prefix : Int,
) -> Int? {
  let consumed = prefix + body.limits.max_work - body.b.work
  if body.phase == ImportedEvidence && body.literal_read is Some(read) {
    guard @evidence.literal_domains_read_consumed_work(read) is Some(nested) else {
      return None
    }
    // Original nested Budget is applied to b only when its transfer completes.
    // Until then retain its actual prefix, including failure, exactly once.
    return Some(consumed + nested)
  }
  Some(consumed)
}
