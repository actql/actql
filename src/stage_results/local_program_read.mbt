///|
/// Original compiler-construction boundaries, not permission or resource grants.
pub(all) enum LocalProgramReadPhase {
  LocalInputs
  Imports
  InputRegistration
  Pipeline
  PipelineCarriers
  PipelineKeys
  PipelineRankings
  PipelineCore
  PipelineCoreInputs
  PipelineCoreParameters
  PipelineCoreImportedEvidence
  PipelineCoreDeltaContracts
  PipelineCoreSteps
  PipelineCoreFinalEvidence
  ParameterCollection
  LocalAttachment
  ImportAttachment
  Results
  Projection
  TableInputs
  StagePorts
  Wiring
  Complete
  Failed
  Taken
  Cleared
} derive(Eq, Debug)

///|
priv enum LocalProgramStageRead {
  LocalInputs
  StageImports(
    @syntax.Stage,
    @local.EnvironmentInputs?,
    @local.Prepared,
    @local.Usage
  )
  InputRegistration(
    @syntax.Stage,
    @local.EnvironmentInputs?,
    @local.Prepared,
    @local.Usage,
    ProgramImports,
    Int,
    Int
  )
  Pipeline(
    @local.EnvironmentInputs?,
    @local.Prepared,
    @local.Usage,
    ProgramImports,
    Int,
    Int,
    @decode.ObjectView,
    Array[(String, @pipeline.InputContract)]
  )
  PipelineRead(
    @local.EnvironmentInputs?,
    @local.Prepared,
    @local.Usage,
    ProgramImports,
    Int,
    Int,
    @decode.ObjectView,
    @pipeline.PipelineEvidenceRead
  )
  ParameterCollection(
    @local.EnvironmentInputs?,
    @local.Prepared,
    @local.Usage,
    ProgramImports,
    Int,
    Int,
    @decode.ObjectView,
    @pipeline.CheckedPipeline
  )
  LocalAttachment(
    @local.EnvironmentInputs?,
    @local.Prepared,
    @local.Usage,
    ProgramImports,
    Int,
    Int,
    @decode.ObjectView,
    @pipeline.CheckedPipeline,
    @parameters.CollectedStage,
    Int
  )
  ImportAttachment(
    ProgramImports,
    Int,
    Int,
    @decode.ObjectView,
    @pipeline.CheckedPipeline,
    @parameters.CollectedStage
  )
  Results(
    ProgramAttachedImports,
    Int,
    @decode.ObjectView,
    @pipeline.CheckedPipeline,
    @parameters.CollectedStage
  )
  Projection(
    ProgramAttachedImports,
    Int,
    @decode.ObjectView,
    @pipeline.CheckedPipeline,
    @parameters.CollectedStage,
    @results.CheckedResults,
    Int
  )
  TableInputs(
    ProgramAttachedImports,
    Int,
    @decode.ObjectView,
    @pipeline.CheckedPipeline,
    @parameters.CollectedStage,
    @results.ResultPorts?,
    @results.CheckedResultInputs?,
    @pipeline.ContextualClosure?,
    @results.Usage
  )
  StagePorts(
    ProgramAttachedImports,
    Int,
    @parameters.CollectedStage,
    @results.ResultPorts?,
    @results.CheckedResultInputs?,
    @pipeline.ContextualClosure?,
    @results.Usage,
    @results.CheckedTableInputs?
  )
  Wiring
}

///|
priv struct LocalProgramReadBody {
  source : @parameters.Source
  limits : LocalProgramLimits
  environment : @local.ProgramEnvironmentInputs?
  sourceview_registrations : Array[Array[(String, @pipeline.InputContract)]]?
  calendar_profile : @calendar_profile.Profile?
  model_tasks : @environment.ModelTasks?
  check_only : Bool
  count : Int
  stages : Array[ProgramStage]
  imports : Array[ProgramAttachedImports]
  local_inputs : Array[@local.Attached]
  reconciled_inputs : Array[@local.ReconciledAttachment]
  mut work : Int
  mut nodes : Int
  mut tokens : Int
  mut text : Int
  mut steps : Int
  mut results : Int
  mut wiring_work : Int
  mut wiring_text : Int
  mut index : Int
  mut stage : LocalProgramStageRead
}

