///|
/// Regular non-test emission roots for the private installed control component.
/// The final shim registration declaration must come from matching generated C.
/// There is deliberately no guessed C stub, profile, acquire or worker launch.
extern "C" fn register_original_control_roots(
  prepare : FuncRef[(String, Bytes, Int64, Int64, Int, Int, Int, Int64, Int64, Int64, Int64) -> @control.InstalledArenaReply],
  acquire : FuncRef[(@control.InstalledArenaHost) -> @control.InstalledArenaReply],
  current : FuncRef[(@control.InstalledArenaHost) -> @control.InstalledArenaReply],
  close : FuncRef[(@control.InstalledArenaHost) -> @control.InstalledArenaReply],
  original : FuncRef[(@control.InstalledArenaReply) -> @control.InstalledArenaHost?],
  operation : FuncRef[(@control.InstalledArenaReply) -> Int],
  issue_family : FuncRef[(@control.InstalledArenaReply) -> Int],
  description : FuncRef[(@control.InstalledArenaReply) -> String],
) -> Unit = "actql_native_control_register_original_roots"

///|
fn original_host(reply : @control.InstalledArenaReply) -> @control.InstalledArenaHost? {
  reply.original_host()
}

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
/// This initializes code references only. Registration is not supplier adoption,
/// original arena acquisition, Root creation, Run admission or VM permission.
fn main {
  register_original_control_roots(
    fn(source, recipe, generation, bytes, planning_work, attempts, holdings,
       transfer_bytes, retained_bytes, execution_bytes, control_envelope_bytes) {
      @control.prepare_installed_arena_reply(
        source, recipe, generation, bytes, planning_work, attempts, holdings,
        transfer_bytes, retained_bytes, execution_bytes, control_envelope_bytes,
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
}
