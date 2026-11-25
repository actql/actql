import type {WireExplanationNarrative} from '@actql/client-wire';
export type StaticExplanationNarrative = WireExplanationNarrative;
/** Present an already disclosed canonical static view. This grants no read access. */
export function renderStaticExplanationNarrative(wire: string,
  locale: 'en' | 'ja'): StaticExplanationNarrative;