///|
priv enum LocalProgramReadState {
  Reading(LocalProgramReadBody)
  Completed(
    Result[(LocalProgramPreparation, LocalProgramUsage), LocalProgramIssue]
  )
  Failed(LocalProgramReadBody, LocalProgramIssue)
  Taken
  Cleared
}

///|
/// A continuation of the original compiler, not a new Resource Owner. The
/// same Source, selected inputs and semantic budgets survive each boundary.
struct LocalProgramRead {
  mut state : LocalProgramReadState
  borrowed_work : Int
  mut inspection_work : Int64
  mut construction_position : Int64
}

///|
/// Fixed continuation controls only. Original typed pipelines, imports,
/// collections, Result/ports bodies and the four staging Arrays are separate.
/// Read1H1R3W; body1H11R11W; Reading/Completed/Failed alternatives3H4R3W;
/// two live Stage variants2H16R8W (component-wise payload maxima7R3W/8R1W,
/// including their tags); advance Result/Some carriers4H4R4W; two owned-work
/// getters10H6R12W and three original-position tuple/Some getters6H3R9W; take Some/error2H2R2W; entry Ok/error2H2R2W.
/// These co-count constructor alternatives, not VM stack frames or a minimum.
pub fn local_program_read_control_construction_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 31L, reference_slots: 49L, scalar_words: 54L, }
}

///|
/// Fixed drivers back each next constructor BEFORE advancing. This entrance
/// runs only the original preflight and creates its original empty collections.
pub fn begin_local_program_read(
  source : @parameters.Source,
  limits : LocalProgramLimits,
  environment? : @local.ProgramEnvironmentInputs? = None,
  sourceview_registrations? : Array[Array[(String, @pipeline.InputContract)]]? = None,
  calendar_profile? : @calendar_profile.Profile? = None,
  model_tasks? : @environment.ModelTasks? = None,
) -> Result[LocalProgramRead, LocalProgramIssue] {
  begin_local_program_read_owned(
    source,
    limits,
    environment~,
    sourceview_registrations~,
    calendar_profile~,
    model_tasks~,
    check_only=false,
  )
}

///|
fn begin_local_program_read_owned(
  source : @parameters.Source,
  limits : LocalProgramLimits,
  environment? : @local.ProgramEnvironmentInputs? = None,
  sourceview_registrations? : Array[Array[(String, @pipeline.InputContract)]]? = None,
  calendar_profile? : @calendar_profile.Profile? = None,
  model_tasks? : @environment.ModelTasks? = None,
  check_only~ : Bool,
) -> Result[LocalProgramRead, LocalProgramIssue] {
  if limits.max_stages < 0 ||
    limits.max_steps < 0 ||
    limits.max_results < 0 ||
    limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_tokens < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if !check_only && @parameters.complete_program(source) is None {
    return Err(CheckOnlyPrefix)
  }
  let count = @parameters.stage_count(source)
  if sourceview_registrations is Some(registrations) &&
    registrations.length() != count {
    return Err(SourceViewStageCount)
  }
  if count > limits.max_stages || count > limits.max_work {
    return Err(BudgetExceeded)
  }
  let mut work = limits.max_work - count
  let mut nodes = limits.max_nodes
  let tokens = limits.max_tokens
  let mut text = limits.max_text_bytes
  let steps = limits.max_steps
  let results = limits.max_results
  let mut borrowed_work = 0
  if environment is Some(inputs) {
    if model_tasks is Some(tasks) &&
      !physical_equal(
        @environment.model_tasks_environment(tasks),
        @local.program_environment(inputs),
      ) {
      return Err(ForeignModelEnvironment)
    }
    if !physical_equal(@local.environment_program(inputs), source) {
      return Err(ForeignEnvironmentSource)
    }
    let used = @local.program_environment_usage(inputs)
    borrowed_work = used.work
    if used.work > work || used.nodes > nodes || used.text_bytes > text {
      return Err(BudgetExceeded)
    }
    work -= used.work
    nodes -= used.nodes
    text -= used.text_bytes
  }
  let stages : Array[ProgramStage] = []
  let imports : Array[ProgramAttachedImports] = []
  let local_inputs : Array[@local.Attached] = []
  let reconciled_inputs : Array[@local.ReconciledAttachment] = []
  // wire_results includes these exact retained prefixes in its reported usage.
  // They have already been charged; refund only those prefixes at that boundary.
  let body : LocalProgramReadBody = {
    source,
    limits,
    environment,
    sourceview_registrations,
    calendar_profile,
    model_tasks,
    check_only,
    count,
    stages,
    imports,
    local_inputs,
    reconciled_inputs,
    work,
    nodes,
    tokens,
    text,
    steps,
    results,
    wiring_work: 0,
    wiring_text: 0,
    index: 0,
    stage: if count == 0 {
      Wiring
    } else {
      LocalInputs
    },
  }
  Ok({
    state: Reading(body),
    borrowed_work,
    inspection_work: 0L,
    construction_position: 0L,
  })
}

