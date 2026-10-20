///|
fn composed_local_sequence_matches(
  occurrence : @publication_host.ClientInferOccurrence,
  sequence : @relation.GeneratedSequence,
  boundary_only : Bool,
) -> Bool {
  let owner = @publication_host.client_infer_occurrence_preparation(occurrence)
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  guard @publication_host.client_infer_occurrence_output_step(occurrence)
    is Some(last) else {
    return false
  }
  let count = last + 1
  if boundary_only {
    return physical_equal(owner, @relation.generated_sequence_owner(sequence)) &&
      @relation.generated_sequence_step_count(sequence) == 1 &&
      @relation.generated_sequence_step_index_at(sequence, 0) == Some(step) &&
      @relation.generated_sequence_step_at(sequence, 0)
      is Some(@lower.InferBoundary(actual)) &&
      actual == step
  }
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
/// Derive the original keyed Model root's entire physical envelope from its
/// checked input and output segments. No sample rows or completed capture is
/// needed. This uses the same Model/input bounds as the ordinary Local family.
pub fn keyed_root_capacity(
  occurrence : @publication_host.ClientInferOccurrence,
  prefix : @relation.GeneratedSequence,
  suffix : @relation.GeneratedSequence?,
  limits : Limits,
) -> @relation.ExecutionCapacity? {
  let owner = @publication_host.client_infer_occurrence_preparation(occurrence)
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  if !physical_equal(owner, @relation.generated_sequence_owner(prefix)) ||
    @relation.generated_sequence_step_count(prefix) != step {
    return None
  }
  for index in 0..<step {
    if @relation.generated_sequence_step_index_at(prefix, index) != Some(index) {
      return None
    }
  }
  guard composed_local_capacity(prefix, limits) is Some(base) else {
    return None
  }
  let mut retained = @relation.execution_capacity_retained_bytes(base)
  let mut executing = @relation.execution_capacity_execution_bytes(base)
  match suffix {
    None =>
      if !@publication_host.client_infer_occurrence_terminal(occurrence) {
        return None
      }
    Some(sequence) => {
      let count = @publication_host.client_infer_occurrence_output_step(
          occurrence,
        ).unwrap_or(-1) -
        step
      if !physical_equal(owner, @relation.generated_sequence_owner(sequence)) ||
        count < 1 ||
        @relation.generated_sequence_step_count(sequence) != count {
        return None
      }
      for index in 0..<count {
        if @relation.generated_sequence_step_index_at(sequence, index) !=
          Some(step + 1 + index) {
          return None
        }
      }
      // Include the original post-Model suffix and retained prefix ports;
      // their overlap is not freed at the first waiting checkpoint.
      guard @relation.generated_sequence_capacity(
          sequence,
          limits.input,
          limits.measurement,
        )
        is Some(extra) else {
        return None
      }
      let suffix_retained = @relation.execution_capacity_retained_bytes(extra)
      let suffix_execution = @relation.execution_capacity_execution_bytes(extra)
      if suffix_retained < 0L ||
        suffix_execution < 0L ||
        suffix_retained > 9223372036854775807L - retained ||
        suffix_execution > 9223372036854775807L - executing {
        return None
      }
      retained += suffix_retained
      executing += suffix_execution
    }
  }
  @relation.execution_capacity(retained, executing)
}

///|
/// Select only the original whole Unit at its checked Model boundary. The
/// common Local driver supplies actual ordered producer reads. The installed
/// Host opens and retains the existing A component before returning it, and
/// binds its original Run, account, physical envelope and egress admissions.
/// This provider creates no separate executor, authorization or publication.
/// With boundary_only, select just the checked Model operation; its preceding
/// Content and Relation producers stay owned by the ordinary Local chain.
pub fn composed_local_provider(
  occurrence : @publication_host.ClientInferOccurrence,
  limits : Limits,
  open : (Array[@local.ManagedProviderInput]) -> Result[Execution, Issue],
  project_issue : (Issue) -> @connector.FixedComputeIssue,
  retain_completed? : (Execution) -> Bool = _ => true,
  allow_cleanup? : (Execution) -> Bool = _ => true,
  boundary_only? : Bool = false,
  input_prefix? : @relation.GeneratedSequence? = None,
) -> @local.ManagedProvider {
  let opened = Ref(false)
  let provider = @local.managed_provider_with_inputs(
    sequence => {
      composed_local_sequence_matches(occurrence, sequence, boundary_only)
    },
    sequence => {
      if composed_local_sequence_matches(occurrence, sequence, boundary_only) {
        composed_local_capacity(sequence, limits)
      } else {
        None
      }
    },
    (sequence, inputs, max_rows, max_value_bytes, _) => {
      if !composed_local_sequence_matches(occurrence, sequence, boundary_only) ||
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
      // A generation selects the occurrence anew from this original checked
      // Run. Require the same physical Program/preparation and coordinates,
      // not allocation identity of the small occurrence descriptor itself.
      if !@publication_host.client_infer_occurrence_matches(
          active.occurrence,
          occurrence.owner,
        ) ||
        @publication_host.client_infer_occurrence_coordinates(active.occurrence) !=
        @publication_host.client_infer_occurrence_coordinates(occurrence) {
        return Err(project_issue(InvalidAdvance))
      }
      local_component(active, project_issue, retain_completed~, allow_cleanup~).map_err(
        project_issue,
      )
    },
  )
  if !boundary_only && input_prefix is Some(prefix) {
    let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
      occurrence,
    )
    @local.managed_provider_with_infer_relation_prefix(
      provider, prefix, step, limits.input, limits.measurement,
    )
  } else {
    provider
  }
}
