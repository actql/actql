///|
/// Code registration only. Matching regular C determines prototypes/ownership
/// before the private shim is compiled or any physical provider is initialized.
extern "C" fn register_local_host_resource_roots_ffi(
  bind : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaOriginalRead,
      @control.InstalledArenaSqliteLibrary,
    ) -> @control.InstalledArenaLocalHostResourcesReply,
  ],
  operate : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaLocalHostResources,
      Int,
    ) -> @control.InstalledArenaLocalHostResourcesReply,
  ],
  host : FuncRef[
    (@control.InstalledArenaLocalHostResourcesReply) -> @control.InstalledArenaHost,
  ],
  sqlite_host : FuncRef[
    (@control.InstalledArenaLocalHostResourcesReply) -> @control.InstalledArenaHost,
  ],
  read : FuncRef[
    (@control.InstalledArenaLocalHostResourcesReply) -> @control.InstalledArenaOriginalRead,
  ],
  sqlite : FuncRef[
    (@control.InstalledArenaLocalHostResourcesReply) -> @control.InstalledArenaSqliteLibrary,
  ],
  original : FuncRef[
    (@control.InstalledArenaLocalHostResourcesReply) -> @control.InstalledArenaLocalHostResources?,
  ],
  operation : FuncRef[(@control.InstalledArenaLocalHostResourcesReply) -> Int],
  origin : FuncRef[(@control.InstalledArenaLocalHostResourcesReply) -> Int],
  family : FuncRef[(@control.InstalledArenaLocalHostResourcesReply) -> Int],
  closed : FuncRef[(@control.InstalledArenaLocalHostResourcesReply) -> Bool],
  capacity : FuncRef[(@control.InstalledArenaHost, Int) -> Int64],
) -> Unit = "actql_native_control_register_local_host_resource_roots"

///|
fn register_original_local_host_resources_roots() -> Unit {
  register_local_host_resource_roots_ffi(
    fn(host, read, sqlite) {
      @control.bind_installed_local_host_resources_reply(host, read, sqlite)
    },
    fn(host, original, operation) {
      @control.operate_installed_local_host_resources_reply(
        host, original, operation,
      )
    },
    fn(reply) { reply.original_host() },
    fn(reply) { reply.sqlite_host() },
    fn(reply) { reply.original_read() },
    fn(reply) { reply.original_sqlite() },
    fn(reply) { reply.original_resources() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.issue_origin() },
    fn(reply) { reply.issue_family() },
    fn(reply) { reply.close_confirmed() },
    fn(host, index) { @control.installed_arena_capacity_scalar(host, index) },
  )
}