///|
pub fn local_program_read_phase(
  original : LocalProgramRead,
) -> LocalProgramReadPhase {
  match original.state {
    Reading(body) =>
      match body.stage {
        LocalInputs => LocalInputs
        StageImports(_, _, _, _) => Imports
        InputRegistration(_, _, _, _, _, _, _) => InputRegistration
        Pipeline(_, _, _, _, _, _, _, _) => Pipeline
        PipelineRead(_, _, _, _, _, _, _, read) =>
          match @pipeline.pipeline_evidence_read_phase(read) {
            Carriers => PipelineCarriers
            Keys => PipelineKeys
            Rankings => PipelineRankings
            Core => PipelineCore
            CoreInputs => PipelineCoreInputs
            CoreParameters => PipelineCoreParameters
            CoreImportedEvidence => PipelineCoreImportedEvidence
            CoreDeltaContracts => PipelineCoreDeltaContracts
            CoreSteps => PipelineCoreSteps
            CoreFinalEvidence => PipelineCoreFinalEvidence
            _ => Failed
          }
        ParameterCollection(_, _, _, _, _, _, _, _) => ParameterCollection
        LocalAttachment(_, _, _, _, _, _, _, _, _, _) => LocalAttachment
        ImportAttachment(_, _, _, _, _, _) => ImportAttachment
        Results(_, _, _, _, _) => Results
        Projection(_, _, _, _, _, _, _) => Projection
        TableInputs(_, _, _, _, _, _, _, _, _) => TableInputs
        StagePorts(_, _, _, _, _, _, _, _) => StagePorts
        Wiring => Wiring
      }
    Completed(Ok(_)) => Complete
    Completed(Err(_)) | Failed(_, _) => Failed
    Taken => Taken
    Cleared => Cleared
  }
}

///|
/// Same original Stage and monotonic constructor position. Repeated
/// same-phase steps remain distinct even when they consume no semantic work.
/// The original Int-sized semantic and input domains bound this count below
/// Int64; it is association DATA, never a work credit or a current callback.
pub fn local_program_read_constructor_position(
  original : LocalProgramRead,
) -> (Int, Int64)? {
  match original.state {
    Reading(body) | Failed(body, _) =>
      Some((body.index, original.construction_position))
    _ => None
  }
}

///|
/// Original successful semantic work and actual constructor-quantity visits,
/// excluding the SAME already-admitted environment prefix. A nested failure
/// has no complete Usage and never becomes zero.
pub fn local_program_read_owned_work(original : LocalProgramRead) -> Int64? {
  let semantic = match original.state {
    Reading(body) => {
      let prefix = match body.stage {
        PipelineRead(_, _, _, _, _, _, _, read) =>
          @pipeline.pipeline_evidence_read_owned_work(read)
        _ => Some(0)
      }
      prefix.map(prefix => {
        body.limits.max_work - body.work - original.borrowed_work + prefix
      })
    }
    Completed(Ok((_, used))) => Some(used.work - original.borrowed_work)
    _ => None
  }
  semantic.bind(semantic => {
    @counts.checked_nonnegative_add_product(
      original.inspection_work,
      semantic.to_int64(),
      1L,
    )
  })
}

