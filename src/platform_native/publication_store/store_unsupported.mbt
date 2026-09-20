///|
type Store

///|
type PayloadWriter

///|
type PayloadReader

///|
type PayloadDelivery

///|
type ConfirmedPayloadDelivery

///|
type ResultDelivery

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
pub fn Store::open_payload_delivery(
  _self : Store,
  _material_generation_cid : String,
  _format : String,
  _schema_wire : String,
  _fields : Array[String],
  _input_chunk_bytes : Int,
  _max_row_bytes : Int,
  _max_nodes : Int,
  _max_depth : Int,
  _max_delivery_bytes : Int64,
) -> Result[PayloadDelivery, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::open_confirmed_payload_delivery(
  _self : Store,
  _material_generation_cid : String,
  _format : String,
  _schema_wire : String,
  _fields : Array[String],
  _input_chunk_bytes : Int,
  _max_row_bytes : Int,
  _max_nodes : Int,
  _max_depth : Int,
  _max_delivery_bytes : Int64,
) -> Result[ConfirmedPayloadDelivery, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn PayloadDelivery::next(
  _self : PayloadDelivery,
  _max_bytes : Int,
) -> Result[NativePublicationDeliveryChunk, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn PayloadDelivery::finish(
  _self : PayloadDelivery,
) -> Result[NativePublicationDeliverySummary, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn PayloadDelivery::close(
  _self : PayloadDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ConfirmedPayloadDelivery::next(
  _self : ConfirmedPayloadDelivery,
  _max_bytes : Int,
) -> Result[NativePublicationDeliveryChunk, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ConfirmedPayloadDelivery::confirm_chunk(
  _self : ConfirmedPayloadDelivery,
) -> Result[Int64, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ConfirmedPayloadDelivery::fail_chunk(
  _self : ConfirmedPayloadDelivery,
  _confirmed_prefix_bytes : Int,
) -> Result[Int64, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ConfirmedPayloadDelivery::fail(
  _self : ConfirmedPayloadDelivery,
) -> Result[Int64, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ConfirmedPayloadDelivery::confirm_sink_finished(
  _self : ConfirmedPayloadDelivery,
) -> Result[NativePublicationDeliverySummary, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ConfirmedPayloadDelivery::close(
  _self : ConfirmedPayloadDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::commit_publication(
  _self : Store,
  _run_definition : @publication.PublicationContract,
  _invocation : @publication.PublicationContract,
  _definitions : Array[@publication.PublicationContract],
  _artifacts : Array[@publication.PublicationContract],
  _derivations : Array[@publication.PublicationContract],
  _orderings : Array[@publication.PublicationContract],
  _retentions : Array[@publication.PublicationContract],
  _bindings : Array[@publication.PublicationContract],
  _binding_schema_wires : Array[String],
  _manifest : @publication.PublicationContract,
  _receipt : @publication.PublicationContract,
  _captured_run : @publication.PublicationContract,
  _request : @publication.PublicationContract,
  _attempt : @publication.PublicationContract,
  _index : @publication.PublicationContract,
  _max_wire_bytes : Int,
  _max_nodes : Int,
  _max_depth : Int,
) -> Result[NativePublicationCommit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::inspect_committed_publication(
  _self : Store,
  _tenant_id : String,
  _authority_scope_cid : String,
  _run_definition_cid : String,
  _max_wire_bytes : Int,
  _max_nodes : Int,
  _max_depth : Int,
) -> Result[@publication.PublicationContract?, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::read_publication_contract(
  _self : Store,
  _name : String,
  _identity : String,
) -> Result[@publication.PublicationContract, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::read_result_schema(
  _self : Store,
  _result_schema_cid : String,
) -> Result[String, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::resolve_committed_result(
  _self : Store,
  _tenant_id : String,
  _authority_scope_cid : String,
  _run_definition_cid : String,
  _result_name : String,
  _max_wire_bytes : Int,
  _max_nodes : Int,
  _max_depth : Int,
) -> Result[NativeCommittedResult?, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::begin_result_delivery(
  _self : Store,
  _index : @publication.PublicationContract,
  _manifest : @publication.PublicationContract,
  _grant : @publication.PublicationContract,
  _retention : @publication.PublicationContract,
  _binding : @publication.PublicationContract,
  _material_generation_cid : String,
  _result_name : String,
  _format : String,
  _attempt_id : String,
  _requested_at : String,
  _schema_wire : String,
  _fields : Array[String],
  _input_chunk_bytes : Int,
  _max_row_bytes : Int,
  _max_wire_bytes : Int,
  _max_nodes : Int,
  _max_depth : Int,
  _max_delivery_bytes : Int64,
) -> Result[ResultDelivery, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ResultDelivery::attempt_cid(_self : ResultDelivery) -> String {
  ""
}

///|
pub fn ResultDelivery::next(
  _self : ResultDelivery,
  _max_bytes : Int,
  _observed_at : String,
) -> Result[NativePublicationDeliveryChunk, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ResultDelivery::confirm_chunk(
  _self : ResultDelivery,
) -> Result[Int64, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ResultDelivery::confirm_sink_finished(
  _self : ResultDelivery,
  _observed_at : String,
) -> Result[NativeResultDeliverySuccess, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ResultDelivery::terminate(
  _self : ResultDelivery,
  _confirmed_prefix_bytes : Int?,
  _cancellation_observed : Bool,
  _exposure : String,
  _possible_unconfirmed_max_bytes : Int?,
  _failure_cid : String?,
  _observed_at : String,
) -> Result[NativeResultDeliveryFailure, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ResultDelivery::close(
  _self : ResultDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::inspect_result_delivery(
  _self : Store,
  _attempt_id : String,
) -> Result[NativeResultDeliveryStatus, NativePublicationStoreIssue] {
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
