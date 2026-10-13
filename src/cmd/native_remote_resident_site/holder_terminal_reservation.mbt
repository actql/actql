///|
/// Private caller lifetime only. Both callbacks come from the existing caller:
/// consume returns no retained diagnostic, and settle invokes the original
/// reservation Owner. A non-returning terminal keeps the reservation live;
/// neither termination nor diagnostic output is a cleanup/settlement ACK.
fn retain_holder_terminal_reservation(
  original : @site.SiteOperation,
  consume : () -> Unit,
  settle : (@site.SiteOperation) -> Unit,
) -> Unit {
  consume()
  settle(original)
}
