///|
/// The original Local member and its same prepared Catalog specification.
pub struct ClientProjectPreparedLocalFileCatalog {
  priv project_files : ClientProjectLocalFiles
  priv resolved_root : String
  priv prepared : @row_host.PreparedLocalFileSourceDeclaration
}

///|
/// An issued Catalog with its original Local Project member.
pub struct ClientProjectLocalFileCatalog {
  priv project_files : ClientProjectLocalFiles
  priv resolved_root : String
  declaration : @row_host.RowDeclaration
  scope_cid : String
  version_cid : String
}

///|
fn local_file_catalog_wrapper_capacity(
  references : Int64,
  words : Int64,
  view_slots? : Int64? = None,
) -> Result[Int64, @row_host.RowHostIssue] {
  let wrapper : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: references,
    scalar_words: words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let extent = if view_slots is Some(count) {
    @execution.preparation_array_representation(1L, count, false).bind(array => {
      @execution.compose_preparation_representation([wrapper, array])
    })
  } else {
    Some(wrapper)
  }
  match extent.bind(@execution.preparation_representation_cost) {
    Some(bytes) => Ok(bytes)
    None => Err(@row_host.InvalidSpecification)
  }
}

///|
/// Quote the actual first phase and its original-member wrapper. The
/// resolved Root comes from the installed Host holding this same member.
pub fn ClientProjectLocalFiles::catalog_specification_capacity(
  self : Self,
  resolved_root : String,
  limits : @row_host.LocalFileSourceDeclarationLimits,
) -> Result[Int64, @row_host.RowHostIssue] {
  @row_host.local_file_source_specification_construction_capacity(
    self.connection,
    resolved_root,
    limits,
    self.csv_tables.length(),
  ).bind(base => {
    local_file_catalog_wrapper_capacity(
      3L,
      1L,
      view_slots=Some(self.csv_tables.length().to_int64()),
    ).bind(wrapper => {
      match @execution.checked_preparation_add_product(base, wrapper, 1L) {
        Some(total) => Ok(total)
        None => Err(@row_host.InvalidSpecification)
      }
    })
  })
}

///|
/// Use the paid first phase for the same member and Root. CSV views come from
/// the typed original member, not a second declaration or transport wire.
pub fn ClientProjectLocalFiles::prepare_catalog_specification(
  self : Self,
  resolved_root : String,
  limits : @row_host.LocalFileSourceDeclarationLimits,
  csv_classification? : (String, @environment.DataClassification)? = None,
) -> Result[ClientProjectPreparedLocalFileCatalog, @row_host.RowHostIssue] {
  let selected = match csv_classification {
    None => None
    Some((resource, classification)) => {
      let mut found = None
      for index, table in self.csv_tables {
        if table.view.resource == resource {
          if found is Some(_) { return Err(@row_host.InvalidSpecification) }
          found = Some(index)
        }
      }
      guard found is Some(index) else { return Err(@row_host.InvalidSpecification) }
      Some((index, classification))
    }
  }
  @row_host.prepare_local_file_source_declaration(
    self.connection,
    resolved_root,
    self.content_version,
    limits,
    self.csv_tables.map(table => table.view),
    csv_classification=selected,
  ).map(prepared => { project_files: self, resolved_root, prepared, })
}

///|
pub fn ClientProjectPreparedLocalFileCatalog::construction_capacity(
  self : Self,
) -> Result[Int64, @row_host.RowHostIssue] {
  self.prepared
  .construction_capacity()
  .bind(base => {
    local_file_catalog_wrapper_capacity(5L, 0L).bind(wrapper => {
      match @execution.checked_preparation_add_product(base, wrapper, 1L) {
        Some(total) => Ok(total)
        None => Err(@row_host.InvalidSpecification)
      }
    })
  })
}

///|
/// Issue the declaration once from the same prepared specification after the
/// installed caller funds this second phase.
pub fn ClientProjectPreparedLocalFileCatalog::issue(
  self : Self,
) -> Result[ClientProjectLocalFileCatalog, @row_host.RowHostIssue] {
  self.prepared
  .issue()
  .map(value => {
    let (declaration, scope_cid, version_cid) = value
    {
      project_files: self.project_files,
      resolved_root: self.resolved_root,
      declaration,
      scope_cid,
      version_cid,
    }
  })
}

