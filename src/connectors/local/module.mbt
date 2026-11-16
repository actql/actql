///|
/// Host-fixed Local implementation configuration. Entries are private sequence
/// handles, not shared planner payloads or reconstructed checked owners.
struct LocalComputeModule {
  registry : @connector.CapabilityRegistry
  registration : @connector.CapabilityRegistration
  sequences : Array[@execution.GeneratedSequence]
  managed_providers : Array[ManagedProvider]
  selected_providers : Array[ManagedProvider?]
  selected_capacities : Array[@execution.ExecutionCapacity?]
  // Original constructor selection only, not permission or runtime liveness.
  selected_default : Array[LocalDefaultConstructor]
  managed_capacity : @connector.FixedComputeCapacity
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
  max_work : Int
}

///|
// Original selected constructor DATA. The same module owns the computed
// startup quote; none of these states supplies permission or liveness.
priv enum LocalDefaultConstructor {
  Injected
  OriginalDefault(@execution.ExecutionCapacity?)
}

///|
/// Owned sequence/provider snapshot arrays and original-slot selection arrays.
/// The provider objects and sequence bodies are borrowed, not copied. Each
/// exact-length array owns one header/backing pair and its module link. This
/// inventories all five containers, not provider/kernel construction backing.
pub fn local_module_container_inventory(
  slots : Int,
  installed_providers : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard @execution.checked_preparation_add_product(10L, slots.to_int64(), 6L)
    is Some(references) &&
    @execution.checked_preparation_add_product(
      references,
      installed_providers.to_int64(),
      1L,
    )
    is Some(references) else {
    return None
  }
  Some({
    // One original selection carrier, its optional startup value and the
    // retained two-word capacity per slot, alongside all five old containers.
    record_headers: 10L + 3L * slots.to_int64(),
    reference_slots: references,
    scalar_words: 8L + 3L * slots.to_int64(),
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// The added immutable recipe reference on each possible standing task
/// provider. Original task count bounds the selected defaults; installed
/// family fields and their two receipt closures are fixed Host controls.
/// Selection may cohold the eleven existing alternative provider records and
/// two complete capacity/Some pairs while the bounded result is merged.
/// This is constructor DATA on the same Plan, not another provider allowance.
pub fn local_module_provider_field_inventory(
  tasks : Int,
) -> @execution.ExecutionCapacity? {
  guard tasks >= 0 &&
    @execution.preparation_representation_cost({
      record_headers: 0L,
      reference_slots: tasks.to_int64(),
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      retained,
      if tasks > 0 {
        local_provider_selection_recipe_field_bytes
      } else {
        0L
      },
      1L,
    )
    is Some(execution) else {
    return None
  }
  @execution.execution_capacity(retained, execution)
}

///|
// Eleven added provider fields plus the callback/merged capacity results:
// each result is a two-word capacity record and its Some (2H/1R/2W).
// Runtime row chains reserve this transient peak once, not once per child.
let local_provider_selection_recipe_field_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 4L,
    reference_slots: 13L,
    scalar_words: 4L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
pub(all) enum LocalModuleIssue {
  Candidate(@connector.FixedComputeIssue)
  NotSelected
  Capacity
  Execution(@connector.FixedComputeIssue)
  Materializing(LocalMaterializingIssue)
}

///|
/// Pure bounded installation. This snapshots only the sequence-handle container;
/// it does not admit values, execute a sequence, or allocate task resources.
pub fn prepare_local_compute_module(
  registry : @connector.CapabilityRegistry,
  registration : @connector.CapabilityRegistration,
  sequences : Array[@execution.GeneratedSequence],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_work : Int,
  max_sequences : Int,
  managed_capacity? : @connector.FixedComputeCapacity,
  managed_providers? : Array[ManagedProvider] = [],
) -> Result[LocalComputeModule, @connector.FixedComputeIssue] {
  if max_work < 1 || max_sequences < 0 || sequences.length() > max_sequences {
    return Err(InvalidLimits)
  }
  if !@connector.capability_registration_matches(registration, registry) {
    return Err(ForeignCapability(0))
  }
  if !@connector.capability_description(registration).fixed_compute {
    return Err(ComputeUnsupported)
  }
  // Snapshot containers before any accepts/capacity callback can reenter.
  // Provider objects and their declared immutable dependencies remain shared.
  let original_sequences = sequences.copy()
  let original_providers = managed_providers.copy()
  let selected_providers : Array[ManagedProvider?] = Array::make(
    original_sequences.length(),
    None,
  )
  let selected_capacities : Array[@execution.ExecutionCapacity?] = Array::make(
    original_sequences.length(),
    None,
  )
  let selected_default : Array[LocalDefaultConstructor] = Array::make(
    original_sequences.length(),
    Injected,
  )
  for slot, sequence in original_sequences {
    let mut selected : ManagedProvider? = None
    for provider in original_providers {
      if managed_provider_accepts(provider, sequence) {
        if selected is Some(_) {
          return Err(ForeignPreparation)
        }
        selected = Some(provider)
      }
    }
    let selected = match selected {
      Some(_) => selected
      None => {
        selected_default[slot] = OriginalDefault(None)
        local_default_managed_provider(
          original_providers, execution, measurement, sequence,
        )
      }
    }
    let capacity = match selected {
      Some(provider) =>
        managed_provider_capacity_for_execution(
          provider, sequence, execution, measurement,
        )
      None =>
        @execution.generated_sequence_capacity(sequence, execution, measurement)
    }
    if selected is Some(_) && capacity is None {
      return Err(ForeignPreparation)
    }
    selected_providers[slot] = selected
    selected_capacities[slot] = capacity
  }
  let installed : LocalComputeModule = {
    registry,
    registration,
    sequences: original_sequences,
    managed_providers: original_providers,
    selected_providers,
    selected_capacities,
    selected_default,
    managed_capacity: managed_capacity.unwrap_or({
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: execution.rows.max_rows,
      max_value_bytes: measurement.max_bytes,
      common_fragment: None,
    }),
    execution,
    measurement,
    max_work,
  }
  // No module handle has escaped. Default constructor quotation is pure and
  // has no external provider/current/IO callback; preserve its result once before the
  // original module reaches dispatch preparation or a Run.
  for slot, sequence in original_sequences {
    if selected_default[slot] is OriginalDefault(_) {
      selected_default[slot] = OriginalDefault(
        local_module_default_output_start_capacity(installed, slot, sequence),
      )
    }
  }
  Ok(installed)
}

///|
/// Pure product preparation for the finite managed Local connection. No
/// representation is opened and no task reservation is started here.
pub fn[T] prepare_local_module_managed_compute(
  installed : LocalComputeModule,
  slot : Int,
  request : @connector.ManagedFixedComputeRequest[T],
  interval_search_ceilings? : Array[(Int, Int64)] = [],
  asof_search_ceilings? : Array[(Int, Int64)] = [],
  sequence_match_ceilings? : Array[(Int, Int64, Int64)] = [],
) -> Result[
  (
    @connector.PreparedManagedCompute[T, @execution.GeneratedSequence],
    @connector.ManagedFixedComputeChoice[T],
  ),
  LocalModuleIssue,
] {
  prepare_local_module_managed_compute_with_estimates(
    installed,
    slot,
    request,
    [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(1L), }],
    interval_search_ceilings~,
    asof_search_ceilings~,
    sequence_match_ceilings~,
  )
}

///|
/// Compatible extension used by Site-aware automatic comparison. The caller
/// supplies connector-owned duration estimates without changing the existing
/// finite Local preparation entrypoint.
pub fn[T] prepare_local_module_managed_compute_with_estimates(
  installed : LocalComputeModule,
  slot : Int,
  request : @connector.ManagedFixedComputeRequest[T],
  estimates : Array[@cost.SerialEstimateLine],
  interval_search_ceilings? : Array[(Int, Int64)] = [],
  asof_search_ceilings? : Array[(Int, Int64)] = [],
  sequence_match_ceilings? : Array[(Int, Int64, Int64)] = [],
) -> Result[
  (
    @connector.PreparedManagedCompute[T, @execution.GeneratedSequence],
    @connector.ManagedFixedComputeChoice[T],
  ),
  LocalModuleIssue,
] {
  guard installed.sequences.get(slot) is Some(configured) else {
    return Err(Candidate(ComputeUnsupported))
  }
  let mut sequence = configured
  for (step, ceiling) in interval_search_ceilings {
    sequence = match
      @execution.constrain_generated_interval_search(sequence, step, ceiling) {
      Ok(value) => value
      Err(_) => return Err(Candidate(ForeignPreparation))
    }
  }
  for (step, ceiling) in asof_search_ceilings {
    sequence = match
      @execution.constrain_generated_asof_search(sequence, step, ceiling) {
      Ok(value) => value
      Err(issue) => return Err(Candidate(Execution(issue)))
    }
  }
  for (step, matches, output) in sequence_match_ceilings {
    sequence = match
      @execution.constrain_generated_sequence_match_limits(
        sequence, step, matches, output,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Candidate(Execution(issue)))
    }
  }
  let provider = local_module_managed_provider(installed, slot, sequence)
  let candidate = match
    local_managed_fixed_compute_candidate(
      installed.registration,
      request,
      sequence,
      estimates,
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      installed.max_work,
      provider_supported=provider is Some(_),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  let choice = match
    @connector.choose_managed_fixed_compute_candidate(
      installed.registry,
      request,
      [@connector.prepared_managed_compute_candidate(candidate)],
      None,
      installed.max_work,
    ) {
    Ok(Proposed(value)) => value
    Ok(_) => return Err(NotSelected)
    Err(issue) => return Err(Candidate(issue))
  }
  Ok((candidate, choice))
}

///|
pub fn local_module_managed_provider(
  installed : LocalComputeModule,
  slot : Int,
  sequence : @execution.GeneratedSequence,
) -> ManagedProvider? {
  guard local_module_original_occurrence(installed, slot, sequence) &&
    installed.selected_providers.get(slot) is Some(Some(provider)) &&
    managed_provider_accepts(provider, sequence) else {
    return None
  }
  Some(provider)
}

///|
fn local_module_original_occurrence(
  installed : LocalComputeModule,
  slot : Int,
  sequence : @execution.GeneratedSequence,
) -> Bool {
  guard installed.sequences.get(slot) is Some(original) else { return false }
  @execution.retain_generated_sequence_refinement(original, sequence) is Some(_)
}

///|
/// Exact original capacity is retained. A genuinely refined sequence follows
/// the same provider's full capacity check and must stay within its original
/// slot envelope; equal step coordinates alone do not create more capacity.
pub fn local_module_capacity_for_sequence(
  installed : LocalComputeModule,
  slot : Int,
  sequence : @execution.GeneratedSequence,
) -> @execution.ExecutionCapacity? {
  guard local_module_original_occurrence(installed, slot, sequence) &&
    installed.sequences.get(slot) is Some(original) &&
    installed.selected_capacities.get(slot) is Some(Some(admitted)) else {
    return None
  }
  if physical_equal(sequence, original) {
    return Some(admitted)
  }
  guard local_module_managed_provider(installed, slot, sequence)
    is Some(provider) &&
    managed_provider_capacity_for_execution(
      provider,
      sequence,
      installed.execution,
      installed.measurement,
    )
    is Some(required) &&
    required.retained_bytes <= admitted.retained_bytes &&
    required.execution_bytes <= admitted.execution_bytes else {
    return None
  }
  Some(required)
}

///|
/// Startup DATA for exact built-in Values/rows/Append, primitive Set/Join and
/// checked bounded row/CROSS JOIN/immediate JOIN chains. The unchanged
/// full capacity remains the fallback and semantic bound. Persistent output
/// DATA is charged by the same task before each buffer commit; all fixed
/// child metadata, input/measurement/traversal and one live child scratch
/// remain prepaid. An injected provider selected for this slot cannot use this constructor proof.
pub fn local_module_metered_output_start_capacity(
  installed : LocalComputeModule,
  slot : Int,
  sequence : @execution.GeneratedSequence,
) -> @execution.ExecutionCapacity? {
  guard installed.sequences.get(slot) is Some(original) else { return None }
  if physical_equal(sequence, original) {
    return match installed.selected_default.get(slot) {
      Some(OriginalDefault(startup)) => startup
      _ => None
    }
  }
  // A genuinely different checked refinement has different constructor
  // demand. It still passes the old same-owner/full-envelope proof below;
  // equal coordinates cannot read another original's retained quote.
  local_module_default_output_start_capacity(installed, slot, sequence)
}

///|
fn local_module_default_output_start_capacity(
  installed : LocalComputeModule,
  slot : Int,
  sequence : @execution.GeneratedSequence,
) -> @execution.ExecutionCapacity? {
  let count = @execution.generated_sequence_step_count(sequence)
  guard installed.selected_default.get(slot) is Some(OriginalDefault(_)) &&
    count > 0 &&
    // Only these existing bounded singletons attach their output budget to
    // this same sequence's before-commit growth owner.
    // Other single-step families keep their original full envelope.
    (
      count > 1 ||
      @execution.generated_sequence_step_at(sequence, 0)
      is Some(
        @lower.ValuesStep(_)
        | @lower.RowStep(_)
        | @lower.AppendStep(_)
        | @lower.SetStep(_)
        | @lower.JoinStep(_)
        | @lower.CrossJoinStep(_)
      )
    ) &&
    relation_chain_reclaimed_prefix(
      sequence,
      installed.execution,
      installed.measurement,
      installed.managed_providers,
    ) ==
    count &&
    local_module_capacity_for_sequence(installed, slot, sequence) is Some(full) else {
    return None
  }
  if count == 1 &&
    @execution.generated_sequence_step_at(sequence, 0)
    is Some(@lower.CrossJoinStep(_)) {
    let prepared = @lower.bound_preparation(
      @execution.generated_sequence_owner(sequence),
    )
    guard @execution.generated_sequence_step_index_at(sequence, 0) is Some(step) &&
      @lower.node_at(prepared, step) is Some(node) &&
      @lower.node_input_count(node) == 2 else {
      return None
    }
    for index in -1..<2 {
      let target = if index < 0 {
        Some(@pipeline.Step(step))
      } else {
        @lower.node_input_target(node, index)
      }
      guard target.bind(target => @lower.preparation_schema_at(prepared, target))
        is Some(schema) &&
        @schema.all_fields_required(schema) else {
        return None
      }
    }
  }
  let borrowed_join = count == 1 &&
    (match @execution.generated_sequence_step_at(sequence, 0) {
      Some(@lower.JoinStep(kernel)) =>
        selected_join_borrows_carried_values(kernel)
      _ => false
    })
  if count == 1 &&
    !borrowed_join &&
    @execution.generated_sequence_step_at(sequence, 0)
    is Some(@lower.SetStep(_) | @lower.JoinStep(_)) {
    let prepared = @lower.bound_preparation(
      @execution.generated_sequence_owner(sequence),
    )
    guard @execution.generated_sequence_step_index_at(sequence, 0) is Some(step) &&
      @lower.node_at(prepared, step) is Some(node) &&
      @lower.node_input_count(node) == 2 else {
      return None
    }
    // Only borrowed immediate cells can defer output DATA here. Recursive,
    // text and absent-field shapes keep the existing full prepaid path.
    for index in -1..<2 {
      let target = if index < 0 {
        Some(@pipeline.Step(step))
      } else {
        @lower.node_input_target(node, index)
      }
      guard target.bind(target => @lower.preparation_schema_at(prepared, target))
        is Some(schema) &&
        @schema.all_fields_required(schema) else {
        return None
      }
      for field in 0..<@schema.field_count(schema) {
        match @schema.field_at(schema, field).unwrap().contract.shape {
          @contract.Number | @contract.Boolean => ()
          _ => return None
        }
      }
    }
  }
  // These selected singleton constructors use their bounded operation
  // workspace, not the generic sequence's retained table and metadata arrays.
  // Keep their exact input, measurement, output and frame allowances in the original
  // bounded recipe before deferring only output DATA to the same growth owner.
  let base = if count == 1 {
    @execution.generated_sequence_step_index_at(sequence, 0)
    .bind(step => @execution.select_generated_sequence_step(sequence, step))
    .bind(selected => {
      @execution.generated_bounded_sequence_capacity(
        selected,
        installed.execution,
        installed.measurement,
      )
    })
  } else {
    @execution.generated_sequence_capacity(
      sequence,
      installed.execution,
      installed.measurement,
    )
  }
  guard base is Some(base) else { return None }
  // Only this built-in row chain gets a constructor-local startup baseline.
  // Each child borrows immutable input backing, attaches output to the same
  // task growth owner, and confirms scratch cleanup before its successor.
  // Other chains keep their generic floor. Constructed row outputs retain
  // their full final-output holding when DATA retention is not deferred.
  let mut unnest_chain = count > 1
  let mut has_unnest = false
  let mut required_row_chain = count > 1
  let unpivot_chain = selected_literal_unpivot_chain(sequence)
  for index in 0..<count {
    match @execution.generated_sequence_step_at(sequence, index) {
      Some(@lower.RowStep(kernel)) => {
        if !selected_binding_rows_supported(kernel) ||
          !@schema.all_fields_required(@lower.kernel_input_schema(kernel)) ||
          !@schema.all_fields_required(@lower.kernel_output_schema(kernel)) {
          required_row_chain = false
        }
        if @lower.kernel_unnest(kernel) is Some(_) {
          has_unnest = true
        } else if !selected_binding_rows_supported(kernel) {
          unnest_chain = false
        }
      }
      _ => {
        unnest_chain = false
        required_row_chain = false
      }
    }
  }
  unnest_chain = unnest_chain && has_unnest
  // This built-in window chain constructs no legacy sequence table. Keep
  // complete bounded child scratch, while the existing chain confirms cleanup
  // before its next child. Each accepted completion grows on the same task
  // before row transfer; carried cells retain their original input owner.
  let mut window_chain = count > 1
  let mut has_window = false
  for index in 0..<count {
    match @execution.generated_sequence_step_at(sequence, index) {
      Some(@lower.WindowStep(_)) => has_window = true
      Some(@lower.RowStep(kernel)) =>
        if !selected_binding_rows_supported(kernel) &&
          !(@lower.kernel_body(kernel) is @lower.Groups(_)) {
          window_chain = false
        }
      _ => window_chain = false
    }
  }
  window_chain = window_chain && has_window
  // Append borrows both original inputs in this reclaimed bounded chain.
  // A JOIN is not a prerequisite; if present, retain its original carried-
  // value constructor proof as well. Every child confirms scratch cleanup
  // before its successor; no legacy sequence table is constructed.
  let mut append_chain = count > 1
  for index in 0..<count {
    if @execution.generated_sequence_step_at(sequence, index)
      is Some(@lower.JoinStep(kernel)) {
      if !selected_join_borrows_carried_values(kernel) {
        append_chain = false
      }
    }
  }
  let mut bounded_family_chain = false
  let mut metered_retention = true
  for index in 0..<count {
    match @execution.generated_sequence_step_at(sequence, index) {
      Some(@lower.WindowStep(_)) if window_chain => ()
      Some(@lower.RowStep(kernel)) if window_chain &&
        @lower.kernel_body(kernel) is @lower.Groups(_) => {
        // Scalar window reductions use the bounded borrowed-cell recipe.
        // Dynamic arguments and filters retain their complete Fragment
        // context, maps and pending rows in operation workspace; persistent
        // output grows before CommitOutput appends the original checked row.
        let direct = @lower.kernel_group(kernel)
          .map(group => {
            let mut direct = @lower.group_is_window(group)
            for aggregate in 0..<@lower.group_aggregate_count(group) {
              let aggregate = @lower.group_aggregate_at(group, aggregate).unwrap()
              match @lower.group_aggregate_argument(aggregate) {
                @lower.AggregateExpression(expression) =>
                  match @lower.expression_contract(expression).shape {
                    @contract.Number | @contract.Boolean => ()
                    // A scalar result such as COUNT can still consume a
                    // newly constructed Text or collection argument.
                    _ => direct = false
                  }
                _ => ()
              }
              if @lower.group_aggregate_filter(aggregate) is Some(filter) &&
                !(@lower.expression_contract(filter).shape is @contract.Boolean) {
                direct = false
              }
              // A newly built text/collection aggregate needs its own full
              // construction backing before the row's persistent-output grow.
              match @lower.group_aggregate_result(aggregate).shape {
                @contract.Number | @contract.Boolean => ()
                _ => direct = false
              }
            }
            direct
          })
          .unwrap_or(false)
        if !direct {
          metered_retention = false
        }
      }
      // The bounded Values child retains its original complete literal
      // recipe below. Its same row-charge owner funds accepted output before
      // transfer; a Values seed does not construct a legacy sequence table.
      Some(@lower.ValuesStep(_)) => ()
      Some(@lower.CrossJoinStep(_)) => ()
      Some(@lower.AppendStep(_)) if count == 1 || append_chain =>
        if count > 1 {
          let prepared = @lower.bound_preparation(
            @execution.generated_sequence_owner(sequence),
          )
          guard @execution.generated_sequence_step_index_at(sequence, index)
            is Some(step) &&
            @lower.node_at(prepared, step) is Some(node) &&
            @lower.node_input_count(node) == 2 else {
            return None
          }
          // Append's existing row-charge owner funds the SAME checked row
          // before push. Preserve both exact original input occurrences;
          // recursive/text/presence shapes retain their prior full recipe.
          for port in -1..<2 {
            let target = if port < 0 {
              Some(@pipeline.Step(step))
            } else {
              @lower.node_input_target(node, port)
            }
            guard target.bind(target => {
                @lower.preparation_schema_at(prepared, target)
              })
              is Some(schema) &&
              @schema.all_fields_required(schema) else {
              return None
            }
            for field in 0..<@schema.field_count(schema) {
              match @schema.field_at(schema, field).unwrap().contract.shape {
                @contract.Number | @contract.Boolean => ()
                _ => return None
              }
            }
          }
        }
      Some(@lower.SetStep(_)) if count == 1 => ()
      Some(@lower.JoinStep(kernel)) =>
        // The same bounded JOIN child funds every complete output row before
        // commit, including inside a reclaimed Relation chain. Admit only
        // required scalar input/output cells here. Text requires the same
        // INNER JOIN borrowed-cell/charged-comparison proof; other DATA keeps
        // its full prepaid lifecycle. This changes no comparison or row bound.
        if count > 1 {
          let prepared = @lower.bound_preparation(
            @lower.join_kernel_owner(kernel),
          )
          let step = @lower.join_kernel_step(kernel)
          guard @lower.node_at(prepared, step) is Some(node) &&
            @lower.node_input_count(node) == 2 else {
            return None
          }
          for port in -1..<2 {
            let target = if port < 0 {
              Some(@pipeline.Step(step))
            } else {
              @lower.node_input_target(node, port)
            }
            guard target.bind(target => {
                @lower.preparation_schema_at(prepared, target)
              })
              is Some(schema) &&
              @schema.all_fields_required(schema) else {
              return None
            }
            for field in 0..<@schema.field_count(schema) {
              match @schema.field_at(schema, field).unwrap().contract.shape {
                @contract.Number | @contract.Boolean => ()
                @contract.Text(_) => if !append_chain { return None }
                _ => return None
              }
            }
          }
        }
      // The same bounded Number group also runs as a reclaimed chain child.
      // It borrows input cells and funds pending rows in its complete child
      // workspace; this existing chain confirms cleanup before its successor.
      Some(@lower.RowStep(kernel)) if @execution.bounded_number_group_borrows_input(
          kernel,
        ) => ()
      Some(@lower.RowStep(kernel)) if @lower.kernel_pivot(kernel) is Some(pivot) => {
        // The existing bounded group/PIVOT child reads original scalar
        // cells, retaining the text axis and aggregate workspace. Scalar
        // pending rows use workspace; complete output grows before transfer.
        // Reclaimed chains stop and clean this same child before its
        // successor; they construct no legacy sequence table.
        let input = @lower.kernel_input_schema(kernel)
        let output = @lower.kernel_output_schema(kernel)
        if !@schema.all_fields_required(input) ||
          !@schema.all_fields_required(output) {
          return None
        }
        for field in 0..<@schema.field_count(input) {
          match @schema.field_at(input, field).unwrap().contract.shape {
            @contract.Number | @contract.Boolean | @contract.Text(_) => ()
            _ => return None
          }
        }
        for field in 0..<@schema.field_count(output) {
          match @schema.field_at(output, field).unwrap().contract.shape {
            @contract.Number | @contract.Boolean => ()
            // Canonical schema order need not put index keys first. Match
            // the checked field identity, not its position in that schema.
            @contract.Text(_) => {
              let name = @schema.field_at(output, field).unwrap().name
              let mut index_key = false
              for index in 0..<@lower.pivot_index_count(pivot) {
                if @lower.pivot_index_at(pivot, index) == Some(name) {
                  index_key = true
                }
              }
              if !index_key {
                return None
              }
            }
            _ => return None
          }
        }
      }
      Some(@lower.RowStep(kernel)) if (count == 1 || unpivot_chain) &&
        @lower.kernel_unpivot_outputs(kernel) is Some(_) =>
        // This bounded constructor borrows original admitted cells, including
        // Text/Array/Object backing, and prepared column labels. Its stepped
        // contract recheck returns the SAME immutable value, not a copied
        // forest. Preserve all independent traversal scratch, while the same
        // row-charge owner funds complete output before transfer.
        if !@schema.all_fields_required(@lower.kernel_input_schema(kernel)) ||
          !@schema.all_fields_required(@lower.kernel_output_schema(kernel)) {
          return None
        }
      Some(@lower.RowStep(kernel)) if count == 1 &&
        @lower.kernel_analytic(kernel) is Some(analytic) => {
        // The existing bounded analytic child funds its accepted buffer row
        // before transfer. Keep all ordering/input/evaluation scratch prepaid;
        // only immediate ROW_NUMBER DATA uses this original growth owner.
        if @lower.analytic_call_count(analytic) < 1 {
          return None
        }
        for index in 0..<@lower.analytic_call_count(analytic) {
          let call = @lower.analytic_call_at(analytic, index).unwrap()
          if !(@lower.analytic_call_function(call) is @lower.PreparedRowNumber) {
            return None
          }
        }
        for
          schema in [
            @lower.kernel_input_schema(kernel),
            @lower.kernel_output_schema(kernel),
          ] {
          if !@schema.all_fields_required(schema) {
            return None
          }
          for field in 0..<@schema.field_count(schema) {
            match @schema.field_at(schema, field).unwrap().contract.shape {
              @contract.Number | @contract.Boolean => ()
              _ => return None
            }
          }
        }
      }
      Some(@lower.RowStep(kernel)) if @lower.kernel_count_group(kernel)
        is Some(group) => {
        // Bounded COUNT now shares this task's before-commit output funding.
        // Keep text, recursive and absent-field inputs on their full recipe;
        // scalar input/output cells retain all original count/null semantics.
        if @lower.count_group_aggregate_count(group) < 1 {
          return None
        }
        for
          schema in [
            @lower.kernel_input_schema(kernel),
            @lower.kernel_output_schema(kernel),
          ] {
          if !@schema.all_fields_required(schema) {
            return None
          }
          for field in 0..<@schema.field_count(schema) {
            match @schema.field_at(schema, field).unwrap().contract.shape {
              @contract.Number | @contract.Boolean => ()
              _ => return None
            }
          }
        }
      }
      Some(@lower.RowStep(kernel)) if @lower.kernel_unnest(kernel) is Some(_) =>
        if !@schema.all_fields_required(@lower.kernel_input_schema(kernel)) ||
          !@schema.all_fields_required(@lower.kernel_output_schema(kernel)) {
          return None
        }
      Some(@lower.RowStep(kernel)) if selected_binding_rows_supported(kernel) =>
        match @lower.kernel_body(kernel) {
          @lower.Filter(_)
          | @lower.Select(_)
          | @lower.StableSort(_)
          | @lower.Limit(_, _, _)
          | @lower.AssertAll(_)
          | @lower.AssertUnique(_) => ()
          @lower.DistinctRows => {
            // The bounded comparator keeps original immediate cells and row
            // indices. CommitOutputRow funds each accepted output on this
            // same attachment; recursive/text/presence shapes keep the full
            // retained envelope and their original constructor recipe.
            let input = @lower.kernel_input_schema(kernel)
            let output = @lower.kernel_output_schema(kernel)
            let mut immediate = @schema.all_fields_required(input) &&
              @schema.all_fields_required(output)
            for field in 0..<@schema.field_count(input) {
              match @schema.field_at(input, field).unwrap().contract.shape {
                @contract.Number | @contract.Boolean => ()
                _ => immediate = false
              }
            }
            if !immediate {
              metered_retention = false
            }
          }
          _ => {
            // Ordered bindings may convert a snapshot cell before output
            // retention is funded. Only Number/Boolean outputs are immediate
            // cells with no copied text/container forest. Their row arrays
            // and logical roots use the already attached workspace owner,
            // and CommitOutputRow funds the complete output before transfer.
            // Other outputs need their own complete constructor funding below.
            let schema = @execution.generated_sequence_step_index_at(
              sequence, index,
            ).bind(step => {
              @lower.preparation_schema_at(
                @lower.bound_preparation(
                  @execution.generated_sequence_owner(sequence),
                ),
                @pipeline.Step(step),
              )
            })
            let primitive = @lower.kernel_bindings(kernel) is Some(_) &&
              schema
              .map(schema => {
                let mut immediate = true
                for field in 0..<@schema.field_count(schema) {
                  match
                    @schema.field_at(schema, field).unwrap().contract.shape {
                    @contract.Number | @contract.Boolean => ()
                    _ => immediate = false
                  }
                }
                immediate
              })
              .unwrap_or(false)
            let input = @lower.kernel_input_schema(kernel)
            let mut funded_snapshot = (
                @lower.kernel_body(kernel) is @lower.SnapshotMap(_) ||
                @lower.kernel_body(kernel) is @lower.OrderedBindings(_)
              ) &&
              @lower.kernel_bindings(kernel) is Some(_) &&
              @schema.all_fields_required(input)
            for field in 0..<@schema.field_count(input) {
              match @schema.field_at(input, field).unwrap().contract.shape {
                @contract.Number | @contract.Boolean => ()
                _ => funded_snapshot = false
              }
            }
            // This constructor borrows immediate input cells. Its original
            // logical roots fund Object/Array builders before mutation, with
            // the complete fragment-live/traversal scratch still prepaid.
            // CommitOutputRow then funds recursive persistent DATA on the
            // same attachment before releasing those temporary roots.
            // Alias/literal leaves also borrow text/container backing from
            // the still-live input or admitted preparation. This is not a
            // general constructed-output recipe: retain the full scratch and
            // use the same before-commit persistent-output growth owner.
            let borrowed_bindings = @schema.all_fields_required(input) &&
              selected_binding_outputs_borrowed(kernel)
            if !primitive && !funded_snapshot && !borrowed_bindings {
              metered_retention = false
            }
          }
        }
      _ => {
        guard @execution.generated_sequence_step_index_at(sequence, index)
          is Some(step) &&
          @execution.select_generated_sequence_step(sequence, step)
          is Some(selected) &&
          bounded_relation_step_provider(
            selected,
            installed.execution,
            installed.measurement,
            family=installed.managed_providers,
          )
          is Some(provider) &&
          managed_provider_bounded_relation_capacity(
            provider,
            selected,
            installed.execution,
            installed.measurement,
          )
          is Some(_) else {
          return None
        }
        bounded_family_chain = true
        metered_retention = false
      }
    }
    let schema = @execution.generated_sequence_step_index_at(sequence, index).bind(step => {
        @lower.preparation_schema_at(
          @lower.bound_preparation(
            @execution.generated_sequence_owner(sequence),
          ),
          @pipeline.Step(step),
        )
      },
    )
    if schema.map(@schema.all_fields_required) != Some(true) {
      metered_retention = false
    }
  }
  let output = installed.execution.rows.output_values
  guard @execution.execution_capacity_inventory_bytes([
      {
        unit: @execution.ValueNodeSlots,
        count: output.max_nodes.to_int64(),
        copies: 1,
      },
      {
        unit: @execution.DecodedTextBytes,
        count: output.max_text_bytes.to_int64(),
        copies: 1,
      },
    ])
    is Some(data) &&
    base.execution_bytes >= data else {
    return None
  }
  // These default singleton constructors retain the SAME admitted output row,
  // not an input forest, measurement wire body or second output forest. Its
  // same before-commit owner pays that row before transfer.
  // Keep the bounded constructor's real maps/row arrays/cursors/frames/depth
  // and every fragment allowance alongside it. The generic provider bound
  // remains unchanged; an injected provider never enters this recipe.
  if count == 1 &&
    @execution.generated_sequence_step_at(sequence, 0)
    is Some(@lower.RowStep(kernel)) &&
    (
      @lower.kernel_unpivot_outputs(kernel) is Some(_) ||
      @lower.kernel_pivot(kernel) is Some(_)
    ) {
    // Constructor DATA grows before append; keep fixed output metadata and
    // all independent workspace. The driver adds those retained metadata
    // bytes alongside workspace, then the same attachment reserves each
    // actual complete row in both dimensions before transfer.
    guard base.execution_bytes >= data &&
      full.retained_bytes >= base.retained_bytes &&
      @execution.execution_capacity_inventory_add(
        base.execution_bytes - data,
        @execution.CursorRootSlots,
        2L * count.to_int64() + 2L,
        1,
      )
      is Some(scratch) &&
      full.retained_bytes >= data &&
      Int64::max(full.retained_bytes - data, scratch) <= full.execution_bytes else {
      return None
    }
    return @execution.execution_capacity(
      full.retained_bytes - data,
      Int64::max(full.retained_bytes - data, scratch),
    )
  }
  let mut fixed = 0L
  let mut coheld_prefix_peak = 0L
  // Every selected child above is the same bounded before-commit constructor.
  // Its chain retires child scratch before the next child. No legacy generic
  // sequence table is built; keep every child's full scratch and fixed roots,
  // while actual output DATA grows on the original shared attachment.
  // The same bounded row children retire scratch before their successor even
  // when they construct Text and keep the full final-output holding prepaid.
  // Retained-output deferral is independent: preserve full R when it is false,
  // while the shared attachment still funds all live intermediate DATA in E.
  let constructor_chain = (count > 1 && metered_retention) ||
    window_chain ||
    required_row_chain ||
    unpivot_chain ||
    selected_literal_binding_chain(sequence) ||
    bounded_family_chain
  let mut scratch = if constructor_chain {
    0L
  } else {
    base.execution_bytes - data
  }
  for index in 0..<count {
    guard @execution.generated_sequence_step_index_at(sequence, index)
      is Some(step) &&
      @execution.select_generated_sequence_step(sequence, step)
      is Some(selected) &&
      bounded_relation_step_provider(
        selected,
        installed.execution,
        installed.measurement,
        family=installed.managed_providers,
      )
      is Some(provider) else {
      return None
    }
    let bounded = managed_provider_bounded_relation_capacity(
      provider,
      selected,
      installed.execution,
      installed.measurement,
    )
    let child = match bounded {
      Some(value) => value
      None =>
        match managed_provider_capacity(provider, selected) {
          Some(value) => value
          None => return None
        }
    }
    // A literal Values child may already quote less DATA than the general
    // output allowance. Preserve its WHOLE original recipe; subtract no
    // hypothetical maximum from its fixed metadata or real input storage.
    let deferred_data = match
      @execution.generated_sequence_step_at(sequence, index) {
      Some(@lower.ValuesStep(_)) => {
        let prepared = @lower.bound_preparation(
          @execution.generated_sequence_owner(sequence),
        )
        match @lower.node_at(prepared, step) {
          // Literal admission may already have selected a smaller exact
          // constructor. Keep that complete quote. Parameter Values retain
          // the original general DATA envelope, which this same before-row
          // charge replaces with actual retained output on the Task.
          Some(node) if @lower.node_values_literal_text_bytes(node) is Some(_) =>
            0L
          _ => data
        }
      }
      // A bounded family receipt retains its whole output holding. It has
      // no before-commit DATA attachment; do not subtract a policy maximum.
      _ => if bounded is Some(_) { 0L } else { data }
    }
    guard child.retained_bytes >= deferred_data &&
      child.execution_bytes >= deferred_data &&
      @execution.checked_preparation_add_product(
        fixed,
        child.retained_bytes - deferred_data,
        1L,
      )
      is Some(next) else {
      return None
    }
    // Before this child starts, only previous completed outputs exist.
    // Its complete E already coholds its own full R and private workspace.
    guard @execution.checked_preparation_add_product(
        fixed,
        child.execution_bytes - deferred_data,
        1L,
      )
      is Some(peak) else {
      return None
    }
    coheld_prefix_peak = Int64::max(coheld_prefix_peak, peak)
    fixed = next
    scratch = Int64::max(scratch, child.execution_bytes - deferred_data)
  }
  if bounded_family_chain {
    // Only an actual same-profile receipt and the ACK-qualified whole prefix
    // select this serial composition. Preserve every accepted output at end.
    fixed = Int64::max(fixed, coheld_prefix_peak)
    scratch = 0L
  }
  if constructor_chain {
    // The legacy sequence table is never constructed by this path. Retain
    // every child's fixed completion metadata, the largest complete live
    // child scratch, and the original chain handles/input-selection cursors.
    // Every logical output is funded BEFORE commit on the shared growth link;
    // reclaiming scratch never releases an earlier accepted output.
    guard @execution.checked_preparation_add_product(
        512L,
        count.to_int64(),
        256L,
      )
      is Some(handles) &&
      @execution.checked_preparation_add_product(
        handles, local_provider_selection_recipe_field_bytes, 1L,
      )
      is Some(handles) &&
      @execution.checked_preparation_add_product(fixed, handles, 1L)
      is Some(next) else {
      return None
    }
    fixed = next
  }
  // Original chain handles/cursors plus one bounded control envelope per
  // output budget for the existing growth link and funded-usage counter.
  guard @execution.checked_preparation_add_product(fixed, scratch, 1L)
    is Some(total) &&
    @execution.execution_capacity_inventory_add(
      total,
      @execution.CursorRootSlots,
      2L * count.to_int64() + 2L,
      1,
    )
    is Some(total) &&
    total <= full.execution_bytes else {
    return None
  }
  let retained = if metered_retention && full.retained_bytes >= data {
    full.retained_bytes - data
  } else {
    full.retained_bytes
  }
  @execution.execution_capacity(retained, Int64::max(retained, total))
}

///|
/// A Values publication check is discharged only by the exact one-step
/// bounded Values provider. Its admitted output and typed row construction
/// enforce the checked source obligation before completion is exposed.
pub fn local_module_bounded_values_publication(
  installed : LocalComputeModule,
  slot : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) else { return false }
  @execution.generated_sequence_step_index_at(sequence, 0) is Some(_) &&
  @execution.generated_sequence_step_index_at(sequence, 1) is None &&
  local_module_bounded_values_obligation(
    installed,
    slot,
    @execution.generated_sequence_step_index_at(sequence, 0).unwrap(),
  )
}

///|
/// Values publication belongs to the exact bounded source child, including
/// a source-free task executed by the existing linear Relation-chain owner.
pub fn local_module_bounded_values_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  guard local_module_relation_obligation_segment(installed, slot, step)
    is Some((sequence, execution, measurement, family)) &&
    local_sequence_contains_exact_step(sequence, step) &&
    @execution.select_generated_sequence_step(sequence, step) is Some(selected) &&
    @execution.generated_sequence_step_at(selected, 0)
    is Some(@lower.ValuesStep(_)) else {
    return false
  }
  let child = values_provider(execution, measurement)
  if !managed_provider_accepts(child, selected) ||
    managed_provider_capacity(child, selected) is None {
    return false
  }
  if @execution.generated_sequence_step_count(sequence) == 1 {
    return @execution.generated_sequence_step_index_at(sequence, 0) ==
      Some(step)
  }
  let owner = selected_relation_provider(execution, measurement, family~)
  managed_provider_accepts(owner, sequence) &&
  managed_provider_capacity(owner, sequence) is Some(_)
}

///|
// Resolve only the selected execution owner's actual bounded Local segment.
// A whole-family match without that original segment remains unsupported.
fn local_module_relation_obligation_segment(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> (
  @execution.GeneratedSequence,
  @execution.SequenceExecutionLimits,
  @execution.FixedInputGuardMeasureLimits,
  Array[ManagedProvider],
)? {
  guard installed.sequences.get(slot) is Some(sequence) else { return None }
  for provider in installed.managed_providers {
    if managed_provider_accepts(provider, sequence) {
      guard provider.infer_relation_prefix
        is Some((prefix, boundary, input_execution, input_measurement)) &&
        boundary > 0 &&
        step < boundary &&
        physical_equal(
          @execution.generated_sequence_owner(prefix),
          @execution.generated_sequence_owner(sequence),
        ) &&
        @execution.select_generated_sequence_step(sequence, boundary)
        is Some(model) &&
        @execution.generated_sequence_step_at(model, 0)
        is Some(@lower.InferBoundary(actual)) &&
        actual == boundary &&
        @execution.generated_sequence_step_count(prefix) == boundary else {
        return None
      }
      for index in 0..<boundary {
        if @execution.generated_sequence_step_index_at(prefix, index) !=
          Some(index) {
          return None
        }
      }
      return Some((prefix, input_execution, input_measurement, []))
    }
  }
  Some(
    (
      sequence,
      installed.execution,
      installed.measurement,
      installed.managed_providers,
    ),
  )
}

///|
pub(all) enum LocalBoundedTemporalRelationCheck {
  TimeSeries
  CalendarSeries
  CalendarBucket
  IntervalJoin
  AsOfJoin
  SequenceMatch
}

///|
fn local_sequence_contains_exact_step(
  sequence : @execution.GeneratedSequence,
  step : Int,
) -> Bool {
  let mut occurrences = 0
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    if @execution.generated_sequence_step_index_at(sequence, index) ==
      Some(step) {
      occurrences += 1
    }
  }
  occurrences == 1
}

///|
/// Temporal Relation obligations require the registered bounded family child,
/// either alone or inside the selected linear Relation-chain owner.
pub fn local_module_bounded_temporal_relation_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
  check : LocalBoundedTemporalRelationCheck,
) -> Bool {
  local_module_bounded_family_relation_obligation(installed, slot, step, selected => {
    match (@execution.generated_sequence_step_at(selected, 0), check) {
      (Some(@lower.TimeSeriesStep(_)), TimeSeries)
      | (Some(@lower.IntervalJoinStep(_)), IntervalJoin)
      | (Some(@lower.AsOfJoinStep(_)), AsOfJoin)
      | (Some(@lower.SequenceMatchStep(_)), SequenceMatch) => true
      (Some(@lower.CalendarStep(calendar)), CalendarSeries) =>
        @lower.calendar_row_bound(calendar) is Some(_)
      (Some(@lower.CalendarStep(calendar)), CalendarBucket) =>
        @lower.calendar_row_bound(calendar) is None &&
        @lower.node_at(
          @lower.bound_preparation(
            @execution.generated_sequence_owner(selected),
          ),
          step,
        ).map(node => @lower.operation(node)) ==
        Some("TEA.calendar.bucket")
      _ => false
    }
  })
}

