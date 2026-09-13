///|
/// The selected contract's read authority, not a current permission grant.
pub(all) enum SourceReadAuthority {
  ReadMetadata
  ReadContent
  ReadBinary
} derive(Eq, Debug)

///|
fn prepare_source_authority(
  source : @sourceviews.ResolvedInput,
) -> SourceReadAuthority raise UnitBuildFailure {
  let selected = @environment.source_request_member(
    @sourceviews.selected_contract(source),
  )
  // Catalog shape admission has already closed the authority vocabulary.
  // Read only the exact selected member; never choose a view by permission.
  let body = @decode.open_object(@environment.member_body(selected)).unwrap()
  let acquisition = @decode.open_object(
    @decode.required(body, "acquisition").unwrap(),
  ).unwrap()
  match @decode.text(@decode.required(acquisition, "authority").unwrap()) {
    Ok("read_metadata") => ReadMetadata
    Ok("read_content") => ReadContent
    Ok("read_binary") => ReadBinary
    _ => raise ForeignOwner
  }
}
