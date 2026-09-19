///|
type Store

///|
type PayloadWriter

///|
type PayloadReader

///|
pub fn open_store(
  _library : @sqlite.Library,
  _root_path : String,
  _authority_cid : String,
  _capacity_bytes : Int64,
  _max_objects : Int64,
  _max_record_bytes : Int64,
) -> Result[Store, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::begin_payload(
  _self : Store,
  _request : @payload.PublicationPayloadRequest,
) -> Result[PayloadWriter, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn PayloadWriter::append(
  _self : PayloadWriter,
  _chunk : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn PayloadWriter::seal(
  _self : PayloadWriter,
) -> Result[NativePublicationPayloadInfo, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn PayloadWriter::cancel(
  _self : PayloadWriter,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::inspect_payload(
  _self : Store,
  _material_generation_cid : String,
) -> Result[NativePublicationPayloadInfo, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::open_payload_reader(
  _self : Store,
  _material_generation_cid : String,
) -> Result[PayloadReader, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn PayloadReader::next(
  _self : PayloadReader,
  _max_bytes : Int,
) -> Result[@filesystem.NativeFileChunk, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn PayloadReader::finish(
  _self : PayloadReader,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn PayloadReader::close(
  _self : PayloadReader,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::reclaim_payload(
  _self : Store,
  _material_generation_cid : String,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::recover(
  _self : Store,
) -> Result[NativePublicationRecovery, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::capacity_usage(
  _self : Store,
) -> Result[@sqlite.NativeCapacityUsage, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::close(_self : Store) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}