///|
/// Session-only Relation admission leaves the public temporal selector enum
/// unchanged. Events-producing occurrences keep their managed Carrier route.
pub fn local_module_bounded_session_relation_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  local_module_bounded_family_relation_obligation(installed, slot, step, selected => {
    @execution.generated_sequence_step_at(selected, 0)
    is Some(@lower.EventStep(_)) &&
    @lower.node_at(
      @lower.bound_preparation(@execution.generated_sequence_owner(selected)),
      step,
    ).map(node => @lower.operation(node)) ==
    Some("TEA.window.session_assign")
  })
}

///|
fn local_module_bounded_family_relation_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
  matches : (@execution.GeneratedSequence) -> Bool,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) &&
    local_sequence_contains_exact_step(sequence, step) &&
    @execution.select_generated_sequence_step(sequence, step) is Some(selected) &&
    !local_sequence_outputs_carrier(selected) else {
    return false
  }
  if !matches(selected) ||
    !installed.managed_providers.any(provider => {
      managed_provider_accepts(provider, selected) &&
      managed_provider_capacity(provider, selected) is Some(_)
    }) {
    return false
  }
  if @execution.generated_sequence_step_count(sequence) == 1 {
    return @execution.generated_sequence_step_index_at(sequence, 0) ==
      Some(step)
  }
  // A different fused family provider cannot prove this child's execution.
  if installed.managed_providers.any(provider => {
      managed_provider_accepts(provider, sequence)
    }) {
    return false
  }
  let provider = selected_relation_provider(
    installed.execution,
    installed.measurement,
    family=installed.managed_providers,
  )
  managed_provider_accepts(provider, sequence) &&
  managed_provider_capacity(provider, sequence) is Some(_)
}

