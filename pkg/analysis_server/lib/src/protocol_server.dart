// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library protocol.server;

import 'package:analysis_server/plugin/protocol/protocol.dart';
import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analysis_server/src/services/search/search_engine.dart'
    as engine;
import 'package:analyzer/src/generated/ast.dart' as engine;
import 'package:analyzer/src/generated/element.dart' as engine;
import 'package:analyzer/src/generated/engine.dart' as engine;
import 'package:analyzer/src/generated/error.dart' as engine;
import 'package:analyzer/src/generated/source.dart' as engine;
import 'package:analyzer/src/generated/utilities_dart.dart' as engine;

export 'package:analysis_server/plugin/protocol/protocol.dart';

/**
 * Returns a list of AnalysisErrors correponding to the given list of Engine
 * errors.
 */
List<AnalysisError> doAnalysisError_listFromEngine(
    engine.LineInfo lineInfo, List<engine.AnalysisError> errors) {
  return errors.map((engine.AnalysisError error) {
    return newAnalysisError_fromEngine(lineInfo, error);
  }).toList();
}

/**
 * Adds [edit] to the [FileEdit] for the given [element].
 */
void doSourceChange_addElementEdit(
    SourceChange change, engine.Element element, SourceEdit edit) {
  engine.AnalysisContext context = element.context;
  engine.Source source = element.source;
  doSourceChange_addSourceEdit(change, context, source, edit);
}

/**
 * Adds [edit] to the [FileEdit] for the given [source].
 */
void doSourceChange_addSourceEdit(SourceChange change,
    engine.AnalysisContext context, engine.Source source, SourceEdit edit) {
  String file = source.fullName;
  int fileStamp = context.getModificationStamp(source);
  change.addEdit(file, fileStamp, edit);
}

String getReturnTypeString(engine.Element element) {
  if (element is engine.ExecutableElement) {
    if (element.kind == engine.ElementKind.SETTER) {
      return null;
    } else {
      return element.returnType.toString();
    }
  } else if (element is engine.VariableElement) {
    engine.DartType type = element.type;
    return type != null ? type.displayName : 'dynamic';
  } else if (element is engine.FunctionTypeAliasElement) {
    return element.returnType.toString();
  } else {
    return null;
  }
}

/**
 * Construct based on error information from the analyzer engine.
 */
AnalysisError newAnalysisError_fromEngine(
    engine.LineInfo lineInfo, engine.AnalysisError error) {
  engine.ErrorCode errorCode = error.errorCode;
  // prepare location
  Location location;
  {
    String file = error.source.fullName;
    int offset = error.offset;
    int length = error.length;
    int startLine = -1;
    int startColumn = -1;
    if (lineInfo != null) {
      engine.LineInfo_Location lineLocation = lineInfo.getLocation(offset);
      if (lineLocation != null) {
        startLine = lineLocation.lineNumber;
        startColumn = lineLocation.columnNumber;
      }
    }
    location = new Location(file, offset, length, startLine, startColumn);
  }
  // done
  var severity = new AnalysisErrorSeverity(errorCode.errorSeverity.name);
  var type = new AnalysisErrorType(errorCode.type.name);
  String message = error.message;
  String correction = error.correction;
  bool fix = hasFix(error.errorCode);
  return new AnalysisError(severity, type, location, message,
      correction: correction, hasFix: fix);
}

/**
 * Construct based on a value from the analyzer engine.
 */
Element newElement_fromEngine(engine.Element element) {
  String name = element.displayName;
  String elementTypeParameters = _getTypeParametersString(element);
  String elementParameters = _getParametersString(element);
  String elementReturnType = getReturnTypeString(element);
  ElementKind kind = newElementKind_fromEngineElement(element);
  return new Element(
      kind,
      name,
      Element.makeFlags(
          isPrivate: element.isPrivate,
          isDeprecated: element.isDeprecated,
          isAbstract: _isAbstract(element),
          isConst: _isConst(element),
          isFinal: _isFinal(element),
          isStatic: _isStatic(element)),
      location: newLocation_fromElement(element),
      typeParameters: elementTypeParameters,
      parameters: elementParameters,
      returnType: elementReturnType);
}

/**
 * Construct based on a value from the analyzer engine.
 * This does not take into account that
 * instances of ClassElement can be an enum and
 * instances of FieldElement can be an enum constant.
 * Use [newElementKind_fromEngineElement] where possible.
 */
