///|
// Preserve the existing Node preparation failure domain while using the same
// portable publication owner as the public check projection.
fn client_table_write_publication(
  environment : @program_check.CheckEnvironment,
  publication : String,
) -> Array[@query_program.TableWriteBinding] raise ClientSourceStop {
  match @source_publication.published_table_writes(environment, publication) {
    Ok(value) => value
    Err(Limit) => raise ClientSourceStop(Limit)
    Err(_) => raise ClientSourceStop(Publication)
  }
}