///|
/// Ranking checks belong to the exact finite-list occurrence owned by the
/// registered bounded family provider, not a generic Relation fallback.
pub fn local_module_bounded_ranking_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) &&
    @execution.generated_sequence_step_index_at(sequence, 0) == Some(step) &&
    @execution.generated_sequence_step_index_at(sequence, 1) is None &&
    @execution.generated_sequence_step_at(sequence, 0)
    is Some(@lower.VectorStep(_)) &&
    @lower.node_at(
      @lower.bound_preparation(@execution.generated_sequence_owner(sequence)),
      step,
    )
    is Some(node) &&
    @lower.operation(node) == "VEC.merge_rankings" else {
    return false
  }
  installed.managed_providers.any(provider => {
    managed_provider_accepts(provider, sequence)
  })
}

///|
/// Nearest checks require the registered bounded family provider for the
/// exact selected occurrence. A generic Relation fallback is insufficient.
pub fn local_module_bounded_nearest_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) &&
    @execution.generated_sequence_step_index_at(sequence, 0) == Some(step) &&
    @execution.generated_sequence_step_index_at(sequence, 1) is None &&
    @execution.generated_sequence_step_at(sequence, 0)
    is Some(@lower.VectorStep(_)) &&
    @lower.node_at(
      @lower.bound_preparation(@execution.generated_sequence_owner(sequence)),
      step,
    )
    is Some(node) &&
    @lower.operation(node) == "VEC.knn_join" else {
    return false
  }
  installed.managed_providers.any(provider => {
    managed_provider_accepts(provider, sequence)
  })
}

