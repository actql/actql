///|
fn composed_local_sequence_matches(
  occurrence : @publication_host.ClientInferOccurrence,
  sequence : @relation.GeneratedSequence,
) -> Bool {
  let owner = @publication_host.client_infer_occurrence_preparation(occurrence)
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  let count = @lower.node_count(@lower.bound_preparation(owner))
  if !physical_equal(owner, @relation.generated_sequence_owner(sequence)) ||
    @relation.generated_sequence_step_count(sequence) != count {
    return false
  }
  guard @relation.generated_sequence_step_at(sequence, step)
    is Some(@lower.InferBoundary(actual)) &&
    actual == step else {
    return false
  }
  for index in 0..<count {
    if @relation.generated_sequence_step_index_at(sequence, index) !=
      Some(index) {
      return false
    }
  }
  true
}

///|
fn composed_local_capacity(
  sequence : @relation.GeneratedSequence,
  limits : Limits,
) -> @relation.ExecutionCapacity? {
  guard @relation.generated_sequence_capacity(
      sequence,
      limits.input,
      limits.measurement,
    )
    is Some(base) else {
    return None
  }
  // The Model's original ledger still owns its attempts and captures. The
  // enclosing Local candidate must also reserve their physical envelope;
  // ordinary Relation capacity alone cannot cover the component's custody.
  let retained_parts = [
    @relation.execution_capacity_retained_bytes(base),
    limits.model.ledger.retained_bytes,
    limits.output_values.max_nodes.to_int64() * 256L,
    limits.output_values.max_text_bytes.to_int64() * 8L,
    limits.identity.logical_wire.max_bytes.to_int64() * 8L,
  ]
  let execution_parts = [
    @relation.execution_capacity_execution_bytes(base),
    limits.model.ledger.execution_bytes,
    limits.measurement.max_nodes.to_int64() * 256L,
    limits.measurement.max_bytes.to_int64() * 8L,
  ]
  let mut retained = 0L
  for amount in retained_parts {
    if amount < 0L || amount > 9223372036854775807L - retained {
      return None
    }
    retained += amount
  }
  let mut executing = retained
  for amount in execution_parts {
    if amount < 0L || amount > 9223372036854775807L - executing {
      return None
    }
    executing += amount
  }
  @relation.execution_capacity(retained, executing)
}

///|
/// Select only the original whole Unit at its checked Model boundary. The
/// common Local driver supplies actual ordered producer reads. The installed
/// Host opens and retains the existing A component before returning it, and
/// binds its original Run, account, physical envelope and egress admissions.
/// This provider creates no separate executor, authorization or publication.
pub fn composed_local_provider(
  occurrence : @publication_host.ClientInferOccurrence,
  limits : Limits,
  open : (Array[@local.ManagedProviderInput]) -> Result[Execution, Issue],
  project_issue : (Issue) -> @connector.FixedComputeIssue,
  retain_completed? : (Execution) -> Bool = _ => true,
) -> @local.ManagedProvider {
  let opened = Ref(false)
  @local.managed_provider_with_inputs(
    sequence => composed_local_sequence_matches(occurrence, sequence),
    sequence => {
      if composed_local_sequence_matches(occurrence, sequence) {
        composed_local_capacity(sequence, limits)
      } else {
        None
      }
    },
    (sequence, inputs, max_rows, max_value_bytes, _) => {
      if !composed_local_sequence_matches(occurrence, sequence) ||
        max_rows < limits.output_rows ||
        max_value_bytes < 0 ||
        opened.val {
        return Err(@connector.ComputeUnsupported)
      }
      // One physical component belongs to this task occurrence. Another
      // strategy attempt must not silently repeat saved Model calls.
      opened.val = true
      let active = match open(inputs) {
        Ok(value) => value
        Err(issue) => return Err(project_issue(issue))
      }
      if !physical_equal(active.occurrence, occurrence) {
        return Err(project_issue(InvalidAdvance))
      }
      local_component(active, project_issue, retain_completed~).map_err(
        project_issue,
      )
    },
  )
}
