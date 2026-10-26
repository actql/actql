# Independent complete Content observations

The two assertion helpers compare a public Content envelope against original
independently authored `Uint8Array` bytes, explicit effective media type and
issuer kind. Capture also requires the separately authored original reported
media spelling. Expected digest and length come only from those authored bytes,
never from a product encoder, current Result or reconstructed output.

This finite oracle covers complete objects only. Truncated or ranged content is
a separate qualification, not silently treated as the full expected payload.
Issuer kind and reported capture headers remain distinct. Source metadata is
not prohibited by issuer kind; its actual original binding is a separate row
and Owner obligation. The oracle does not prohibit legitimate product range
operations or decide their meaning.

Saved comparison takes the actual persisted first envelope and the recovered
envelope. Both must match the independent payload, and every original field
must remain equal, including issuer, policy, availability and lifetime. Same
bytes alone cannot stand in for the original issued reference. Callers must
retain that first envelope before closing; a current response is not its own
Saved baseline. Source resource/version correlation remains a separate row
and original-publication obligation.

These are assertions for existing provider/Result oracles, not a new client,
Content fetch API, schema validator, issuer, storage holder or authority. They
do not recompute reference/evidence preimages or prove nominal admission,
durable bytes, current permission, real SDK/Host/Source/Effect/Saved/close/FD,
restart, normal packaging or performance. The synthetic envelopes are unissued
fixture DATA. Actual same-candidate ordinary connection remains unexecuted.
