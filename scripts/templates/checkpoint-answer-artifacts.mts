/* @wire-bindings */

const valid = structuralWireValidator({schemas, extended: true, compositeConstants: true});

export function validAnswerResolution(value: unknown): value is AnswerResolution {
  return valid(value, schemas.resolution);
}

export function validAnswerEvidence(value: unknown): value is AnswerEvidence {
  return valid(value, schemas.evidence);
}