///|
/// Actual named metadata visits and original semantic work share one meter.
/// This is a work envelope, NEVER memory demand or a semantic limit increase.
/// Input occurrences are bounded by their original Program nodes. Per input:
/// four pre/post input visits +four optional original container visits; keys
/// use at most three tuple and two retained-buffer visits per Environment node;
/// ranking uses three geometry, two field/name and one retained-map visits.
/// Original semantic caps still run unchanged in every actual callee.
pub fn local_program_read_work_bound(original : LocalProgramRead) -> Int64? {
  guard original.state is Reading(body) &&
    !body.check_only &&
    body.environment is Some(environment) else {
    return None
  }
  let p = @decode.admission_usage(@parameters.source_body(body.source)).nodes.to_int64()
  let e = @environment.usage(@local.program_environment(environment)).1.to_int64()
  let per_environment = if e == 0L {
    Some(0L)
  } else {
    @counts.checked_nonnegative_add_product(0L, p, e)
  }
  guard per_environment is Some(per_environment) &&
    @counts.checked_nonnegative_add_product(body.work.to_int64(), p, 8L)
    is Some(base) else {
    return None
  }
  @counts.checked_nonnegative_add_product(base, per_environment, 11L)
}

///|
fn record_local_program_read_inspection(
  original : LocalProgramRead,
  work : Int64,
) -> Bool {
  match
    @counts.checked_nonnegative_add_product(original.inspection_work, work, 1L) {
    Some(total) => {
      original.inspection_work = total
      true
    }
    None => false
  }
}

///|
/// Advance exactly one original constructor boundary. No current callback or
/// capacity decision is hidden here; the fixed parent backs this step first.
pub fn advance_local_program_read(
  original : LocalProgramRead,
) -> LocalProgramReadPhase {
  guard original.state is Reading(body) else {
    return local_program_read_phase(original)
  }
  original.construction_position += 1L
  match advance_local_program_read_owned(body) {
    Err(issue) => original.state = Failed(body, issue)
    Ok(Some(completed)) => original.state = Completed(Ok(completed))
    Ok(None) => ()
  }
  local_program_read_phase(original)
}

///|
pub fn take_local_program_read(
  original : LocalProgramRead,
) -> Result[(LocalProgramPreparation, LocalProgramUsage), LocalProgramIssue]? {
  match original.state {
    Completed(result) => {
      original.state = Taken
      Some(result)
    }
    Failed(_, issue) => {
      original.state = Taken
      Some(Err(issue))
    }
    _ => None
  }
}

///|
/// Drop this continuation's roots only. A taken original result keeps all of
/// its legitimate Source/pipeline/Result aliases; this is no physical ACK.
pub fn clear_local_program_read(original : LocalProgramRead) -> Unit {
  if !(original.state is Taken) {
    match original.state {
      Reading(body) | Failed(body, _) =>
        match body.stage {
          PipelineRead(_, _, _, _, _, _, _, read) =>
            @pipeline.clear_pipeline_evidence_read(read)
          _ => ()
        }
      _ => ()
    }
    original.state = Cleared
  }
}

