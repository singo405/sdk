// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "package:expect/expect.dart";
import '../../../sdk/lib/_internal/compiler/implementation/scanner/scannerlib.dart';
import '../../../sdk/lib/_internal/compiler/implementation/source_file.dart';
import '../../../sdk/lib/_internal/compiler/implementation/types/types.dart';

import "parser_helper.dart";
import "compiler_helper.dart";

/**
 * Finds the node corresponding to the last occurence of the substring
 * [: identifier; :] in the program represented by the visited AST.
 */
class VariableFinderVisitor extends Visitor {
  final String identifier;
  Node result;

  VariableFinderVisitor(this.identifier);

  visitSend(Send node) {
    if (node.isPropertyAccess
        && node.selector.asIdentifier().source.slowToString() == identifier) {
      result = node;
    } else {
      node.visitChildren(this);
    }
  }

  visitNode(Node node) {
    node.visitChildren(this);
  }
}

class AnalysisResult {
  MockCompiler compiler;
  ConcreteTypesInferrer inferrer;
  Node ast;

  BaseType int;
  BaseType double;
  BaseType num;
  BaseType bool;
  BaseType string;
  BaseType list;
  BaseType growableList;
  BaseType map;
  BaseType nullType;
  BaseType functionType;

  AnalysisResult(MockCompiler compiler) : this.compiler = compiler {
    inferrer = compiler.typesTask.concreteTypesInferrer;
    int = inferrer.baseTypes.intBaseType;
    double = inferrer.baseTypes.doubleBaseType;
    num = inferrer.baseTypes.numBaseType;
    bool = inferrer.baseTypes.boolBaseType;
    string = inferrer.baseTypes.stringBaseType;
    list = inferrer.baseTypes.listBaseType;
    growableList = inferrer.baseTypes.growableListBaseType;
    map = inferrer.baseTypes.mapBaseType;
    nullType = const NullBaseType();
    functionType = inferrer.baseTypes.functionBaseType;
    Element mainElement = compiler.mainApp.find(buildSourceString('main'));
    ast = mainElement.parseNode(compiler);
  }

  BaseType base(String className) {
    final source = buildSourceString(className);
    return new ClassBaseType(compiler.mainApp.find(source));
  }

  /**
   * Finds the [Node] corresponding to the last occurence of the substring
   * [: identifier; :] in the program represented by the visited AST. For
   * instance, returns the AST node representing [: foo; :] in
   * [: main() { foo = 1; foo; } :].
   */
  Node findNode(String identifier) {
    VariableFinderVisitor finder = new VariableFinderVisitor(identifier);
    ast.accept(finder);
    return finder.result;
  }

  /**
   * Finds the [Element] corresponding to [: className#fieldName :].
   */
  Element findField(String className, String fieldName) {
    ClassElement element = compiler.mainApp.find(buildSourceString(className));
    return element.lookupLocalMember(buildSourceString(fieldName));
  }

  ConcreteType concreteFrom(List<BaseType> baseTypes) {
    ConcreteType result = inferrer.emptyConcreteType;
    for (final baseType in baseTypes) {
      result = result.union(inferrer.singletonConcreteType(baseType));
    }
    // We make sure the concrete types expected by the tests don't default to
    // dynamic because of widening.
    assert(!result.isUnknown());
    return result;
  }

  /**
   * Checks that the inferred type of the node corresponding to the last
   * occurence of [: variable; :] in the program is the concrete type
   * made of [baseTypes].
   */
  void checkNodeHasType(String variable, List<BaseType> baseTypes) {
    return Expect.equals(
        concreteFrom(baseTypes),
        inferrer.inferredTypes[findNode(variable)]);
  }

  /**
   * Checks that the inferred type of the node corresponding to the last
   * occurence of [: variable; :] in the program is the unknown concrete type.
   */
  void checkNodeHasUnknownType(String variable) {
    return Expect.isTrue(inferrer.inferredTypes[findNode(variable)].isUnknown());
  }

  /**
   * Checks that [: className#fieldName :]'s inferred type is the concrete type
   * made of [baseTypes].
   */
  void checkFieldHasType(String className, String fieldName,
                         List<BaseType> baseTypes) {
    return Expect.equals(
        concreteFrom(baseTypes),
        inferrer.inferredFieldTypes[findField(className, fieldName)]);
  }

  /**
   * Checks that [: className#fieldName :]'s inferred type is the unknown
   * concrete type.
   */
  void checkFieldHasUknownType(String className, String fieldName) {
    return Expect.isTrue(
        inferrer.inferredFieldTypes[findField(className, fieldName)]
                .isUnknown());
  }
}

const String CORELIB = r'''
  print(var obj) {}
  abstract class num { 
    num operator +(num x);
    num operator *(num x);
    num operator -(num x);
    operator ==(x);
    num floor();
  }
  abstract class int extends num {
    bool get isEven;
  }
  abstract class double extends num {
    bool get isNaN;
  }
  class bool {}
  class String {}
  class Object {
    Object();
  }
  class Function {}
  abstract class List<E> {
    factory List([int length]) {}
  }
  abstract class Map<K, V> {}
  class Closure {}
  class Type {}
  class StackTrace {}
  class Dynamic_ {}
  bool identical(Object a, Object b) {}''';

