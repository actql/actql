///|
#export_name("clientRenderStaticExplanationNarrative")
pub fn client_render_static_explanation_narrative(
  wire : String,
  locale : String,
) -> Result[String, Int] {
  @publication_host.render_client_static_explanation_narrative_wire(
    wire, locale,
  )
}