///|
/// An operation obligation is discharged only by the bounded provider for
/// the exact source step, inside the provider selected for the whole task.
priv enum LocalBinaryRelationOperation {
  Append
  Set
  CrossJoin
}

///|
fn local_bounded_binary_relation_step(
  installed : LocalComputeModule,
  slot : Int,
  required_step : Int,
  operation : LocalBinaryRelationOperation,
) -> Bool {
  guard local_module_relation_obligation_segment(installed, slot, required_step)
    is Some((sequence, execution, measurement, family)) else {
    return false
  }
  let count = @execution.generated_sequence_step_count(sequence)
  let mut position = -1
  for index in 0..<count {
    if @execution.generated_sequence_step_index_at(sequence, index) ==
      Some(required_step) {
      if position >= 0 {
        return false
      }
      position = index
    }
  }
  guard position >= 0 &&
    @execution.select_generated_sequence_step(sequence, required_step)
    is Some(selected) else {
    return false
  }
  let matches = match
    @execution.generated_sequence_step_at(sequence, position) {
    Some(@lower.AppendStep(_)) => operation is Append
    Some(@lower.SetStep(_)) => operation is Set
    Some(@lower.CrossJoinStep(_)) => operation is CrossJoin
    _ => false
  }
  if !matches {
    return false
  }
  // Family registrations precede the built-in Relation providers. Do not
  // discharge a Relation check with a different provider's acceptance.
  for provider in family {
    if managed_provider_accepts(provider, sequence) {
      return false
    }
  }
  if count > 1 &&
    !managed_provider_accepts(
      selected_relation_provider(execution, measurement, family~),
      sequence,
    ) {
    return false
  }
  let provider = match operation {
    Append => append_provider(execution, measurement)
    Set => set_provider(execution, measurement)
    CrossJoin => cross_join_provider(execution, measurement)
  }
  managed_provider_accepts(provider, selected)
}

