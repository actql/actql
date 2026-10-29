///|
/// Static installation facts only. Query values, current permission and Run
/// admission remain with their existing operation owners.
#export_name("clientValuesHostPreparePublishedEnvironment")
pub fn client_values_host_prepare_published_environment(
  environment : @checked.CheckEnvironment,
  publication : String,
) -> Result[
  @source_publication.PreparedPublishedQueryEnvironment,
  @source_publication.PublicationIssue,
] {
  @source_publication.prepare_published_query_environment(
    environment, publication,
  )
}

///|
fn client_values_host_published_catalog(
  prepared : @source_publication.PreparedPublishedQueryEnvironment?,
  environment : @checked.CheckEnvironment,
) -> Result[
  @checked.PreparedSourceCatalog?,
  @source_publication.PreparedPublicationIssue,
] {
  match prepared {
    None => Ok(None)
    Some(value) =>
      @source_publication.prepared_published_query_catalog(value, environment).map(catalog => {
          Some(catalog)
        },
      )
  }
}

///|
fn client_values_host_published_effect_parts(
  prepared : @source_publication.PreparedPublishedQueryEnvironment?,
  environment : @checked.CheckEnvironment,
) -> Result[
  (
    @query.UpdateTargetPublication?,
    @query.StoreTargetPublication?,
    @query.CommandTargetPublication?,
    @checked.PreparedSourceCatalog?,
  ),
  @source_publication.PreparedPublicationIssue,
] {
  match prepared {
    None => Ok((None, None, None, None))
    Some(value) =>
      @source_publication.prepared_published_effect_parts(value, environment).map(parts => {
          (parts.0, parts.1, parts.2, Some(parts.3))
        },
      )
  }
}
