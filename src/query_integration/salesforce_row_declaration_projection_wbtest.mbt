///|
// Frozen original Salesforce evidence emitter, independently retained from
// the original producer; the new shared projection does not generate its
// expected bytes. It is a test oracle, not a second production path.
fn original_salesforce_evidence_oracle(
  declaration : @salesforce_catalog.StaticDeclaration,
) -> (Array[String], Array[String]) raise @encode.EncodeFailure {
  let schemas = []
  let capabilities = []
  for view in declaration.views {
    if view.carrier_schema_cid.is_empty() || view.data_policy_cid.is_empty() {
      raise @encode.EncodeFailure::InvalidStructure
    }
    let schema = @encode.writer(4096, 64, 8)
    @encode.begin_object(schema)
    for
      (key, value) in [
        ("carrier_schema_contract_cid", view.carrier_schema_cid),
        ("data_classification", "unknown"),
        ("output_carrier", "relation"),
        ("read_mode", "snapshot"),
        ("source_contract_cid", view.view_cid),
        ("source_data_policy_cid", view.data_policy_cid),
        ("source_ref", view.source_ref),
        ("source_view_contract_cid", view.view_cid),
      ] {
      @encode.key(schema, key)
      @encode.string_value(schema, value)
    }
    @encode.end_object(schema)
    schemas.push(@encode.finish(schema))
    let capability = @encode.writer(4096, 64, 8)
    @encode.begin_object(capability)
    @encode.key(capability, "capability_contract_cids")
    @encode.begin_array(capability)
    @encode.string_value(
      capability,
      @planning.query_evidence_contract_identity(),
    )
    @encode.end_array(capability)
    for
      (key, value) in [
        ("read_mode", "snapshot"),
        ("source_contract_cid", view.view_cid),
        ("source_ref", view.source_ref),
        ("source_view_contract_cid", view.view_cid),
      ] {
      @encode.key(capability, key)
      @encode.string_value(capability, value)
    }
    @encode.end_object(capability)
    capabilities.push(@encode.finish(capability))
  }
  (schemas, capabilities)
}

///|
fn project_row_parts(
  declaration : @row_host.RowDeclaration,
  views : Array[@row_host.RowDeclaredView],
  bodies : Array[String],
) -> Result[@row_host.RowDeclaration, @row_host.RowDeclarationIssue] {
  @row_host.project_row_declaration(
    declaration.connector_id,
    declaration.connector_registration,
    declaration.connector_version,
    declaration.catalog,
    declaration.catalog_cid,
    declaration.contracts,
    views,
    bodies,
    declaration.manifest_entry,
    declaration.manifest_entry_cid,
  )
}

///|
test "Salesforce row projection preserves every original declaration and evidence byte" {
  let original = salesforce_declaration_fixture()
  let projected = @salesforce_host.salesforce_row_declaration(original).unwrap()
  assert_eq(projected.connector_id, original.connector_id)
  assert_eq(projected.connector_registration, "salesforce")
  assert_eq(projected.connector_version, original.connector_version)
  assert_eq(projected.catalog, original.catalog)
  assert_eq(projected.catalog_cid, original.catalog_cid)
  assert_eq(projected.contracts, original.contracts)
  assert_eq(projected.view_bodies, original.view_bodies)
  assert_eq(projected.manifest_entry, original.manifest_entry)
  assert_eq(projected.manifest_entry_cid, original.manifest_entry_cid)
  assert_eq(projected.views.length(), original.views.length())
  for index, view in projected.views {
    let before = original.views[index]
    assert_eq(view.resource, before.resource)
    assert_eq(view.source_ref, before.source_ref)
    assert_eq(view.view_cid, before.view_cid)
    assert_eq(view.fields, before.fields)
    assert_eq(view.carrier_schema_cid, before.carrier_schema_cid)
    assert_eq(view.data_policy_cid, before.data_policy_cid)
    assert_eq(view.classification, "unknown")
    assert_true(
      physical_equal(
        @row_host.row_declaration_view(projected, view.source_ref).unwrap(),
        view,
      ),
    )
  }
  // Copy only bounded metadata containers. Canonical strings are not parsed,
  // normalized or regenerated into a provider-neutral replacement Catalog.
  assert_false(physical_equal(projected.contracts, original.contracts))
  assert_false(physical_equal(projected.view_bodies, original.view_bodies))
  let expected = original_salesforce_evidence_oracle(original)
  assert_eq(@row_host.row_declaration_evidence_members(projected), expected)
  assert_eq(
    @salesforce_host.salesforce_source_evidence_members(original),
    expected,
  )
}

