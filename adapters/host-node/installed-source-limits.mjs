// One installed read authority per sourceRef, shared by inventory admission
// and the Checkpoint owner. A member may publish multiple authorities.
export const MAX_INSTALLED_SOURCE_AUTHORITIES = 128;
