///|
// Admit only the next construction on this SAME Request. Both growth calls
// can invoke current; reentry may neither replace nor revive the original.
fn[I] reserve_request_domain_graph_construction(
  owner : ClientRequestPreparation[I],
  input : I,
  prepared : @publication_host.PreparedClientProgram,
  bytes : Int64,
) -> Result[Unit, ClientRequestProgramPlanIssue] {
  guard bytes >= 0L &&
    owner.phase == Selecting &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(body) &&
    physical_equal(body, prepared) &&
    owner.program_capacity is Some(capacity) else {
    return Err(Preparation(ForeignOriginal))
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
    return Err(Preparation(Policy))
  }
  owner.program_domain_quote = Some((r, e))
  let result = @resources.reserve_working_preparation_phase(
    capacity, input, r, e,
  )
  guard owner.phase == Selecting &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(body) &&
    physical_equal(body, prepared) &&
    owner.program_capacity is Some(original_capacity) &&
    physical_equal(original_capacity, capacity) &&
    owner.program_domain_quote == Some((r, e)) else {
    return Err(Preparation(ForeignOriginal))
  }
  result.map_err(issue => Preparation(Capacity(issue)))
}

///|
// The original supplied policy String is borrowed, not copied. Its two real
// admissions coexist with the original dependency body during Graph issuance.
// UTF-8 is at most three bytes per UTF-16 unit; nodes cannot outnumber bytes.
// The existing parser limits clip this input-derived construction envelope.
fn serialization_source_free_policy_construction_cost(wire : String) -> Int64? {
  guard wire.length() > 0 && wire.length() <= 1000000 else { return None }
  let bytes = Int::min(3 * wire.length(), 1000000)
  let nodes = Int::min(bytes, 100000)
  guard program_artifact_parse_layout((bytes, nodes, Int::min(nodes, 100)))
    is Some(parse) &&
    @execution.compose_preparation_representation([
      parse.value,
      parse.value,
      parse.temporary,
    ])
    is Some(units) else {
    return None
  }
  @execution.preparation_representation_cost(units)
}

///|
/// Construct the existing source-free Content component only after the SAME
/// Request has reserved its actual measurement storage and complete measured
/// Graph/prefix/Result overlap. The original policy/Graph issuers still admit
/// every semantic field. A sizing result never issues a policy or I/O grant.
/// The original component stays in the parent's existing domain slot through
/// compilation or failed-child cleanup; no second Ledger or Graph cache exists.
pub fn[I] prepare_request_serialization_graph(
  owner : ClientRequestPreparation[I],
  input : I,
  task : Int,
  step : Int,
  policy_cid : String,
  policy_wire : String,
  max_rows : Int,
  max_bytes : Int,
  include_results : Bool,
  contracts : ClientInstalledSequenceContracts,
  manifests~ : @publication_host.ClientCompilationManifests,
  compilation_limits~ : @publication_host.ClientPureCompilationLimits,
  model_occurrence? : @publication_host.ClientInferOccurrence? = None,
) -> Result[
  @publication_host.ClientSerializationPlanGraph,
  ClientRequestProgramPlanIssue,
] {
  prepare_request_serialization_graph_owned(
    owner,
    input,
    task,
    step,
    Some((policy_cid, policy_wire)),
    max_rows,
    max_bytes,
    include_results,
    contracts,
    manifests~,
    compilation_limits~,
    model_occurrence~,
  )
}

