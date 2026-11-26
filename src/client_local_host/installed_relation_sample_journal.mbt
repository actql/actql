///|
/// Supplement the live prefix reservation with the synchronous Journal
/// constructor. Durable pages, SQLite's native operation bounds and any
/// uncertain COMMIT remain in the Journal's own physical custody.
fn fund_installed_relation_sample_journal(
  profile : ClientCheckedRelationSampleProfile,
  prefix : InstalledRelationSamplePrefix,
  input : InstalledRelationSampleAdoptionInput,
) -> Result[Int, InstalledRelationSampleAdoptionIssue] {
  guard prefix.adoption_reservation is Some(reservation) &&
    @publication.run_definition_namespace(profile.definition)
    is Some(namespace_id) else {
    return Err(SampleAdoptionOriginalUnavailable)
  }
  let bound = 1024L + 6L * namespace_id.length().to_int64()
  let (relation_bytes, prefix_nodes, prefix_depth) = @encode.document_usage(
    input.relation,
  )
  let originals = [
    input.source_generation,
    input.capture,
    input.emission,
    input.reference,
  ]
  let mut wire_bytes = relation_bytes.to_int64() + bound
  for original in originals {
    guard @publication.run_evidence_value_wire_usage(original)
      is Some((bytes, _, _)) else {
      return Err(SampleAdoptionLimits)
    }
    wire_bytes += bytes.to_int64()
  }
  guard bound <= 131072L &&
    wire_bytes <= 2147483647L &&
    installed_sample_adoption_construction(
      bound.to_int(),
      prefix_nodes,
      prefix_depth,
    )
    is Some(prefix_charge) &&
    @execution.preparation_representation_cost({
      // Four closed JS record trees, receipt body and projections, the
      // callback/transaction frames, positional operands and bounded rows.
      // Each metadata document has at most 32 nodes. The Relation remains
      // a wire, never a recursively decoded JS tree in this write operation.
      record_headers: 768L,
      reference_slots: 2048L,
      scalar_words: 2048L,
      // Borrowed original wires are already funded. The second set covers
      // JS key/text materialization and the receipt's UTF-16 builder.
      owned_utf16_units: 8L * bound,
      // UTF-8 digest input, SQLite binds and their synchronous native copy
      // may coexist until the call returns. Persistent DB/WAL pages are
      // charged independently on the original bounded Journal.
      owned_wire_bytes: 3L * wire_bytes,
    })
    is Some(bridge_charge) &&
    @execution.checked_preparation_add_product(bridge_charge, prefix_charge, 3L)
    is Some(total) else {
    return Err(SampleAdoptionLimits)
  }
  // Twice the four-record constructor additionally covers the four Common
  // readmissions and receipt seal/readmission. Include the existing prefix
  // charge when growing this exact reservation, never a new durable owner.
  let ledger = @strategy.captured_dag_ledger(profile.captured)
  @resources.grow_capacity_reservation(ledger, reservation, total, total)
  .map_err(issue => SampleAdoptionCapacity(issue))
  .map(_ => wire_bytes.to_int())
}

///|
/// The Journal receives only a synchronous scoped visit of the actual
/// committed output. An equivalent checked profile cannot relabel a prefix.
pub fn with_installed_relation_sample_journal(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  prefix : InstalledRelationSamplePrefix,
  require_current : () -> Bool,
  consume : (InstalledRelationSampleAdoptionInput, () -> Bool, Int) -> Bool,
) -> Result[Unit, InstalledRelationSampleAdoptionIssue] {
  guard prefix.original is Some(original) &&
    physical_equal(profile, original.profile) else {
    return Err(SampleAdoptionOriginalUnavailable)
  }
  with_installed_relation_sample_adoption(owner, prefix, require_current, (
    input,
    current,
  ) => {
    let bytes = match
      fund_installed_relation_sample_journal(profile, prefix, input) {
      Err(issue) => return Err(issue)
      Ok(bytes) => bytes
    }
    if !current() {
      return Err(SampleAdoptionAuthorityLost)
    }
    if consume(input, current, bytes) {
      Ok(())
    } else {
      Err(SampleAdoptionVisitorRefused)
    }
  })
}
