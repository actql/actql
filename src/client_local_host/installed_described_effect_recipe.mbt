///|
/// The existing described-record driver has three member Describe reads and,
/// for targeted writes, three distinct row reads. Its Native constructors use
/// the SAME four-entry request/target/response/metadata profile as the standard
/// composer. Metadata output lives once per member; its synchronous workspace
/// lives on the existing Run control frame by default. Input-staged metadata
/// instead lives on its SAME physical child through native decode/projection.
/// No provider policy, authority, new allocation Owner or tariff is selected.
pub fn installed_described_effect_recipe_capacities(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  capture_original : Array[@execution.ExecutionCapacity]?,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  row_input_bytes : Int,
  row_input_nodes : Int,
  row_input_depth : Int,
  request_bytes : Int,
  response_bytes : Int,
  target_reads : Bool,
  target_request_bytes : Int,
  target_response_bytes : Int,
  metadata_request_bytes : Int,
  metadata_response_bytes : Int,
  secret_bytes : Int,
  secret_prefix_units : Int,
  header_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  metadata_units : Int64,
  response_read_quantum? : Int = 1,
  metadata_on_child? : Bool = false,
  control_wire_bytes? : Int? = None,
  host_input_bytes? : Int? = None,
  defer_ledger_codec? : Bool = false,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  guard original is Some(entries) &&
    entries.length() == 4 &&
    capture_original is Some(capture) &&
    capture.length() == 3 &&
    target_request_bytes > 0 &&
    target_response_bytes > 0 &&
    metadata_request_bytes > 0 &&
    metadata_response_bytes > 0 else {
    return Err(Unsupported)
  }
  let (native_metadata, metadata_input, metadata_output) = entries[3]
  let (native_request, request_input, request_output) = entries[0]
  let metadata = match
    installed_standard_create_constructor_capacity(
      native_metadata, metadata_input, metadata_output,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  // Cold recovery rebuilds requests inside the member capture, rather than
  // invoking the warm row constructor child. Reuse this SAME constructor
  // fold, including its Host output parse, before that capture can run.
  let request = match
    installed_standard_create_constructor_capacity(
      native_request, request_input, request_output,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let capture = capture.copy()
  guard @execution.add_execution_capacity(capture[1], request)
    is Some(recovered_row) else {
    return Err(Unsupported)
  }
  capture[1] = recovered_row
  let adjusted = entries.copy()
  adjusted[3] = (empty, None, None)
  let base = match
    installed_standard_recipe_capacities(
      Some(adjusted),
      Some(capture),
      input_bytes,
      input_nodes,
      input_depth,
      row_input_bytes,
      row_input_nodes,
      row_input_depth,
      request_bytes,
      response_bytes,
      if target_reads {
        target_request_bytes
      } else {
        0
      },
      if target_reads {
        target_response_bytes
      } else {
        0
      },
      false,
      secret_bytes,
      secret_prefix_units,
      header_bytes,
      stored_bytes,
      stored_nodes,
      stored_depth,
      metadata_units,
      response_read_quantum~,
      control_wire_bytes~,
      host_input_bytes~,
      defer_ledger_codec~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let metadata_retained = if metadata_on_child {
    0L
  } else {
    @execution.execution_capacity_retained_bytes(metadata)
  }
  let metadata_workspace = if metadata_on_child {
    0L
  } else {
    @execution.execution_capacity_execution_bytes(metadata) - metadata_retained
  }
  guard @execution.execution_capacity(metadata_retained, metadata_retained)
    is Some(retained) &&
    @execution.add_execution_capacity(base[0], retained) is Some(fixed) &&
    // Warm capability/footprint/recheck constructors and cold reconstruction
    // use this SAME synchronous frame. Their original capture material stays
    // on the member/row children. Only completed private scratch is reused.
    @execution.execution_capacity(
      0L,
      Int64::max(
        metadata_workspace,
        Int64::max(
          @execution.execution_capacity_execution_bytes(base[2]) -
          @execution.execution_capacity_retained_bytes(base[2]),
          Int64::max(
            @execution.execution_capacity_execution_bytes(capture[0]) -
            @execution.execution_capacity_retained_bytes(capture[0]),
            @execution.execution_capacity_execution_bytes(capture[1]) -
            @execution.execution_capacity_retained_bytes(capture[1]),
          ),
        ),
      ),
    )
    is Some(workspace) &&
    standard_create_sequence_pair_capacity(base[4], workspace) is Some(controls) &&
    standard_create_grant_capacity() is Some(grant) &&
    installed_effect_http_response_construction_capacity(
      metadata_response_bytes,
      header_bytes,
      response_read_quantum~,
    )
    is Some(receive) &&
    standard_create_secret_capacity(secret_bytes, secret_prefix_units)
    is Some(secret) &&
    standard_create_sum_capacities(
      if metadata_on_child {
        [receive, secret, metadata]
      } else {
        [receive, secret]
      },
    )
    is Some(metadata_physical) else {
    return Err(Unsupported)
  }
  let mut controls = controls
  // capture/apply/resume Describe grants are distinct original occurrences;
  // grant construction completes before the HTTP await. This does not alter
  // the declared physical-attempt/transfer inventory or refund consumed work.
  for _ in 0..<3 {
    guard standard_create_sequence_pair_capacity(controls, grant) is Some(next) else {
      return Err(Unsupported)
    }
    controls = next
  }
  Ok([
    fixed,
    base[1],
    base[2],
    base[3],
    controls,
    base[base.length() - 1],
    if target_reads {
      base[5]
    } else {
      empty
    },
    metadata_physical,
  ])
}
