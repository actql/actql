///|
// Constructor DATA and synchronous borrows only. The caller retains its actual
// resource issue; neither this adapter nor Account owns a replacement Read.
fn local_account_construction_cost(
  units : @authorization.AccountConfigurationConstructionUnits,
) -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: units.record_headers,
    reference_slots: units.reference_slots,
    scalar_words: units.scalar_words,
    owned_utf16_units: units.owned_utf16_units,
    owned_wire_bytes: units.owned_wire_bytes,
  })
}

///|
let local_account_construction_zero : @authorization.AccountConfigurationConstructionUnits = {
  record_headers: 0L,
  reference_slots: 0L,
  scalar_words: 0L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
fn local_account_read(
  root : @filesystem.Root,
  name : String,
  max_bytes : Int64?,
  construction : ((@authorization.AccountConfigurationConstruction) -> Bool)?,
  retain? : Bool = false,
) -> Result[(Bytes, @filesystem.NativeFileGeneration), NativeLocalAdoptionIssue] {
  // Only the SAME numeric constructor can replace the standalone intake bound.
  // Keep that legacy refusal before Reader open, FixedArray and UTF8 allocation.
  let max_bytes = match construction {
    Some(_) => max_bytes
    None =>
      Some(
        match max_bytes {
          Some(bound) => Int64::min(bound, 1048576L)
          None => 1048576L
        },
      )
  }
  local_adoption_read_observed(
    root,
    name,
    max_bytes,
    prepare=construction.map(prepare => {
      fn(size) {
        // Destination FixedArray/Bytes conversion and one original 65536-byte
        // Reader chunk coexist. Fixed reader/finish/refusal controls are included
        // before open, so even a failed child keeps its constructor reservation.
        let body : @authorization.AccountConfigurationConstructionUnits = {
          record_headers: 2L,
          reference_slots: 0L,
          scalar_words: 0L,
          owned_utf16_units: 0L,
          owned_wire_bytes: size,
        }
        prepare({
          retained: if retain {
            body
          } else {
            local_account_construction_zero
          },
          execution: {
            record_headers: 24L,
            reference_slots: 32L,
            scalar_words: 32L,
            owned_utf16_units: 0L,
            owned_wire_bytes: 2L * size + Int64::min(size, 65536L),
          },
        })
      }
    }),
  )
}

///|
fn local_account_decode(
  body : Bytes,
  construction : ((@authorization.AccountConfigurationConstruction) -> Bool)?,
) -> Result[
  @authorization.AdmittedAccountConfiguration,
  NativeLocalAdoptionIssue,
] {
  if construction is Some(prepare) {
    let text : @authorization.AccountConfigurationConstructionUnits = {
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: body.length().to_int64(),
      owned_wire_bytes: 0L,
    }
    // Native UTF8 decoding first writes its bounded UTF16 array, then creates
    // the returned String. It may fail after either constructor has started.
    if !prepare({
        retained: text,
        execution: {
          record_headers: 8L,
          reference_slots: 8L,
          scalar_words: 8L,
          owned_utf16_units: 2L * body.length().to_int64(),
          owned_wire_bytes: 0L,
        },
      }) {
      return Err(ConfigurationLimit)
    }
  }
  let text = @utf8.decode(body) catch { _ => return Err(Encoding) }
  let admitted = match construction {
    Some(prepare) =>
      match
        @authorization.admit_account_configuration_json_prepared(text, prepare) {
        None => return Err(ConfigurationLimit)
        Some(value) => value
      }
    None => @authorization.admit_account_configuration_json(text)
  }
  admitted.map_err(issue => Configuration(issue))
}

///|
// Current access borrows THIS paired Read only for this synchronous check.
// Existing retained metadata remains beside the new temporary file buffers;
// completion never refunds a previous or failed constructor.
fn NativeLocalJournalOriginalResources::prepare_account_construction(
  self : NativeLocalJournalOriginalResources,
  construction : @authorization.AccountConfigurationConstruction,
) -> Bool {
  guard !self.interrupted &&
    self.active_phase is Some(@arena.HostRead) &&
    local_account_construction_cost(construction.retained) is Some(r) &&
    local_account_construction_cost(construction.execution) is Some(e) &&
    @execution.checked_preparation_add_product(self.metadata_retained, r, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(self.metadata_retained, e, 1L)
    is Some(e) else {
    return false
  }
  match
    self.host.prepare_domain_original_read_construction(
      self.read,
      r,
      e,
      Int64::max(r, e),
    ) {
    Err(issue) => {
      self.account_construction_issue = Some(
        OriginalResources(@arena.Read(issue)),
      )
      false
    }
    Ok(_) => {
      self.metadata_retained = r
      true
    }
  }
}
