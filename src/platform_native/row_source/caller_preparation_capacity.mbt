///|
// Caller-owned constructors before the Source metadata reservation exists.
// The existing mapping inventory pays for ONE actual preflight Contract. The
// Source's later mapping, holder, path copy and provider payload are excluded.
//
// The finite quote frontier includes three mapping-inventory evaluations,
// document/projection quote walks over the validated Contract. read_checked
// consumes one contract node per Read; Relation decrements cumulative remaining
// nodes across fields and adds at most one final outer object. Hence V<=n+1,
// F<=n and D<=n; five walks cost H(11n+24)/R(26n+81)/S(11n+26). This is a
// validated schema bound, not an assumption about raw document node counts.
// The frontier also includes
// transport arithmetic, original checks, two input validations, nonce
// validation, and their success/refusal products. H/R/S use the central
// representation tariff, including concrete Ok(Unit) and conservative view
// and zero-capture function records. No allocator reuse or unused allowance
// supplies these constructors. Arena Ledger borrow and metadata reservation
// have separate original Native Work components.
pub fn native_relation_file_caller_preparation_inventory(
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
) -> @execution.PreparationRepresentationUnits? {
  if !native_relation_file_input_valid(selection, limits) {
    return None
  }
  let paths = selection.items_path.length().to_int64() +
    (match selection.key_path {
      None => 0L
      Some(path) => path.length().to_int64()
    })
  guard @rows.relation_document_mapping_construction_inventory(limits.page)
    is Some(mapping) else {
    return None
  }
  let nodes = limits.page.max_nodes.to_int64()
  @execution.compose_preparation_representation([
    mapping,
    {
      // Original Query/whole-Source selector before metadata reservation.
      record_headers: 3158L + 11L * nodes + 4L * paths,
      reference_slots: 1223L + 26L * nodes + 4L * paths,
      scalar_words: 7285L + 11L * nodes + 8L * paths,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
/// Constructor DATA for evaluating the preceding inventory query on accepted
/// inputs. A coordinator composes this under its actual preparation owner.
/// This query itself constructs one five-scalar record in its caller's realm;
/// it performs no mapping construction, reservation or original acquisition.
/// The supplied selection still requires native_relation_file_input_valid.
pub fn native_relation_file_caller_preparation_evaluation_inventory(
  selection : NativeRelationFileSelection,
) -> @execution.PreparationRepresentationUnits {
  let paths = selection.items_path.length().to_int64() +
    (match selection.key_path {
      None => 0L
      Some(path) => path.length().to_int64()
    })
  // Mapping inventory evaluation H600/R198/S1402; Source input validation
  // H(14+2K)/R(12+2K)/S(24+4K); Controls record H1/S5;
  // two-part grow-array H3/R19/S2; composition H17/R1/S36.
  {
    record_headers: 635L + 2L * paths,
    reference_slots: 230L + 2L * paths,
    scalar_words: 1469L + 4L * paths,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}
