///|
/// Regular non-test emission roots for the private installed control component.
/// The final shim registration declaration must come from matching generated C.
/// There is deliberately no guessed C stub, profile, acquire or worker launch.
extern "C" fn register_original_control_roots(
  prepare : FuncRef[
    (String, Bytes, Int64, Int64, Int, Int, Int, Int64, Int64, Int64, Int64) -> @control.InstalledArenaReply,
  ],
  acquire : FuncRef[
    (@control.InstalledArenaHost) -> @control.InstalledArenaReply,
  ],
  current : FuncRef[
    (@control.InstalledArenaHost) -> @control.InstalledArenaReply,
  ],
  close : FuncRef[(@control.InstalledArenaHost) -> @control.InstalledArenaReply],
  original : FuncRef[
    (@control.InstalledArenaReply) -> @control.InstalledArenaHost?,
  ],
  operation : FuncRef[(@control.InstalledArenaReply) -> Int],
  issue_family : FuncRef[(@control.InstalledArenaReply) -> Int],
  description : FuncRef[(@control.InstalledArenaReply) -> String],
) -> Unit = "actql_native_control_register_original_roots"

///|
/// Source declaration only until matching regular C emission confirms the
/// callback prototypes and ownership. No guessed C header or stub is supplied.
extern "C" fn register_original_backing_roots(
  borrow : FuncRef[
    (@control.InstalledArenaHost) -> @control.InstalledArenaBackingReply,
  ],
  current : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaBackingBorrow) -> @control.InstalledArenaBackingReply,
  ],
  return_loan : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaBackingBorrow) -> @control.InstalledArenaBackingReply,
  ],
  original : FuncRef[
    (@control.InstalledArenaBackingReply) -> @control.InstalledArenaHost?,
  ],
  loan : FuncRef[
    (@control.InstalledArenaBackingReply) -> @control.InstalledArenaBackingBorrow?,
  ],
  operation : FuncRef[(@control.InstalledArenaBackingReply) -> Int],
  issue_family : FuncRef[(@control.InstalledArenaBackingReply) -> Int],
  description : FuncRef[(@control.InstalledArenaBackingReply) -> String],
) -> Unit = "actql_native_control_register_backing_roots"

///|
extern "C" fn register_original_backing_scope_roots(
  enter : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaBackingBorrow) -> @control.InstalledArenaBackingReply,
  ],
  leave : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaBackingBorrow) -> @control.InstalledArenaBackingReply,
  ],
) -> Unit = "actql_native_control_register_backing_scope_roots"

///|
/// Code registration only. The C declaration and managed-input ownership must
/// be checked against this source's actual regular emission before linking.
extern "C" fn register_original_fd_root(
  acquire : FuncRef[
    (@control.InstalledArenaHost, Int) -> @control.InstalledArenaReply,
  ],
) -> Unit = "actql_native_control_register_fd_root"

///|
/// Code registration only. Matching regular C emission must establish the
/// exact prototypes/borrow ownership before any shim is linked or loaded.
extern "C" fn register_original_domain_roots(
  prepare : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaBackingBorrow,
      Int,
      Int64,
      Int,
      Int,
      Int,
      Int64,
      Int64,
      Int64,
    ) -> @control.InstalledArenaDomainReply,
  ],
  current : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaDomain) -> @control.InstalledArenaDomainReply,
  ],
  transfer : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaDomain) -> @control.InstalledArenaDomainReply,
  ],
  enter : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaDomain) -> @control.InstalledArenaDomainReply,
  ],
  leave : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaDomain) -> @control.InstalledArenaDomainReply,
  ],
  close : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaDomain) -> @control.InstalledArenaDomainReply,
  ],
  original : FuncRef[
    (@control.InstalledArenaDomainReply) -> @control.InstalledArenaHost,
  ],
  domain : FuncRef[
    (@control.InstalledArenaDomainReply) -> @control.InstalledArenaDomain?,
  ],
  operation : FuncRef[(@control.InstalledArenaDomainReply) -> Int],
  issue : FuncRef[(@control.InstalledArenaDomainReply) -> Int],
  description : FuncRef[(@control.InstalledArenaDomainReply) -> String],
) -> Unit = "actql_native_control_register_domain_roots"

///|
/// One first domain from actual charged control; code registration is not a
/// numerical profile. Match the regular emitted C before defining its shim.
extern "C" fn register_original_initial_domain_root(
  prepare : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaBackingBorrow,
      Int,
      Int,
      Int,
      Int,
      Int64,
    ) -> @control.InstalledArenaDomainReply,
  ],
) -> Unit = "actql_native_control_register_initial_domain_root"

///|
/// Data getters only. The matching actual regular C must determine signatures
/// and managed ownership before linking the transport shim.
extern "C" fn register_original_domain_material_roots(
  project : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaDomain) -> @control.InstalledArenaDomainReply,
  ],
  scalar : FuncRef[(@control.InstalledArenaDomainReply, Int) -> Int64],
  source : FuncRef[(@control.InstalledArenaDomainReply) -> String],
  recipe : FuncRef[(@control.InstalledArenaDomainReply) -> Bytes],
) -> Unit = "actql_native_control_register_domain_material_roots"