///|
/// Same acquired policy/Source originals, backed before their provenance walk.
/// The Source's physical capture, Account/current and completion remain required.
pub fn[I] prepare_request_acquired_serialization_graph(
  owner : ClientRequestPreparation[I],
  input : I,
  task : Int,
  step : Int,
  max_rows : Int,
  max_bytes : Int,
  include_results : Bool,
  contracts : ClientInstalledSequenceContracts,
  manifests~ : @publication_host.ClientCompilationManifests,
  compilation_limits~ : @publication_host.ClientPureCompilationLimits,
  model_occurrence? : @publication_host.ClientInferOccurrence? = None,
) -> Result[
  @publication_host.ClientSerializationPlanGraph,
  ClientRequestProgramPlanIssue,
] {
  prepare_request_serialization_graph_owned(
    owner,
    input,
    task,
    step,
    None,
    max_rows,
    max_bytes,
    include_results,
    contracts,
    manifests~,
    compilation_limits~,
    model_occurrence~,
  )
}

///|
fn[I] prepare_request_serialization_graph_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  task : Int,
  step : Int,
  source_free_policy : (String, String)?,
  max_rows : Int,
  max_bytes : Int,
  include_results : Bool,
  contracts : ClientInstalledSequenceContracts,
  manifests~ : @publication_host.ClientCompilationManifests,
  compilation_limits~ : @publication_host.ClientPureCompilationLimits,
  model_occurrence~ : @publication_host.ClientInferOccurrence?,
) -> Result[
  @publication_host.ClientSerializationPlanGraph,
  ClientRequestProgramPlanIssue,
] {
  guard (
      owner.phase == ContentPlanReserved ||
      owner.phase == ModelPlanReserved ||
      owner.phase == EffectPlanReserved
    ) &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_domain_compilation_inputs is None &&
    owner.program_domain_quote is None &&
    owner.program_compilation is None &&
    !owner.program_body_attempted else {
    return Err(Preparation(ForeignOriginal))
  }
  let selected : (
    ClientLocalSequenceOwner,
    @publication_host.PreparedClientProgram,
  ) = match owner.phase {
    ContentPlanReserved | ModelPlanReserved => {
      guard model_occurrence is None &&
        owner.compiled_program is Some(prepared) &&
        owner.program_capacity is Some(_) else {
        return Err(Preparation(ForeignOriginal))
      }
      (Pure(prepared), prepared)
    }
    EffectPlanReserved => {
      // This is only the original Effect's intermediate Content component.
      // It cannot issue a standalone pure Result or an Effect-free owner.
      guard !include_results &&
        owner.compiled_effect is Some(effect) &&
        owner.effect_capacity is Some(_) &&
        owner.effect_plan is None &&
        model_occurrence is Some(occurrence) &&
        @publication_host.client_infer_occurrence_matches_effect(
          occurrence, effect,
        ) &&
        task ==
        @publication_host.client_infer_occurrence_coordinates(occurrence).1 &&
        step <
        @publication_host.client_infer_occurrence_coordinates(occurrence).2 else {
        return Err(Preparation(ForeignOriginal))
      }
      (Effect(effect), occurrence.owner)
    }
    _ => return Err(Preparation(ForeignOriginal))
  }
  let (sequence_owner, prepared) = selected
  guard (
      source_free_policy is Some(_) &&
      @publication_host.prepared_client_acquisition_count(prepared) == 0
    ) ||
    (
      source_free_policy is None &&
      @publication_host.prepared_client_acquisition_count(prepared) > 0
    ) else {
    return Err(Installed(Unsupported))
  }
  let previous = owner.phase
  owner.phase = Selecting
  preparation_module_call(
    () => {
      // This returned inventory contains actual task/Result/port counts. The
      // original Plan input envelope already backs nested lowering helpers.
      let units = match
        @publication_host.prepared_client_pure_measurement_storage(
          prepared, compilation_limits,
        ) {
        Err(issue) => return Err(Construction(issue))
        Ok(value) => value
      }
      guard @execution.preparation_representation_cost(units) is Some(storage) else {
        return Err(Preparation(Policy))
      }
      let policy_geometry = match source_free_policy {
        Some(_) => None
        None =>
          Some(
            match
              @publication_host.prepared_client_serialization_policy_construction(
                prepared, task,
              ) {
              Err(issue) => return Err(SerializationGraph(issue))
              Ok(value) => value
            },
          )
      }
      let policy_collections = match policy_geometry {
        None => 0L
        Some(value) =>
          match serialization_policy_collection_cost(value) {
            None => return Err(Preparation(Policy))
            Some(value) => value
          }
      }
      guard @execution.checked_preparation_add_product(
          storage, policy_collections, 1L,
        )
        is Some(storage) else {
        return Err(Preparation(Policy))
      }
      match
        reserve_request_model_graph_construction(
          owner, input, sequence_owner, storage,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let geometry = match
        @publication_host.measure_prepared_client_serialization_graph_construction(
          prepared,
          task,
          step,
          max_rows,
          max_bytes,
          10000,
          @publication_host.prepared_client_values_sequence_limits(prepared),
          1000000,
          100000,
          100,
          include_results~,
        ) {
        Err(issue) => return Err(SerializationGraph(issue))
        Ok(value) => value
      }
      let policy_bytes = match source_free_policy {
        Some((_, wire)) =>
          serialization_source_free_policy_construction_cost(wire)
        None =>
          serialization_acquired_policy_body_cost(policy_geometry.unwrap())
      }
      guard serialization_graph_construction_cost(geometry) is Some(graph_bytes) &&
        policy_bytes is Some(policy_bytes) &&
        @execution.checked_preparation_add_product(
          graph_bytes, policy_bytes, 1L,
        )
        is Some(bytes) else {
        return Err(Preparation(Policy))
      }
      match
        reserve_request_model_graph_construction(
          owner, input, sequence_owner, bytes,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let selected = match source_free_policy {
        Some((policy_cid, policy_wire)) => {
          let policy = match
            @publication_host.admit_source_free_result_policy_body(
              policy_cid, policy_wire, 1000000, 100000, 100,
            ) {
            Err(issue) => return Err(SerializationGraph(Policy(issue)))
            Ok(value) => value
          }
          match
            (if include_results {
              @publication_host.issue_prepared_client_serialization_plan_graph(
                prepared,
                task,
                step,
                policy,
                max_rows,
                max_bytes,
                10000,
                @publication_host.prepared_client_values_sequence_limits(
                  prepared,
                ),
                1000000,
                100000,
                100,
              )
            } else {
              @publication_host.issue_prepared_client_serialization_plan_component(
                prepared,
                task,
                step,
                policy,
                max_rows,
                max_bytes,
                10000,
                @publication_host.prepared_client_values_sequence_limits(
                  prepared,
                ),
                1000000,
                100000,
                100,
              )
            }) {
            Err(issue) => return Err(SerializationGraph(issue))
            Ok(value) => value
          }
        }
        None =>
          match
            (if include_results {
              @publication_host.issue_prepared_client_acquired_serialization_plan_graph(
                prepared,
                task,
                step,
                max_rows,
                max_bytes,
                10000,
                @publication_host.prepared_client_values_sequence_limits(
                  prepared,
                ),
                1000000,
                100000,
                100,
              )
            } else {
              @publication_host.issue_prepared_client_acquired_serialization_plan_component(
                prepared,
                task,
                step,
                max_rows,
                max_bytes,
                10000,
                @publication_host.prepared_client_values_sequence_limits(
                  prepared,
                ),
                1000000,
                100000,
                100,
              )
            }) {
            Err(issue) => return Err(SerializationGraph(issue))
            Ok(value) => value
          }
      }
      owner.program_domain_compilation_inputs = Some(
        RequestSerializationGraph(
          manifests, compilation_limits, contracts, selected,
        ),
      )
      owner.program_domain_quote = None
      owner.phase = previous
      Ok(selected)
    },
    () => {
      if owner.phase == Selecting {
        owner.phase = if previous == EffectPlanReserved {
          EffectBodyFailed
        } else {
          ProgramBodyFailed
        }
      }
    },
  )
}