///|
fn advance_local_program_read_owned(
  read : LocalProgramReadBody,
) -> Result[(LocalProgramPreparation, LocalProgramUsage)?, LocalProgramIssue] {
  let source = read.source
  let limits = read.limits
  let environment = read.environment
  let sourceview_registrations = read.sourceview_registrations
  let calendar_profile = read.calendar_profile
  let model_tasks = read.model_tasks
  let check_only = read.check_only
  let count = read.count
  let stages = read.stages
  let imports = read.imports
  let local_inputs = read.local_inputs
  let reconciled_inputs = read.reconciled_inputs
  let i = read.index
  let mut work = read.work
  let mut nodes = read.nodes
  let mut tokens = read.tokens
  let mut text = read.text
  let mut steps = read.steps
  let mut results = read.results
  let mut wiring_work = read.wiring_work
  let mut wiring_text = read.wiring_text
  match read.stage {
    LocalInputs => {
      let stage = @parameters.stage_at(source, i).unwrap()
      let declared_imports = @syntax.import_count(stage)
      if declared_imports > work {
        return Err(BudgetExceeded)
      }
      work -= declared_imports
      for j in 0..<declared_imports {
        let (name, port) = @syntax.import_at(stage, j).unwrap()
        match port {
          @syntax.Receipt(..) => return Err(UnsupportedReceipt(i, name))
          @syntax.Result(..) => ()
        }
      }
      let reconciled = environment.map(inputs => {
        @local.program_environment_stage(inputs, i).unwrap()
      })
      let prepared = match reconciled {
        Some(inputs) =>
          @local.snapshot_inputs(@local.environment_assertions(inputs))
        None =>
          match
            @local.prepare(source, i, {
              max_work: work,
              max_nodes: nodes,
              max_text_bytes: text,
              max_depth: limits.max_depth,
            }) {
            Err(e) => return Err(LocalInput(i, e))
            Ok(v) => v
          }
      }
      let local_used : @local.Usage = match reconciled {
        None => @local.usage(prepared)
        Some(_) => { work: 0, nodes: 0, text_bytes: 0, }
      }
      work -= local_used.work
      nodes -= local_used.nodes
      text -= local_used.text_bytes
      read.stage = StageImports(stage, reconciled, prepared, local_used)
    }
    StageImports(stage, reconciled, prepared, local_used) => {
      let resolved = match
        resolve_program_imports(
          source,
          i,
          stages,
          { max_work: work, max_imports: work, max_text_bytes: text, },
          check_only,
        ) {
        Err(e) => return Err(Import(i, e))
        Ok(v) => v
      }
      let (import_work, import_text) = program_import_usage(resolved)
      work -= import_work
      text -= import_text
      read.stage = InputRegistration(
        stage, reconciled, prepared, local_used, resolved, import_work, import_text,
      )
    }
    InputRegistration(
      stage,
      reconciled,
      prepared,
      local_used,
      resolved,
      import_work,
      import_text
    ) => {
      let local_count = @local.count(prepared)
      let resolved_count = program_import_count(resolved)
      let remote = match sourceview_registrations {
        Some(registrations) => registrations[i]
        None => []
      }
      let remote_count = remote.length()
      if local_count > work ||
        resolved_count > work - local_count ||
        remote_count > work - local_count - resolved_count {
        return Err(BudgetExceeded)
      }
      work -= local_count + resolved_count + remote_count
      let body = @decode.open_object(@syntax.stage_body(stage)).unwrap()
      let authored_inputs = @decode.required(body, "inputs").unwrap()
      if @decode.object_length(authored_inputs).unwrap() -
        local_count -
        resolved_count !=
        remote_count {
        return Err(MissingSourceViewRegistrations(i))
      }
      let inputs = []
      for j in 0..<local_count {
        inputs.push(
          match reconciled {
            None => @local.input_at(prepared, j).unwrap()
            Some(checked) => @local.environment_input_at(checked, j).unwrap()
          },
        )
      }
      for j in 0..<resolved_count {
        let (name, input) = program_import_at(resolved, j)
        inputs.push((name, @pipeline.ProducedInput(input)))
      }
      let names : Map[String, Unit] = Map([])
      for (name, registration) in remote {
        if name.length() > work {
          return Err(BudgetExceeded)
        }
        work -= name.length()
        guard @local.sourceview_inputs(prepared) is Some(partition) else {
          return Err(InvalidSourceViewRegistration(i, name))
        }
        if @sourceviews.input_for(partition, i, name) is None ||
          names.contains(name) ||
          !(registration is @pipeline.SourceViewInput(_, _, _, _)) {
          return Err(InvalidSourceViewRegistration(i, name))
        }
        names[name] = ()
        inputs.push((name, registration))
      }
      read.stage = Pipeline(
        reconciled, prepared, local_used, resolved, import_work, import_text, body,
        inputs,
      )
    }
    Pipeline(
      reconciled,
      prepared,
      local_used,
      resolved,
      import_work,
      import_text,
      body,
      inputs
    ) => {
      let pipeline_read = match
        @pipeline.begin_pipeline_evidence_read(
          @decode.required(body, "steps").unwrap(),
          inputs,
          Some(@parameters.declarations(source)),
          @decode.lookup(body, "from"),
          {
            max_steps: steps,
            max_work: work,
            max_nodes: nodes,
            max_tokens: tokens,
            max_text_bytes: text,
            max_depth: limits.max_depth,
          },
          calendar_profile~,
          model_tasks~,
        ) {
        Err(e) => return Err(Pipeline(i, e))
        Ok(v) => v
      }
      read.stage = PipelineRead(
        reconciled, prepared, local_used, resolved, import_work, import_text, body,
        pipeline_read,
      )
    }
    PipelineRead(
      reconciled,
      prepared,
      local_used,
      resolved,
      import_work,
      import_text,
      body,
      pipeline_read
    ) => {
      let phase = @pipeline.advance_pipeline_evidence_read(pipeline_read)
      if phase != @pipeline.Complete && phase != @pipeline.Failed {
        return Ok(None)
      }
      let pipeline = match
        @pipeline.take_pipeline_evidence_read(pipeline_read).unwrap() {
        Err(issue) => return Err(Pipeline(i, issue))
        Ok(pipeline) => pipeline
      }
      let used = @pipeline.usage(pipeline)
      work -= used.work
      nodes -= used.nodes
      tokens -= used.tokens
      text -= used.text_bytes
      steps -= @pipeline.step_count(pipeline)
      read.stage = ParameterCollection(
        reconciled, prepared, local_used, resolved, import_work, import_text, body,
        pipeline,
      )
    }
    ParameterCollection(
      reconciled,
      prepared,
      local_used,
      resolved,
      import_work,
      import_text,
      body,
      pipeline
    ) => {
      let collected = match
        @parameters.collect(source, i, pipeline, {
          max_work: work,
          max_slots: work,
          max_references: work,
          max_pointer_units: work,
          max_direct_text_bytes: text,
        }) {
        Err(e) => return Err(Collection(i, e))
        Ok(v) => v
      }
      let collection_work = @parameters.collection_work(collected)
      work -= collection_work
      text -= @collection.direct_text_bytes(@parameters.collection(collected))
      read.stage = LocalAttachment(
        reconciled, prepared, local_used, resolved, import_work, import_text, body,
        pipeline, collected, collection_work,
      )
    }
    LocalAttachment(
      reconciled,
      prepared,
      local_used,
      resolved,
      import_work,
      import_text,
      body,
      pipeline,
      collected,
      collection_work
    ) => {
      match reconciled {
        Some(checked) => {
          let prior = @local.environment_usage(checked).work
          let attachment = match
            @local.attach_reconciled(
              checked,
              collected,
              max_work=work + prior + collection_work,
            ) {
            Ok(v) => v
            Err(e) => return Err(LocalInput(i, e))
          }
          work -= @local.reconciled_work(attachment) - prior - collection_work
          reconciled_inputs.push(attachment)
        }
        None => {
          let input_attachment = match
            @local.attach(
              prepared,
              collected,
              max_work=work + local_used.work + collection_work,
            ) {
            Err(e) => return Err(LocalInput(i, e))
            Ok(v) => v
          }
          work -= @local.attached_work(input_attachment) -
            local_used.work -
            collection_work
          local_inputs.push(input_attachment)
        }
      }
      read.stage = ImportAttachment(
        resolved, import_work, import_text, body, pipeline, collected,
      )
    }
    ImportAttachment(
      resolved,
      import_work,
      import_text,
      body,
      pipeline,
      collected
    ) => {
      let attached = match
        attach_program_imports(resolved, collected, work + import_work) {
        Err(e) => return Err(Import(i, e))
        Ok(v) => v
      }
      work -= program_attached_work(attached) - import_work
      read.stage = Results(attached, import_text, body, pipeline, collected)
    }
    Results(attached, import_text, body, pipeline, collected) => {
      let checked = match
        @results.check_inventory(
          pipeline,
          @decode.required(body, "results").unwrap(),
          {
            max_results: results,
            max_work: work,
            max_nodes: nodes,
            max_text_bytes: text,
            max_depth: limits.max_depth,
          },
        ) {
        Err(e) => return Err(Results(i, e))
        Ok(v) => v
      }
      let result_count = @results.count(checked)
      results -= result_count
      let used = @results.usage(checked)
      work -= used.work
      nodes -= used.nodes
      text -= used.text_bytes
      read.stage = Projection(
        attached, import_text, body, pipeline, collected, checked, result_count,
      )
    }
    Projection(
      attached,
      import_text,
      body,
      pipeline,
      collected,
      checked,
      result_count
    ) => {
      let (publication, projected, contextual, projection_used) = if check_only {
        let contextual = match
          @pipeline.resolve_contextual_closure(
            pipeline,
            max_steps=work,
            max_work=work,
            max_text_bytes=text,
          ) {
          Err(e) =>
            return Err(
              Order(
                i,
                if physical_equal(e.pipeline, pipeline) {
                  @results.PipelineOrder(e.issue)
                } else {
                  @results.ProducerOrder(e)
                },
              ),
            )
          Ok(v) => v
        }
        let (order_work, order_text) = @pipeline.contextual_closure_usage(
          contextual,
        )
        let inputs = match
          @results.prepare_checked_inputs(checked, {
            max_results: result_count,
            max_work: work - order_work,
            max_nodes: nodes,
            max_text_bytes: text - order_text,
            max_depth: limits.max_depth,
          }) {
          Err(e) => return Err(Ports(i, e))
          Ok(v) => v
        }
        let used = @results.checked_inputs_usage(inputs)
        (
          None,
          Some(inputs),
          Some(contextual),
          {
            ..used,
            work: used.work + order_work,
            text_bytes: used.text_bytes + order_text,
          },
        )
      } else {
        let orders = match
          @results.resolve_all_orders(checked, {
            // Contextual traversal includes earlier producers, not new source steps.
            max_steps: work,
            max_results: result_count,
            max_work: work,
            max_text_bytes: text,
          }) {
          Err(e) => return Err(Order(i, e))
          Ok(v) => v
        }
        // prepare_ports includes the orders' prefix; bill the combined result once.
        let ports = match
          @results.prepare_ports(orders, {
            max_results: result_count,
            max_work: work,
            max_nodes: nodes,
            max_text_bytes: text,
            max_depth: limits.max_depth,
          }) {
          Err(e) => return Err(Ports(i, e))
          Ok(v) => v
        }
        let used = @results.ports_usage(ports)
        (Some(ports), None, None, used)
      }
      work -= projection_used.work
      nodes -= projection_used.nodes
      text -= projection_used.text_bytes
      read.stage = TableInputs(
        attached, import_text, body, pipeline, collected, publication, projected,
        contextual, projection_used,
      )
    }
    TableInputs(
      attached,
      import_text,
      body,
      pipeline,
      collected,
      publication,
      projected,
      contextual,
      projection_used
    ) => {
      let table_inputs = match @decode.lookup(body, "table_inputs") {
        None => None
        Some(source) => {
          let inputs = match
            @results.check_table_inputs(pipeline, source, {
              max_results: results,
              max_work: work,
              max_nodes: nodes,
              max_text_bytes: text,
              max_depth: limits.max_depth,
            }) {
            Ok(inputs) => inputs
            Err(issue) => return Err(TableInputs(i, issue))
          }
          results -= @results.table_input_count(inputs)
          let table_used = @results.table_inputs_usage(inputs)
          work -= table_used.work
          nodes -= table_used.nodes
          text -= table_used.text_bytes
          wiring_work += table_used.work
          wiring_text += table_used.text_bytes
          Some(inputs)
        }
      }
      read.stage = StagePorts(
        attached, import_text, collected, publication, projected, contextual, projection_used,
        table_inputs,
      )
    }
    StagePorts(
      attached,
      import_text,
      collected,
      publication,
      projected,
      contextual,
      projection_used,
      table_inputs
    ) => {
      let owner : ProgramStage = match publication {
        Some(ports) =>
          match bind_ports(collected, ports, table_inputs~) {
            Err(e) => return Err(Import(i, e))
            Ok(v) => Publication(v)
          }
        None =>
          Topology({
            stage: collected,
            results: projected.unwrap(),
            contextual: contextual.unwrap(),
            table_inputs,
          })
      }
      wiring_work += projection_used.work + program_attached_work(attached)
      wiring_text += projection_used.text_bytes + import_text
      stages.push(owner)
      imports.push(attached)
      read.index += 1
      read.stage = if read.index == count { Wiring } else { LocalInputs }
    }
    Wiring =>
      return finish_local_program_read_wiring(read).map(value => Some(value))
  }
  read.work = work
  read.nodes = nodes
  read.tokens = tokens
  read.text = text
  read.steps = steps
  read.results = results
  read.wiring_work = wiring_work
  read.wiring_text = wiring_text
  Ok(None)
}

