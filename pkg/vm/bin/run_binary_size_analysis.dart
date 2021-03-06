// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This tool creates interactive navigatable binary size reports from
// JSON file generated by the AOT compiler's --print-instructions-sizes-to
// flag.
//
// It used the same visualization framework as Chromium's binary_size tool
// located in runtime/third_party/binary_size.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;

import 'package:path/path.dart' as p;

import 'package:vm/snapshot/instruction_sizes.dart' as instruction_sizes;

void main(List<String> args) async {
  if (args.length != 2) {
    print(r"""
Usage: run_binary_size_analysis.dart <symbol-sizes.json> <output-directory>

This tool is used to process snapshot size reports produced by
--print-instructions-sizes-to=symbol-sizes.json.

It will create an interactive web-page in the output-directory which can be
viewed in a browser:

$ google-chrome <output-directory>/index.html
""");
    exit(-1);
  }

  final input = new File(args[0]);
  final outputDir = new Directory(args[1]);

  if (!input.existsSync()) {
    print("Input file ${input} does not exist");
    return;
  }

  // Load symbols data produced by the AOT compiler and convert it to
  // a tree.
  final symbols = await instruction_sizes.load(input);

  final root = {'n': '', 'children': {}, 'k': kindPath, 'maxDepth': 0};
  for (var symbol in symbols) {
    addSymbol(root, treePath(symbol), symbol.name.scrubbed, symbol.size);
  }
  final tree = flatten(root);

  // Create output directory and copy all auxiliary files from binary_size tool.
  await outputDir.create(recursive: true);

  final scriptLocation = p.dirname(Platform.script.toFilePath());
  final sdkRoot = p.join(scriptLocation, '..', '..', '..');
  final d3SrcDir = p.join(sdkRoot, 'runtime', 'third_party', 'd3', 'src');
  final templateDir = p.join(
      sdkRoot, 'runtime', 'third_party', 'binary_size', 'src', 'template');

  final d3OutDir = p.join(outputDir.path, 'd3');
  await new Directory(d3OutDir).create(recursive: true);

  for (var file in ['LICENSE', 'd3.js']) {
    await copyFile(d3SrcDir, file, d3OutDir);
  }
  for (var file in ['index.html', 'D3SymbolTreeMap.js']) {
    await copyFile(templateDir, file, outputDir.path);
  }

  // Serialize symbol size tree as JSON.
  final dataJsPath = p.join(outputDir.path, 'data.js');
  final sink = new File(dataJsPath).openWrite();
  sink.write('var tree_data=');
  await sink.addStream(new Stream<Object>.fromIterable([tree])
      .transform(json.encoder.fuse(utf8.encoder)));
  await sink.close();

  // Done.
  print('Generated ${p.toUri(p.absolute(outputDir.path, 'index.html'))}');
}

/// Returns a /-separated path to the given symbol within the treemap.
String treePath(instruction_sizes.SymbolInfo symbol) {
  if (symbol.name.isStub) {
    if (symbol.name.isAllocationStub) {
      return '@stubs/allocation-stubs/${symbol.libraryUri}/${symbol.className}';
    } else {
      return '@stubs';
    }
  } else {
    return '${symbol.libraryUri}/${symbol.className}';
  }
}

const kindSymbol = 's';
const kindPath = 'p';
const kindBucket = 'b';
const symbolTypeGlobalText = 'T';

/// Create a child with the given name within the given node or return
/// an existing child.
Map<String, dynamic> addChild(
    Map<String, dynamic> node, String kind, String name) {
  if (kind == kindSymbol && node['children'].containsKey(name)) {
    print('Duplicate symbol ${name}');
  }
  return node['children'].putIfAbsent(name, () {
    final n = <String, dynamic>{'n': name, 'k': kind};
    if (kind != kindSymbol) {
      n['children'] = {};
    }
    return n;
  });
}

/// Add the given symbol to the tree.
void addSymbol(Map<String, dynamic> root, String path, String name, int size) {
  var node = root;
  var depth = 0;
  for (var part in path.split('/')) {
    node = addChild(node, kindPath, part);
    depth++;
  }
  node['lastPathElement'] = true;
  node = addChild(node, kindBucket, symbolTypeGlobalText);
  node['t'] = symbolTypeGlobalText;
  node = addChild(node, kindSymbol, name);
  node['t'] = symbolTypeGlobalText;
  node['value'] = size;
  depth += 2;
  root['maxDepth'] = max<int>(root['maxDepth'], depth);
}

/// Convert all children entries from maps to lists.
Map<String, dynamic> flatten(Map<String, dynamic> node) {
  dynamic children = node['children'];
  if (children != null) {
    children = children.values.map((dynamic v) => flatten(v)).toList();
    node['children'] = children;
    if (children.length == 1 && children.first['k'] == 'p') {
      final singleChild = children.first;
      singleChild['n'] = '${node['n']}/${singleChild['n']}';
      return singleChild;
    }
  }
  return node;
}

/// Copy file with the given name from [fromDir] to [toDir].
Future<void> copyFile(String fromDir, String name, String toDir) async {
  await new File(p.join(fromDir, name)).copy(p.join(toDir, name));
}