///|
pub fn local_module_bounded_append_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  local_bounded_binary_relation_step(installed, slot, step, Append)
}

///|
pub fn local_module_bounded_set_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  local_bounded_binary_relation_step(installed, slot, step, Set)
}

///|
pub fn local_module_bounded_cross_join_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  local_bounded_binary_relation_step(installed, slot, step, CrossJoin)
}

///|
/// A retained Relation check is discharged by the exact bounded child of the
/// selected task. A registered family provider cannot stand in for that child.
pub(all) enum LocalBoundedRelationCheck {
  Group
  Analytic
  Pivot
  RowWindow
  TopK
  Lag
  JsonPick
  Watermark
  Dedupe
  Assertion
  Expansion
}

///|
fn local_bounded_relation_check(
  installed : LocalComputeModule,
  slot : Int,
  required_step : Int,
  check : LocalBoundedRelationCheck,
) -> Bool {
  guard local_module_relation_obligation_segment(installed, slot, required_step)
    is Some((sequence, execution, measurement, family)) else {
    return false
  }
  let count = @execution.generated_sequence_step_count(sequence)
  let mut position = -1
  for index in 0..<count {
    if @execution.generated_sequence_step_index_at(sequence, index) ==
      Some(required_step) {
      if position >= 0 {
        return false
      }
      position = index
    }
  }
  guard position >= 0 &&
    @execution.select_generated_sequence_step(sequence, required_step)
    is Some(selected) else {
    return false
  }
  let matches = match
    @execution.generated_sequence_step_at(sequence, position) {
    Some(@lower.RowStep(kernel)) =>
      if @lower.kernel_json_pick(kernel) is Some(_) {
        check is JsonPick
      } else if @lower.kernel_unique_keys(kernel) is Some(_) {
        check is Assertion
      } else if @lower.kernel_bindings(kernel) is Some(_) ||
        @lower.kernel_is_projection(kernel) {
        false
      } else {
        match check {
          Group =>
            (match @lower.kernel_group(kernel) {
              Some(group) =>
                @execution.group_execution_supported_with_numeric(group)
              None => false
            }) ||
            @lower.kernel_count_group(kernel) is Some(_)
          Analytic =>
            match @lower.kernel_analytic(kernel) {
              Some(analytic) =>
                @execution.analytic_execution_supported_with_numeric(analytic)
              None => false
            }
          Pivot =>
            match @lower.kernel_pivot(kernel) {
              Some(pivot) =>
                @execution.pivot_execution_supported_with_numeric(pivot)
              None => false
            }
          RowWindow => false
          TopK =>
            match @lower.kernel_body(kernel) {
              @lower.TopK(_, _) | @lower.PartitionedTopK(_, _) => true
              _ => false
            }
          Lag => @lower.kernel_body(kernel) is @lower.Lag(_, _)
          JsonPick => false
          Watermark =>
            @lower.kernel_body(kernel) is @lower.Watermark(_, _, _, _)
          Dedupe => @lower.kernel_body(kernel) is @lower.DedupeRows
          Assertion =>
            match @lower.kernel_body(kernel) {
              @lower.AssertAll(_) => true
              _ => false
            }
          Expansion =>
            match @lower.kernel_body(kernel) {
              @lower.Unpivot(_, _, _, _) | @lower.Unnest(_, _, _, _, _) => true
              _ => false
            }
        }
      }
    Some(@lower.WindowStep(_)) => check is RowWindow
    _ => false
  }
  if !matches {
    return false
  }
  if count > 1 &&
    !managed_provider_accepts(
      selected_relation_provider(execution, measurement, family~),
      sequence,
    ) {
    return false
  }
  bounded_relation_step_provider(selected, execution, measurement) is Some(_)
}