ElementKind newElementKind_fromEngine(engine.ElementKind kind) {
  if (kind == engine.ElementKind.CLASS) {
    return ElementKind.CLASS;
  }
  if (kind == engine.ElementKind.COMPILATION_UNIT) {
    return ElementKind.COMPILATION_UNIT;
  }
  if (kind == engine.ElementKind.CONSTRUCTOR) {
    return ElementKind.CONSTRUCTOR;
  }
  if (kind == engine.ElementKind.FIELD) {
    return ElementKind.FIELD;
  }
  if (kind == engine.ElementKind.FUNCTION) {
    return ElementKind.FUNCTION;
  }
  if (kind == engine.ElementKind.FUNCTION_TYPE_ALIAS) {
    return ElementKind.FUNCTION_TYPE_ALIAS;
  }
  if (kind == engine.ElementKind.GETTER) {
    return ElementKind.GETTER;
  }
  if (kind == engine.ElementKind.LABEL) {
    return ElementKind.LABEL;
  }
  if (kind == engine.ElementKind.LIBRARY) {
    return ElementKind.LIBRARY;
  }
  if (kind == engine.ElementKind.LOCAL_VARIABLE) {
    return ElementKind.LOCAL_VARIABLE;
  }
  if (kind == engine.ElementKind.METHOD) {
    return ElementKind.METHOD;
  }
  if (kind == engine.ElementKind.PARAMETER) {
    return ElementKind.PARAMETER;
  }
  if (kind == engine.ElementKind.PREFIX) {
    return ElementKind.PREFIX;
  }
  if (kind == engine.ElementKind.SETTER) {
    return ElementKind.SETTER;
  }
  if (kind == engine.ElementKind.TOP_LEVEL_VARIABLE) {
    return ElementKind.TOP_LEVEL_VARIABLE;
  }
  if (kind == engine.ElementKind.TYPE_PARAMETER) {
    return ElementKind.TYPE_PARAMETER;
  }
  return ElementKind.UNKNOWN;
}

/**
 * Construct based on a value from the analyzer engine.
 */
ElementKind newElementKind_fromEngineElement(engine.Element element) {
  if (element is engine.ClassElement && element.isEnum) {
    return ElementKind.ENUM;
  }
  if (element is engine.FieldElement &&
      element.isEnumConstant &&
      // MyEnum.values and MyEnum.one.index return isEnumConstant = true
      // so these additional checks are necessary.
      // TODO(danrubel) MyEnum.values is constant, but is a list
      // so should it return isEnumConstant = true?
      // MyEnum.one.index is final but *not* constant
      // so should it return isEnumConstant = true?
      // Or should we return ElementKind.ENUM_CONSTANT here
      // in either or both of these cases?
      element.type != null &&
      element.type.element == element.enclosingElement) {
    return ElementKind.ENUM_CONSTANT;
  }
  return newElementKind_fromEngine(element.kind);
}

/**
 * Create a Location based on an [engine.Element].
 */
Location newLocation_fromElement(engine.Element element) {
  engine.AnalysisContext context = element.context;
  engine.Source source = element.source;
  if (context == null || source == null) {
    return null;
  }
  int offset = element.nameOffset;
  int length = element.nameLength;
  if (element is engine.CompilationUnitElement) {
    offset = 0;
    length = 0;
  }
  engine.SourceRange range = new engine.SourceRange(offset, length);
  return _locationForArgs(context, source, range);
}

/**
 * Create a Location based on an [engine.SearchMatch].
 */
Location newLocation_fromMatch(engine.SearchMatch match) {
  engine.Element enclosingElement = match.element;
  return _locationForArgs(
      enclosingElement.context, enclosingElement.source, match.sourceRange);
}

/**
 * Create a Location based on an [engine.AstNode].
 */
Location newLocation_fromNode(engine.AstNode node) {
  engine.CompilationUnit unit =
      node.getAncestor((node) => node is engine.CompilationUnit);
  engine.CompilationUnitElement unitElement = unit.element;
  engine.AnalysisContext context = unitElement.context;
  engine.Source source = unitElement.source;
  engine.SourceRange range = new engine.SourceRange(node.offset, node.length);
  return _locationForArgs(context, source, range);
}

/**
 * Create a Location based on an [engine.CompilationUnit].
 */
Location newLocation_fromUnit(
    engine.CompilationUnit unit, engine.SourceRange range) {
  engine.CompilationUnitElement unitElement = unit.element;
  engine.AnalysisContext context = unitElement.context;
  engine.Source source = unitElement.source;
  return _locationForArgs(context, source, range);
}

/**
 * Construct based on an element from the analyzer engine.
 */
OverriddenMember newOverriddenMember_fromEngine(engine.Element member) {
  Element element = newElement_fromEngine(member);
  String className = member.enclosingElement.displayName;
  return new OverriddenMember(element, className);
}

/**
 * Construct based on a value from the search engine.
 */
SearchResult newSearchResult_fromMatch(engine.SearchMatch match) {
  SearchResultKind kind = newSearchResultKind_fromEngine(match.kind);
  Location location = newLocation_fromMatch(match);
  List<Element> path = _computePath(match.element);
  return new SearchResult(location, kind, !match.isResolved, path);
}

/**
 * Construct based on a value from the search engine.
 */
