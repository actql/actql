import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import ts from 'typescript';

const guide = readFileSync(new URL('../docs/guides/node.md', import.meta.url), 'utf8');
const blocks = [...guide.matchAll(/```ts\n([\s\S]*?)\n```/gu)].map((match, index) =>
  ts.createSourceFile(`node-guide-${index}.mts`, match[1], ts.ScriptTarget.Latest, true));

function calls(method) {
  const found = [];
  const visit = node => {
    if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) &&
        node.expression.name.text === method) found.push(node);
    ts.forEachChild(node, visit);
  };
  blocks.forEach(visit);
  return found;
}

function properties(node, label) {
  assert.ok(node && ts.isObjectLiteralExpression(node), `${label} must be explicit`);
  return new Map(node.properties.map(property => {
    assert.ok(ts.isPropertyAssignment(property), `${label} must not infer properties`);
    assert.ok(ts.isIdentifier(property.name) || ts.isStringLiteral(property.name));
    return [property.name.text, property.initializer];
  }));
}

function declaredParameters(parameters, options) {
  const declarations = properties(options.get('parameterDeclarations'), 'parameterDeclarations');
  for (const [name, value] of parameters) {
    const declaration = properties(declarations.get(name), `declaration for ${name}`);
    const type = declaration.get('type');
    assert.ok(type && ts.isStringLiteral(type), `${name} needs an explicit type`);
    assert.ok(ts.isStringLiteral(value), 'This guide control uses a literal string parameter');
    assert.equal(type.text, 'string');
  }
}

test('Node guide short-query parameters include explicit declarations', () => {
  const selected = calls('sql').filter(call => call.arguments.length >= 2);
  assert.equal(selected.length, 1, 'Keep the current short-query example in this control');
  const [query] = selected;
  assert.ok(ts.isStringLiteral(query.arguments[0]));
  assert.equal(query.arguments[0].text, 'SELECT @owner AS owner',
    'The first query must not require an unconfigured external source');
  declaredParameters(properties(query.arguments[1], 'query parameters'),
    properties(query.arguments[2], 'query options'));
});

test('Node guide startSource parameters include explicit declarations', () => {
  const selected = calls('startSource').map(call => properties(call.arguments[1], 'startSource options'))
    .filter(options => options.has('parameters'));
  assert.equal(selected.length, 1, 'Keep the current Program example in this control');
  const [options] = selected;
  declaredParameters(properties(options.get('parameters'), 'Program parameters'), options);
});

test('Node guides use the installed Checkpoint API for embedded approvals', () => {
  const effects = readFileSync(new URL('../docs/guides/effects-and-approvals.md', import.meta.url), 'utf8');
  for (const document of [guide, effects]) {
    const examples = [...document.matchAll(/```ts\n([\s\S]*?)\n```/gu)].map(([, body]) => body);
    assert.ok(examples.some(body => body.includes("stopBefore: 'commit'")));
    assert.ok(examples.every(body => !/\bdecide\s*:/u.test(body)), 'No unimplemented connection option in an example');
  }
  assert.equal(calls('reviewCheckpoint').length, 1);
  assert.equal(calls('approve').length, 1);
  assert.equal(calls('reject').length, 1);
});

test('Node guide handles the completed check before reading its verified verdict', () => {
  const section = guide.split('## Checking without running')[1]?.split('\n## ')[0];
  assert.match(section, /outcome\.outcome === 'completed' && outcome\.report\.verdict === 'verified'/u);
  assert.doesNotMatch(section, /report\.verdict\s*!?==?\s*'valid'/u);
});
