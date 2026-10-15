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
fn original_host(
  reply : @control.InstalledArenaReply,
) -> @control.InstalledArenaHost? {
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
}
