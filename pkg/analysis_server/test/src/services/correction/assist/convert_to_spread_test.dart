// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/assist.dart';
import 'package:analysis_server/src/services/linter/lint_names.dart';
import 'package:analyzer/src/dart/analysis/experiments.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'assist_processor.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ConvertToSpreadTest);
    defineReflectiveTests(ConvertToSpreadWithControlFlowTest);
  });
}

@reflectiveTest
class ConvertToSpreadTest extends AssistProcessorTest {
  @override
  AssistKind get kind => DartAssistKind.CONVERT_TO_SPREAD;

  void setUp() {
    createAnalysisOptionsFile(experiments: [EnableString.spread_collections]);
    super.setUp();
  }

  test_addAll_expression() async {
    await resolveTestUnit('''
f() {
  var ints = [1, 2, 3];
  print(['a']..addAl/*caret*/l(ints.map((i) => i.toString()))..addAll(['c']));
}
''');
    await assertHasAssist('''
f() {
  var ints = [1, 2, 3];
  print(['a', ...ints.map((i) => i.toString())]..addAll(['c']));
}
''');
  }

  test_addAll_expression_noAssistWithLint() async {
    createAnalysisOptionsFile(lints: [LintNames.prefer_spread_collections]);
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
f() {
  var ints = [1, 2, 3];
  print(['a']..addAl/*caret*/l(ints.map((i) => i.toString()))..addAll(['c']));
}
''');
    await assertNoAssist();
  }

  test_addAll_expression_toEmptyList() async {
    await resolveTestUnit('''
f() {
  var ints = [1, 2, 3];
  print([]..addAl/*caret*/l(ints.map((i) => i.toString()))..addAll(['c']));
}
''');
    await assertHasAssist('''
f() {
  var ints = [1, 2, 3];
  print([...ints.map((i) => i.toString())]..addAll(['c']));
}
''');
  }

  test_addAll_literal() async {
    // This case is covered by the INLINE_INVOCATION assist.
    await resolveTestUnit('''
var l = ['a']..add/*caret*/All(['b'])..addAll(['c']);
''');
    await assertNoAssist();
  }

  test_addAll_nonLiteralTarget() async {
    await resolveTestUnit('''
var l1 = [];
var l2 = l1..addAl/*caret*/l(['b'])..addAll(['c']);
''');
    await assertNoAssist();
  }

  test_addAll_notFirst() async {
    await resolveTestUnit('''
var l = ['a']..addAll(['b'])../*caret*/addAll(['c']);
''');
    await assertNoAssist();
  }

  test_addAll_nullAware_const() async {
    await resolveTestUnit('''
var things;
var l = ['a']..add/*caret*/All(things ?? const []);
''');
    await assertHasAssist('''
var things;
var l = ['a', ...?things];
''');
  }

  test_addAll_nullAware_nonConst() async {
    await resolveTestUnit('''
var things;
var l = ['a']..add/*caret*/All(things ?? []);
''');
    await assertHasAssist('''
var things;
var l = ['a', ...?things];
''');
  }
}

@reflectiveTest
class ConvertToSpreadWithControlFlowTest extends AssistProcessorTest {
  @override
  AssistKind get kind => DartAssistKind.CONVERT_TO_SPREAD;

  void setUp() {
    createAnalysisOptionsFile(experiments: [
      EnableString.control_flow_collections,
      EnableString.spread_collections
    ]);
    super.setUp();
  }

  test_addAll_condition_const() async {
    await resolveTestUnit('''
bool condition;
var things;
var l = ['a']..add/*caret*/All(condition ? things : const []);
''');
    await assertHasAssist('''
bool condition;
var things;
var l = ['a', if (condition) ...things];
''');
  }

  test_addAll_condition_nonConst() async {
    await resolveTestUnit('''
bool condition;
var things;
var l = ['a']..add/*caret*/All(condition ? things : []);
''');
    await assertHasAssist('''
bool condition;
var things;
var l = ['a', if (condition) ...things];
''');
  }
}
