///|
fn metadata(b : Budget, root : @decode.Cursor) -> Unit raise Stop {
  let object = match @decode.open_object(root) {
    Ok(v) => v
    Err(_) => fail(root, InvalidMetadata)
  }
  let keys = @decode.object_field_names(root).unwrap()
  if keys.is_empty() {
    fail(root, InvalidMetadata)
  }
  spend(b, root, keys.length())
  for key in keys {
    if key.has_prefix("actql_") {
      fail(@decode.lookup(object, key).unwrap(), ReservedMetadataKey(key))
    }
  }
  let work = [(root, 0)]
  while work.pop() is Some((cursor, depth)) {
    spend(b, cursor, 1)
    if b.nodes == 0 {
      fail(cursor, BudgetExceeded)
    }
    b.nodes -= 1
    match @decode.view(cursor) {
      TextValue(v) => charge(b, cursor, v)
      ArrayValue(items) => {
        if depth >= b.limits.max_depth {
          fail(cursor, BudgetExceeded)
        }
        spend(b, cursor, items.length())
        for item in items {
          work.push((item, depth + 1))
        }
      }
      ObjectValue(obj) => {
        if depth >= b.limits.max_depth {
          fail(cursor, BudgetExceeded)
        }
        let names = @decode.object_field_names(cursor).unwrap()
        spend(b, cursor, names.length())
        for key in names {
          charge(b, cursor, key)
          work.push((@decode.lookup(obj, key).unwrap(), depth + 1))
        }
      }
      _ => ()
    }
  }
}

///|
fn check_impl(
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
) -> CheckedPipeline raise Stop {
  let original = match
    begin_pipeline_core_read(
      source, supplied_inputs, parameters, from, limits, calendar_profile, text_rank_profile,
      delta_contracts, keyed_inputs, ranked_inputs, produced_inputs, input_contracts,
      model_tasks,
    ) {
    Err(issue) => raise Stop(issue)
    Ok(original) => original
  }
  while (match pipeline_core_read_phase(original) {
          Inputs
          | Parameters
          | ImportedEvidence
          | DeltaContracts
          | Steps
          | FinalEvidence => true
          _ => false
        }) {
    let _ = advance_pipeline_core_read(original)
  }
  match take_pipeline_core_read(original).unwrap() {
    Ok(checked) => checked
    Err(issue) => raise Stop(issue)
  }
}

///|
fn resolve_target(
  b : Budget,
  source : @decode.Cursor,
  names : Map[String, Target],
) -> Target raise Stop {
  let name = read_name(b, source)
  match names.get(name) {
    Some(v) => v
    None => fail(source, UnknownName(name))
  }
}

///|
/// Inputs are resolved materialized Relations, never search-template bindings.
/// Source is the normalized steps array; from is the optional stage selector.
pub fn check(
  source : @decode.Cursor,
  inputs : Array[(String, @schema.Schema)],
  parameters : @parameter.Declarations?,
  from : @decode.Cursor?,
  limits : Limits,
  calendar_profile? : @calendar_profile.Profile? = None,
  text_rank_profile? : @text_rank_profile.Profile? = None,
  delta_contracts? : Array[
    (String, @schema.FieldName, @graph_contract.CheckedContract),
  ] = [],
  model_tasks? : @model_environment.ModelTasks? = None,
) -> Result[CheckedPipeline, Issue] {
  check_carriers(
    source,
    inputs.map(pair => (pair.0, @carrier.relation(@carrier.typed_rows(pair.1)))),
    parameters,
    from,
    limits,
    calendar_profile~,
    text_rank_profile~,
    delta_contracts~,
    model_tasks~,
  )
}

///|
/// Structural Carrier inputs carry no implicit runtime, ordering or uniqueness
/// proof. Existing Relation operations require complete row type information.
pub fn check_carriers(
  source : @decode.Cursor,
  inputs : Array[(String, @carrier.Carrier)],
  parameters : @parameter.Declarations?,
  from : @decode.Cursor?,
  limits : Limits,
  calendar_profile? : @calendar_profile.Profile? = None,
  text_rank_profile? : @text_rank_profile.Profile? = None,
  delta_contracts? : Array[
    (String, @schema.FieldName, @graph_contract.CheckedContract),
  ] = [],
  model_tasks? : @model_environment.ModelTasks? = None,
) -> Result[CheckedPipeline, Issue] {
  Ok(
    check_impl(
      source,
      inputs,
      parameters,
      from,
      limits,
      calendar_profile,
      text_rank_profile,
      delta_contracts,
      inputs.map(_ => None),
      inputs.map(_ => None),
      inputs.map(_ => None),
      inputs.map(pair => CarrierInput(pair.1)),
      model_tasks,
    ),
  ) catch {
    Stop(issue) => Err(issue)
  }
}

///|
/// Keyed inputs retain conditional admission assertions, not runtime proof.
pub fn check_with_evidence(
  source : @decode.Cursor,
  inputs : Array[(String, InputContract)],
  parameters : @parameter.Declarations?,
  from : @decode.Cursor?,
  limits : Limits,
  calendar_profile? : @calendar_profile.Profile? = None,
  text_rank_profile? : @text_rank_profile.Profile? = None,
  delta_contracts? : Array[
    (String, @schema.FieldName, @graph_contract.CheckedContract),
  ] = [],
  model_tasks? : @model_environment.ModelTasks? = None,
) -> Result[CheckedPipeline, Issue] {
  let original = match
    begin_pipeline_evidence_read(
      source,
      inputs,
      parameters,
      from,
      limits,
      calendar_profile~,
      text_rank_profile~,
      delta_contracts~,
      model_tasks~,
    ) {
    Err(issue) => return Err(issue)
    Ok(original) => original
  }
  while (match pipeline_evidence_read_phase(original) {
          Carriers
          | Keys
          | Rankings
          | Core
          | CoreInputs
          | CoreParameters
          | CoreImportedEvidence
          | CoreDeltaContracts
          | CoreSteps
          | CoreFinalEvidence => true
          _ => false
        }) {
    let _ = advance_pipeline_evidence_read(original)
  }
  take_pipeline_evidence_read(original).unwrap()
}
