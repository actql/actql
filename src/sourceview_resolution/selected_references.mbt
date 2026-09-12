///|
fn request_catalog_references(
  catalog : @environment.SourceRequestContracts,
) -> @environment.CatalogReferences {
  @environment.data_policy_references(
    @environment.value_contract_policies(
      @environment.source_view_shape_values(
        @environment.read_mode_shapes(
          @environment.carrier_schema_modes(
            @environment.source_request_carriers(catalog),
          ),
        ),
      ),
    ),
  )
}

///|
/// All admitted role occurrences of the selected SourceView, not the complete
/// Program's local contract closure or a mode-specific dependency projection.
pub fn selected_reference_count(v : ResolvedInput) -> Int {
  @environment.catalog_member_reference_count(
    request_catalog_references(v.owner.catalog),
    @environment.source_request_member(v.selected.contract),
  ).unwrap()
}

///|
pub fn selected_reference_at(
  v : ResolvedInput,
  index : Int,
) -> @environment.CatalogReference? {
  @environment.catalog_member_reference_at(
    request_catalog_references(v.owner.catalog),
    @environment.source_request_member(v.selected.contract),
    index,
  )
}
