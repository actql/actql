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
  initial_prefix? : @relation.ExecutionCapacity,
  phase_funded? : Bool = false,
) -> @relation.ExecutionCapacity? {
  guard (match initial_prefix {
      Some(capacity) => Some(capacity)
      None =>
        @relation.generated_sequence_capacity(
          sequence,
          limits.input,
          limits.measurement,
        )
    })
    is Some(base) else {
    return None
  }
  // Fresh phase-funded Models use their separately funded original handoff
  // and attempt reservations; other callers prepay the component envelope.
  @relation.execution_capacity_inventory(
    [
      {
        unit: QuotedBytes,
        count: @relation.execution_capacity_retained_bytes(base),
        copies: 1,
      },
      {
        unit: QuotedBytes,
        count: if phase_funded {
          0L
        } else {
          limits.model.ledger.retained_bytes
        },
        copies: 1,
      },
      {
        unit: ValueNodeSlots,
        count: if phase_funded {
          0L
        } else {
          limits.output_values.max_nodes.to_int64()
        },
        copies: 1,
      },
      {
        unit: DecodedTextBytes,
        count: if phase_funded {
          0L
        } else {
          limits.output_values.max_text_bytes.to_int64()
        },
        copies: 1,
      },
      {
        unit: CanonicalWireBytes,
        count: if phase_funded {
          0L
        } else {
          limits.identity.logical_wire.max_bytes.to_int64()
        },
        copies: 1,
      },
    ],
    [
      {
        unit: QuotedBytes,
        count: @relation.execution_capacity_execution_bytes(base),
        copies: 1,
      },
      {
        unit: QuotedBytes,
        count: if phase_funded {
          0L
        } else {
          limits.model.ledger.execution_bytes
        },
        copies: 1,
      },
      {
        unit: ValueNodeSlots,
        count: if phase_funded {
          0L
        } else {
          limits.measurement.max_nodes.to_int64()
        },
        copies: 1,
      },
      {
        unit: CanonicalWireBytes,
        count: if phase_funded {
          0L
        } else {
          limits.measurement.max_bytes.to_int64()
        },
        copies: 1,
      },
    ],
    @relation.RetainedAlongsideExecution,
  )
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
  let mut capacity = base
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
      guard @relation.add_execution_capacity(capacity, extra) is Some(combined) else {
        return None
      }
      capacity = combined
    }
  }
  Some(capacity)
}

///|
/// A terminal Model's single checked UNIQUE prefix consumes its exact
/// supplied relation view. The regular bounded row recipe still covers its
/// key inventory and output. Model and result growth remain phase-funded.
fn portable_supplied_unique_prefix_capacity(
  prefix : @relation.GeneratedSequence,
  limits : Limits,
) -> @relation.ExecutionCapacity? {
  let owner = @lower.bound_preparation(
    @relation.generated_sequence_owner(prefix),
  )
  guard @relation.generated_sequence_step_count(prefix) == 1 &&
    @relation.generated_sequence_step_index_at(prefix, 0) == Some(0) &&
    @relation.generated_sequence_step_at(prefix, 0)
    is Some(@lower.RowStep(kernel)) &&
    @lower.kernel_body(kernel) is @lower.AssertUnique(_) &&
    @lower.node_at(owner, 0) is Some(node) &&
    @lower.node_input_count(node) == 1 &&
    @lower.node_input_target(node, 0) == Some(@pipeline.Input(0)) &&
    @lower.node_accepts_managed_relation_view(node, 0) &&
    @relation.select_generated_sequence_step(prefix, 0) is Some(selected) else {
    return None
  }
  @relation.generated_bounded_sequence_capacity(
    selected,
    limits.input,
    limits.measurement,
  )
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
  host_await_io? : Bool = false,
  original_step? : (
    (Execution) -> Result[Unit, @connector.FixedComputeIssue],
    (Execution, Bool) -> Result[Unit, @connector.FixedComputeIssue],
  )? = None,
) -> @local.ManagedProvider {
  composed_local_provider_with_workspace(
    occurrence,
    limits,
    (_, inputs, _) => open(inputs),
    project_issue,
    retain_completed~,
    allow_cleanup~,
    boundary_only~,
    input_prefix~,
    host_await_io~,
    original_step~,
  )
}

