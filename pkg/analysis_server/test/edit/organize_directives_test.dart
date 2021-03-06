// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analysis_server/protocol/protocol.dart';
import 'package:analysis_server/protocol/protocol_generated.dart';
import 'package:analysis_server/src/edit/edit_domain.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../analysis_abstract.dart';
import '../mocks.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(OrganizeDirectivesTest);
  });
}

@reflectiveTest
class OrganizeDirectivesTest extends AbstractAnalysisTest {
  SourceFileEdit fileEdit;

  @override
  void setUp() {
    super.setUp();
    createProject();
    handler = new EditDomainHandler(server);
  }

  @failingTest
  Future test_BAD_doesNotExist() async {
    // The analysis driver fails to return an error
    Request request =
        new EditOrganizeDirectivesParams(convertPath('/no/such/file.dart'))
            .toRequest('0');
    Response response = await waitResponse(request);
    expect(
        response, isResponseFailure('0', RequestErrorCode.FILE_NOT_ANALYZED));
  }

  Future test_BAD_hasParseError() async {
    addTestFile('''
import 'dart:async'

main() {}
''');
    Request request = new EditOrganizeDirectivesParams(testFile).toRequest('0');
    Response response = await waitResponse(request);
    expect(response,
        isResponseFailure('0', RequestErrorCode.ORGANIZE_DIRECTIVES_ERROR));
  }

  Future test_BAD_notDartFile() async {
    Request request = new EditOrganizeDirectivesParams(
      convertPath('/not-a-Dart-file.txt'),
    ).toRequest('0');
    Response response = await waitResponse(request);
    expect(
        response, isResponseFailure('0', RequestErrorCode.FILE_NOT_ANALYZED));
  }

  test_invalidFilePathFormat_notAbsolute() async {
    var request = new EditOrganizeDirectivesParams('test.dart').toRequest('0');
    var response = await waitResponse(request);
    expect(
      response,
      isResponseFailure('0', RequestErrorCode.INVALID_FILE_PATH_FORMAT),
    );
  }

  test_invalidFilePathFormat_notNormalized() async {
    var request =
        new EditOrganizeDirectivesParams(convertPath('/foo/../bar/test.dart'))
            .toRequest('0');
    var response = await waitResponse(request);
    expect(
      response,
      isResponseFailure('0', RequestErrorCode.INVALID_FILE_PATH_FORMAT),
    );
  }

  Future test_keep_unresolvedDirectives() {
    var code = r'''
import 'dart:noSuchImportSdkLibrary';

import 'package:noSuchImportPackage/andLib.dart';

export 'dart:noSuchExportSdkLibrary';

export 'package:noSuchExportPackage/andLib.dart';

part 'no_such_part.dart';
''';
    addTestFile(code);
    return _assertOrganized(code);
  }

  Future test_OK_remove_duplicateImports_withSamePrefix() {
    addTestFile('''
library lib;

import 'dart:async' as async;
import 'dart:async' as async;

main() {
  async.Future f;
}
''');
    return _assertOrganized(r'''
library lib;

import 'dart:async' as async;

main() {
  async.Future f;
}
''');
  }

  Future test_OK_remove_unusedImports() {
    addTestFile('''
library lib;

import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:collection';

main() {
  print(PI);
  new HashMap();
}
''');
    return _assertOrganized(r'''
library lib;

import 'dart:collection';
import 'dart:math';

main() {
  print(PI);
  new HashMap();
}
''');
  }

  Future _assertOrganized(String expectedCode) async {
    await _requestOrganize();
    String resultCode = SourceEdit.applySequence(testCode, fileEdit.edits);
    expect(resultCode, expectedCode);
  }

  Future _requestOrganize() async {
    Request request = new EditOrganizeDirectivesParams(testFile).toRequest('0');
    Response response = await waitResponse(request);
    var result = new EditOrganizeDirectivesResult.fromResponse(response);
    fileEdit = result.edit;
  }
}