///|
fn finish_local_program_read_wiring(
  read : LocalProgramReadBody,
) -> Result[(LocalProgramPreparation, LocalProgramUsage), LocalProgramIssue] {
  let source = read.source
  let limits = read.limits
  let environment = read.environment
  let calendar_profile = read.calendar_profile
  let model_tasks = read.model_tasks
  let check_only = read.check_only
  let stages = read.stages
  let imports = read.imports
  let local_inputs = read.local_inputs
  let reconciled_inputs = read.reconciled_inputs
  let mut work = read.work
  let nodes = read.nodes
  let tokens = read.tokens
  let mut text = read.text
  let steps = read.steps
  let results = read.results
  let wiring_work = read.wiring_work
  let wiring_text = read.wiring_text
  if check_only {
    let topology = match
      finish_checked_topology(
        source,
        stages,
        imports,
        {
          max_work: work,
          max_text_bytes: text,
          max_imports: limits.max_work,
          max_exports: limits.max_work,
        },
        local_inputs,
        environment,
        reconciled_inputs,
        {
          work: limits.max_work - work,
          nodes: limits.max_nodes - nodes,
          tokens: limits.max_tokens - tokens,
          text_bytes: limits.max_text_bytes - text,
          steps: limits.max_steps - steps,
          results: limits.max_results - results,
        },
        calendar_profile,
        model_tasks,
      ) {
      Err(e) => return Err(Wiring(e))
      Ok(v) => v
    }
    return Ok((Topology(topology), topology.usage))
  }
  let stages = stages.map(fn(stage) {
    guard stage is Publication(owner) else { abort("mixed preparation modes") }
    owner
  })
  let imports = imports.map(fn(imported) {
    guard imported is Publication(owner) else {
      abort("mixed preparation modes")
    }
    owner
  })
  let wired = match
    wire_results(source, stages, imports, {
      max_work: work + wiring_work,
      max_text_bytes: text + wiring_text,
      max_imports: limits.max_work,
      max_exports: limits.max_work,
    }) {
    Err(e) => return Err(Wiring(e))
    Ok(v) => v
  }
  let (final_work, final_text) = wiring_usage(wired)
  work -= final_work - wiring_work
  text -= final_text - wiring_text
  let preparation_usage : LocalProgramUsage = {
    work: limits.max_work - work,
    nodes: limits.max_nodes - nodes,
    tokens: limits.max_tokens - tokens,
    text_bytes: limits.max_text_bytes - text,
    steps: limits.max_steps - steps,
    results: limits.max_results - results,
  }
  Ok(
    (
      Publication({
        ..wired,
        preparation_usage: Some(preparation_usage),
        local_inputs: if environment is None {
          Some(local_inputs)
        } else {
          None
        },
        local_environment: environment,
        reconciled_inputs: if environment is Some(_) {
          Some(reconciled_inputs)
        } else {
          None
        },
      }),
      preparation_usage,
    ),
  )
}