///|
/// Typed code registration only; the matching regular C emission must be read
/// before declaring or linking the derived read callback ABI in a C shim.
extern "C" fn register_original_domain_read_roots(
  prepare : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaDomain) -> @control.InstalledArenaDomainReply,
  ],
  current : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaDomain) -> @control.InstalledArenaDomainReply,
  ],
  enter : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaDomain) -> @control.InstalledArenaDomainReply,
  ],
  leave : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaDomain) -> @control.InstalledArenaDomainReply,
  ],
  cleanup : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaDomain) -> @control.InstalledArenaDomainReply,
  ],
  close : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaDomain) -> @control.InstalledArenaDomainReply,
  ],
) -> Unit = "actql_native_control_register_domain_read_roots"

///|
/// Code registration only. Matching regular C emission must determine the
/// exact managed ownership before the selection transport shim is linked.
extern "C" fn register_original_worker_selection_roots(
  select : FuncRef[
    (@control.InstalledArenaHost) -> @control.InstalledArenaWorkerSelectionReply,
  ],
  current : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaWorkerSelection) -> @control.InstalledArenaWorkerSelectionReply,
  ],
  original : FuncRef[
    (@control.InstalledArenaWorkerSelectionReply) -> @control.InstalledArenaHost,
  ],
  selection : FuncRef[
    (@control.InstalledArenaWorkerSelectionReply) -> @control.InstalledArenaWorkerSelection?,
  ],
  selection_host : FuncRef[
    (@control.InstalledArenaWorkerSelection) -> @control.InstalledArenaHost,
  ],
  operation : FuncRef[(@control.InstalledArenaWorkerSelectionReply) -> Int],
  issue : FuncRef[(@control.InstalledArenaWorkerSelectionReply) -> Int],
) -> Unit = "actql_native_control_register_worker_selection_roots"

///|
/// Code registration only. Actual regular emission must establish the callback
/// prototypes and reference ownership before a private transport is linked.
extern "C" fn register_original_sqlite_roots(
  prepare : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
      String,
      Int64,
      Int,
    ) -> @control.InstalledArenaSqliteReply,
  ],
  current : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteLibrary) -> @control.InstalledArenaSqliteReply,
  ],
  close : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteLibrary) -> @control.InstalledArenaSqliteReply,
  ],
  host : FuncRef[
    (@control.InstalledArenaSqliteReply) -> @control.InstalledArenaHost,
  ],
  domain : FuncRef[
    (@control.InstalledArenaSqliteReply) -> @control.InstalledArenaDomain,
  ],
  original : FuncRef[
    (@control.InstalledArenaSqliteReply) -> @control.InstalledArenaSqliteLibrary?,
  ],
  operation : FuncRef[(@control.InstalledArenaSqliteReply) -> Int],
  issue : FuncRef[(@control.InstalledArenaSqliteReply) -> Int],
) -> Unit = "actql_native_control_register_sqlite_roots"

