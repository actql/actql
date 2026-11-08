# Managed response construction capacity

The existing managed HubSpot sequence receives Account details, then Properties,
then object pages, and finally rechecks Properties. Its original Reader retains
and charges every received body before projection. Capacity is quantity DATA;
it grants no access and does not replace current, schema or cleanup checks.

The first two positions have closed metadata constructors. Account reuses the
existing account projection/export inventory. Properties reuses the same native
PropertyMetadata/option projection extent as initialization, its retained Catalog
inventory, and the original-catalog recheck Map. Neither position constructs a
row ValueNode forest, a row-wire writer or a Host row JSON.parse tree. Those row
policy maxima therefore do not contribute to the first two response capacities.

The byte-length prefix does not identify the final Properties position when the
page count varies. Positions after the first two retain the existing conservative
metadata/page envelope. No input role, interface, permission or payload is inferred
from a byte length. Every earlier and failed constructor prefix remains charged
until the same Reader's actual retirement; returning from a projection does not
acknowledge its cleanup or discard the received body.

The shared Ledger equations, tariffs and configured retention/execution limits
are unchanged. Metadata still uses its complete byte/node/depth/property bounds.
Refining those bounds from actual structural geometry is a separate question;
removing a wrong-role row term alone does not establish that a full workflow fits.