///|
/// Select the same managed provider with its checked output workspace. The
/// ordinary fixed provider above still uses this exact lifecycle owner.
pub fn composed_local_provider_with_workspace(
  occurrence : @publication_host.ClientInferOccurrence,
  limits : Limits,
  open : (
    @relation.GeneratedSequence,
    Array[@local.ManagedProviderInput],
    @relation.GeneratedSequence?,
  ) -> Result[Execution, Issue],
  project_issue : (Issue) -> @connector.FixedComputeIssue,
  retain_completed? : (Execution) -> Bool = _ => true,
  allow_cleanup? : (Execution) -> Bool = _ => true,
  boundary_only? : Bool = false,
  input_prefix? : @relation.GeneratedSequence? = None,
  host_await_io? : Bool = false,
  portable_vm? : Bool = false,
  original_step? : (
    (Execution) -> Result[Unit, @connector.FixedComputeIssue],
    (Execution, Bool) -> Result[Unit, @connector.FixedComputeIssue],
  )? = None,
) -> @local.ManagedProvider {
  let opened = Ref(false)
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  let initial_prefix = match input_prefix {
    Some(prefix) if portable_vm &&
      host_await_io &&
      !boundary_only &&
      @publication_host.client_infer_occurrence_terminal(occurrence) &&
      physical_equal(
        @relation.generated_sequence_owner(prefix),
        @publication_host.client_infer_occurrence_preparation(occurrence),
      ) &&
      @relation.generated_sequence_step_count(prefix) == step => {
      let mut exact = true
      for index in 0..<step {
        if @relation.generated_sequence_step_index_at(prefix, index) !=
          Some(index) {
          exact = false
          break
        }
      }
      if !exact {
        None
      } else if @publication_host.client_infer_occurrence_has_captured_sources(
          occurrence,
        ) {
        portable_supplied_unique_prefix_capacity(prefix, limits)
      } else {
        @local.literal_unique_relation_chain_capacity(
          prefix,
          limits.input,
          limits.measurement,
        )
      }
    }
    _ => None
  }
  let metered_output_start = match (input_prefix, initial_prefix) {
    (Some(prefix), Some(base)) if limits.output_values.max_nodes > 0 ||
      limits.output_values.max_text_bytes > 0 =>
      composed_local_capacity(
        prefix,
        limits,
        initial_prefix=base,
        phase_funded=true,
      )
    _ => None
  }
  let provider = @local.managed_provider_with_task_workspace(
    sequence => {
      composed_local_sequence_matches(occurrence, sequence, boundary_only)
    },
    sequence => {
      if composed_local_sequence_matches(occurrence, sequence, boundary_only) {
        composed_local_capacity(sequence, limits, initial_prefix?)
      } else {
        None
      }
    },
    (sequence, inputs, max_rows, max_value_bytes, _, task_workspace) => {
      if !composed_local_sequence_matches(occurrence, sequence, boundary_only) ||
        max_rows < limits.output_rows ||
        max_value_bytes < 0 ||
        opened.val ||
        (
          metered_output_start is Some(_) &&
          !@relation.generated_output_workspace_matches(
            sequence,
            @publication_host.client_infer_occurrence_preparation(occurrence),
            @pipeline.Step(step),
            metered=true,
          )
        ) {
        return Err(@connector.ComputeUnsupported)
      }
      let prepaid_prefix = if metered_output_start is Some(_) {
        guard input_prefix is Some(prefix) &&
          @relation.borrow_generated_component_workspace(
            sequence,
            prefix,
            prepaid_model_prefix=true,
          )
          is Some(prepaid) else {
          return Err(project_issue(InvalidAdvance))
        }
        Some(prepaid)
      } else {
        None
      }
      // One physical component belongs to this task occurrence. Another
      // strategy attempt must not silently repeat saved Model calls.
      opened.val = true
      let active = match open(sequence, inputs, prepaid_prefix) {
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
      local_component(
        active,
        project_issue,
        retain_completed~,
        allow_cleanup~,
        host_await_io~,
        original_step~,
        output_workspace=if portable_vm { Some(sequence) } else { None },
        fund_original_phases=metered_output_start is Some(_),
        task_workspace~,
      ).map_err(project_issue)
    },
  )
  if !boundary_only && input_prefix is Some(prefix) {
    @local.managed_provider_with_infer_relation_prefix(
      provider,
      prefix,
      step,
      limits.input,
      limits.measurement,
      metered_output_start~,
    )
  } else {
    provider
  }
}