///|
/// Register only exact code roots; matching emitted C must establish the ABI.
extern "C" fn register_original_sqlite_database_roots(
  restore : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteLibrary,
      String,
      Int64,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  initialize : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteLibrary,
      String,
      Int64,
      UInt64,
      UInt64,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  observe : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteDatabase) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  read : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteDatabase,
      String,
      String,
      Int64,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  insert : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteDatabase,
      String,
      String,
      Bytes,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  compare : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteDatabase,
      String,
      String,
      Int64,
      Bytes,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  transaction : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteDatabase, Int) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  close : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteDatabase) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  fence : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteDatabase) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  host : FuncRef[
    (@control.InstalledArenaSqliteDatabaseReply) -> @control.InstalledArenaHost,
  ],
  library : FuncRef[
    (@control.InstalledArenaSqliteDatabaseReply) -> @control.InstalledArenaSqliteLibrary,
  ],
  database : FuncRef[
    (@control.InstalledArenaSqliteDatabaseReply) -> @control.InstalledArenaSqliteDatabase?,
  ],
  operation : FuncRef[(@control.InstalledArenaSqliteDatabaseReply) -> Int],
  stage : FuncRef[(@control.InstalledArenaSqliteDatabaseReply) -> Int],
  issue : FuncRef[(@control.InstalledArenaSqliteDatabaseReply) -> Int],
  after : FuncRef[(@control.InstalledArenaSqliteDatabaseReply) -> Int],
  has_row : FuncRef[(@control.InstalledArenaSqliteDatabaseReply) -> Int],
  revision : FuncRef[(@control.InstalledArenaSqliteDatabaseReply) -> Int64],
  body : FuncRef[(@control.InstalledArenaSqliteDatabaseReply) -> Bytes],
  bound : FuncRef[(@control.InstalledArenaSqliteDatabaseReply) -> Int64],
  scan : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteDatabase,
      String,
      String,
      Int64,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  key : FuncRef[(@control.InstalledArenaSqliteDatabaseReply) -> Bytes],
  reserve_capacity : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteDatabase,
      String,
      String,
      Int64,
      Int64,
      Int64,
      Int64,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  capacity_usage : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteDatabase, String) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  release_capacity : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteDatabase,
      String,
      String,
      Int64,
      Int64,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  capacity_changed : FuncRef[
    (@control.InstalledArenaSqliteDatabaseReply) -> Int,
  ],
  reserved_bytes : FuncRef[
    (@control.InstalledArenaSqliteDatabaseReply) -> Int64,
  ],
  reserved_objects : FuncRef[
    (@control.InstalledArenaSqliteDatabaseReply) -> Int64,
  ],
  read_capacity : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteDatabase,
      String,
      String,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  database_usage : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteDatabase) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  transaction_state : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteDatabase) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  record_count : FuncRef[(@control.InstalledArenaSqliteDatabaseReply) -> Int64],
  record_body_bytes : FuncRef[
    (@control.InstalledArenaSqliteDatabaseReply) -> Int64,
  ],
  reservation_count : FuncRef[
    (@control.InstalledArenaSqliteDatabaseReply) -> Int64,
  ],
  transaction_active : FuncRef[
    (@control.InstalledArenaSqliteDatabaseReply) -> Int,
  ],
  header : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteDatabase,
      String,
      String,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  has_header : FuncRef[(@control.InstalledArenaSqliteDatabaseReply) -> Int],
  header_body_bytes : FuncRef[
    (@control.InstalledArenaSqliteDatabaseReply) -> Int64,
  ],
  begin_read : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteDatabase) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  reserve_bounded : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteDatabase,
      String,
      String,
      Int64,
      Int64,
      Int64,
      Int64,
      Int64,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  lookup_start : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteDatabase) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  lookup_observe : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteLookup) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  lookup_read : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteLookup,
      String,
      String,
      Int64,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  lookup_scan : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteLookup,
      String,
      String,
      Int64,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  lookup_header : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteLookup,
      String,
      String,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  lookup_capacity : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaSqliteLookup,
      String,
      String,
    ) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  lookup_capacity_usage : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteLookup, String) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  lookup_database_usage : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteLookup) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  lookup_finish : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteLookup) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  lookup_close : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaSqliteLookup) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
  original_lookup : FuncRef[
    (@control.InstalledArenaSqliteDatabaseReply) -> @control.InstalledArenaSqliteLookup?,
  ],
  revalidate_copy : FuncRef[
    (@control.InstalledArenaSqliteDatabaseReply) -> @control.InstalledArenaSqliteDatabaseReply,
  ],
) -> Unit = "actql_native_control_register_sqlite_database_roots"

///|
fn original_host(
  reply : @control.InstalledArenaReply,
) -> @control.InstalledArenaHost? {
  reply.original_host()
}

///|
/// Code roots only. Read the matching regular emission's prototypes and RC
/// before implementing a shim; no guessed callback layout is installed here.
extern "C" fn register_original_live_channel_roots(
  prepare : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
      Int,
      Int,
      Int,
      Int64,
    ) -> @control.InstalledArenaLiveChannelReply,
  ],
  bind_vm : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
      @bootstrap.NativeBackedLiveChannel[
        @control.InstalledArenaHost,
        @control.InstalledArenaDomain,
      ],
      Int64,
      Int64,
      Int64,
    ) -> @control.InstalledArenaLiveChannelReply,
  ],
  operate : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
      @bootstrap.NativeBackedLiveChannel[
        @control.InstalledArenaHost,
        @control.InstalledArenaDomain,
      ],
      Int,
    ) -> @control.InstalledArenaLiveChannelReply,
  ],
  report : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
      @bootstrap.NativeBackedLiveChannel[
        @control.InstalledArenaHost,
        @control.InstalledArenaDomain,
      ],
      Int,
      Int,
      Int,
      Int64,
      Int64,
      Int64,
      Int64,
      Int64,
      Int64,
      Int64,
    ) -> @control.InstalledArenaLiveChannelReply,
  ],
  original_host : FuncRef[
    (@control.InstalledArenaLiveChannelReply) -> @control.InstalledArenaHost,
  ],
  original_domain : FuncRef[
    (@control.InstalledArenaLiveChannelReply) -> @control.InstalledArenaDomain,
  ],
  original_channel : FuncRef[
    (@control.InstalledArenaLiveChannelReply) -> @bootstrap.NativeBackedLiveChannel[
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
    ]?,
  ],
  operation : FuncRef[(@control.InstalledArenaLiveChannelReply) -> Int],
  issue : FuncRef[(@control.InstalledArenaLiveChannelReply) -> Int],
  state : FuncRef[(@control.InstalledArenaLiveChannelReply) -> Int],
  limit : FuncRef[(@control.InstalledArenaLiveChannelReply, Int) -> Int64],
  description : FuncRef[(@control.InstalledArenaLiveChannelReply) -> String],
) -> Unit = "actql_native_control_register_live_channel_roots"