///|
pub fn local_module_bounded_relation_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
  check : LocalBoundedRelationCheck,
) -> Bool {
  local_bounded_relation_check(installed, slot, step, check)
}

///|
/// Nest output checks belong to the exact bounded child of the selected task.
/// A family provider cannot discharge these retained Relation obligations.
pub fn local_module_bounded_nest_obligation(
  installed : LocalComputeModule,
  slot : Int,
  step : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) &&
    local_sequence_contains_exact_step(sequence, step) &&
    @execution.select_generated_sequence_step(sequence, step) is Some(selected) &&
    @execution.generated_sequence_step_at(selected, 0)
    is Some(@lower.NestStep(_)) else {
    return false
  }
  for provider in installed.managed_providers {
    if managed_provider_accepts(provider, sequence) {
      return false
    }
  }
  if @execution.generated_sequence_step_count(sequence) > 1 &&
    !managed_provider_accepts(
      selected_relation_provider(
        installed.execution,
        installed.measurement,
        family=installed.managed_providers,
      ),
      sequence,
    ) {
    return false
  }
  let provider = nest_provider(installed.execution, installed.measurement)
  managed_provider_accepts(provider, selected) &&
  managed_provider_capacity(provider, selected) is Some(_)
}

///|
/// The bounded provider owning `sequence`: a registered family provider first,
/// then the built-in relation providers bound to the module limits.