///|
/// The installed source's own transfer ceilings, separate from the Result.
pub(all) struct ClientProjectLocalCsvSourceLimits {
  max_file_bytes : Int64
  max_page_bytes : Int
  max_files : Int64
  max_page_rows : Int64
}

///|
pub(all) enum ClientProjectLocalCsvSourceIssue {
  ForeignOriginal
  SourceUnavailable
  ReadDenied
  InvalidLimits
} derive(Eq, Debug)

///|
/// A Whole CSV Source selected from the original, admitted Check. Holding
/// this choice pays for its geometry but grants no read and opens no root.
pub struct ClientProjectLocalCsvSource {
  priv check : ClientProjectLocalFileCheck
  priv catalog : ClientProjectLocalFileCatalog
  priv original : @acquisition.SourceAcquisition
  priv table : @row_host.LocalCsvTable
  transport : @row_host.LocalCsvPageTransport
  max_page_bytes : Int
}

///|
/// Choose a supported declared CSV before compiling the Whole Plan. The
/// request caller must supply the Source retained by that same Request.
pub fn[E] ClientProjectLocalFileCheck::prepare_csv_source(
  self : Self,
  original : @acquisition.SourceAcquisition,
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
  limits : ClientProjectLocalCsvSourceLimits,
  prepare : (@execution.PreparationRepresentationUnits) -> Result[Unit, E],
  issue : (ClientProjectLocalCsvSourceIssue) -> E,
) -> Result[ClientProjectLocalCsvSource, E] {
  guard physical_equal(account, self.account) && principal == self.principal else {
    return Err(issue(ForeignOriginal))
  }
  match
    prepare({
      // Use bounded scans of retained declarations and one evidence, decision,
      // transfer, and source record. No new schema, path or wire is built here.
      record_headers: 24L,
      reference_slots: 48L,
      scalar_words: 32L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }) {
    Ok(_) => ()
    Err(cause) => return Err(cause)
  }
  let input = @acquisition.mode_input(
    @acquisition.source_acquisition_mode(original),
  )
  let selected = @acquisition.declaration(input)
  guard @planning.source_acquisition_evidence_facts(original) is Some(facts) else {
    return Err(issue(ForeignOriginal))
  }
  let mut catalog = None
  for candidate in self.catalogs {
    if candidate.project_files.connection == selected.connector {
      guard catalog is None else { return Err(issue(ForeignOriginal)) }
      catalog = Some(candidate)
    }
  }
  guard catalog is Some(catalog) &&
    @row_host.row_declaration_view(catalog.declaration, facts.source_ref)
    is Some(view) &&
    view.resource == selected.resource &&
    view.view_cid == facts.source_contract_cid &&
    view.carrier_schema_cid == facts.carrier_schema_contract_cid &&
    view.data_policy_cid == facts.source_data_policy_cid &&
    @acquisition.selected_cid(input) == view.view_cid else {
    return Err(issue(ForeignOriginal))
  }
  guard @authorization.evaluate_account(account, {
      principal,
      connection: selected.connector,
      resource: view.resource,
      operation: "read",
    })
    is Allow(_) else {
    return Err(issue(ReadDenied))
  }
  guard catalog.project_files.csv_tables
    .iter()
    .find_first(table => table.view.resource == view.resource)
    is Some(table) else {
    return Err(issue(SourceUnavailable))
  }
  guard table.page_transport(
      limits.max_file_bytes,
      limits.max_page_bytes.to_int64(),
      limits.max_files,
      limits.max_page_rows,
    )
    is Some(transport) &&
    transport.transfer_bytes > 0L &&
    transport.transfer_bytes <= 2147483647L &&
    transport.max_rows <= 2147483647L else {
    return Err(issue(InvalidLimits))
  }
  Ok({
    check: self,
    catalog,
    original,
    table,
    transport,
    max_page_bytes: limits.max_page_bytes,
  })
}

