export type StaticExplanationNarrative = Readonly<{
  context: readonly string[];
  steps: readonly string[];
}>;
/** Present an already disclosed canonical static view. This grants no read access. */
export function renderStaticExplanationNarrative(wire: string,
  locale: 'en' | 'ja'): StaticExplanationNarrative;
