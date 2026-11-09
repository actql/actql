// Scalar implementation inventories compiled in the SAME Common issuer.
// No provider Catalog/Mapping, foreign capacity, authorization or callback is
// accepted. These private tags select constructors, never operations/permits.

///|
#export_name("clientProgramHubSpotEffectConstructorCapacity")
pub fn client_program_hubspot_effect_constructor_capacity(
  kind : Int,
  input : Array[Int],
  output : Array[Int],
  counts : Array[Int],
) -> @execution.ExecutionCapacity? {
  match kind {
    7 if input.is_empty() && output.is_empty() && counts.length() == 4 =>
      @hubspot_catalog.effect_installation_construction_capacity(
        counts[0],
        counts[1],
        counts[2],
        counts[3],
      )
    0 | 6 if input.length() == 23 && output.is_empty() && counts.length() == 3 => {
      let capacity = if kind == 0 {
        @hubspot_catalog.effect_request_construction_capacity
      } else {
        @hubspot_catalog.effect_finalization_construction_capacity
      }
      capacity(
        {
          max_input_bytes: input[0],
          max_nodes: input[1],
          max_depth: input[2],
          max_fields: input[3],
          max_name_bytes: input[4],
          max_value_nodes: input[5],
          max_value_text_bytes: input[6],
          max_comparison_work: input[7],
          max_output_bytes: input[8],
          max_output_nodes: input[9],
          max_output_depth: input[10],
        },
        {
          max_rows: input[11],
          max_properties: input[12],
          max_trace_bytes: input[13],
          max_body_bytes: input[14],
          max_body_nodes: input[15],
          max_body_depth: input[16],
        },
        {
          max_rows: input[17],
          max_properties: input[18],
          max_columns: input[19],
          max_request_bytes: input[20],
          max_request_nodes: input[21],
          max_request_depth: input[22],
        },
        counts[0],
        counts[1],
        counts[2],
      )
    }
    1 if input.length() == 8 && output.length() == 3 && counts.length() == 3 =>
      @hubspot_catalog.effect_target_construction_capacity(
        {
          max_bytes: input[0],
          max_nodes: input[1],
          max_depth: input[2],
          max_rows: input[3],
          max_columns: input[4],
          max_cursor_units: input[5],
          max_value_nodes: input[6],
          max_value_text_bytes: input[7],
        },
        {
          max_input_bytes: output[0],
          max_nodes: output[1],
          max_depth: output[2],
        },
        counts[0],
        counts[1],
        counts[2],
      )
    2 if input.length() == 3 && output.is_empty() && counts.is_empty() =>
      @hubspot_catalog.effect_response_construction_capacity(
        input[0],
        input[1],
        input[2],
      )
    3 if input.length() == 5 && output.is_empty() && counts.is_empty() =>
      @hubspot_catalog.effect_account_construction_capacity(
        input[0],
        input[1],
        input[2],
        input[3],
        input[4],
      )
    4 if input.length() == 7 && output.is_empty() =>
      @hubspot_catalog.effect_metadata_observed_construction_capacity(
        input[0],
        input[1],
        {
          max_bytes: input[2],
          max_nodes: input[3],
          max_depth: input[4],
          max_properties: input[5],
          max_name_units: input[6],
        },
        counts,
      )
    5 if input.length() == 8 && output.is_empty() && counts.is_empty() => {
      guard @hubspot_catalog.effect_account_construction_capacity(
          input[0],
          input[1],
          input[3],
          input[4],
          input[5],
        )
        is Some(account) &&
        @hubspot_catalog.effect_metadata_construction_capacity(
          input[0],
          input[2],
          {
            max_bytes: input[3],
            max_nodes: input[4],
            max_depth: input[5],
            max_properties: input[6],
            max_name_units: input[7],
          },
        )
        is Some(metadata) else {
        return None
      }
      let retained = Int64::max(
        @execution.execution_capacity_retained_bytes(account),
        @execution.execution_capacity_retained_bytes(metadata),
      )
      let workspace = Int64::max(
        @execution.execution_capacity_execution_bytes(account) -
        @execution.execution_capacity_retained_bytes(account),
        @execution.execution_capacity_execution_bytes(metadata) -
        @execution.execution_capacity_retained_bytes(metadata),
      )
      @execution.add_execution_capacity(
        @execution.execution_capacity(retained, retained).unwrap(),
        @execution.execution_capacity(0L, workspace).unwrap(),
      )
    }
    _ => None
  }
}

///|
#export_name("clientProgramHubSpotEffectRecipeCapacities")
pub fn client_program_hubspot_effect_recipe_capacities(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ],
  finalization_original : @execution.ExecutionCapacity?,
  limits : Array[Int],
  metadata_units : Int64,
  response_read_quantum : Int,
  control_wire_bytes : Int,
  host_input_bytes : Int,
) -> Result[
  Array[@execution.ExecutionCapacity],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  guard limits.length() == 18 && finalization_original is Some(finalization) else {
    return Err(Unsupported)
  }
  // This driver saves only Host request DATA. Common already owns complete
  // authenticated Preview/envelope admission and charges its row constructor
  // on cold restore. There is no separate Native Catalog/Preview re-admission.
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  let cold_row = if host_input_bytes == 0 {
    zero
  } else {
    let retained = @execution.execution_capacity_retained_bytes(finalization)
    @execution.execution_capacity(retained, retained).unwrap()
  }
  @client_local_host.installed_described_effect_recipe_capacities(
    // JavaScript supplies the complete vector. Keep its generic Option
    // representation inside this typed bridge, just like capture_original.
    Some(original),
    Some([zero, cold_row, zero]),
    limits[0],
    limits[1],
    limits[2],
    limits[3],
    limits[4],
    limits[5],
    limits[6],
    limits[7],
    true,
    limits[8],
    limits[9],
    limits[10],
    limits[11],
    limits[12],
    limits[13],
    limits[14],
    limits[15],
    limits[16],
    limits[17],
    metadata_units,
    response_read_quantum~,
    metadata_on_child=true,
    target_on_child=true,
    // Three declared phases: two member reads and four row reads in EACH.
    // The Plan still owns all nineteen distinct original physical slots.
    metadata_occurrences=6,
    target_occurrences=12,
    defer_ledger_codec=control_wire_bytes > 0,
    control_wire_bytes=if control_wire_bytes == 0 {
      None
    } else {
      Some(control_wire_bytes)
    },
    host_input_bytes=if host_input_bytes < 0 {
      None
    } else {
      Some(host_input_bytes)
    },
  )
}
