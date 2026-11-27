///|
/// Fund complete UPDATE/STORE original DATA on its SAME checked Request before
/// the Host constructs the outer JSON. No new preparation, compiler, selection
/// or authority is issued. Each actually retained projection coexists; scratch
/// is a sequential peak. A refused grow leaves the original debit/cleanup live.
pub fn[I] reserve_request_effect_original_material(
  owner : ClientRequestPreparation[I],
  input : I,
  prepared : @publication_host.PreparedClientEffectComputation,
  count : Int,
  wire_at : (Int) -> String,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == EffectPlanReserved &&
    owner.effect_capacity is Some(capacity) &&
    owner.compiled_effect is Some(original_prepared) &&
    physical_equal(original_prepared, prepared) &&
    owner.input is Some(original) &&
    physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      let (old_r, old_e) = match
        @resources.preparation_capacity_working_extents(capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => value
      }
      match
        @resources.check_working_preparation_capacity_current(capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(_) => ()
      }
      guard @publication_host.client_effect_target_original_envelope_capacity(
          count, wire_at,
        )
        is Some(required) &&
        @execution.checked_preparation_add_product(
          old_r,
          @execution.execution_capacity_retained_bytes(required),
          1L,
        )
        is Some(r) &&
        @execution.checked_preparation_add_product(
          old_r,
          @execution.execution_capacity_execution_bytes(required),
          1L,
        )
        is Some(e) else {
        return Err(Policy)
      }
      guard owner.phase == Selecting &&
        owner.input is Some(original) &&
        physical_equal(original, input) &&
        owner.compiled_effect is Some(current) &&
        physical_equal(current, prepared) else {
        return Err(ForeignOriginal)
      }
      let result = @resources.reserve_working_preparation_phase(
        capacity,
        input,
        r,
        Int64::max(old_e, e),
      )
      guard owner.phase == Selecting &&
        owner.input is Some(original) &&
        physical_equal(original, input) &&
        owner.compiled_effect is Some(current) &&
        physical_equal(current, prepared) else {
        return Err(ForeignOriginal)
      }
      result.map_err(issue => Capacity(issue))
    },
    () => if owner.phase == Selecting { owner.phase = EffectPlanReserved },
  )
}