///|
/// Remaining original semantic work, not memory demand or new work credit.
/// The same successful read has already debited Stage/environment prefixes.
pub fn local_program_read_remaining_work(original : LocalProgramRead) -> Int? {
  match original.state {
    Reading(body) =>
      match body.stage {
        PipelineRead(_, _, _, _, _, _, _, read) =>
          @pipeline.pipeline_evidence_read_owned_work(read).map(prefix => {
            body.work - prefix
          })
        _ => Some(body.work)
      }
    _ => None
  }
}

///|
/// Reconciled Local-input selection only. The original environment supplies
/// the SAME prepared inputs; no schema/rows/snapshot constructor runs here.
/// Stage/import getters2H2R2W, original map closure1H1W plus two Some2H2R2W,
/// retained zero-owned-usage1H3W and original Receipt-issue alternative1H1R2W.
/// Each import getter unwinds before the next: imported tuple/name/port bodies
/// are borrowed, and no array or per-import body escapes this constructor.
/// Read-state/result/phase carriers stay in the existing read-control packet.
pub fn local_program_read_reconciled_input_construction_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 7L, reference_slots: 5L, scalar_words: 10L, }
}

///|
/// The SAME selected zero-owned-usage record remains in the next Stage variant;
/// all lookup/map/return alternatives above have returned before reconcile.
pub fn local_program_read_reconciled_input_retained_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 1L, reference_slots: 0L, scalar_words: 3L, }
}
