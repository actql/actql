///|
// Closed caller selection only. Neither variant owns a physical child or
// grants Source access. Its original managed Plan/read will consume it later.
priv enum LocalProjectMockEffectReader {
  Rows(LocalProjectMockRowBinding)
  Files(LocalProjectMockFileSource, @row_file.NativeRelationFileListingProvider)
}

///|
priv struct LocalProjectMockEffectSourceInput {
  _retained_coordinates : (Int, Int, Int)
  _retained_source : LocalProjectMockSourceDeclaration
  _retained_input : @local_values.ClientInstalledEffectSourceInput
  _retained_reader : LocalProjectMockEffectReader
}

///|
fn LocalProjectMockDeclarations::prepare_effect_sources(
  self : Self,
  prepared : @run_host.PreparedClientEffectComputation,
  occurrences : @run_host.ClientDirectAcquisitionOccurrences,
) -> Array[LocalProjectMockEffectSourceInput] raise ClientStop {
  guard !self.closing &&
    !self.retired &&
    self.sources_started &&
    @run_host.client_direct_acquisition_occurrences_match_effect_program(
      occurrences, prepared,
    ) else {
    stop("LocalOriginalSourceUnavailable")
  }
  let selected = []
  for
    index in 0..<@run_host.client_direct_acquisition_occurrence_count(
      occurrences,
    ) {
    let coordinates = @run_host.client_direct_acquisition_occurrence_at(
      occurrences, index,
    ).unwrap_or_else(() => stop("LocalOriginalSourceUnavailable"))
    let subject = @run_host.client_direct_acquisition_occurrence_subject(
      occurrences, index,
    ).unwrap_or_else(() => stop("LocalOriginalSourceUnavailable"))
    let declaration = @sourceviews.declaration(subject.source)
    let source = self.sources
      .iter()
      .find_first(value => {
        value._retained_connection == declaration.connector &&
        value._retained_declaration.views.any(view => {
          view.resource == declaration.resource
        })
      })
      .unwrap_or_else(() => stop("LocalOriginalSourceUnavailable"))
    // The installed Plan chooses the original Query/whole-input constructor.
    // This metadata adapter needs no second route derivation or dispatcher.
    let reader = match
      source._retained_rows
      .iter()
      .find_first(row => row.view.resource == declaration.resource) {
      Some(row) => Rows(row)
      None => {
        guard self.file_sources is Some(files) &&
          files
          .iter()
          .find_first(file => physical_equal(file._retained_original, source))
          is Some(file) &&
          file._retained_listings
          .iter()
          .find_first(pair => pair.1.listing.resource == declaration.resource)
          is Some((provider, _)) else {
          stop("LocalOriginalSourceUnavailable")
        }
        Files(file, provider)
      }
    }
    let (provider, page) = match reader {
      Rows(row) => (row.provider.capacity(), row.limits.page)
      Files(original, listing) => {
        guard original.references.known is Some(_) else {
          stop("LocalOriginalSourceUnavailable")
        }
        (listing.capacity(), local_project_mock_file_limits().page)
      }
    }
    let input = @local_values.prepare_installed_effect_row_source_input(
      source._retained_declaration,
      Some(provider),
      input_limits=Some(
        @local_values.installed_row_input_policy(
          page.max_rows,
          page.max_bytes,
          page.max_nodes,
          page.max_depth,
          page.max_rows,
        ),
      ),
    ).unwrap_or_else(() => stop("LocalOriginalSourceUnavailable"))
    selected.push({
      _retained_coordinates: coordinates,
      _retained_source: source,
      _retained_input: input,
      _retained_reader: reader,
    })
  }
  selected
}