///|
test "Salesforce row acquisition requires the same projected view and checked requirement" {
  let original = salesforce_row_declaration()
  let projected = @salesforce_host.salesforce_row_declaration(original).unwrap()
  let requirement = row_page_requirement()
  let (query, evidence) = query_evidence_test_bodies()
  // The older projection-only requirement deliberately omits Source evidence.
  // Keep that refusal; use the existing complete evidence fixture for a real
  // acquisition instead of weakening the Row Owner's evidence admission.
  assert_true(
    @row_host.prepare_row_acquisition(
      projected,
      salesforce_row_requirement(),
      @identity.stringify_value(query, 100000, 10000, 100),
      @identity.stringify_value(evidence, 100000, 10000, 100),
    )
    is Err(SourceEvidence(_)),
  )
  let acquisition = @row_host.prepare_row_acquisition(
    projected,
    requirement,
    @identity.stringify_value(query, 100000, 10000, 100),
    @identity.stringify_value(evidence, 100000, 10000, 100),
  ).unwrap()
  assert_true(
    @row_host.check_row_acquisition_original(
      acquisition, projected, requirement,
    )
    is Ok(_),
  )
  assert_true(
    physical_equal(
      @row_host.row_acquisition_requirement(acquisition),
      requirement,
    ),
  )
  assert_eq(
    @row_host.row_source_target(projected, requirement).unwrap(),
    ("r", ["id"]),
  )
  // Equal canonical parts do not turn another legitimate projection into this
  // acquisition's original view. A separately checked equal requirement also
  // cannot replace the actual checked request the acquisition was prepared for.
  let equal_projection = @salesforce_host.salesforce_row_declaration(original).unwrap()
  assert_eq(projected.catalog_cid, equal_projection.catalog_cid)
  assert_eq(projected.view_bodies, equal_projection.view_bodies)
  assert_true(
    @row_host.check_row_acquisition_original(
      acquisition, equal_projection, requirement,
    )
    is Err(ForeignDeclaration),
  )
  let equal_requirement = row_page_requirement()
  assert_true(
    @row_host.check_row_acquisition_original(
      acquisition, projected, equal_requirement,
    )
    is Err(ForeignDeclaration),
  )
  let foreign = @salesforce_host.salesforce_row_declaration(
    salesforce_row_declaration(resource="other"),
  ).unwrap()
  assert_true(
    @row_host.check_row_acquisition_original(acquisition, foreign, requirement)
    is Err(ForeignDeclaration),
  )
}

///|
test "row metadata projection refuses partial or duplicate declared members without granting authority" {
  let original = @salesforce_host.salesforce_row_declaration(
    salesforce_declaration_fixture(),
  ).unwrap()
  assert_true(
    project_row_parts(original, original.views, []) is Err(InvalidView),
  )
  let view = original.views[0]
  assert_true(
    project_row_parts(original, [view, view], [
      original.view_bodies[0],
      original.view_bodies[0],
    ])
    is Err(DuplicateName(_)),
  )
  let again = project_row_parts(original, original.views, original.view_bodies).unwrap()
  assert_eq(again.catalog_cid, original.catalog_cid)
  assert_true(physical_equal(again.views[0], original.views[0]))
}