SearchResultKind newSearchResultKind_fromEngine(engine.MatchKind kind) {
  if (kind == engine.MatchKind.DECLARATION) {
    return SearchResultKind.DECLARATION;
  }
  if (kind == engine.MatchKind.READ) {
    return SearchResultKind.READ;
  }
  if (kind == engine.MatchKind.READ_WRITE) {
    return SearchResultKind.READ_WRITE;
  }
  if (kind == engine.MatchKind.WRITE) {
    return SearchResultKind.WRITE;
  }
  if (kind == engine.MatchKind.INVOCATION) {
    return SearchResultKind.INVOCATION;
  }
  if (kind == engine.MatchKind.REFERENCE) {
    return SearchResultKind.REFERENCE;
  }
  return SearchResultKind.UNKNOWN;
}

/**
 * Construct based on a SourceRange.
 */
SourceEdit newSourceEdit_range(engine.SourceRange range, String replacement,
    {String id}) {
  return new SourceEdit(range.offset, range.length, replacement, id: id);
}

List<Element> _computePath(engine.Element element) {
  List<Element> path = <Element>[];
  while (element != null) {
    path.add(newElement_fromEngine(element));
    // go up
    if (element is engine.PrefixElement) {
      // imports are library children, but they are physically in the unit
      engine.LibraryElement library = element.enclosingElement;
      element = library.definingCompilationUnit;
    } else {
      element = element.enclosingElement;
    }
  }
  return path;
}

String _getParametersString(engine.Element element) {
  // TODO(scheglov) expose the corresponding feature from ExecutableElement
  List<engine.ParameterElement> parameters;
  if (element is engine.ExecutableElement) {
    // valid getters don't have parameters
    if (element.kind == engine.ElementKind.GETTER &&
        element.parameters.isEmpty) {
      return null;
    }
    parameters = element.parameters;
  } else if (element is engine.FunctionTypeAliasElement) {
    parameters = element.parameters;
  } else {
    return null;
  }
  StringBuffer sb = new StringBuffer();
  String closeOptionalString = '';
  for (engine.ParameterElement parameter in parameters) {
    if (sb.isNotEmpty) {
      sb.write(', ');
    }
    if (closeOptionalString.isEmpty) {
      engine.ParameterKind kind = parameter.parameterKind;
      if (kind == engine.ParameterKind.NAMED) {
        sb.write('{');
        closeOptionalString = '}';
      }
      if (kind == engine.ParameterKind.POSITIONAL) {
        sb.write('[');
        closeOptionalString = ']';
      }
    }
    parameter.appendToWithoutDelimiters(sb);
  }
  sb.write(closeOptionalString);
  return '(' + sb.toString() + ')';
}

String _getTypeParametersString(engine.Element element) {
  List<engine.TypeParameterElement> typeParameters;
  if (element is engine.ClassElement) {
    typeParameters = element.typeParameters;
  } else if (element is engine.FunctionTypeAliasElement) {
    typeParameters = element.typeParameters;
  }
  if (typeParameters == null || typeParameters.isEmpty) {
    return null;
  }
  return '<${typeParameters.join(', ')}>';
}

bool _isAbstract(engine.Element element) {
  // TODO(scheglov) add isAbstract to Element API
  if (element is engine.ClassElement) {
    return element.isAbstract;
  }
  if (element is engine.MethodElement) {
    return element.isAbstract;
  }
  if (element is engine.PropertyAccessorElement) {
    return element.isAbstract;
  }
  return false;
}

bool _isConst(engine.Element element) {
  // TODO(scheglov) add isConst to Element API
  if (element is engine.ConstructorElement) {
    return element.isConst;
  }
  if (element is engine.VariableElement) {
    return element.isConst;
  }
  return false;
}

bool _isFinal(engine.Element element) {
  // TODO(scheglov) add isFinal to Element API
  if (element is engine.VariableElement) {
    return element.isFinal;
  }
  return false;
}

bool _isStatic(engine.Element element) {
  // TODO(scheglov) add isStatic to Element API
  if (element is engine.ExecutableElement) {
    return element.isStatic;
  }
  if (element is engine.PropertyInducingElement) {
    return element.isStatic;
  }
  return false;
}

/**
 * Creates a new [Location].
 */
Location _locationForArgs(engine.AnalysisContext context, engine.Source source,
    engine.SourceRange range) {
  int startLine = 0;
  int startColumn = 0;
  {
    engine.LineInfo lineInfo = context.getLineInfo(source);
    if (lineInfo != null) {
      engine.LineInfo_Location offsetLocation =
          lineInfo.getLocation(range.offset);
      startLine = offsetLocation.lineNumber;
      startColumn = offsetLocation.columnNumber;
    }
  }
  return new Location(
      source.fullName, range.offset, range.length, startLine, startColumn);
}
