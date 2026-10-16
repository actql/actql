"""Read normal wheel payloads with stdlib parsers; never import product code.

RECORD supplies distributed members. AST supplies public bindings and private
helpers, including helpers outside the conventional SDK package directory.
This is coverage data, not a second Python execution/permission authority.
"""
import argparse
import ast
import base64
import csv
import hashlib
import io
import json
from pathlib import PurePosixPath
import zipfile


def python_interface(source: str) -> dict:
    tree = ast.parse(source)
    operations = []
    imports = []
    exports = set()

    def visit(node, scope=()):
        child_scope = scope
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            child_scope = (*scope, node.name)
            if not scope and not node.name.startswith('_'):
                exports.add(node.name)
            parameters = []
            if not isinstance(node, ast.ClassDef):
                parameters = [argument.arg for argument in
                              (*node.args.posonlyargs, *node.args.args, *node.args.kwonlyargs)]
                if node.args.vararg:
                    parameters.append('*' + node.args.vararg.arg)
                if node.args.kwarg:
                    parameters.append('**' + node.args.kwarg.arg)
            operations.append({'name': '/'.join(child_scope), 'parameters': parameters,
                               'async': isinstance(node, ast.AsyncFunctionDef)})
        if isinstance(node, ast.Import):
            imports.extend(alias.name for alias in node.names)
            if not scope:
                exports.update(alias.asname or alias.name.split('.')[0] for alias in node.names
                               if not (alias.asname or alias.name).startswith('_'))
        if isinstance(node, ast.ImportFrom):
            imports.append('.' * node.level + (node.module or ''))
            if not scope:
                exports.update(alias.asname or alias.name for alias in node.names
                               if not (alias.asname or alias.name).startswith('_'))
        if not scope and isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name) and not target.id.startswith('_'):
                    exports.add(target.id)
            if any(isinstance(target, ast.Name) and target.id == '__all__' for target in targets):
                try:
                    declared = ast.literal_eval(node.value)
                except (ValueError, TypeError) as failure:
                    raise ValueError('Nonliteral wheel export inventory requires owner projection') from failure
                if not isinstance(declared, (list, tuple)) or not all(isinstance(x, str) for x in declared):
                    raise ValueError('Invalid wheel export inventory')
                exports.update(declared)
        for child in ast.iter_child_nodes(node):
            visit(child, child_scope)

    visit(tree)
    return {'exports': sorted(exports), 'operations': sorted(operations, key=lambda x: x['name']),
            'imports': sorted(set(imports))}


def wheel_interfaces(path) -> dict:
    with zipfile.ZipFile(path) as wheel:
        names = wheel.namelist()
        if len(names) != len(set(names)) or any(
                PurePosixPath(name).is_absolute() or '..' in PurePosixPath(name).parts
                or '\\' in name for name in names):
            raise ValueError('Unsafe or duplicate wheel member')
        records = [name for name in names if name.endswith('.dist-info/RECORD')]
        if len(records) != 1:
            raise ValueError('One normal wheel RECORD is required')
        rows = list(csv.reader(io.StringIO(wheel.read(records[0]).decode())))
        by_name = {row[0]: row for row in rows}
        files = {name for name in names if not name.endswith('/')}
        if len(by_name) != len(rows) or set(by_name) != files:
            raise ValueError('Incomplete wheel RECORD coverage')
        modules = []
        for name in sorted(files):
            data = wheel.read(name)
            row = by_name[name]
            if len(row) != 3:
                raise ValueError('Invalid wheel RECORD member')
            if name != records[0]:
                expected = 'sha256=' + base64.urlsafe_b64encode(hashlib.sha256(data).digest()).decode().rstrip('=')
                if row[1] != expected or row[2] != str(len(data)):
                    raise ValueError('Wheel original digest mismatch: ' + name)
            if name.endswith(('.py', '.pyi')):
                modules.append({'module': name, 'sha256': hashlib.sha256(data).hexdigest(),
                                **python_interface(data.decode('utf-8'))})
        return {'entrance': records[0], 'modules': modules}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('wheel')
    print(json.dumps(wheel_interfaces(parser.parse_args().wheel), sort_keys=True))
