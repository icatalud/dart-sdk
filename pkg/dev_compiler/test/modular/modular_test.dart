// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Test the modular compilation pipeline of ddc.
///
/// This is a shell that runs multiple tests, one per folder under `data/`.
import 'dart:io';

import 'package:expect/expect.dart';
import 'package:modular_test/src/io_pipeline.dart';
import 'package:modular_test/src/pipeline.dart';
import 'package:modular_test/src/suite.dart';
import 'package:modular_test/src/runner.dart';

Options _options;
main(List<String> args) async {
  _options = Options.parse(args);
  await runSuite(
      Platform.script.resolve('data/'),
      _options,
      new IOPipeline([
        SourceToSummaryDillStep(),
        DDKStep(),
        RunD8(),
      ], cacheSharedModules: true));
}

const dillId = const DataId("dill");
const jsId = const DataId("js");
const txtId = const DataId("txt");

class SourceToSummaryDillStep implements IOModularStep {
  @override
  List<DataId> get resultData => const [dillId];

  @override
  bool get needsSources => true;

  @override
  List<DataId> get dependencyDataNeeded => const [dillId];

  @override
  List<DataId> get moduleDataNeeded => const [];

  @override
  bool get onlyOnMain => false;

  @override
  Future<void> execute(Module module, Uri root, ModuleDataToRelativeUri toUri,
      List<String> flags) async {
    if (_options.verbose) print("\nstep: source-to-dill on $module");

    // We use non file-URI schemes for representing source locations in a
    // root-agnostic way. This allows us to refer to file across modules and
    // across steps without exposing the underlying temporary folders that are
    // created by the framework. In build systems like bazel this is especially
    // important because each step may be run on a different machine.
    //
    // Files in packages are defined in terms of `package:` URIs, while
    // non-package URIs are defined using the `dart-dev-app` scheme.
    String rootScheme = module.isSdk ? 'dart-dev-sdk' : 'dev-dart-app';
    String sourceToImportUri(Uri relativeUri) =>
        _sourceToImportUri(module, rootScheme, relativeUri);

    Set<Module> transitiveDependencies = computeTransitiveDependencies(module);
    _createPackagesFile(module, root, transitiveDependencies);

    var sdkRoot = Platform.script.resolve("../../../../");
    List<String> sources;
    List<String> extraArgs;
    if (module.isSdk) {
      sources = ['dart:core'];
      extraArgs = ['--libraries-file', '$rootScheme:///sdk/lib/libraries.json'];
      assert(transitiveDependencies.isEmpty);
    } else {
      sources = module.sources.map(sourceToImportUri).toList();
      extraArgs = ['--packages-file', '$rootScheme:/.packages'];
    }

    List<String> args = [
      sdkRoot.resolve("utils/bazel/kernel_worker.dart").toFilePath(),
      '--summary-only',
      '--target',
      'ddc',
      '--multi-root',
      '$root',
      '--multi-root-scheme',
      rootScheme,
      ...extraArgs,
      '--output',
      '${toUri(module, dillId)}',
      ...(transitiveDependencies
          .expand((m) => ['--input-linked', '${toUri(m, dillId)}'])),
      ...(sources.expand((String uri) => ['--source', uri])),
      ...(flags.expand((String flag) => ['--enable-experiment', flag])),
    ];

    var result =
        await _runProcess(Platform.resolvedExecutable, args, root.toFilePath());
    _checkExitCode(result, this, module);
  }

  @override
  void notifyCached(Module module) {
    if (_options.verbose) print("\ncached step: source-to-dill on $module");
  }
}

class DDKStep implements IOModularStep {
  @override
  List<DataId> get resultData => const [jsId];

  @override
  bool get needsSources => true;

  @override
  List<DataId> get dependencyDataNeeded => const [dillId];

  @override
  List<DataId> get moduleDataNeeded => const [dillId];

  @override
  bool get onlyOnMain => false;

  @override
  Future<void> execute(Module module, Uri root, ModuleDataToRelativeUri toUri,
      List<String> flags) async {
    if (_options.verbose) print("\nstep: ddk on $module");
    var sdkRoot = Platform.script.resolve("../../../../");

    Set<Module> transitiveDependencies = computeTransitiveDependencies(module);
    _createPackagesFile(module, root, transitiveDependencies);

    List<String> args;
    if (module.isSdk) {
      // TODO(sigmund): this produces an error because kernel_sdk doesn't have a
      // way to provide a .packages file. Technically is not needed, but it
      // would be nice to proceed without any error messages.
      args = [
        '--packages=${sdkRoot.toFilePath()}/.packages',
        sdkRoot.resolve('pkg/dev_compiler/tool/kernel_sdk.dart').toFilePath(),
        '--libraries',
        'sdk/lib/libraries.json',
        '--output',
        '${toUri(module, jsId)}.ignored_dill',
      ];
      var result = await _runProcess(
          Platform.resolvedExecutable, args, root.toFilePath());
      _checkExitCode(result, this, module);
      await File.fromUri(root.resolve('es6/dart_sdk.js'))
          .copy(root.resolveUri(toUri(module, jsId)).toFilePath());
    } else {
      Uri output = toUri(module, jsId);
      Module sdkModule = module.dependencies.firstWhere((m) => m.isSdk);
      String sourceToImportUri(Uri relativeUri) =>
          _sourceToImportUri(module, 'dev-dart-app', relativeUri);

      args = [
        '--packages=${sdkRoot.toFilePath()}/.packages',
        sdkRoot.resolve('pkg/dev_compiler/bin/dartdevc.dart').toFilePath(),
        '--kernel',
        '--modules=es6',
        '--no-summarize',
        '--no-source-map',
        '--multi-root-scheme',
        'dev-dart-app',
        '--dart-sdk-summary',
        '${toUri(sdkModule, dillId)}',
        '--packages',
        '.packages',
        ...module.sources.map(sourceToImportUri),
        for (String flag in flags) '--enable-experiment=$flag',
        ...(transitiveDependencies
            .where((m) => !m.isSdk)
            .expand((m) => ['-s', '${toUri(m, dillId)}=${m.name}'])),
        '-o',
        '$output',
      ];
      var result = await _runProcess(
          Platform.resolvedExecutable, args, root.toFilePath());
      _checkExitCode(result, this, module);
    }
  }

