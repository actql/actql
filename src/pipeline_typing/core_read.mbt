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
  let keyed_inputs = original.keyed_inputs
  let ranked_inputs = original.ranked_inputs
  let produced_inputs = original.produced_inputs
  let input_contracts = original.input_contracts
  let b = original.b
  let names = original.names
  match original.phase {
    Inputs => advance_pipeline_core_inputs(original)
    Parameters => advance_pipeline_core_parameters(original)
    ImportedEvidence => advance_pipeline_core_imported(original)
    DeltaContracts => advance_pipeline_core_delta_bindings(original)
    Steps => {
      let steps = original.steps.unwrap()
      let index = steps.length()
      if index < original.bodies.length() {
        original.current = Some(
          check_pipeline_core_step(original, original.bodies[index]),
        )
      }
      // A successful original body appends exactly one step. The last body
      // completes here; an empty table never needs an extra Pick boundary.
      if steps.length() == original.bodies.length() {
        original.phase = FinalEvidence
      }
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