///|
/// Code roots only. Actual regular C emission determines the private callback
/// prototypes and borrow/return RC before the matching C transport is defined.
extern "C" fn register_original_live_preparation_roots(
  prepare : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
      Int,
      Int,
      Int64,
    ) -> @control.InstalledArenaLiveChannelReply,
  ],
  bind_child : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
      @bootstrap.NativeBackedLiveChannel[
        @control.InstalledArenaHost,
        @control.InstalledArenaDomain,
      ],
      Int,
    ) -> @control.InstalledArenaLiveChannelReply,
  ],
  prepare_ledger : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
      @bootstrap.NativeBackedLiveChannel[
        @control.InstalledArenaHost,
        @control.InstalledArenaDomain,
      ],
    ) -> @control.InstalledArenaChannelLedgerReply,
  ],
  operate_ledger : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
      @bootstrap.NativeBackedLiveChannel[
        @control.InstalledArenaHost,
        @control.InstalledArenaDomain,
      ],
      @resources.ImportedChildLedger,
      Int,
      Int64,
      Int64,
    ) -> @control.InstalledArenaChannelLedgerReply,
  ],
  original_host : FuncRef[
    (@control.InstalledArenaChannelLedgerReply) -> @control.InstalledArenaHost,
  ],
  original_domain : FuncRef[
    (@control.InstalledArenaChannelLedgerReply) -> @control.InstalledArenaDomain,
  ],
  original_channel : FuncRef[
    (@control.InstalledArenaChannelLedgerReply) -> @bootstrap.NativeBackedLiveChannel[
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
    ],
  ],
  original_frame : FuncRef[
    (@control.InstalledArenaChannelLedgerReply) -> @resources.ImportedChildLedger?,
  ],
  operation : FuncRef[(@control.InstalledArenaChannelLedgerReply) -> Int],
  issue : FuncRef[(@control.InstalledArenaChannelLedgerReply) -> Int],
  limit : FuncRef[(@control.InstalledArenaChannelLedgerReply, Int) -> Int64],
  description : FuncRef[(@control.InstalledArenaChannelLedgerReply) -> String],
) -> Unit = "actql_native_control_register_live_preparation_roots"

///|
/// Matching regular C emission determines the callback ABI before its private
/// transport is declared or linked. Registration contains code references only.
extern "C" fn register_original_parent_read_roots(
  prepare : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
      Int64,
      Int64,
      Int64,
      Int64,
      Int64,
    ) -> @control.InstalledArenaOriginalReadReply,
  ],
  current : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaOriginalRead) -> @control.InstalledArenaOriginalReadReply,
  ],
  enter : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaOriginalRead) -> @control.InstalledArenaOriginalReadReply,
  ],
  leave : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaOriginalRead) -> @control.InstalledArenaOriginalReadReply,
  ],
  cleanup : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaOriginalRead) -> @control.InstalledArenaOriginalReadReply,
  ],
  close : FuncRef[
    (@control.InstalledArenaHost, @control.InstalledArenaOriginalRead) -> @control.InstalledArenaOriginalReadReply,
  ],
  host : FuncRef[
    (@control.InstalledArenaOriginalReadReply) -> @control.InstalledArenaHost,
  ],
  domain : FuncRef[
    (@control.InstalledArenaOriginalReadReply) -> @control.InstalledArenaDomain,
  ],
  original : FuncRef[
    (@control.InstalledArenaOriginalReadReply) -> @control.InstalledArenaOriginalRead?,
  ],
  operation : FuncRef[(@control.InstalledArenaOriginalReadReply) -> Int],
  issue : FuncRef[(@control.InstalledArenaOriginalReadReply) -> Int],
) -> Unit = "actql_native_control_register_parent_read_roots"

///|
/// Code roots only. The matching generated C and ownership must be observed
/// before a runtime shim can be linked; registration does not capture files.
extern "C" fn register_original_packaged_runtime_roots(
  capture : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaOriginalRead,
      String,
      String,
      String,
      String,
      Int,
    ) -> @runtime.NativeLocalPackagedRuntimeReply,
  ],
  current : FuncRef[
    (@runtime.NativeLocalPackagedRuntime) -> @runtime.NativeLocalPackagedRuntimeReply,
  ],
  close : FuncRef[
    (@runtime.NativeLocalPackagedRuntime) -> @runtime.NativeLocalPackagedRuntimeReply,
  ],
  host : FuncRef[
    (@runtime.NativeLocalPackagedRuntimeReply) -> @control.InstalledArenaHost?,
  ],
  original : FuncRef[
    (@runtime.NativeLocalPackagedRuntimeReply) -> @control.InstalledArenaOriginalRead?,
  ],
  runtime : FuncRef[
    (@runtime.NativeLocalPackagedRuntimeReply) -> @runtime.NativeLocalPackagedRuntime?,
  ],
  operation : FuncRef[(@runtime.NativeLocalPackagedRuntimeReply) -> Int],
  issue : FuncRef[(@runtime.NativeLocalPackagedRuntimeReply) -> Int],
  capture_pair : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaOriginalRead,
      @control.InstalledArenaLocalHostResources,
      String,
      String,
      String,
      String,
      Int,
    ) -> @runtime.NativeLocalPackagedRuntimeReply,
  ],
) -> Unit = "actql_native_control_register_packaged_runtime_roots"

