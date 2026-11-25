///|
// Fixed same-Request control census; no payload bodies or engine-heap claim.
// Retained: selected typed profiles and their schema DTO (6H/5R/35W);
// capacity+return with the selected row scalar (2H/2R/4W);
// Node generation/output/workspace/bundle (4H/3R/30W), existing-map entry and
// original bag links (1H/5R/1W). The original checked input schema and
// text/wire bodies remain borrowed.
let request_serialization_output_retained_controls : Int64 = @execution.preparation_representation_cost({
    record_headers: 13L,
    reference_slots: 16L,
    scalar_words: 70L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
// In addition to that retained census, conservatively cohold fixed scratch:
// remaining input template+closure with generation rows (6H/6R/63W);
// capacity's 20 inventory items+2 arrays
// (22H/20R/60W), validation arrays (3H/0R/39W) and two LocalExport records
// (2H/4R/4W); 32 scalar Option/Result/checked-arithmetic cells (32H/32R/32W);
// bridge argument/result arrays+tuples including that scalar (4H/5R/57W).
// The schema DTO is shared into the selected export: transfer its H1/W4 from
// scratch to retained, not a second peak allocation or a borrowed Graph schema.
// These are finite actual constructor carriers, never a row-sized allowance.
let request_serialization_output_execution_controls : Int64 = @execution.preparation_representation_cost({
    record_headers: 13L + 6L + 22L + 3L + 2L + 32L + 4L,
    reference_slots: 16L + 6L + 20L + 4L + 32L + 5L,
    scalar_words: 70L + 63L + 60L + 39L + 4L + 32L + 57L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
let terminal_result_controls : Int64 = @execution.preparation_representation_cost({
    record_headers: 5L,
    reference_slots: 5L,
    scalar_words: 20L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
// Typed Result profile, two export limits, capacity sums and temporary
// inventory, coheld with the already quoted input projection.
let terminal_result_construction : Int64 = @execution.preparation_representation_cost({
    record_headers: 24L,
    reference_slots: 24L,
    scalar_words: 64L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
pub(all) struct ClientSerializationOutputDemand {
  limits : ClientSerializationWorkspaceLimits
  capacity : @execution.ExecutionCapacity
  generation_rows : Int
  result_limits : @publication_host.PublicationOutputExportLimits?
}

///|
/// Before any demand accessor/projection, admit its fixed constructor on the
/// existing original Request. The result is bounded DATA, never permission.
pub fn[I] prepare_request_serialization_output_limits(
  owner : ClientRequestPreparation[I],
  input : I,
  compiled : @publication_host.ClientCompiledRun,
  component : @publication_host.ClientSerializationPlanGraph,
  generation_rows : Int,
  construct_limits : () -> ClientSerializationWorkspaceLimits?,
  terminal? : Bool = false,
) -> Result[ClientSerializationOutputDemand, ClientRequestPreparationIssue] {
  let previous = owner.phase
  guard (previous == ContentPlanReserved || previous == ModelPlanReserved) &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_compilation is Some(@publication_host.Tasks(compilation)) &&
    owner.program_capacity is Some(capacity) &&
    owner.program_content is NoContent &&
    !owner.program_body_attempted else {
    return Err(ForeignOriginal)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  guard @execution.checked_preparation_add_product(
      r,
      request_serialization_output_retained_controls +
      (if terminal { terminal_result_controls } else { 0L }),
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      e,
      request_serialization_output_execution_controls +
      (if terminal { terminal_result_construction } else { 0L }),
      1L,
    )
    is Some(e) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      match
        @resources.reserve_working_preparation_phase(capacity, input, r, e) {
        Ok(_) => ()
        Err(issue) => return Err(Capacity(issue))
      }
      match
        @resources.check_working_preparation_capacity_current(capacity, input) {
        Ok(_) => ()
        Err(issue) => return Err(Capacity(issue))
      }
      guard owner.phase == Selecting &&
        owner.input is Some(original) &&
        physical_equal(original, input) &&
        owner.compiled_program is Some(body) &&
        physical_equal(body, prepared) &&
        owner.program_capacity is Some(current) &&
        physical_equal(current, capacity) &&
        owner.program_compilation is Some(@publication_host.Tasks(artifact)) &&
        physical_equal(artifact, compilation) &&
        @publication_host.client_compiled_run_matches_tasks(
          compiled, prepared, compilation,
        ) &&
        @publication_host.client_compiled_run_serialization(compiled)
        is Some(observed_component) &&
        physical_equal(observed_component, component) &&
        @publication_host.client_task_compilation_serialization(compilation)
        is Some(original_component) &&
        physical_equal(component, original_component) else {
        return Err(ForeignOriginal)
      }
      let limits = match construct_limits() {
        Some(value) => value
        None => return Err(Policy)
      }
      let selected = match
        client_serialization_output_limits(component, generation_rows, limits) {
        Some(value) => value
        None => return Err(Policy)
      }
      let workspace = match client_serialization_workspace_capacity(selected) {
        Some(value) => value
        None => return Err(Policy)
      }
      let (workspace, result_limits) = if terminal {
        guard client_terminal_content_result_workspace(
            limits,
            @publication_host.prepared_client_result_count(prepared),
          )
          is Some((result_limits, result_capacity)) &&
          @execution.add_execution_capacity(workspace, result_capacity)
          is Some(combined) else {
          return Err(Policy)
        }
        (combined, Some(result_limits))
      } else {
        (workspace, None)
      }
      let demand = {
        limits: selected,
        capacity: workspace,
        generation_rows: Int::min(generation_rows, component.max_rows),
        result_limits,
      }
      // The same original imported current check must still run even though
      // the already-admitted extents do not change. No current result is kept.
      match
        @resources.check_working_preparation_capacity_current(capacity, input) {
        Ok(_) => ()
        Err(issue) => return Err(Capacity(issue))
      }
      guard owner.phase == Selecting &&
        owner.input is Some(original) &&
        physical_equal(original, input) &&
        owner.compiled_program is Some(body) &&
        physical_equal(body, prepared) &&
        owner.program_capacity is Some(original_capacity) &&
        physical_equal(original_capacity, capacity) &&
        owner.program_compilation
        is Some(@publication_host.Tasks(original_compilation)) &&
        physical_equal(original_compilation, compilation) &&
        owner.program_content is NoContent &&
        !owner.program_body_attempted else {
        return Err(ForeignOriginal)
      }
      Ok(demand)
    },
    () => owner.phase = previous,
  )
}