  @override
  void notifyCached(Module module) {
    if (_options.verbose) print("\ncached step: ddk on $module");
  }
}

class RunD8 implements IOModularStep {
  @override
  List<DataId> get resultData => const [txtId];

  @override
  bool get needsSources => false;

  @override
  List<DataId> get dependencyDataNeeded => const [jsId];

  @override
  List<DataId> get moduleDataNeeded => const [jsId];

  @override
  bool get onlyOnMain => true;

  @override
  Future<void> execute(Module module, Uri root, ModuleDataToRelativeUri toUri,
      List<String> flags) async {
    if (_options.verbose) print("\nstep: d8 on $module");
    var sdkRoot = Platform.script.resolve("../../../../");

    // Rename sdk.js to dart_sdk.js (the alternative, but more hermetic solution
    // would be to rename the import on all other .js files, but seems
    // overkill/unnecessary.
    if (await File.fromUri(root.resolve('dart_sdk.js')).exists()) {
      print('error: dart_sdk.js already exists.');
      exitCode = 1;
    }

    await File.fromUri(root.resolve('sdk.js'))
        .copy(root.resolve('dart_sdk.js').toFilePath());
    var runjs = '''
    import { dart, _isolate_helper } from 'dart_sdk.js';
    import { main } from 'main.js';
    _isolate_helper.startRootIsolate(() => {}, []);
    main.main();
    ''';

    var wrapper =
        root.resolveUri(toUri(module, jsId)).toFilePath() + ".wrapper.js";
    await File(wrapper).writeAsString(runjs);
    List<String> d8Args = ['--module', wrapper];
    var result = await _runProcess(
        sdkRoot.resolve(_d8executable).toFilePath(), d8Args, root.toFilePath());

    _checkExitCode(result, this, module);

    await File.fromUri(root.resolveUri(toUri(module, txtId)))
        .writeAsString(result.stdout as String);
  }

  @override
  void notifyCached(Module module) {
    if (_options.verbose) print("\ncached step: d8 on $module");
  }
}

void _checkExitCode(ProcessResult result, IOModularStep step, Module module) {
  if (result.exitCode != 0 || _options.verbose) {
    stdout.write(result.stdout);
    stderr.write(result.stderr);
  }
  if (result.exitCode != 0) {
    exitCode = result.exitCode;
    Expect.fail("${step.runtimeType} failed on $module");
  }
}

Future<ProcessResult> _runProcess(
    String command, List<String> arguments, String workingDirectory) {
  if (_options.verbose) {
    print('command:\n$command ${arguments.join(' ')} from $workingDirectory');
  }
  return Process.run(command, arguments, workingDirectory: workingDirectory);
}

String get _d8executable {
  if (Platform.isWindows) {
    return 'third_party/d8/windows/d8.exe';
  } else if (Platform.isLinux) {
    return 'third_party/d8/linux/d8';
  } else if (Platform.isMacOS) {
    return 'third_party/d8/macos/d8';
  }
  throw new UnsupportedError('Unsupported platform.');
}

Future<void> _createPackagesFile(
    Module module, Uri root, Set<Module> transitiveDependencies) async {
  // We create a .packages file which defines the location of this module if
  // it is a package.  The CFE requires that if a `package:` URI of a
  // dependency is used in an import, then we need that package entry in the
  // .packages file. However, after it checks that the definition exists, the
  // CFE will not actually use the resolved URI if a library for the import
  // URI is already found in one of the provided .dill files of the
  // dependencies. For that reason, and to ensure that a step only has access
  // to the files provided in a module, we generate a .packages with invalid
  // folders for other packages.
  // TODO(sigmund): follow up with the CFE to see if we can remove the need
  // for the .packages entry altogether if they won't need to read the
  // sources.
  var packagesContents = new StringBuffer();
  if (module.isPackage) {
    packagesContents.write('${module.name}:${module.packageBase}\n');
  }
  for (Module dependency in transitiveDependencies) {
    if (dependency.isPackage) {
      packagesContents.write('${dependency.name}:unused\n');
    }
  }

  await File.fromUri(root.resolve('.packages'))
      .writeAsString('$packagesContents');
}

String _sourceToImportUri(Module module, String rootScheme, Uri relativeUri) {
  if (module.isPackage) {
    var basePath = module.packageBase.path;
    var packageRelativePath = basePath == "./"
        ? relativeUri.path
        : relativeUri.path.substring(basePath.length);
    return 'package:${module.name}/$packageRelativePath';
  } else {
    return '$rootScheme:/$relativeUri';
  }
}