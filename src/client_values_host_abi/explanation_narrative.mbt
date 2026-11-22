///|
#export_name("clientValuesHostRenderStaticExplanation")
pub fn client_values_host_render_static_explanation(
  wire : String,
  locale : String,
) -> Result[String, Int] {
  @host.render_client_static_explanation_narrative_wire(wire, locale)
}