///|
/// Select the same installed bounded implementation for an acquisition's
/// checked Relation prefix. This grants no task or acquisition authority.
/// Unsupported prefixes return None; there is no synchronous fallback.
pub fn local_bounded_relation_provider(
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  sequence : @execution.GeneratedSequence,
  family? : Array[ManagedProvider] = [],
) -> ManagedProvider? {
  local_managed_provider_for(family, execution, measurement, sequence)
}

///|
fn local_managed_provider_for(
  family : Array[ManagedProvider],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  sequence : @execution.GeneratedSequence,
) -> ManagedProvider? {
  for provider in family {
    if managed_provider_accepts(provider, sequence) {
      return Some(provider)
    }
  }
  local_default_managed_provider(family, execution, measurement, sequence)
}

///|
fn local_default_managed_provider(
  family : Array[ManagedProvider],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  sequence : @execution.GeneratedSequence,
) -> ManagedProvider? {
  let relation = selected_relation_provider(execution, measurement, family~)
  if managed_provider_accepts(relation, sequence) {
    return Some(relation)
  }
  let global_count = global_count_provider(execution, measurement)
  if managed_provider_accepts(global_count, sequence) {
    return Some(global_count)
  }
  let group = group_provider(execution, measurement)
  if managed_provider_accepts(group, sequence) {
    return Some(group)
  }
  let row_window = row_window_provider(execution, measurement)
  if managed_provider_accepts(row_window, sequence) {
    return Some(row_window)
  }
  let unpivot = unpivot_provider(execution, measurement)
  if managed_provider_accepts(unpivot, sequence) {
    return Some(unpivot)
  }
  let unnest = unnest_provider(execution, measurement)
  if managed_provider_accepts(unnest, sequence) {
    return Some(unnest)
  }
  let cross_join = cross_join_provider(execution, measurement)
  if managed_provider_accepts(cross_join, sequence) {
    return Some(cross_join)
  }
  let append = append_provider(execution, measurement)
  if managed_provider_accepts(append, sequence) {
    return Some(append)
  }
  let set = set_provider(execution, measurement)
  if managed_provider_accepts(set, sequence) {
    return Some(set)
  }
  let nest = nest_provider(execution, measurement)
  if managed_provider_accepts(nest, sequence) {
    return Some(nest)
  }
  let values = values_provider(execution, measurement)
  if managed_provider_accepts(values, sequence) {
    return Some(values)
  }
  None
}