AnalysisResult analyze(String code, {int maxConcreteTypeSize: 1000}) {
  Uri uri = new Uri(scheme: 'source');
  MockCompiler compiler = new MockCompiler(
      coreSource: CORELIB,
      enableConcreteTypeInference: true,
      maxConcreteTypeSize: maxConcreteTypeSize);
  compiler.sourceFiles[uri.toString()] = new SourceFile(uri.toString(), code);
  compiler.typesTask.concreteTypesInferrer.testMode = true;
  compiler.runCompiler(uri);
  return new AnalysisResult(compiler);
}

testDynamicBackDoor() {
  final String source = r"""
    main () {
      var x = "__dynamic_for_test";
      x;
    }
    """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasUnknownType('x');
}

testVariableDeclaration() {
  final String source = r"""
      main() {
        var v1;
        var v2;
        v2 = 1;
        v1; v2;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('v1', [result.nullType]);
  result.checkNodeHasType('v2', [result.int]);
}

testLiterals() {
  final String source = r"""
      main() {
        var v1 = 42;
        var v2 = 42.0;
        var v3 = 'abc';
        var v4 = true;
        var v5 = null;
        v1; v2; v3; v4; v5;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('v1', [result.int]);
  result.checkNodeHasType('v2', [result.double]);
  result.checkNodeHasType('v3', [result.string]);
  result.checkNodeHasType('v4', [result.bool]);
  result.checkNodeHasType('v5', [result.nullType]);
}

testRedefinition() {
  final String source = r"""
      main() {
        var foo = 42;
        foo = 'abc';
        foo;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.string]);
}

testIfThenElse() {
  final String source = r"""
      main() {
        var foo = 42;
        if (true) {
          foo = 'abc';
        } else {
          foo = false;
        }
        foo;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.string, result.bool]);
}

testTernaryIf() {
  final String source = r"""
      main() {
        var foo = 42;
        foo = true ? 'abc' : false;
        foo;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.string, result.bool]);
}

testWhile() {
  final String source = r"""
      class A { f() => new B(); }
      class B { f() => new C(); }
      class C { f() => new A(); }
      main() {
        var bar = null;
        var foo = new A();
        while(bar = 42) {
          foo = foo.f();
        }
        foo; bar;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType(
      'foo',
      [result.base('A'), result.base('B'), result.base('C')]);
  // Check that the condition is evaluated.
  result.checkNodeHasType('bar', [result.int]);
}

testFor1() {
  final String source = r"""
      class A { f() => new B(); }
      class B { f() => new C(); }
      class C { f() => new A(); }
      main() {
        var foo = new A();
        for(;;) {
          foo = foo.f();
        }
        foo;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType(
      'foo',
      [result.base('A'), result.base('B'), result.base('C')]);
}

testFor2() {
  final String source = r"""
      class A { f() => new B(); test() => true; }
      class B { f() => new A(); test() => true; }
      main() {
        var bar = null;
        var foo = new A();
        for(var i = new A(); bar = 42; i = i.f()) {
           foo = i;
        }
        foo; bar;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.base('A'), result.base('B')]);
  // Check that the condition is evaluated.
  result.checkNodeHasType('bar', [result.int]);
}

testFor3() {
  final String source = r"""
      main() {
        var i = 1;
        for(;;) {
          var x = 2;
          i = x;
        }
        i;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('i', [result.int]);
}

testForIn() {
  final String source = r"""
      class MyIterator {
        var counter = 0;

        moveNext() {
          if (counter == 0) {
            counter = 1;
            return true;
          } else if (counter == 1) {
            counter = 2;
            return true;
          } else {
            return false;
          }
        }

        get current => (counter == 1) ? "foo" : 42;
      }

      class MyIterable {
        get iterator => new MyIterator();
      }

      main() {
        var res;
        for (var i in new MyIterable()) {
          res = i;
        }
        res;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('res', [result.int, result.string, result.nullType]);
}

testToplevelVariable() {
  final String source = r"""
      final top = 'abc';
      class A {
         f() => top;
      }
      main() { 
        var foo = top;
        var bar = new A().f();
        foo; bar;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.string]);
  result.checkNodeHasType('bar', [result.string]);
}

testNonRecusiveFunction() {
  final String source = r"""
      f(x, y) => true ? x : y;
      main() { var foo = f(42, "abc"); foo; }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.int, result.string]);
}

testRecusiveFunction() {
  final String source = r"""
      f(x) {
        if (true) return x;
        else return f(true ? x : "abc");
      }
      main() { var foo = f(42); foo; }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.int, result.string]);
}

testMutuallyRecusiveFunction() {
  final String source = r"""
      f() => true ? 42 : g();
      g() => true ? "abc" : f(); 
      main() { var foo = f(); foo; }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.int, result.string]);
}

