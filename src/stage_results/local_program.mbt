///|
pub(all) struct LocalProgramLimits {
  max_stages : Int
  max_steps : Int
  max_results : Int
  max_work : Int
  max_nodes : Int
  max_tokens : Int
  max_text_bytes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
pub(all) struct LocalProgramUsage {
  work : Int
  nodes : Int
  tokens : Int
  text_bytes : Int
  steps : Int
  results : Int
} derive(Eq, Debug)

///|
pub enum LocalProgramIssue {
  InvalidLimits
  BudgetExceeded
  ForeignEnvironmentSource
  ForeignModelEnvironment
  SourceViewStageCount
  MissingSourceViewRegistrations(Int)
  InvalidSourceViewRegistration(Int, String)
  UnsupportedReceipt(Int, String)
  LocalInput(Int, @local.Issue)
  Import(Int, ImportIssue)
  Pipeline(Int, @pipeline.Issue)
  Collection(Int, @parameters.Issue)
  Results(Int, @results.Issue)
  Order(Int, @results.OrderCheckIssue)
  Ports(Int, @results.PortIssue)
  Wiring(WiringIssue)
}

///|
/// Construct local-input and Result-import pipelines from one retained source.
/// This orchestrates topology and publication preparation, not full static
/// closure, input-value admission, Parameter binding or execution permission.
/// Parsing and declaration admission precede this call and are not billed here.
pub fn prepare_local_program(
  source : @parameters.Source,
  limits : LocalProgramLimits,
  environment? : @local.ProgramEnvironmentInputs? = None,
  sourceview_registrations? : Array[Array[(String, @pipeline.InputContract)]]? = None,
  calendar_profile? : @calendar_profile.Profile? = None,
  model_tasks? : @environment.ModelTasks? = None,
) -> Result[(ResultWiring, LocalProgramUsage), LocalProgramIssue] {
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
  let mut tokens = limits.max_tokens
  let mut text = limits.max_text_bytes
  let mut steps = limits.max_steps
  let mut results = limits.max_results
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
    if used.work > work || used.nodes > nodes || used.text_bytes > text {
      return Err(BudgetExceeded)
    }
    work -= used.work
    nodes -= used.nodes
    text -= used.text_bytes
  }
  let stages : Array[StagePorts] = []
  let imports : Array[AttachedImports] = []
  let local_inputs : Array[@local.Attached] = []
  let reconciled_inputs : Array[@local.ReconciledAttachment] = []
  // wire_results includes these exact retained prefixes in its reported usage.
  // They have already been charged; refund only those prefixes at that boundary.
  let mut wiring_work = 0
  let mut wiring_text = 0
  for i in 0..<count {
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
    let resolved = match
      resolve_imports(source, i, stages, {
        max_work: work,
        max_imports: work,
        max_text_bytes: text,
      }) {
      Err(e) => return Err(Import(i, e))
      Ok(v) => v
    }
    let (import_work, import_text) = import_usage(resolved)
    work -= import_work
    text -= import_text
    let local_count = @local.count(prepared)
    let resolved_count = import_count(resolved)
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
      let entry = import_at(resolved, j).unwrap()
      inputs.push(
        (input_name(entry), @pipeline.ProducedInput(input_producer(entry))),
      )
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
        !(registration is @pipeline.CarrierInput(_)) {
        return Err(InvalidSourceViewRegistration(i, name))
      }
      names[name] = ()
      inputs.push((name, registration))
    }
    let pipeline = match
      @pipeline.check_with_evidence(
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
    let used = @pipeline.usage(pipeline)
    work -= used.work
    nodes -= used.nodes
    tokens -= used.tokens
    text -= used.text_bytes
    steps -= @pipeline.step_count(pipeline)
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
    let attached = match
      attach_imports(resolved, collected, max_work=work + import_work) {
      Err(e) => return Err(Import(i, e))
      Ok(v) => v
    }
    work -= attached_work(attached) - import_work
    let checked = match
      @results.check(pipeline, @decode.required(body, "results").unwrap(), {
        max_results: results,
        max_work: work,
        max_nodes: nodes,
        max_text_bytes: text,
        max_depth: limits.max_depth,
      }) {
      Err(e) => return Err(Results(i, e))
      Ok(v) => v
    }
    let result_count = @results.count(checked)
    results -= result_count
    let used = @results.usage(checked)
    work -= used.work
    nodes -= used.nodes
    text -= used.text_bytes
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
    work -= used.work
    nodes -= used.nodes
    text -= used.text_bytes
    let owner = match bind_ports(collected, ports) {
      Err(e) => return Err(Import(i, e))
      Ok(v) => v
    }
    wiring_work += used.work + attached_work(attached)
    wiring_text += used.text_bytes + import_text
    stages.push(owner)
    imports.push(attached)
  }
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
      {
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
      },
      preparation_usage,
    ),
  )
}