///|
extern "C" fn register_original_packaged_product_roots(
  observe : FuncRef[
    (@runtime.NativeLocalPackagedRuntime, String, String, String, Int) -> @runtime.NativeLocalPackagedProductReply,
  ],
  identity : FuncRef[
    (@runtime.NativeLocalPackagedRuntime) -> @runtime.NativeLocalPackagedProductReply,
  ],
  host : FuncRef[
    (@runtime.NativeLocalPackagedProductReply) -> @control.InstalledArenaHost?,
  ],
  original : FuncRef[
    (@runtime.NativeLocalPackagedProductReply) -> @control.InstalledArenaOriginalRead?,
  ],
  runtime : FuncRef[
    (@runtime.NativeLocalPackagedProductReply) -> @runtime.NativeLocalPackagedRuntime,
  ],
  operation : FuncRef[(@runtime.NativeLocalPackagedProductReply) -> Int],
  issue : FuncRef[(@runtime.NativeLocalPackagedProductReply) -> Int],
  length : FuncRef[(@runtime.NativeLocalPackagedProductReply) -> Int],
  unit_at : FuncRef[(@runtime.NativeLocalPackagedProductReply, Int) -> Int],
) -> Unit = "actql_native_control_register_packaged_product_roots"

///|
fn operation_tag(reply : @control.InstalledArenaReply) -> Int {
  reply.operation_tag()
}

///|
fn issue_family(reply : @control.InstalledArenaReply) -> Int {
  reply.issue_family()
}

///|
fn description(reply : @control.InstalledArenaReply) -> String {
  reply.issue_description()
}

///|
/// Code roots only. Matching regular C emission establishes the exact private
/// prototypes and borrowed/owned references before any shim is implemented.
extern "C" fn register_original_process_roots(
  prepare : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
      String,
      Int,
      Int64,
      Int64,
      Int64,
    ) -> @control.InstalledArenaProcessReply,
  ],
  operate : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
      @control.InstalledArenaProcess,
      Int,
    ) -> @control.InstalledArenaProcessReply,
  ],
  prepare_child : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
      @control.InstalledArenaProcess,
      String,
      Bytes,
      Bytes,
    ) -> @control.InstalledArenaProcessReply,
  ],
  host : FuncRef[
    (@control.InstalledArenaProcessReply) -> @control.InstalledArenaHost,
  ],
  domain : FuncRef[
    (@control.InstalledArenaProcessReply) -> @control.InstalledArenaDomain,
  ],
  process : FuncRef[
    (@control.InstalledArenaProcessReply) -> @control.InstalledArenaProcess?,
  ],
  channel : FuncRef[
    (@control.InstalledArenaProcessReply) -> @bootstrap.NativeBackedLiveChannel[
      @control.InstalledArenaHost,
      @control.InstalledArenaDomain,
    ]?,
  ],
  frame : FuncRef[
    (@control.InstalledArenaProcessReply) -> @resources.ImportedChildLedger?,
  ],
  operation : FuncRef[(@control.InstalledArenaProcessReply) -> Int],
  issue : FuncRef[(@control.InstalledArenaProcessReply) -> Int],
  descriptor : FuncRef[(@control.InstalledArenaProcessReply, Int) -> Int],
  backing_descriptor : FuncRef[(@control.InstalledArenaProcessReply) -> Int],
  stop : FuncRef[(@control.InstalledArenaProcessReply) -> Int],
  description : FuncRef[(@control.InstalledArenaProcessReply) -> String],
) -> Unit = "actql_native_control_register_process_roots"