///|
// One synchronous codec scope: two scalar Arrays/backings for seventeen fixed
// purposes, a failure Ref/Some, a scratch Ref, callback and return carriers.
// Census bounds: two scalar Array/backings (4H/34W); two Ref and failure
// Some (3H/3R); the driver/finalizer/body callbacks and return/error carriers
// (12H/32R/16W); role/extent/checked-arithmetic tuples and Options
// (13H/24R/24W); one active metadata-only parser/emitter/validator recipe
// family, its composition Arrays and result (32H/69R/58W). The sum is
// 64H/128R/132W. The fixed retained installed record below adds
// 3H/9R/7W. Normalization custody adds one original issuer record
// (1H/10R) borrowing its compiled values and retaining the funded wire.
// Total 68H/147R/139W in this same reservation.
// Original entry arguments/codec closure precede this grow
// within the Request's existing exclusive 4096-byte control group. These
// arrays and variable body constructors begin only after this grow succeeds.
// No variable body or policy maximum is hidden in this control extent.
let request_effect_material_control_bytes : Int64 = @execution.preparation_representation_cost({
    // Same installed owner's retained codec-result record (1H/8R), its
    // existing state's additional alias (1R), and the
    // seven frozen Bool flags (Array/backing: 2H/7W). Aliases end before the
    // original holder returns; no second owner or body copy is created.
    record_headers: 68L,
    reference_slots: 147L,
    scalar_words: 139L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
fn request_effect_material_purpose(purpose : String) -> (Int, Bool)? {
  match purpose {
    "program" => Some((0, false))
    "parameters" => Some((1, false))
    "environment" => Some((2, false))
    "run_materials" => Some((3, false))
    "run_materials_read" => Some((4, true))
    "parameters_read" => Some((5, true))
    "environment_read" => Some((6, true))
    "prepared_invocation_read" => Some((7, true))
    "run_authorization_read" => Some((8, true))
    "request_read" => Some((9, true))
    "normalization_read" => Some((10, true))
    "run_definition_read" => Some((11, true))
    "model_execution" => Some((12, false))
    "model_inventory" => Some((13, false))
    "source_free_policy_read" => Some((14, true))
    "request" => Some((15, false))
    "retention_policy_read" => Some((16, true))
    _ => None
  }
}

///|

///|
/// Quote the captured Task material writers and the existing first Run
/// Definition, authorization, invocation and retention constructors.
/// The downstream UTF-8/hash/chunk owner supplies its own separate quote.
pub fn client_captured_task_material_body_capacity(
  purpose : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> (Int64, Int64)? {
  match purpose {
    "program" | "parameters" | "environment" | "run_materials" =>
      request_effect_material_body_layout(bytes, nodes, depth, false, purpose~)
    "retention_policy_read"
    | "prepared_invocation_read"
    | "run_authorization_read"
    | "run_definition_read" =>
      request_effect_material_body_layout(bytes, nodes, depth, true, purpose~)
    _ => None
  }
}

///|
// Canonical emission borrows the already checked value. A nested wire reader
// owns its duplicate decoded value until complete material admission returns.
// Both routes use the existing parser/writer representation recipes, not a
// profile maximum or a byte count substituted for an admitted node count.
fn request_effect_material_body_layout(
  bytes : Int,
  nodes : Int,
  depth : Int,
  reading : Bool,
  purpose? : String = "",
) -> (Int64, Int64)? {
  if bytes < 1 || nodes < 1 || depth < 1 {
    return None
  }
  if reading {
    // This installed inverse always supplies its SAME nominal Environment.
    // Core compares its complete canonical wire before borrowing the already
    // admitted checker/ModelTasks. Generic Environment parsing is not priced
    // as a canonical-value parse and cannot enter this funded alternative.
    if purpose == "environment_read" {
      return None
    }
    let evidence = match purpose {
      "prepared_invocation_read" => Some("prepared_invocation")
      "run_authorization_read" => Some("run_authorization")
      "normalization_read" => Some("normalization_journal")
      _ => None
    }
    if evidence is Some(name) {
      guard @publication.cold_static_plan_validation_construction(
          name,
          true,
          nodes,
          bytes.to_int64(),
          bytes,
          nodes,
          depth,
        )
        is Some(check) &&
        client_static_plan_codec_layout(
          (bytes, nodes, depth),
          {
            record_headers: check.owner.record_headers,
            reference_slots: check.owner.reference_slots,
            scalar_words: check.owner.scalar_words,
            owned_utf16_units: check.owned_utf16_units,
            owned_wire_bytes: check.owned_wire_bytes,
          },
          check.owned_utf16_units,
          check.pending_reference_items + check.unique_reference_items,
          0L,
        )
        is Some(codec) &&
        @execution.preparation_representation_cost(codec.retained)
        is Some(retained) &&
        @execution.preparation_representation_cost(codec.scratch)
        is Some(scratch) else {
        return None
      }
      // Existing evidence admission parses and validates the actual generated
      // schema, copies the identity-free root, hashes it, then stringifies the
      // complete evidence. The shared complete codec owns these constructors.
      return Some((retained, scratch))
    }
    if purpose == "source_free_policy_read" {
      // This existing semantic reader first requires its one exact unknown-
      // provenance literal (five fields and two empty reference lists).
      // Only that literal reaches catalog canonicalization/hash. Preserve
      // the reader; price its field/name/list controls beside the full codec.
      guard @shape.collection_construction_extent({
          records: 12L,
          record_references: 32L,
          record_words: 8L,
          reference_arrays: 4L,
          reference_items: 20L,
          scalar_arrays: 0L,
          scalar_items: 0L,
          maps: 0L,
          map_entries: 0L,
        })
        is Some(fields) &&
        client_static_plan_codec_layout(
          (bytes, nodes, depth),
          {
            record_headers: fields.record_headers,
            reference_slots: fields.reference_slots,
            scalar_words: fields.scalar_words,
            owned_utf16_units: 0L,
            owned_wire_bytes: 0L,
          },
          0L,
          20L,
          0L,
        )
        is Some(codec) &&
        @execution.preparation_representation_cost(codec.retained)
        is Some(retained) &&
        @execution.preparation_representation_cost(codec.scratch)
        is Some(scratch) else {
        return None
      }
      return Some((retained, scratch))
    }
    guard program_artifact_parse_layout((bytes, nodes, depth)) is Some(parse) else {
      return None
    }
    let (value, temporary) = if purpose == "request_read" {
      let scope = @request_scope.logical_request_scope_construction_inventory()
      guard @encode.text_writer_construction_inventory(1024, 5, 1)
        is Some(intent) &&
        @encode.hash_writer_construction_inventory(0, 0) is Some(hash) &&
        @execution.compose_preparation_representation([
          parse.value,
          {
            // Request record, original Scope and copied program/parameter CIDs,
            // intent/scope CID Strings. The existing schema bounds CIDs to71
            // UTF16 units; no source/parameter payload is retained here.
            record_headers: 6L,
            reference_slots: 12L,
            scalar_words: 0L,
            owned_utf16_units: 284L,
            owned_wire_bytes: 0L,
          },
        ])
        is Some(value) &&
        @execution.compose_preparation_representation([
          parse.temporary,
          {
            // SAME request scope validation/hash followed by the existing
            // five-node intent writer, UTF8 SHA and two71-unit CID copy Arrays.
            record_headers: scope.record_headers +
            intent.record_headers +
            hash.record_headers +
            4L,
            reference_slots: scope.reference_slots +
            intent.reference_slots +
            hash.reference_slots,
            scalar_words: scope.scalar_words +
            intent.scalar_words +
            hash.scalar_words +
            142L,
            owned_utf16_units: scope.owned_utf16_units +
            intent.owned_utf16_units +
            hash.owned_utf16_units,
            owned_wire_bytes: scope.owned_wire_bytes +
            hash.owned_wire_bytes +
            1024L,
          },
        ])
        is Some(temporary) else {
        return None
      }
      (value, temporary)
    } else {
      (parse.value, parse.temporary)
    }
    guard @execution.preparation_representation_cost(value) is Some(retained) &&
      @execution.preparation_representation_cost(temporary) is Some(scratch) else {
      return None
    }
    Some((retained, scratch))
  } else {
    let emission : @execution.PreparationRepresentationUnits = if purpose ==
      "program" ||
      purpose == "parameters" ||
      purpose == "model_execution" {
      guard @syntax.admitted_source_emission_construction_extent(nodes)
        is Some(source) &&
        @encode.text_writer_construction_inventory(bytes, nodes, depth)
        is Some(writer) else {
        return None
      }
      // This is the actual admitted Source emitter, not canonical-value
      // traversal. Source/parameter trees remain with their original owner.
      {
        record_headers: source.record_headers + writer.record_headers,
        reference_slots: source.reference_slots + writer.reference_slots,
        scalar_words: source.scalar_words + writer.scalar_words,
        owned_utf16_units: writer.owned_utf16_units,
        owned_wire_bytes: 0L,
      }
    } else if purpose == "environment" {
      guard @environment.wire_text_construction_extent(bytes, nodes, depth)
        is Some(value) else {
        return None
      }
      {
        record_headers: value.record_headers,
        reference_slots: value.reference_slots,
        scalar_words: value.scalar_words,
        owned_utf16_units: value.owned_utf16_units,
        owned_wire_bytes: value.owned_wire_bytes,
      }
    } else {
      guard client_static_plan_canonical_emission_layout((bytes, nodes, depth))
        is Some(value) else {
        return None
      }
      value
    }
    let emission = if purpose == "model_inventory" {
      if (nodes - 1) % 8 != 0 {
        return None
      }
      let count = ((nodes - 1) / 8).to_int64()
      guard @shape.collection_construction_extent({
          // Actual complete expected-occurrence and retained-original
          // projection Arrays/pairs coexist with the inventory writer.
          records: 2L * count + 4L,
          record_references: 12L * count + 4L,
          record_words: 3L * count + 4L,
          reference_arrays: 2L,
          reference_items: 2L * count,
          scalar_arrays: 0L,
          scalar_items: 0L,
          maps: 0L,
          map_entries: 0L,
        })
        is Some(items) &&
        @execution.compose_preparation_representation([
          emission,
          {
            record_headers: items.record_headers,
            reference_slots: items.reference_slots,
            scalar_words: items.scalar_words,
            owned_utf16_units: 0L,
            owned_wire_bytes: 0L,
          },
        ])
        is Some(combined) else {
        return None
      }
      combined
    } else {
      emission
    }
    guard @execution.preparation_representation_cost(emission) is Some(scratch) &&
      @execution.preparation_representation_cost({
        record_headers: 1L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: bytes.to_int64(),
        owned_wire_bytes: 0L,
      })
      is Some(retained) else {
      return None
    }
    Some((retained, scratch))
  }
}

///|
/// Construct or admit the original Effect materials under this SAME Request.
/// The installed typed bridge supplies the closed codec, never caller quotas.
/// Each body is funded before its writer/parser starts. Returned originals and
/// failure prefixes remain retained by this existing owner through cleanup.
pub fn[I, A] construct_request_effect_materials(
  owner : ClientRequestPreparation[I],
  input : I,
  prepared : @publication_host.PreparedClientEffectComputation,
  codec_owner? : @publication_host.PreparedClientEffectComputation? = None,
  construct : ((String, Int, Int, Int) -> Bool) -> Result[
    A,
    @publication_host.ClientEffectRunMaterialsIssue,
  ],
) -> Result[A, ClientRequestProgramPlanIssue] {
  guard owner.phase == EffectPlanReserved &&
    owner.effect_capacity is Some(capacity) &&
    owner.compiled_effect is Some(original_prepared) &&
    physical_equal(original_prepared, prepared) &&
    (
      codec_owner is None ||
      (codec_owner is Some(codec) && physical_equal(codec, prepared))
    ) &&
    owner.input is Some(original) &&
    physical_equal(original, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  construct_request_original_materials_owned(
    owner,
    input,
    capacity,
    () => {
      owner.phase == Selecting &&
      owner.input is Some(original) &&
      physical_equal(original, input) &&
      owner.compiled_effect is Some(current) &&
      physical_equal(current, prepared)
    },
    fund => construct(fund).map_err(issue => EffectMaterials(issue)),
  )
}

///|
// Same fixed control inventory, accumulating retained bodies, active nested
// writer and scratch peak for both original material families. The typed
// family supplies its original-binding fence before entering this private loop.
fn[I, O, A] construct_request_original_materials_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  capacity : @resources.PreparationCapacity[I, O],
  original_is_current : () -> Bool,
  retained_aliases? : Int64 = 0L,
  extra_control_bytes? : Int64 = 0L,
  extra_scratch_bytes? : Int64 = 0L,
  construct : ((String, Int, Int, Int) -> Bool) -> Result[
    A,
    ClientRequestProgramPlanIssue,
  ],
) -> Result[A, ClientRequestProgramPlanIssue] {
  let previous_phase = owner.phase
  let base = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(value) => value
  }
  // One Model Plan field retains its already-funded original ticket. Admit
  // that reference before the existing view is constructed; no extra view,
  // closure or authority wrapper is created. Effects retain their old count.
  guard retained_aliases >= 0L &&
    extra_control_bytes >= 0L &&
    extra_scratch_bytes >= 0L &&
    @execution.preparation_representation_cost({
      record_headers: 0L,
      reference_slots: retained_aliases,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(aliases) &&
    @execution.checked_preparation_add_product(
      request_effect_material_control_bytes, aliases, 1L,
    )
    is Some(control) &&
    @execution.checked_preparation_add_product(control, extra_control_bytes, 1L)
    is Some(control) &&
    @execution.checked_preparation_add_product(base.0, control, 1L)
    is Some(base_r) &&
    @execution.checked_preparation_add_product(base.1, control, 1L)
    is Some(base_e) else {
    return Err(Preparation(Policy))
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      match
        @resources.reserve_working_preparation_phase(
          capacity, input, base_r, base_e,
        ) {
        Err(issue) => return Err(Preparation(Capacity(issue)))
        Ok(_) => ()
      }
      guard original_is_current() else {
        return Err(Preparation(ForeignOriginal))
      }
      let retained : Array[Int64] = Array::make(17, 0L)
      let temporary : Array[Int64] = Array::make(17, 0L)
      let scratch = Ref(extra_scratch_bytes)
      let failed : Ref[ClientRequestProgramPlanIssue?] = Ref(None)
      let before_body = fn(
        purpose : String,
        bytes : Int,
        nodes : Int,
        depth : Int,
      ) {
        if failed.val is Some(_) {
          return false
        }
        if !original_is_current() {
          failed.val = Some(Preparation(ForeignOriginal))
          return false
        }
        guard request_effect_material_purpose(purpose) is Some((slot, reading)) &&
          request_effect_material_body_layout(
            bytes,
            nodes,
            depth,
            reading,
            purpose~,
          )
          is Some((body_r, body_s)) else {
          failed.val = Some(Preparation(Policy))
          return false
        }
        let selected = Int64::max(retained[slot], body_r)
        let mut prefix = base_r
        for index in 0..<retained.length() {
          let current = if index == slot { selected } else { retained[index] }
          guard @execution.checked_preparation_add_product(prefix, current, 1L)
            is Some(next) else {
            failed.val = Some(Preparation(Policy))
            return false
          }
          prefix = next
        }
        // Original Model execution emission nests inside the inventory
        // writer. That active writer coexists; unrelated phases reuse MAX.
        let body_s = if purpose == "model_execution" {
          guard @execution.checked_preparation_add_product(
              body_s,
              temporary[13],
              1L,
            )
            is Some(combined) else {
            failed.val = Some(Preparation(Policy))
            return false
          }
          combined
        } else {
          body_s
        }
        let peak_scratch = Int64::max(scratch.val, body_s)
        guard @execution.checked_preparation_add_product(
            base_e,
            prefix - base_r,
            1L,
          )
          is Some(execution) &&
          @execution.checked_preparation_add_product(
            execution, peak_scratch, 1L,
          )
          is Some(execution) else {
          failed.val = Some(Preparation(Policy))
          return false
        }
        let result = @resources.reserve_working_preparation_phase(
          capacity, input, prefix, execution,
        )
        guard original_is_current() else {
          failed.val = Some(Preparation(ForeignOriginal))
          return false
        }
        match result {
          Err(issue) => {
            failed.val = Some(Preparation(Capacity(issue)))
            false
          }
          Ok(_) => {
            retained[slot] = selected
            temporary[slot] = body_s
            scratch.val = peak_scratch
            true
          }
        }
      }
      let result = construct(before_body)
      if failed.val is Some(issue) {
        return Err(issue)
      }
      guard original_is_current() else {
        return Err(Preparation(ForeignOriginal))
      }
      let output = match result {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      // The closed codec and all of its parser/writer stacks have returned.
      // Keep every actual returned String/decoded original and the baseline
      // compiler owner; only this scope's sequential temporary peak can end.
      let mut retained_bytes = 0L
      for bytes in retained {
        guard @execution.checked_preparation_add_product(
            retained_bytes, bytes, 1L,
          )
          is Some(next) else {
          return Err(Preparation(Policy))
        }
        retained_bytes = next
      }
      guard @execution.checked_preparation_add_product(
          base_r, retained_bytes, 1L,
        )
        is Some(retained_peak) &&
        @execution.checked_preparation_add_product(base_e, retained_bytes, 1L)
        is Some(execution_peak) else {
        return Err(Preparation(Policy))
      }
      match
        @resources.reconcile_current_working_preparation_phase(
          capacity, input, retained_peak, execution_peak,
        ) {
        Err(issue) => return Err(Preparation(Capacity(issue)))
        Ok(_) => ()
      }
      guard original_is_current() else {
        return Err(Preparation(ForeignOriginal))
      }
      Ok(output)
    },
    () => if owner.phase == Selecting { owner.phase = previous_phase },
  )
}
