import 'package:dart_mappable/dart_mappable.dart';

import '../elements/enum/target_enum_mapper_element.dart';
import 'generator.dart';

/// Generates code for a specific enum.
class EnumMapperGenerator extends MapperGenerator<TargetEnumMapperElement> {
  EnumMapperGenerator(super.element);

  @override
  Future<String> generate() async {
    bool useCustomProperty = element.mode == ValuesMode.customProperty;
    final decode = useCustomProperty
        ? _generateDecodeByCustomProperty()
        : _generateDefaultDecode(element.values);
    final encode = useCustomProperty
        ? _generateEncodeByCustomProperty()
        : _generateDefaultEncode(element.values);

    return '''
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
        extension ${element.mapperName}Extension on ${element.prefixedClassName} {
          ${element.hasAllStringValues ? 'String' : 'dynamic'} toValue() {
            ${element.mapperName}.ensureInitialized();
            return MapperContainer.globals.toValue<${element.prefixedClassName}>(this)${element.hasAllStringValues ? ' as String' : ''};
          }
        }
      ''';

      
  }

  String _generateDefaultCase() {
    if (element.defaultValue != null) {
      return 'return ${element.prefixedClassName}.values[${element.defaultValue}];';
    }
    return 'throw MapperException.unknownEnumValue(value);';
  } 

  String _generateDefaultDecode(List<MapEntry<String, dynamic>> values) {
    return '  @override\n'
        '  ${element.prefixedClassName} decode(dynamic value) {\n'
        '    switch (value) {\n'
        '      ${values.map((v) => "case ${v.value}: return ${element.prefixedClassName}.${v.key};").join("\n      ")}\n'
        '      default: ${_generateDefaultCase()}\n'
        '    }\n'
        '  }\n\n';
  }

  String _generateDefaultEncode(List<MapEntry<String, dynamic>> values) {
    return '  dynamic encode(${element.prefixedClassName} self) {\n'
        '    switch (self) {\n'
        '      ${values.map((v) => "case ${element.prefixedClassName}.${v.key}: return ${v.value};").join("\n      ")}\n'
        '    }\n'
        '  }\n';
  }

  String _generateEncodeByCustomProperty() {
    return '  dynamic encode(${element.prefixedClassName} self) {\n'
        '    return self.token;\n'
        '  }\n';
  }

  String _generateDecodeByCustomProperty() {
    return '  @override\n'
        '  ${element.prefixedClassName} decode(dynamic value) {\n'
        '    return ${element.prefixedClassName}.values.firstWhere((element) => element.${element.customProperty} == value);\n'
        '  }\n\n';
  }

  String _generateDefaultDecode(List<MapEntry<String, dynamic>> values) {
    return '  @override\n'
        '  ${element.prefixedClassName} decode(dynamic value) {\n'
        '    switch (value) {\n'
        '      ${values.map((v) => "case ${v.value}: return ${element.prefixedClassName}.${v.key};").join("\n      ")}\n'
        '      default: ${_generateDefaultCase()}\n'
        '    }\n'
        '  }\n\n';
  }

  String _generateDefaultEncode(List<MapEntry<String, dynamic>> values) {
    return '  dynamic encode(${element.prefixedClassName} self) {\n'
        '    switch (self) {\n'
        '      ${values.map((v) => "case ${element.prefixedClassName}.${v.key}: return ${v.value};").join("\n      ")}\n'
        '    }\n'
        '  }\n';
  }

  String _generateEncodeByCustomProperty() {
    return '  dynamic encode(${element.prefixedClassName} self) {\n'
        '    return self.token;\n'
        '  }\n';
  }

  String _generateDecodeByCustomProperty() {
    return '  @override\n'
        '  ${element.prefixedClassName} decode(dynamic value) {\n'
        '    return ${element.prefixedClassName}.values.firstWhere((element) => element.${element.customProperty} == value);\n'
        '  }\n\n';
  }

  String _generateDefaultDecode(List<MapEntry<String, dynamic>> values) {
    return '  @override\n'
        '  ${element.prefixedClassName} decode(dynamic value) {\n'
        '    switch (value) {\n'
        '      ${values.map((v) => "case ${v.value}: return ${element.prefixedClassName}.${v.key};").join("\n      ")}\n'
        '      default: ${_generateDefaultCase()}\n'
        '    }\n'
        '  }\n\n';
  }

  String _generateDefaultEncode(List<MapEntry<String, dynamic>> values) {
    return '  dynamic encode(${element.prefixedClassName} self) {\n'
        '    switch (self) {\n'
        '      ${values.map((v) => "case ${element.prefixedClassName}.${v.key}: return ${v.value};").join("\n      ")}\n'
        '    }\n'
        '  }\n';
  }

  String _generateEncodeByCustomProperty() {
    return '  dynamic encode(${element.prefixedClassName} self) {\n'
        '    return self.token;\n'
        '  }\n';
  }

  String _generateDecodeByCustomProperty() {
    return '  @override\n'
        '  ${element.prefixedClassName} decode(dynamic value) {\n'
        '    return ${element.prefixedClassName}.values.firstWhere((element) => element.${element.customProperty} == value);\n'
        '  }\n\n';
  }
}
