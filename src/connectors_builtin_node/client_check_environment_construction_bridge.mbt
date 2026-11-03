///|
fn client_check_environment_capacity(
  retained : @check_environment.RegistryConstructionExtent,
  peak : @check_environment.RegistryConstructionExtent,
) -> @execution.ExecutionCapacity? {
  guard @execution.preparation_representation_cost({
      record_headers: retained.record_headers,
      reference_slots: retained.reference_slots,
      scalar_words: retained.scalar_words,
      owned_utf16_units: retained.owned_utf16_units,
      owned_wire_bytes: retained.owned_wire_bytes,
    }) is Some(retained_bytes) &&
    @execution.preparation_representation_cost({
      record_headers: peak.record_headers,
      reference_slots: peak.reference_slots,
      scalar_words: peak.scalar_words,
      owned_utf16_units: peak.owned_utf16_units,
      owned_wire_bytes: peak.owned_wire_bytes,
    }) is Some(peak_bytes) else {
    return None
  }
  @execution.execution_capacity(retained_bytes, peak_bytes)
}

///|
/// Exact same-input geometry supplied by the funded immutable document owner.
/// The opaque quantity is composed into its existing SourceMaterial debit;
/// this function cannot create a reservation, parse a body or grant admission.
#export_name("clientProgramCheckEnvironmentWireConstructionCapacity")
pub fn client_program_check_environment_wire_construction_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
  fields : Int,
  objects : Int,
  arrays : Int,
  root_fields : Int,
  max_fields : Int,
  key_utf16_units : Int,
  max_key_utf16_units : Int,
  members : Int,
  snapshots : Int,
  catalogs : Int,
  manifest_entries : Int,
) -> @execution.ExecutionCapacity? {
  let geometry : @check_environment.WireAdmissionConstructionGeometry = {
    bytes, nodes, depth, fields, objects, arrays, root_fields, max_fields,
    key_utf16_units, max_key_utf16_units, members, snapshots, catalogs,
    manifest_entries,
  }
  guard @check_environment.wire_admission_construction_extent(geometry)
    is Some(peak) &&
    @check_environment.wire_admission_retained_extent(geometry)
    is Some(retained) else {
    return None
  }
  client_check_environment_capacity(retained, peak)
}

///|
/// Called only after the SAME SourceMaterial owner reserves the wire recipe.
/// The compatibility entry uses this identical bounded reader. It returns the
/// real original wire, never a same-shaped replacement or selected Catalog.
#export_name("clientProgramReadCheckEnvironmentWire")
pub fn client_program_read_check_environment_wire(
  body : String,
  evidence_bundle_cid : String,
) -> @check_environment.WireEnvironment? {
  @publication_host.admit_client_check_environment_wire(body, evidence_bundle_cid)
}

///|
fn client_check_environment_add_extent(
  left : @check_environment.RegistryConstructionExtent,
  right : @check_environment.RegistryConstructionExtent,
) -> @check_environment.RegistryConstructionExtent {
  {
    record_headers: left.record_headers + right.record_headers,
    reference_slots: left.reference_slots + right.reference_slots,
    scalar_words: left.scalar_words + right.scalar_words,
    owned_utf16_units: left.owned_utf16_units + right.owned_utf16_units,
    owned_wire_bytes: left.owned_wire_bytes + right.owned_wire_bytes,
  }
}

///|
/// Initial Source/Effect composition has no ModelTask declarations. A later
/// Model owner must supply its own populated constructor inventory. Absence of
/// this quote is refusal, never an implicit zero-cost ModelTask admission.
#export_name("clientProgramCheckEnvironmentFromWireConstructionCapacity")
pub fn client_program_check_environment_from_wire_construction_capacity(
  original : @check_environment.WireEnvironment,
) -> @execution.ExecutionCapacity? {
  guard @check_environment.empty_model_tasks_construction_extent(original)
    is Some(peak) &&
    @check_environment.empty_model_tasks_retained_extent(original)
    is Some(retained) else {
    return None
  }
  client_check_environment_capacity(
    client_check_environment_add_extent(retained, @publication_host.client_check_environment_wrapper_construction_extent(false)),
    client_check_environment_add_extent(peak, @publication_host.client_check_environment_wrapper_construction_extent(true)),
  )
}

///|
/// Private installed composition cut: same wire, same seven selected flags and
/// the original empty ModelTask reader. The full public compatibility entry
/// continues to admit populated ModelTasks through its separate owner/path.
#export_name("clientProgramCheckEnvironmentFromWire")
pub fn client_program_check_environment_from_wire(
  original : @check_environment.WireEnvironment,
  text_time : Bool,
  veca : Bool,
  rela : Bool,
  sga : Bool,
  tea : Bool,
  calendar : Bool,
  text_rank : Bool,
) -> @program_check.CheckEnvironment? {
  if @check_environment.member_count(original, @check_environment.ModelTaskContracts) != 0 ||
    (sga && !selected_sga_supported()) {
    return None
  }
  @publication_host.admit_client_check_environment_from_wire(
    original,
    { text_time, veca, },
    { rela, sga, tea, calendar, text_rank, },
  )
}