testSimpleSend() {
  final String source = r"""
      class A {
        f(x) => x;
      }
      class B {
        f(x) => 'abc';
      }
      class C {
        f(x) => 3.14;
      }
      class D {
        var f;  // we check that this field is ignored in calls to dynamic.f() 
        D(this.f);
      }
      main() {
        new B(); new D(42); // we instantiate B and D but not C
        var foo = new A().f(42);
        var bar = "__dynamic_for_test".f(42);
        foo; bar;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.int]);
  result.checkNodeHasType('bar', [result.int, result.string]);
}

testSendToClosureField() {
  final String source = r"""
      f(x) => x;
      class A {
        var g;
        A(this.g);
      }
      main() {
        var foo = new A(f).g(42);
        foo;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.int]);
}

testSendToThis1() {
  final String source = r"""
      class A {
        A();
        f() => g();
        g() => 42;
      }
      main() {
        var foo = new A().f();
        foo;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.int]);
}

testSendToThis2() {
  final String source = r"""
      class A {
        foo() => this;
      }
      class B extends A {
        bar() => foo();
      }
      main() {
        var x = new B().bar();
        x;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', [result.base('B')]);
}

testSendToThis3() {
  final String source = r"""
      class A {
        bar() => 42;
        foo() => bar();
      }
      class B extends A {
        bar() => "abc";
      }
      main() {
        var x = new B().foo();
        x;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', [result.string]);
}

testConstructor() {
  final String source = r"""
      class A {
        var x, y, z;
        A(this.x, a) : y = a { z = 'abc'; }
      }
      main() {
        new A(42, 'abc');
        new A(true, null);
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkFieldHasType('A', 'x', [result.int, result.bool]);
  result.checkFieldHasType('A', 'y', [result.string, result.nullType]);
  // TODO(polux): we can be smarter and infer {string} for z
  result.checkFieldHasType('A', 'z', [result.string, result.nullType]);
}

testGetters() {
  final String source = r"""
      class A {
        var x;
        A(this.x);
        get y => x;
        get z => y;
      }
      class B {
        var x;
        B(this.x);
      }
      main() {
        var a = new A(42);
        var b = new B('abc');
        var foo = a.x;
        var bar = a.y;
        var baz = a.z;
        var qux = null.x;
        var quux = "__dynamic_for_test".x;
        foo; bar; baz; qux; quux;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.int]);
  result.checkNodeHasType('bar', [result.int]);
  result.checkNodeHasType('baz', [result.int]);
  result.checkNodeHasType('qux', []);
  result.checkNodeHasType('quux', [result.int, result.string]);
}

testSetters() {
  final String source = r"""
      class A {
        var x;
        var w;
        A(this.x, this.w);
        set y(a) { x = a; z = a; }
        set z(a) { w = a; }
      }
      class B {
        var x;
        B(this.x);
      }
      main() {
        var a = new A(42, 42);
        var b = new B(42);
        a.x = 'abc';
        a.y = true;
        null.x = 42;  // should be ignored
        "__dynamic_for_test".x = null;
        "__dynamic_for_test".y = 3.14;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkFieldHasType('B', 'x',
                           [result.int,         // new B(42)
                            result.nullType]);  // dynamic.x = null
  result.checkFieldHasType('A', 'x',
                           [result.int,       // new A(42, ...)
                            result.string,    // a.x = 'abc'
                            result.bool,      // a.y = true
                            result.nullType,  // dynamic.x = null
                            result.double]);  // dynamic.y = 3.14
  result.checkFieldHasType('A', 'w',
                           [result.int,       // new A(..., 42)
                            result.bool,      // a.y = true
                            result.double]);  // dynamic.y = double
}

testOptionalNamedParameters() {
  final String source = r"""
      class A {
        var x, y, z, w;
        A(this.x, {this.y, this.z, this.w});
      }
      class B {
        var x, y;
        B(this.x, {this.y});
      }
      class C {
        var x, y;
        C(this.x, {this.y});
      }
      class Test {
        var a, b, c, d;
        var e, f;
        var g, h;

        Test(this.a, this.b, this.c, this.d,
             this.e, this.f,
             this.g, this.h);

        f1(x, {y, z, w}) {
          a = x;
          b = y;
          c = z;
          d = w;
        }
        f2(x, {y}) {
          e = x;
          f = y;
        }
        f3(x, {y}) {
          g = x;
          h = y;
        }
      }
      class Foo {
      }
      main() {
        // We want to test expiclitely for null later so we initialize all the
        // fields of Test with a placeholder type: Foo.
        var foo = new Foo();
        var test = new Test(foo, foo, foo, foo, foo, foo, foo, foo);

        new A(42);
        new A('abc', w: true, z: 42.0);
        test.f1(42);
        test.f1('abc', w: true, z: 42.0);

        new B('abc', y: true);
        new B(1, 2);  // too many positional arguments
        test.f2('abc', y: true);
        test.f2(1, 2);  // too many positional arguments

        new C('abc', y: true);
        new C(1, z: 2);  // non-existing named parameter
        test.f3('abc', y: true);
        test.f3(1, z: 2);  // non-existing named parameter
      }
      """;
  AnalysisResult result = analyze(source);

  final foo = result.base('Foo');
  final nil = result.nullType;

  result.checkFieldHasType('A', 'x', [result.int, result.string]);
  result.checkFieldHasType('A', 'y', [nil]);
  result.checkFieldHasType('A', 'z', [nil, result.double]);
  result.checkFieldHasType('A', 'w', [nil, result.bool]);
  result.checkFieldHasType('Test', 'a', [foo, result.int, result.string]);
  result.checkFieldHasType('Test', 'b', [foo, nil]);
  result.checkFieldHasType('Test', 'c', [foo, nil, result.double]);
  result.checkFieldHasType('Test', 'd', [foo, nil, result.bool]);

  result.checkFieldHasType('B', 'x', [result.string]);
  result.checkFieldHasType('B', 'y', [result.bool]);
  result.checkFieldHasType('Test', 'e', [foo, result.string]);
  result.checkFieldHasType('Test', 'f', [foo, result.bool]);

  result.checkFieldHasType('C', 'x', [result.string]);
  result.checkFieldHasType('C', 'y', [result.bool]);
  result.checkFieldHasType('Test', 'g', [foo, result.string]);
  result.checkFieldHasType('Test', 'h', [foo, result.bool]);
}

testOptionalPositionalParameters() {
  final String source = r"""
    class A {
      var x, y, z, w;
      A(this.x, [this.y, this.z, this.w]);
    }
    class B {
      var x, y;
      B(this.x, [this.y]);
    }
    class Test {
      var a, b, c, d;
      var e, f;

      Test(this.a, this.b, this.c, this.d,
           this.e, this.f);

      f1(x, [y, z, w]) {
        a = x;
        b = y;
        c = z;
        d = w;
      }
      f2(x, [y]) {
        e = x;
        f = y;
      }
    }
    class Foo {
    }
    main() {
      // We want to test expiclitely for null later so we initialize all the
      // fields of Test with a placeholder type: Foo.
      var foo = new Foo();
      var test = new Test(foo, foo, foo, foo, foo, foo);

      new A(42);
      new A('abc', true, 42.0);
      test.f1(42);
      test.f1('abc', true, 42.0);

      new B('a', true);
      new B(1, 2, 3);  // too many arguments
      test.f2('a', true);
      test.f2(1, 2, 3);  // too many arguments
    }
  """;
  AnalysisResult result = analyze(source);

  final foo = result.base('Foo');
  final nil = result.nullType;

  result.checkFieldHasType('A', 'x', [result.int, result.string]);
  result.checkFieldHasType('A', 'y', [nil, result.bool]);
  result.checkFieldHasType('A', 'z', [nil, result.double]);
  result.checkFieldHasType('A', 'w', [nil]);
  result.checkFieldHasType('Test', 'a', [foo, result.int, result.string]);
  result.checkFieldHasType('Test', 'b', [foo, nil, result.bool]);
  result.checkFieldHasType('Test', 'c', [foo, nil, result.double]);
  result.checkFieldHasType('Test', 'd', [foo, nil]);

  result.checkFieldHasType('B', 'x', [result.string]);
  result.checkFieldHasType('B', 'y', [result.bool]);
  result.checkFieldHasType('Test', 'e', [foo, result.string]);
  result.checkFieldHasType('Test', 'f', [foo, result.bool]);
}

testListLiterals() {
  final String source = r"""
      class A {
        var x;
        A(this.x);
      }
      main() {
        var x = [];
        var y = [1, "a", null, new A(42)];
        x; y;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', [result.growableList]);
  result.checkNodeHasType('y', [result.growableList]);
  result.checkFieldHasType('A', 'x', [result.int]);
}

testMapLiterals() {
  final String source = r"""
      class A {
        var x;
        A(this.x);
      }
      main() {
        var x = {};
        var y = {'a': "foo", 'b': new A(42) };
        x; y;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', [result.map]);
  result.checkNodeHasType('y', [result.map]);
  result.checkFieldHasType('A', 'x', [result.int]);
}

testReturn() {
  final String source = r"""
      f() { if (true) { return 1; }; return "a"; }
      g() { f(); return; }
      main() {
        var x = f();
        var y = g();
        x; y;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', [result.int, result.string]);
  result.checkNodeHasType('y', [result.nullType]);
}

testNoReturn() {
  final String source = r"""
      f() { if (true) { return 1; }; }
      g() { f(); }
      main() {
        var x = f();
        var y = g();
        x; y;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', [result.int, result.nullType]);
  result.checkNodeHasType('y', [result.nullType]);
}

testArithmeticOperators() {
  String source(op) {
    return """
        main() {
          var a = 1 $op 2;
          var b = 1 $op 2.0;
          var c = 1.0 $op 2;
          var d = 1.0 $op 2.0;
          var e = (1 $op 2.0) $op 1;
          var f = 1 $op (1 $op 2.0);
          var g = (1 $op 2.0) $op 1.0;
          var h = 1.0 $op (1 $op 2);
          var i = (1 $op 2) $op 1;
          var j = 1 $op (1 $op 2);
          var k = (1.0 $op 2.0) $op 1.0;
          var l = 1.0 $op (1.0 $op 2.0);
          a; b; c; d; e; f; g; h; i; j; k; l;
        }""";
  }
  for (String op in ['+', '*', '-']) {
    AnalysisResult result = analyze(source(op));
    result.checkNodeHasType('a', [result.int]);
    result.checkNodeHasType('b', [result.num]);
    result.checkNodeHasType('c', [result.num]);
    result.checkNodeHasType('d', [result.double]);
    result.checkNodeHasType('e', [result.num]);
    result.checkNodeHasType('f', [result.num]);
    result.checkNodeHasType('g', [result.num]);
    result.checkNodeHasType('h', [result.num]);
    result.checkNodeHasType('i', [result.int]);
    result.checkNodeHasType('j', [result.int]);
    result.checkNodeHasType('k', [result.double]);
    result.checkNodeHasType('l', [result.double]);
  }
}

testBooleanOperators() {
  String source(op) {
    return """
        main() {
          var a = true $op null;
          var b = null $op true;
          var c = 1 $op true;
          var d = true $op "a";
          a; b; c; d;
        }""";
  }
  for (String op in ['&&', '||']) {
    AnalysisResult result = analyze(source(op));
    result.checkNodeHasType('a', [result.bool]);
    result.checkNodeHasType('b', [result.bool]);
    result.checkNodeHasType('c', [result.bool]);
    result.checkNodeHasType('d', [result.bool]);
  }
}

testBooleanOperatorsShortCirtcuit() {
  String source(op) {
    return """
        main() {
          var x = null;
          "foo" $op (x = 42);
          x;
        }""";
  }
  for (String op in ['&&', '||']) {
    AnalysisResult result = analyze(source(op));
    result.checkNodeHasType('x', [result.nullType, result.int]);
  }
}

testOperators() {
  final String source = r"""
      class A {
        operator <(x) => 42;
        operator <<(x) => "a";
      }
      main() {
        var x = new A() < "foo";
        var y = new A() << "foo";
        x; y;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', [result.int]);
  result.checkNodeHasType('y', [result.string]);
}

testSetIndexOperator() {
  final String source = r"""
      class A {
        var witness1;
        var witness2;
        operator []=(i, x) { witness1 = i; witness2 = x; }
      }
      main() {
        var x = new A()[42] = "abc";
        x;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', [result.string]);
  result.checkFieldHasType('A', 'witness1', [result.int, result.nullType]);
  result.checkFieldHasType('A', 'witness2', [result.string, result.nullType]);
}

testCompoundOperators1() {
  final String source = r"""
      class A {
        operator +(x) => "foo";
      }
      main() {
        var x1 = 1;
        x1++;
        var x2 = 1;
        ++x2;
        var x3 = 1;
        x3 += 42;
        var x4 = new A();
        x4++;
        var x5 = new A();
        ++x5;
        var x6 = new A();
        x6 += true;

        x1; x2; x3; x4; x5; x6;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x1', [result.int]);
  result.checkNodeHasType('x2', [result.int]);
  result.checkNodeHasType('x3', [result.int]);
  result.checkNodeHasType('x4', [result.string]);
  result.checkNodeHasType('x5', [result.string]);
  result.checkNodeHasType('x6', [result.string]);
}


testCompoundOperators2() {
  final String source = r"""
    class A {
      var xx;
      var yy;
      var witness1;
      var witness2;
      var witness3;
      var witness4;

      A(this.xx, this.yy);
      get x { witness1 = "foo"; return xx; }
      set x(a) { witness2 = "foo"; xx = a; }
      get y { witness3 = "foo"; return yy; }
      set y(a) { witness4 = "foo"; yy = a; }
    }
    main () {
      var a = new A(1, 1);
      a.x++;
      a.y++; 
    }
    """;
  AnalysisResult result = analyze(source);
  result.checkFieldHasType('A', 'xx', [result.int]);
  result.checkFieldHasType('A', 'yy', [result.int]);
  result.checkFieldHasType('A', 'witness1', [result.string, result.nullType]);
  result.checkFieldHasType('A', 'witness2', [result.string, result.nullType]);
  result.checkFieldHasType('A', 'witness3', [result.string, result.nullType]);
  result.checkFieldHasType('A', 'witness4', [result.string, result.nullType]);
}

testInequality() {
  final String source = r"""
      class A {
        var witness;
        operator ==(x) { witness = "foo"; return "abc"; }
      }
      class B {
        operator ==(x) { throw "error"; }
      }
      main() {
        var foo = 1 != 2;
        var bar = new A() != 2;
        var baz = new B() != 2;
        foo; bar; baz;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.bool]);
  result.checkNodeHasType('bar', [result.bool]);
  result.checkNodeHasType('baz', []);
  result.checkFieldHasType('A', 'witness', [result.string, result.nullType]);
}

testFieldInitialization1() {
  final String source = r"""
    class A {
      var x;
      var y = 1;
    }
    class B extends A {
      var z = "foo";
    }
    main () {
      new B();
    }
    """;
  AnalysisResult result = analyze(source);
  result.checkFieldHasType('A', 'x', [result.nullType]);
  result.checkFieldHasType('A', 'y', [result.int]);
  result.checkFieldHasType('B', 'z', [result.string]);
}

testFieldInitialization2() {
  final String source = r"""
    var top = 42;
    class A {
      var x = top;
    }
    main () {
      new A();
    }
    """;
  AnalysisResult result = analyze(source);
  result.checkFieldHasType('A', 'x', [result.int]);
}

testFieldInitialization3() {
  final String source = r"""
    class A {
      var x;
    }
    f() => new A().x;
    class B {
      var x = new A().x;
      var y = f();
    }
    main () {
      var foo = new B().x;
      var bar = new B().y;
      new A().x = "a";
      foo; bar;
    }
    """;
  AnalysisResult result = analyze(source);
  // checks that B.B is set as a reader of A.x
  result.checkFieldHasType('B', 'x', [result.nullType, result.string]);
  // checks that B.B is set as a caller of f
  result.checkFieldHasType('B', 'y', [result.nullType, result.string]);
  // checks that readers of x are notified by changes in x's type
  result.checkNodeHasType('foo', [result.nullType, result.string]);
  // checks that readers of y are notified by changes in y's type
  result.checkNodeHasType('bar', [result.nullType, result.string]);
}

testLists() {
  final String source = r"""
    main() {
      var l1 = [1.2];
      var l2 = [];
      l1['a'] = 42;  // raises an error, so int should not be recorded
      l1[1] = 'abc';
      "__dynamic_for_test"[1] = true;
      var x = l1[1];
      var y = l2[1];
      var z = l1['foo'];
      x; y; z;
    }""";
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', [result.double, result.string, result.bool]);
  result.checkNodeHasType('y', [result.double, result.string, result.bool]);
  result.checkNodeHasType('z', []);
}

testListWithCapacity() {
  final String source = r"""
    main() {
      var l = new List(10);
      var x = [][0];
      x;
    }""";
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', [result.nullType]);
}

testEmptyList() {
  final String source = r"""
    main() {
      var l = new List();
      var x = l[0];
      x;
    }""";
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', []);
}

testSendWithWrongArity() {
  final String source = r"""
    f(x) { }
    class A { g(x) { } }
    main () {
      var x = f();
      var y = f(1, 2);
      var z = new A().g();
      var w = new A().g(1, 2);
      x; y; z; w;
    }
    """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', []);
  result.checkNodeHasType('y', []);
  result.checkNodeHasType('z', []);
  result.checkNodeHasType('w', []);
}

testBigTypesWidening1() {
  final String source = r"""
    small() => true ? 1 : 'abc';
    big() => true ? 1 : (true ? 'abc' : false);
    main () {
      var x = small();
      var y = big();
      x; y;
    }
    """;
  AnalysisResult result = analyze(source, maxConcreteTypeSize: 2);
  result.checkNodeHasType('x', [result.int, result.string]);
  result.checkNodeHasUnknownType('y');
}

testBigTypesWidening2() {
  final String source = r"""
    class A {
      var x, y;
      A(this.x, this.y);
    }
    main () {
      var a = new A(1, 1);
      a.x = 'abc';
      a.y = 'abc';
      a.y = true;
    }
    """;
  AnalysisResult result = analyze(source, maxConcreteTypeSize: 2);
  result.checkFieldHasType('A', 'x', [result.int, result.string]);
  result.checkFieldHasUknownType('A', 'y');
}

testDynamicIsAbsorbing() {
  final String source = r"""
    main () {
      var x = 1;
      if (true) {
        x = "__dynamic_for_test";
      } else {
        x = 42;
      }
      x;
    }
    """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasUnknownType('x');
}

testJsCall() {
  final String source = r"""
    import 'dart:foreign';
    import 'dart:helper' show Null;
    import 'dart:interceptors';

    abstract class AbstractA {}
    class A extends AbstractA {}
    class B extends A {}
    class BB extends B {}
    class C extends A {}
    class D implements A {}
    class E extends A {}

    class X {}

    main () {
      // we don't create any E on purpose
      new B(); new BB(); new C(); new D();

      var a = JS('', '1');
      var b = JS('Object', '1');
      var c = JS('JSExtendableArray', '1');
      var cNull = JS('JSExtendableArray|Null', '1');
      var d = JS('String', '1');
      var dNull = JS('String|Null', '1');
      var e = JS('int', '1');
      var eNull = JS('int|Null', '1');
      var f = JS('double', '1');
      var fNull = JS('double|Null', '1');
      var g = JS('num', '1');
      var gNull = JS('num|Null', '1');
      var h = JS('bool', '1');
      var hNull = JS('bool|Null', '1');
      var i = JS('AbstractA', '1');
      var iNull = JS('AbstractA|Null', '1');
      var j = JS('X', '1');

      a; b; c; cNull; d; dNull; e; eNull; f; fNull; g; gNull; h; hNull; i;
      iNull; j;
    }
    """;
  AnalysisResult result = analyze(source);
  List maybe(List types) => new List.from(types)..add(result.nullType);
  result.checkNodeHasUnknownType('a');
  result.checkNodeHasUnknownType('b');
  final expectedCType = [result.growableList];
  result.checkNodeHasType('c', expectedCType);
  result.checkNodeHasType('cNull', maybe(expectedCType));
  final expectedDType = [result.string];
  result.checkNodeHasType('d', expectedDType);
  result.checkNodeHasType('dNull', maybe(expectedDType));
  final expectedEType = [result.int];
  result.checkNodeHasType('e', expectedEType);
  result.checkNodeHasType('eNull', maybe(expectedEType));
  final expectedFType = [result.double];
  result.checkNodeHasType('f', expectedFType);
  result.checkNodeHasType('fNull', maybe(expectedFType));
  final expectedGType = [result.num];
  result.checkNodeHasType('g', expectedGType);
  result.checkNodeHasType('gNull', maybe(expectedGType));
  final expectedHType = [result.bool];
  result.checkNodeHasType('h', expectedHType);
  result.checkNodeHasType('hNull', maybe(expectedHType));
  final expectedIType = [result.base('A'), result.base('B'),
                         result.base('BB'), result.base('C'),
                         result.base('D')];
  result.checkNodeHasType('i', expectedIType);
  result.checkNodeHasType('iNull', maybe(expectedIType));
  result.checkNodeHasType('j', []);
}

testJsCallAugmentsSeenClasses() {
  final String source1 = r"""
    main () {
      var x = "__dynamic_for_test".truncate();
      x;
    }
    """;
  AnalysisResult result1 = analyze(source1);
  result1.checkNodeHasType('x', []);

  final String source2 = r"""
    import 'dart:foreign';

    main () {
      var x = "__dynamic_for_test".truncate();
      JS('double', 'foo');
      x;
    }
    """;
  AnalysisResult result2 = analyze(source2);
  result2.checkNodeHasType('x', [result2.int]);
}

testIsCheck() {
  final String source = r"""
    main () {
      var x = (1 is String);
      x;
    }
    """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', [result.bool]);
}

testSeenClasses() {
  final String source = r"""
      class A {
        witness() => 42;
      }
      class B {
        witness() => "abc";
      }
      class AFactory {
        onlyCalledInAFactory() => new A();
      }
      class BFactory {
        onlyCalledInAFactory() => new B();
      }

      main() {
        new AFactory().onlyCalledInAFactory();
        new BFactory();
        // should be of type {int} and not {int, String} since B is unreachable
        var foo = "__dynamic_for_test".witness();
        foo;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('foo', [result.int]);
}

testIntDoubleNum() {
  final String source = r"""
      main() {
        var a = 1;
        var b = 1.0;
        var c = true ? 1 : 1.0;
        a; b; c;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('a', [result.int]);
  result.checkNodeHasType('b', [result.double]);
  result.checkNodeHasType('c', [result.num]);
}

testConcreteTypeToTypeMask() {
  final String source = r"""
      class A {}
      class B extends A {}
      class C extends A {}
      class D implements A {}
      main() {
        new A();
        new B();
        new C();
        new D();
      }
      """;
  AnalysisResult result = analyze(source);

  convert(ConcreteType type) {
    return result.compiler.typesTask.concreteTypesInferrer
        .concreteTypeToTypeMask(type);
  }

  final nullSingleton =
      result.compiler.typesTask.concreteTypesInferrer.singletonConcreteType(
          new NullBaseType());

  singleton(ClassElement element) {
    return result.compiler.typesTask.concreteTypesInferrer
        .singletonConcreteType(new ClassBaseType(element));
  }

  ClassElement a = findElement(result.compiler, 'A');
  ClassElement b = findElement(result.compiler, 'B');
  ClassElement c = findElement(result.compiler, 'C');
  ClassElement d = findElement(result.compiler, 'D');

  for (ClassElement cls in [a, b, c, d]) {
    Expect.equals(convert(singleton(cls)),
                  new TypeMask.nonNullExact(cls.rawType));
  }

  for (ClassElement cls in [a, b, c, d]) {
    Expect.equals(convert(singleton(cls).union(nullSingleton)),
                  new TypeMask.exact(cls.rawType));
  }

  Expect.equals(convert(singleton(a).union(singleton(b))),
                new TypeMask.nonNullSubclass(a.rawType));

  Expect.equals(convert(singleton(a).union(singleton(b)).union(nullSingleton)),
                new TypeMask.subclass(a.rawType));

  Expect.equals(
      convert(singleton(b).union(singleton(d))).simplify(result.compiler),
      new TypeMask.nonNullSubtype(a.rawType));
}

testSelectors() {
  final String source = r"""
      // ABC <--- A
      //       `- BC <--- B
      //               `- C

      class ABC {}
      class A extends ABC {}
      class BC extends ABC {}
      class B extends BC {}
      class C extends BC {}

      class XY {}
      class X extends XY { foo() => new B(); }
      class Y extends XY { foo() => new C(); }
      class Z { foo() => new A(); }

      main() {
        new X().foo();
        new Y().foo();
        new Z().foo();
      }
      """;
  AnalysisResult result = analyze(source);

  inferredType(Selector selector) {
    return result.compiler.typesTask.concreteTypesInferrer
        .getTypeOfSelector(selector);
  }

  ClassElement abc = findElement(result.compiler, 'ABC');
  ClassElement bc = findElement(result.compiler, 'BC');
  ClassElement a = findElement(result.compiler, 'A');
  ClassElement b = findElement(result.compiler, 'B');
  ClassElement c = findElement(result.compiler, 'C');
  ClassElement xy = findElement(result.compiler, 'XY');
  ClassElement x = findElement(result.compiler, 'X');
  ClassElement y = findElement(result.compiler, 'Y');
  ClassElement z = findElement(result.compiler, 'Z');

  Selector foo = new Selector.call(buildSourceString("foo"), null, 0);

  Expect.equals(
      inferredType(foo).simplify(result.compiler),
      new TypeMask.nonNullSubclass(abc.rawType));
  Expect.equals(
      inferredType(new TypedSelector.subclass(x.rawType, foo)),
      new TypeMask.nonNullExact(b.rawType));
  Expect.equals(
      inferredType(new TypedSelector.subclass(y.rawType, foo)),
      new TypeMask.nonNullExact(c.rawType));
  Expect.equals(
      inferredType(new TypedSelector.subclass(z.rawType, foo)),
      new TypeMask.nonNullExact(a.rawType));
  Expect.equals(
      inferredType(new TypedSelector.subclass(
          xy.rawType, foo)).simplify(result.compiler),
      new TypeMask.nonNullSubclass(bc.rawType));

  Selector bar = new Selector.call(buildSourceString("bar"), null, 0);

  Expect.isNull(inferredType(bar));
}

testMixins() {
  final String source = r"""
      class A {
        foo() => "abc";
        get x => 42;
      }
      class B extends Object with A {
        bar() => foo();
        baz() => x;
      }
      main() {
        var b = new B();
        var x = b.foo();
        var y = b.bar();
        var z = b.x;
        var w = b.baz();
        x; y; z; w;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('x', [result.string]);
  result.checkNodeHasType('y', [result.string]);
  result.checkNodeHasType('z', [result.int]);
  result.checkNodeHasType('w', [result.int]);
}

testClosures() {
  final String source = r"""
      class A {
        final foo = 42;
      }
      class B {
        final foo = "abc";
      }
      main() {
        new A(); new B();

        var a;
        var f = (x) {
          a = x.foo;
        };
        var b = f(42);
        a; b; f;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('a', [result.int, result.string]);
  result.checkNodeHasType('f', [result.functionType]);
  result.checkNodeHasUnknownType('b');
}

testNestedFunctions() {
  final String source = r"""
      class A {
        final foo = 42;
      }
      class B {
        final foo = "abc";
      }
      main() {
        new A(); new B();

        var a;
        f(x) {
          a = x.foo;
        }
        var b = f(42);
        a; b; f;
      }
      """;
  AnalysisResult result = analyze(source);
  result.checkNodeHasType('a', [result.int, result.string]);
  result.checkNodeHasType('f', [result.functionType]);
  result.checkNodeHasUnknownType('b');
}

void main() {
  testDynamicBackDoor();
  testVariableDeclaration();
  testLiterals();
  testRedefinition();
  testIfThenElse();
  testTernaryIf();
  testWhile();
  testFor1();
  testFor2();
  testFor3();
  testForIn();
  testToplevelVariable();
  testNonRecusiveFunction();
  testRecusiveFunction();
  testMutuallyRecusiveFunction();
  testSimpleSend();
  // testSendToClosureField();  // closures are not yet supported
  testSendToThis1();
  testSendToThis2();
  testSendToThis3();
  testConstructor();
  testGetters();
  testSetters();
  testOptionalNamedParameters();
  testOptionalPositionalParameters();
  testListLiterals();
  testMapLiterals();
  testReturn();
  // testNoReturn(); // right now we infer the empty type instead of null
  testArithmeticOperators();
  testBooleanOperators();
  testBooleanOperatorsShortCirtcuit();
  testOperators();
  testCompoundOperators1();
  testCompoundOperators2();
  testSetIndexOperator();
  testInequality();
  testFieldInitialization1();
  testFieldInitialization2();
  testFieldInitialization3();
  testSendWithWrongArity();
  testBigTypesWidening1();
  testBigTypesWidening2();
  testDynamicIsAbsorbing();
  testLists();
  testListWithCapacity();
  testEmptyList();
  testJsCall();
  testJsCallAugmentsSeenClasses();
  testIsCheck();
  testSeenClasses();
  testIntDoubleNum();
  testConcreteTypeToTypeMask();
  testSelectors();
  testMixins();
  testClosures();
  testNestedFunctions();
}
