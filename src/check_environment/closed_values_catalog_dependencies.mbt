///|
/// Conservative eligibility of the initial resource-planned Values route.
/// This is not a language or Catalog validity check. A noneligible installation
/// keeps the ordinary preparation path; it must not borrow an empty quote for
/// newly interpreted carrier facts or pushdown contracts.
pub(all) struct ClosedValuesCatalogDependencies {
  registry_entries : Int
  reference_entries : Int
  scanned_work : Int
} derive(Eq, Debug)

///|
/// Scan only the exact already interpreted installation owner, before creating
/// any per-query lookup/pushdown inventory. No registry or body is readmitted.
/// All contracts, including unused ones, retain their existing semantic checks.
pub fn closed_values_catalog_dependencies(
  references : CatalogReferences,
  max_work : Int,
) -> ClosedValuesCatalogDependencies? {
  if max_work < 0 {
    return None
  }
  let registry = references.contents.registry.entries
  let count = references.references.length()
  if registry.length() > max_work || count > max_work - registry.length() {
    return None
  }
  for envelope in registry {
    if envelope.kind == "carrier_facts" || envelope.kind == "pushdown" {
      return None
    }
  }
  for reference in references.references {
    if reference.contract.kind == "carrier_facts" ||
      reference.contract.kind == "pushdown" {
      return None
    }
  }
  Some({
    registry_entries: registry.length(),
    reference_entries: count,
    scanned_work: registry.length() + count,
  })
}