///|
/// This initializes code references only. Registration is not supplier adoption,
/// original arena acquisition, Root creation, Run admission or VM permission.
fn main {
  register_original_read_crypto_roots()
  @runtime.register_native_local_journal_capture_roots()
  @runtime.register_native_local_adoption_binding_roots()
  register_original_local_host_resources_roots()
  register_original_sqlite_database_roots(
    fn(host, library, path, bound) {
      @control.restore_installed_sqlite_database_reply(
        host, library, path, bound,
      )
    },
    fn(host, library, path, bound, device, inode) {
      @control.initialize_installed_sqlite_database_reply(
        host, library, path, bound, device, inode,
      )
    },
    fn(host, original) {
      @control.observe_installed_sqlite_database_reply(host, original)
    },
    fn(host, original, scope, key, bound) {
      @control.read_installed_sqlite_database_reply(
        host, original, scope, key, bound,
      )
    },
    fn(host, original, scope, key, body) {
      @control.insert_installed_sqlite_database_reply(
        host, original, scope, key, body,
      )
    },
    fn(host, original, scope, key, expected, body) {
      @control.compare_installed_sqlite_database_reply(
        host, original, scope, key, expected, body,
      )
    },
    fn(host, original, operation) {
      @control.transaction_installed_sqlite_database_reply(
        host, original, operation,
      )
    },
    fn(host, original) {
      @control.close_installed_sqlite_database_reply(host, original)
    },
    fn(host, original) {
      @control.fence_installed_sqlite_database_reply(host, original)
    },
    fn(reply) { reply.original_host() },
    fn(reply) { reply.original_library() },
    fn(reply) { reply.original_database() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.stage_tag() },
    fn(reply) { reply.issue_family() },
    fn(reply) { reply.after_issue_family() },
    fn(reply) { reply.has_row() },
    fn(reply) { reply.revision() },
    fn(reply) { reply.body() },
    fn(reply) { reply.body_bound() },
    fn(host, original, scope, after_key, bound) {
      @control.scan_installed_sqlite_database_reply(
        host, original, scope, after_key, bound,
      )
    },
    fn(reply) { reply.row_key_bytes() },
    fn(host, original, scope, key, bytes, objects, max_bytes, max_objects) {
      @control.reserve_installed_sqlite_capacity_reply(
        host, original, scope, key, bytes, objects, max_bytes, max_objects,
      )
    },
    fn(host, original, scope) {
      @control.observe_installed_sqlite_capacity_reply(host, original, scope)
    },
    fn(host, original, scope, key, bytes, objects) {
      @control.release_installed_sqlite_capacity_reply(
        host, original, scope, key, bytes, objects,
      )
    },
    fn(reply) { reply.capacity_changed() },
    fn(reply) { reply.reserved_bytes() },
    fn(reply) { reply.reserved_objects() },
    fn(host, original, scope, key) {
      @control.read_installed_sqlite_capacity_reply(host, original, scope, key)
    },
    fn(host, original) {
      @control.observe_installed_sqlite_database_usage_reply(host, original)
    },
    fn(host, original) {
      @control.observe_installed_sqlite_transaction_state_reply(host, original)
    },
    fn(reply) { reply.record_count() },
    fn(reply) { reply.record_body_bytes() },
    fn(reply) { reply.reservation_count() },
    fn(reply) { reply.transaction_active() },
    fn(host, original, scope, key) {
      @control.read_installed_sqlite_header_reply(host, original, scope, key)
    },
    fn(reply) { reply.has_header() },
    fn(reply) { reply.header_body_bytes() },
    fn(host, original) {
      @control.begin_installed_sqlite_read_reply(host, original)
    },
    fn(
      host,
      original,
      scope,
      key,
      bytes,
      objects,
      max_bytes,
      max_objects,
      max_reservations,
    ) {
      @control.reserve_installed_sqlite_bounded_capacity_reply(
        host, original, scope, key, bytes, objects, max_bytes, max_objects, max_reservations,
      )
    },
    fn(host, original) {
      @control.start_installed_sqlite_lookup_reply(host, original)
    },
    fn(host, original) {
      @control.observe_installed_sqlite_lookup_reply(host, original)
    },
    fn(host, original, scope, key, bound) {
      @control.read_installed_sqlite_lookup_reply(
        host, original, scope, key, bound,
      )
    },
    fn(host, original, scope, cursor, bound) {
      @control.scan_installed_sqlite_lookup_reply(
        host, original, scope, cursor, bound,
      )
    },
    fn(host, original, scope, key) {
      @control.header_installed_sqlite_lookup_reply(host, original, scope, key)
    },
    fn(host, original, scope, key) {
      @control.capacity_installed_sqlite_lookup_reply(
        host, original, scope, key,
      )
    },
    fn(host, original, scope) {
      @control.capacity_usage_installed_sqlite_lookup_reply(
        host, original, scope,
      )
    },
    fn(host, original) {
      @control.database_usage_installed_sqlite_lookup_reply(host, original)
    },
    fn(host, original) {
      @control.finish_installed_sqlite_lookup_reply(host, original)
    },
    fn(host, original) {
      @control.close_installed_sqlite_lookup_reply(host, original)
    },
    fn(reply) { reply.original_lookup() },
    fn(reply) { reply.revalidate_copy() },
  )
  register_original_sqlite_roots(
    fn(host, domain, path, heap, diagnostic) {
      @control.prepare_installed_arena_sqlite_reply(
        host, domain, path, heap, diagnostic,
      )
    },
    fn(host, original) {
      @control.current_installed_arena_sqlite_reply(host, original)
    },
    fn(host, original) {
      @control.close_installed_arena_sqlite_reply(host, original)
    },
    fn(reply) { reply.original_host() },
    fn(reply) { reply.original_domain() },
    fn(reply) { reply.original_library() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.issue_family() },
  )
  register_original_live_channel_roots(
    fn(host, domain, pid, read_fd, write_fd, nonce) {
      @control.prepare_installed_arena_live_channel_reply(
        host, domain, pid, read_fd, write_fd, nonce,
      )
    },
    fn(host, domain, channel, nonce, offset, bytes) {
      @control.bind_installed_arena_live_channel_reply(
        host, domain, channel, nonce, offset, bytes,
      )
    },
    fn(host, domain, channel, operation) {
      @control.operate_installed_arena_live_channel_reply(
        host, domain, channel, operation,
      )
    },
    fn(
      host,
      domain,
      channel,
      planning,
      attempts,
      holdings,
      transferred,
      uncertain,
      reserved_transfer,
      held,
      reserved_retention,
      reserved_execution,
      peak_retention,
    ) {
      @control.report_installed_arena_live_channel_reply(
        host, domain, channel, planning, attempts, holdings, transferred, uncertain,
        reserved_transfer, held, reserved_retention, reserved_execution, peak_retention,
      )
    },
    fn(reply) { reply.original_host() },
    fn(reply) { reply.original_domain() },
    fn(reply) { reply.original_channel() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.issue_family() },
    fn(reply) { reply.state_tag() },
    fn(reply, ordinal) { reply.limit(ordinal) },
    fn(reply) { reply.issue_description() },
  )
  register_original_live_preparation_roots(
    fn(host, domain, read_fd, write_fd, nonce) {
      @control.prepare_installed_arena_live_channel_before_spawn_reply(
        host, domain, read_fd, write_fd, nonce,
      )
    },
    fn(host, domain, channel, child_pid) {
      @control.bind_installed_arena_live_channel_child_reply(
        host, domain, channel, child_pid,
      )
    },
    fn(host, domain, channel) {
      @control.prepare_installed_arena_channel_ledger_reply(
        host, domain, channel,
      )
    },
    fn(host, domain, channel, frame, operation, retained, execution) {
      @control.operate_installed_arena_channel_ledger_reply(
        host, domain, channel, frame, operation, retained, execution,
      )
    },
    fn(reply) { reply.original_host() },
    fn(reply) { reply.original_domain() },
    fn(reply) { reply.original_channel() },
    fn(reply) { reply.original_frame() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.issue_family() },
    fn(reply, ordinal) { reply.limit(ordinal) },
    fn(reply) { reply.issue_description() },
  )
  register_original_process_roots(
    fn(host, domain, path, descriptor, nonce, retained, execution) {
      @control.prepare_installed_arena_process_reply(
        host, domain, path, descriptor, nonce, retained, execution,
      )
    },
    fn(host, domain, process, operation) {
      @control.operate_installed_arena_process_reply(
        host, domain, process, operation,
      )
    },
    fn(host, domain, process, executable, arguments, environment) {
      @control.prepare_installed_arena_process_child_bytes_reply(
        host, domain, process, executable, arguments, environment,
      )
    },
    fn(reply) { reply.original_host() },
    fn(reply) { reply.original_domain() },
    fn(reply) { reply.original_process() },
    fn(reply) { reply.original_channel() },
    fn(reply) { reply.original_frame() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.issue_family() },
    fn(reply, ordinal) { reply.descriptor(ordinal) },
    fn(reply) { reply.backing_descriptor() },
    fn(reply) { reply.transport_observation() },
    fn(reply) { reply.issue_description() },
  )
  register_original_worker_selection_roots(
    fn(host) { @control.installed_arena_worker_selection_reply(host) },
    fn(host, selection) {
      @control.current_installed_arena_worker_selection_reply(host, selection)
    },
    fn(reply) { reply.original_host() },
    fn(reply) { reply.original_selection() },
    fn(selection) { selection.original_host() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.issue_family() },
  )

  register_original_control_roots(
    fn(
      source,
      recipe,
      generation,
      bytes,
      planning_work,
      attempts,
      holdings,
      transfer_bytes,
      retained_bytes,
      execution_bytes,
      control_envelope_bytes,
    ) {
      @control.prepare_installed_arena_reply(
        source, recipe, generation, bytes, planning_work, attempts, holdings, transfer_bytes,
        retained_bytes, execution_bytes, control_envelope_bytes,
      )
    },
    fn(original) { @control.acquire_installed_arena_reply(original) },
    fn(original) { @control.current_installed_arena_reply(original) },
    fn(original) { @control.close_installed_arena_reply(original) },
    fn(reply) { original_host(reply) },
    fn(reply) { operation_tag(reply) },
    fn(reply) { issue_family(reply) },
    fn(reply) { description(reply) },
  )
  register_original_backing_roots(
    fn(original) { @control.borrow_installed_arena_backing_reply(original) },
    fn(original, loan) {
      @control.current_installed_arena_backing_reply(original, loan)
    },
    fn(original, loan) {
      @control.return_installed_arena_backing_reply(original, loan)
    },
    fn(reply) { reply.original_host() },
    fn(reply) { reply.original_loan() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.issue_family() },
    fn(reply) { reply.issue_description() },
  )
  register_original_backing_scope_roots(
    fn(original, loan) {
      @control.enter_installed_arena_backing_scope_reply(original, loan)
    },
    fn(original, loan) {
      @control.leave_installed_arena_backing_scope_reply(original, loan)
    },
  )
  register_original_fd_root(fn(original, fd) {
    @control.acquire_installed_arena_fd_reply(original, fd)
  })
  register_original_domain_roots(
    fn(
      host,
      scope,
      fd,
      bytes,
      work,
      attempts,
      holdings,
      transfer,
      retained,
      execution,
    ) {
      @control.prepare_installed_arena_domain_reply(
        host, scope, fd, bytes, work, attempts, holdings, transfer, retained, execution,
      )
    },
    fn(host, domain) {
      @control.current_installed_arena_domain_reply(host, domain)
    },
    fn(host, domain) {
      @control.transfer_installed_arena_domain_reply(host, domain)
    },
    fn(host, domain) {
      @control.enter_installed_arena_domain_reply(host, domain)
    },
    fn(host, domain) {
      @control.leave_installed_arena_domain_reply(host, domain)
    },
    fn(host, domain) {
      @control.close_installed_arena_domain_reply(host, domain)
    },
    fn(reply) { reply.original_host() },
    fn(reply) { reply.original_domain() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.issue_family() },
    fn(reply) { reply.issue_description() },
  )
  register_original_initial_domain_root(fn(
    host,
    scope,
    fd,
    work,
    attempts,
    holdings,
    transfer,
  ) {
    @control.prepare_installed_arena_initial_domain_reply(
      host, scope, fd, work, attempts, holdings, transfer,
    )
  })
  register_original_domain_material_roots(
    fn(host, domain) {
      @control.project_installed_arena_domain_reply(host, domain)
    },
    fn(reply, ordinal) { reply.material_scalar(ordinal) },
    fn(reply) { reply.material_source() },
    fn(reply) { reply.material_recipe() },
  )
  register_original_domain_read_roots(
    fn(host, domain) {
      @control.prepare_installed_arena_domain_read_reply(host, domain)
    },
    fn(host, domain) {
      @control.current_installed_arena_domain_read_reply(host, domain)
    },
    fn(host, domain) {
      @control.enter_installed_arena_domain_read_reply(host, domain)
    },
    fn(host, domain) {
      @control.leave_installed_arena_domain_read_reply(host, domain)
    },
    fn(host, domain) {
      @control.cleanup_installed_arena_domain_read_reply(host, domain)
    },
    fn(host, domain) {
      @control.close_installed_arena_domain_read_reply(host, domain)
    },
  )
  register_original_parent_read_roots(
    fn(
      host,
      domain,
      bootstrap_retained,
      bootstrap_execution,
      workspace_execution,
      read_retained,
      read_execution,
    ) {
      @control.prepare_installed_arena_original_read_reply(
        host, domain, bootstrap_retained, bootstrap_execution, workspace_execution,
        read_retained, read_execution,
      )
    },
    fn(host, original) {
      @control.current_installed_arena_original_read_reply(host, original)
    },
    fn(host, original) {
      @control.enter_installed_arena_original_read_reply(host, original)
    },
    fn(host, original) {
      @control.leave_installed_arena_original_read_reply(host, original)
    },
    fn(host, original) {
      @control.cleanup_installed_arena_original_read_reply(host, original)
    },
    fn(host, original) {
      @control.close_installed_arena_original_read_reply(host, original)
    },
    fn(reply) { reply.original_host() },
    fn(reply) { reply.original_domain() },
    fn(reply) { reply.original_read() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.issue_family() },
  )
  register_original_packaged_runtime_roots(
    fn(host, original, root, source, platform, manifest, ceiling) {
      @runtime.capture_native_local_packaged_runtime_reply(
        Some((host, original)),
        root,
        source,
        platform,
        manifest,
        ceiling,
      )
    },
    fn(runtime) {
      @runtime.current_native_local_packaged_runtime_reply(runtime)
    },
    fn(runtime) { @runtime.close_native_local_packaged_runtime_reply(runtime) },
    fn(reply) { reply.original_host() },
    fn(reply) { reply.original_read() },
    fn(reply) { reply.original_runtime() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.issue_family() },
    fn(host, read, resources, root, source, platform, manifest, ceiling) {
      @runtime.capture_native_local_packaged_runtime_in_host_resources_reply(
        Some((host, read, resources)),
        root,
        source,
        platform,
        manifest,
        ceiling,
      )
    },
  )
  register_original_packaged_product_roots(
    fn(runtime, root, launcher_hash, platform_hash, ceiling) {
      @runtime.observe_native_local_packaged_product_reply(
        runtime, root, launcher_hash, platform_hash, ceiling,
      )
    },
    fn(runtime) { @runtime.read_native_local_packaged_product_reply(runtime) },
    fn(reply) { reply.original_host() },
    fn(reply) { reply.original_read() },
    fn(reply) { reply.original_runtime() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.issue_family() },
    fn(reply) { reply.metadata_units() },
    fn(reply, index) { reply.metadata_unit_at(index) },
  )
}
