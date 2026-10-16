// Independent review-content fixture; no approval, permission or Run admission.
export const reviewFixtureText="{\"action\":\"declared only\",\"note\":\"<script>not HTML</script>\"}";
export const reviewFixtureCid="sha256:521d5d43a9f1ae6d5636876dae307d871e08ed8354296d9185dd2f2eed5021f8";
export const checkpointFixture=()=>({checkpointId:'original-effect-checkpoint',checkpointCid:'sha256:'+'c'.repeat(64),
 kind:'effect_set',phase:'commit',subject:{kind:'run_unit',runId:'original-run',runDefinitionCid:'sha256:'+'b'.repeat(64)},
 requiredArtifact:{type:'effect_set',cid:'sha256:'+'d'.repeat(64)},reviewProjectionCid:reviewFixtureCid,
 requirements:['effect_approved'],createdAt:'2026-10-15T00:00:00.000Z',expiresAt:'2026-10-16T00:00:00.000Z',
 humanSummary:'Original declared Effect set'});
export const reviewFixture=()=>({checkpointCid:checkpointFixture().checkpointCid,artifactCid:reviewFixtureCid,
 bytes:new TextEncoder().encode(reviewFixtureText)});
