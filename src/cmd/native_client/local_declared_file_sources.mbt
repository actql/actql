///|
// Build declarations from the exact operator member retained by adoption.
// Prepared providers hold locators only. Source Work owns payload access,
// dispatch authorization and cleanup on the eventual checked Request.
fn LocalCommandPreparationOriginal::prepare_declared_file_sources(
  self : Self,
  configuration : LocalCommandConfiguration,
  capture : @local_host.NativeLocalJournalCapture,
) -> Unit raise ClientStop {
  guard configuration.declared_file_source is Some(original) else { return }
  guard !self.closing &&
    !self.closed &&
    self.primary is None &&
    self.declared_file_sources is None &&
    self.journal is Some(journal) &&
    physical_equal(journal, capture) &&
    self.journal_read_open &&
    !(self.project is Some(project) && project.mock_declarations is Some(_)) &&
    configuration.declared_file_source_current(capture) else {
    stop("LocalDeclaredFileSourceOriginalUnavailable")
  }
  let (connections, catalog, data_file) = original.material
  if catalog.count() == 0 || catalog.count() != connections.count() {
    stop("InvalidLocalDeclaredFileSourceInstallation")
  }
  let declarations = []
  let listings = []
  self.declared_file_sources = Some((declarations, listings))
  for index in 0..<catalog.count() {
    let (connection, wire) = catalog.at(index).unwrap()
    let mut selected = None
    for position in 0..<connections.count() {
      let (id, provider, _) = connections.at(position).unwrap()
      if id == connection {
        selected = Some(provider)
        break
      }
    }
    guard selected is Some(provider) else {
      stop("LocalDeclaredFileSourceOriginalUnavailable")
    }
    let projection = @row_host.relation_public_projection_construction_inventory(
      wire,
    ).unwrap_or_else(() => stop("LocalCommandPreparationLayoutUnavailable"))
    let bytes = local_host_metadata_price(projection)
    local_host_metadata_prepare(bytes, bytes)
    let (entry, declaration, files, scope) = local_command_query_preparation_result(
      self,
      local_native_file_source_declaration(
        connection,
        provider,
        catalog.original_wire(),
        wire,
        data_file,
      ).map_err(issue => CommandBusinessQueryRow(issue)),
      "InvalidLocalDeclaredFileSourceInstallation",
    )
    let rows = local_command_query_preparation_result(
      self,
      local_project_mock_row_bindings(entry, declaration, files, data_file).map_err(issue => {
          CommandBusinessQueryRow(issue)
        },
      ),
      "InvalidLocalDeclaredFileSourceInstallation",
    )
    let source : LocalProjectMockSourceDeclaration = {
      _retained_provider_namespace: provider,
      _retained_connection: connection,
      _retained_entry: entry,
      _retained_scope_cid: scope,
      _retained_declaration: declaration,
      _retained_files: files,
      _retained_rows: rows,
      _retained_writes: [],
    }
    declarations.push(source)
    if !files.is_empty() {
      let authority = local_host_result(
        capture.authority_scope_cid_in_original_read(
          configuration.settings.principal,
          connection,
        ),
      )
      let listing = local_command_query_preparation_result(
        self,
        local_project_mock_file_source(source, authority).map_err(issue => {
          CommandBusinessQueryRow(issue)
        }),
        "InvalidLocalDeclaredFileSourceInstallation",
      )
      listings.push(listing)
    }
  }
  if !configuration.declared_file_source_current(capture) {
    stop("LocalDeclaredFileSourceOriginalUnavailable")
  }
}
