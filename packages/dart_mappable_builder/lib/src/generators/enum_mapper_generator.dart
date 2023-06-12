import 'package:analyzer/dart/element/element.dart';
import 'package:collection/collection.dart';
import 'package:dart_mappable/dart_mappable.dart';

import '../elements/enum/target_enum_mapper_element.dart';
import '../utils.dart';
import 'class_mapper_generator.dart';

/// Generates code for a specific enum
class EnumMapperGenerator extends MapperGenerator<TargetEnumMapperElement> {
  EnumMapperGenerator(super.element);

  @override
  Future<String> generate() async {
    bool hasAllStringValues = element.mode == ValuesMode.named;
    bool useCustomProperty = element.mode == ValuesMode.customProperty;
    var values = await Future.wait(element.element.fields //
        .where((f) => f.isEnumConstant)
        .mapIndexed((i, f) async {
      if (enumValueChecker.hasAnnotationOf(f)) {
        hasAllStringValues = false;
        return MapEntry(f.name, await getAnnotatedValue(f));
      } else {
        if (element.mode == ValuesMode.named) {
          return MapEntry(f.name, "'${element.caseStyle.transform(f.name)}'");
        } else {
          return MapEntry(f.name, i);
        }
      }
    }));

    final decode = useCustomProperty
        ? _generateDecodeByCustomProperty()
        : _generateDefaultDecode(values);
    final encode = useCustomProperty
        ? _generateEncodeByCustomProperty()
        : _generateDefaultEncode(values);

    return ''
        'class ${element.mapperName} extends EnumMapper<${element.prefixedClassName}> {\n'
        '  ${element.mapperName}._();\n'
        '  static ${element.mapperName}? _instance;\n'
        '  static ${element.mapperName} ensureInitialized() {\n'
        '    if (_instance == null) {\n'
        '      MapperContainer.globals.use(_instance = ${element.mapperName}._());\n'
        '    }\n'
        '    return _instance!;\n'
        '  }\n\n'
        '  static ${element.prefixedClassName} fromValue(dynamic value) {\n'
        '    ensureInitialized();\n'
        '    return MapperContainer.globals.fromValue(value);\n'
        '  }\n\n'
        '  $decode '
        '  $encode '
        '}\n\n'
        'extension ${element.mapperName}Extension on ${element.prefixedClassName} {\n'
        '  ${hasAllStringValues ? 'String' : 'dynamic'} toValue() {\n'
        '    ${element.mapperName}.ensureInitialized();\n'
        '    return MapperContainer.globals.toValue(this)${hasAllStringValues ? ' as String' : ''};\n'
        '  }\n'
        '}';
  }

  String _generateDefaultDecode(List<MapEntry<String, Object>> values) {
    return '  @override\n'
        '  ${element.prefixedClassName} decode(dynamic value) {\n'
        '    switch (value) {\n'
        '      ${values.map((v) => "case ${v.value}: return ${element.prefixedClassName}.${v.key};").join("\n      ")}\n'
        '      default: ${_generateDefaultCase()}\n'
        '    }\n'
        '  }\n\n';
  }

  String _generateDefaultEncode(List<MapEntry<String, Object>> values) {
    return '  @override\n'
        '  dynamic encode(${element.prefixedClassName} self) {\n'
        '    switch (self) {\n'
        '      ${values.map((v) => "case ${element.prefixedClassName}.${v.key}: return ${v.value};").join("\n      ")}\n'
        '    }\n'
        '  }\n';
  }

  String _generateEncodeByCustomProperty() {
    return '  @override\n'
        '  dynamic encode(${element.prefixedClassName} self) {\n'
        '    return self.token;\n'
        '  }\n';
  }

  String _generateDecodeByCustomProperty() {
    return '  @override\n'
        '  ${element.prefixedClassName} decode(dynamic value) {\n'
        '    return ${element.prefixedClassName}.values.firstWhere(\n'
        '      (element) => element.${element.customProperty} == value,\n'
        '      orElse: () => throw MapperException.unknownEnumValue(value),\n'
        '    );\n'
        '  }\n\n';
  }

  String _generateDefaultCase() {
    if (element.defaultValue != null) {
      return 'return ${element.prefixedClassName}.values[${element.defaultValue}];';
    }
    return 'throw MapperException.unknownEnumValue(value);';
  }

  Future<String> getAnnotatedValue(FieldElement f) async {
    var node = await getResolvedAnnotationNode(f, MappableValue, 0);
    return node!.toSource();
  }
}