///|
/// Exact installed sequence capability used by candidate estimation. This is
/// the same bounded provider decision used during preparation: managed Local
/// work never falls back to the synchronous whole-sequence evaluator.
pub fn local_module_managed_sequence_supported(
  installed : LocalComputeModule,
  slot : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) else { return false }
  local_module_managed_provider(installed, slot, sequence) is Some(_)
}

///|
/// Exact output kind of the installed physical task, including a selected
/// prefix whose target differs from the final Stage target.
pub fn local_module_sequence_outputs_carrier(
  installed : LocalComputeModule,
  slot : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) else { return false }
  local_sequence_outputs_carrier(sequence)
}

///|
pub fn local_module_sequence_contains_carrier_step(
  installed : LocalComputeModule,
  slot : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) else { return false }
  local_sequence_contains_carrier_step(sequence)
}

///|
pub fn local_module_sequence_has_carrier_input(
  installed : LocalComputeModule,
  slot : Int,
) -> Bool {
  guard installed.sequences.get(slot) is Some(sequence) else { return false }
  local_sequence_has_carrier_input(sequence)
}

///|
pub fn local_module_managed_capacity(
  installed : LocalComputeModule,
) -> @connector.FixedComputeCapacity {
  installed.managed_capacity
}

///|
pub fn local_module_execution_limits(
  installed : LocalComputeModule,
) -> @execution.SequenceExecutionLimits {
  installed.execution
}

///|
pub fn local_module_measurement_limits(
  installed : LocalComputeModule,
) -> @execution.FixedInputGuardMeasureLimits {
  installed.measurement
}

///|
pub fn local_module_max_work(installed : LocalComputeModule) -> Int {
  installed.max_work
}

///|
/// The slot is this module's bounded configuration index, not a semantic task
/// identity. Candidate preparation still verifies the exact request owner.
pub fn prepare_local_module_compute(
  installed : LocalComputeModule,
  slot : Int,
  request : @connector.FixedComputeRequest,
  join_output_ceiling : (Int, Int64)?,
  join_output_ceilings? : Array[(Int, Int64)] = [],
) -> Result[@connector.SynchronousCompute, LocalModuleIssue] {
  let (candidate, choice) = match
    local_module_candidate(installed, slot, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    prepare_local_compute_execution(
      choice,
      candidate,
      installed.execution,
      installed.measurement,
      join_output_ceiling~,
      join_output_ceilings~,
    ) {
    Ok(compute) => Ok(compute)
    Err(InvalidLimits) => Err(Capacity)
    Err(issue) => Err(Execution(issue))
  }
}

///|
/// Both execution forms select the exact installed sequence and request. A
/// conversion changes representation, never the selected computation or owner.
fn local_module_candidate(
  installed : LocalComputeModule,
  slot : Int,
  request : @connector.FixedComputeRequest,
) -> Result[
  (
    @connector.PreparedCompute[@execution.GeneratedSequence],
    @connector.FixedComputeChoice,
  ),
  LocalModuleIssue,
] {
  guard installed.sequences.get(slot) is Some(sequence) else {
    return Err(Candidate(ForeignPreparation))
  }
  let candidate = match
    local_fixed_compute_candidate(
      installed.registration,
      request,
      sequence,
      [],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      installed.max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  let choice = match
    @connector.choose_fixed_compute_candidate(
      installed.registry,
      request,
      [@connector.prepared_compute_candidate(candidate)],
      Some([0]),
      installed.max_work,
    ) {
    Ok(Proposed(choice)) => choice
    Ok(_) => return Err(NotSelected)
    Err(issue) => return Err(Candidate(issue))
  }
  Ok((candidate, choice))
}

///|
/// Pure preparation for an installed Local implementation receiving retained
/// inputs. The common Host must reserve and start the returned execution before
/// a Store reader is invoked. No file or transport implementation is selected here.
pub fn[E] prepare_local_module_materializing_compute(
  installed : LocalComputeModule,
  slot : Int,
  request : @connector.FixedComputeRequest,
  imports : LocalImportLimits,
  issue : (LocalMaterializingIssue) -> E,
  join_output_ceiling : (Int, Int64)?,
  output_limits? : LocalExportLimits? = None,
  join_output_ceilings? : Array[(Int, Int64)] = [],
  expansion_output_ceilings? : Array[(Int, Int64)] = [],
  session_output_ceilings? : Array[(Int, Int64)] = [],
  interval_search_ceilings? : Array[(Int, Int64)] = [],
  asof_search_ceilings? : Array[(Int, Int64)] = [],
  sequence_match_ceilings? : Array[(Int, Int64, Int64)] = [],
  aggregate_output_ceilings? : Array[@connector.AggregateOutputCeiling] = [],
  analytic_envelopes? : Array[@connector.AnalyticEnvelope] = [],
) -> Result[
  @connector.PreparedExecution[LocalMaterializingAttempt, E],
  LocalModuleIssue,
] {
  let (candidate, choice) = match
    local_module_candidate(installed, slot, request) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let startup = local_module_materializing_start_capacity(installed, slot)
  prepare_local_materializing_execution_with_startup(
    choice,
    candidate,
    installed.execution,
    installed.measurement,
    imports,
    issue,
    join_output_ceiling~,
    output_limits~,
    join_output_ceilings~,
    expansion_output_ceilings~,
    session_output_ceilings~,
    interval_search_ceilings~,
    asof_search_ceilings~,
    sequence_match_ceilings~,
    aggregate_output_ceilings~,
    analytic_envelopes~,
    family_providers=installed.managed_providers,
    provider_capacity=Some(installed.managed_capacity),
    startup~,
  ).map_err(error => Materializing(error))
}

///|
/// Only this module's original default constructor can fund variable output
/// before its buffer commits. Its importer and file writer use the same Task
/// reservation before decoding or emitting each actual bounded prefix. Unknown and injected providers keep the full
/// constructor, including its original completion accounting.
pub fn local_module_materializing_start_capacity(
  installed : LocalComputeModule,
  slot : Int,
) -> (@execution.ExecutionCapacity, Bool)? {
  guard installed.sequences.get(slot) is Some(sequence) &&
    local_module_metered_output_start_capacity(installed, slot, sequence)
    is Some(startup) &&
    local_module_capacity(installed, slot) is Some(full) else {
    return None
  }
  // Standing growth: the copied GeneratedSequence (22 borrowed references),
  // WorkspaceGrowth and its option/counter, reserve closures, typed failure
  // Ref and same-task completion closure. The transport link adds seven
  // peak/reentry/cumulative Refs, the summed-growth and importer/exporter
  // callbacks and their options. Include old/new Result/Some and quantity
  // carriers at the refusal/current fence. Per-port/export state is quoted
  // separately before those original transfer closures are constructed.
  guard @execution.preparation_representation_cost({
      record_headers: 42L,
      reference_slots: 84L,
      scalar_words: 48L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) &&
    @execution.checked_preparation_add_product(
      startup.retained_bytes,
      controls,
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      startup.execution_bytes,
      controls,
      1L,
    )
    is Some(execution) &&
    startup.retained_bytes <= full.retained_bytes &&
    startup.execution_bytes <= full.execution_bytes &&
    (
      startup.retained_bytes < full.retained_bytes ||
      startup.execution_bytes < full.execution_bytes
    ) else {
    return None
  }
  @execution.execution_capacity(retained, execution).map(capacity => {
    (capacity, startup.retained_bytes < full.retained_bytes)
  })
}

///|
/// Capacity for the module's actual fixed sequence and selected limits, not an
/// estimate derived from output cardinality or an exported mutable sequence.
pub fn local_module_capacity(
  installed : LocalComputeModule,
  slot : Int,
) -> @execution.ExecutionCapacity? {
  match installed.selected_capacities.get(slot) {
    Some(value) => value
    None => None
  }
}
