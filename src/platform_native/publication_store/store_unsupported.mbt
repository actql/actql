///|
// No failure value is acquired on unsupported targets. Keep the exported
// nominal type opaque without fabricating Native Root/Lock/Database custody.
type NativePublicationStoreOpenFailure

///|
pub fn NativePublicationStoreOpenFailure::issue(
  _self : NativePublicationStoreOpenFailure,
) -> NativePublicationStoreIssue {
  UnsupportedTarget
}

///|
pub fn NativePublicationStoreOpenFailure::retry_cleanup(
  _self : NativePublicationStoreOpenFailure,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
type Store

///|
type PayloadWriter

///|
type PayloadCleanupOwner

///|
type PayloadReader

///|
type PayloadDelivery

///|
type ConfirmedPayloadDelivery

///|
type ResultDelivery

///|
pub fn Store::reconcile_original_return(
  _self : Store,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::retry_pending_result_delivery_cleanup(
  _self : Store,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

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
pub fn open_existing_store(
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
pub fn open_store_with_custody(
  _library : @sqlite.Library,
  _root_path : String,
  _authority_cid : String,
  _capacity_bytes : Int64,
  _max_objects : Int64,
  _max_record_bytes : Int64,
  diagnostic_ceiling? : Int? = None,
) -> Result[Store, NativePublicationStoreOpenError] {
  if diagnostic_ceiling is Some(value) && value <= 0 {
    return Err(RefusedBeforeAcquisition(Filesystem(@filesystem.InvalidLimit)))
  }
  Err(RefusedBeforeAcquisition(UnsupportedTarget))
}

///|
pub fn open_existing_store_with_custody(
  _library : @sqlite.Library,
  _root_path : String,
  _authority_cid : String,
  _capacity_bytes : Int64,
  _max_objects : Int64,
  _max_record_bytes : Int64,
  diagnostic_ceiling? : Int? = None,
) -> Result[Store, NativePublicationStoreOpenError] {
  if diagnostic_ceiling is Some(value) && value <= 0 {
    return Err(RefusedBeforeAcquisition(Filesystem(@filesystem.InvalidLimit)))
  }
  Err(RefusedBeforeAcquisition(UnsupportedTarget))
}

///|
pub fn Store::begin_payload(
  _self : Store,
  _request : @payload.PublicationPayloadRequest,
) -> Result[PayloadWriter, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::acquire_payload_cleanup(
  _self : Store,
  _request : @payload.PublicationPayloadRequest,
) -> Result[PayloadCleanupOwner, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn PayloadCleanupOwner::pending(_self : PayloadCleanupOwner) -> Bool {
  false
}

///|
pub fn PayloadCleanupOwner::retry(
  _self : PayloadCleanupOwner,
) -> Result[Bool, NativePublicationStoreIssue] {
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
pub fn Store::reconcile_payload(
  _self : Store,
  _request : @payload.PublicationPayloadRequest,
) -> Result[NativePublicationPayloadInfo?, NativePublicationStoreIssue] {
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
  capture? : @local.ClientProgramCapture? = None,
) -> Result[NativePublicationCommit, NativePublicationStoreIssue] {
  ignore(capture)
  Err(UnsupportedTarget)
}

///|
pub fn Store::inspect_committed_publication(
  _self : Store,
  _namespace_id : String,
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
pub fn Store::observe_trusted_clock(
  _self : Store,
  _clock_contract_cid : String,
  _observed_at : String,
) -> Result[String, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::resolve_committed_result(
  _self : Store,
  _namespace_id : String,
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
pub fn Store::lookup_result_delivery(
  _self : Store,
  _scope : @publication.DeliveryAttemptLookupScope,
) -> Result[NativeResultDeliveryLookup?, NativePublicationStoreIssue] {
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
pub fn Store::observe_allocation(
  _self : Store,
  _observer : (String) -> Unit,
) -> Unit {
  ()
}

///|
pub fn Store::close(_self : Store) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
#warnings("-unused_value")
fn retain_native_imports() -> Unit {
  ignore(@sha.hasher())
  ignore(@utf8.encode(""))
}

///|
pub fn Store::custody_location(
  _self : Store,
) -> Result[(String, UInt64, UInt64), NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::matches_original_operation(
  _self : Store,
  _original : @sqlite.NativeStoreOperationOriginal,
) -> Bool {
  false
}

///|
pub fn open_local_store_with_custody(
  _library : @sqlite.Library,
  _root_path : String,
  _authority_cid : String,
  _capacity_bytes : Int64,
  _max_objects : Int64,
  _max_record_bytes : Int64,
  diagnostic_ceiling? : Int? = None,
) -> Result[Store, NativePublicationStoreOpenError] {
  if diagnostic_ceiling is Some(value) && value <= 0 {
    return Err(RefusedBeforeAcquisition(Filesystem(@filesystem.InvalidLimit)))
  }
  Err(RefusedBeforeAcquisition(UnsupportedTarget))
}

///|
pub fn open_existing_local_store_with_custody(
  _library : @sqlite.Library,
  _root_path : String,
  _authority_cid : String,
  _capacity_bytes : Int64,
  _max_objects : Int64,
  _max_record_bytes : Int64,
  diagnostic_ceiling? : Int? = None,
) -> Result[Store, NativePublicationStoreOpenError] {
  if diagnostic_ceiling is Some(value) && value <= 0 {
    return Err(RefusedBeforeAcquisition(Filesystem(@filesystem.InvalidLimit)))
  }
  Err(RefusedBeforeAcquisition(UnsupportedTarget))
}

///|
pub fn open_original_local_store_with_custody(
  _library : @sqlite.Library,
  _original : @sqlite.NativeStoreOperationOriginal,
  _root_path : String,
  _authority_cid : String,
  _capacity_bytes : Int64,
  _max_objects : Int64,
  _max_record_bytes : Int64,
  existing? : Bool = false,
  diagnostic_ceiling? : Int? = None,
) -> Result[Store, NativePublicationStoreOpenError] {
  ignore(existing)
  ignore(diagnostic_ceiling)
  Err(RefusedBeforeAcquisition(UnsupportedTarget))
}

///|
pub fn Store::retained_data_current(
  _self : Store,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}