///|
/// The exact declaration to supply to the whole plan. This projection
/// does not create a second Source or provide an alternate provider route.
pub fn ClientProjectLocalCsvSource::declaration(
  self : Self,
) -> @row_host.RowDeclaration {
  self.catalog.declaration
}

///|
/// The original whole-plan acquisition, held until the same response closes.
pub struct ClientProjectLocalCsvSelection {
  priv source : ClientProjectLocalCsvSource
  priv acquisition : @row_host.RowInputAcquisition
}

///|
/// Join the actual installed Whole Plan acquisition to the paid choice.
pub fn ClientProjectLocalCsvSource::bind_input(
  self : Self,
  acquisition : @row_host.RowInputAcquisition,
) -> Result[
  ClientProjectLocalCsvSelection,
  @row_host.LocalCsvWholeResponseIssue,
] {
  @row_host.check_row_input_acquisition_original(
    acquisition,
    self.catalog.declaration,
    self.original,
  )
  .map(_ => { source: self, acquisition, })
  .map_err(issue => @row_host.Row(issue))
}

///|
/// Match the exact Check held by the selected Request and its physical run.
pub fn ClientProjectLocalCsvSelection::matches_check(
  self : Self,
  check : ClientProjectLocalFileCheck,
) -> Bool {
  physical_equal(self.source.check, check)
}

///|
pub fn ClientProjectLocalCsvSelection::transport(
  self : Self,
) -> @row_host.LocalCsvPageTransport {
  self.source.transport
}

///|
pub fn ClientProjectLocalCsvSelection::declaration(
  self : Self,
) -> @row_host.RowDeclaration {
  self.source.catalog.declaration
}

///|
pub fn ClientProjectLocalCsvSelection::source_acquisition(
  self : Self,
) -> @acquisition.SourceAcquisition {
  self.source.original
}

///|
/// Re-evaluate read access through the same Check and original Account before
/// the installed owner opens the file or uses the returned response.
pub fn ClientProjectLocalCsvSelection::read_current(
  self : Self,
  check : ClientProjectLocalFileCheck,
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
) -> Bool {
  self.matches_check(check) &&
  physical_equal(account, check.account) &&
  principal == check.principal &&
  @authorization.evaluate_account(account, {
    principal,
    connection: self.source.catalog.project_files.connection,
    resource: self.source.table.view.resource,
    operation: "read",
  })
  is Allow(_)
}

///|
/// Complete paid setup before the installed owner performs any physical read.
/// Return the held Root and declared relative path with the same Run receiver.
pub fn ClientProjectLocalCsvSelection::file_locator(self : Self) -> (String, String) {
  (self.source.catalog.resolved_root, self.source.table.path)
}

///|
pub fn ClientProjectLocalCsvSelection::observed_extent_transport(
  self : Self,
  observed_bytes : Int64,
) -> (@row_host.LocalCsvPageTransport, Int)? {
  let source = self.source
  source.table.observed_extent_transport(
    source.transport, source.max_page_bytes, observed_bytes,
  )
}

///|
pub fn ClientProjectLocalCsvSelection::prepare_response(
  self : Self,
  borrow : @row_host.RowRunResponseBorrow,
  observed_bytes? : Int64? = None,
) -> Result[
  (String, String, @row_host.LocalCsvWholeResponse),
  @row_host.LocalCsvWholeResponseIssue,
] {
  match @row_host.row_run_response_selection(borrow) {
    Ok(@row_host.InputResponse(acquisition)) if physical_equal(
        self.acquisition,
        acquisition,
      ) => ()
    Err(issue) => return Err(@row_host.Row(issue))
    _ => return Err(@row_host.Row(@row_host.ForeignDeclaration))
  }
  let source = self.source
  let (transport, page_bytes) = match observed_bytes {
    None => (source.transport, source.max_page_bytes)
    Some(extent) => {
      guard self.observed_extent_transport(extent) is Some(quote) else {
        return Err(@row_host.Csv(@row_host.InvalidLocalCsvLimits))
      }
      quote
    }
  }
  @row_host.prepare_local_csv_whole_response(
    borrow,
    source.catalog.declaration,
    source.table,
    transport,
    page_bytes,
  ).map(response => (source.catalog.resolved_root, source.table.path, response))
}
