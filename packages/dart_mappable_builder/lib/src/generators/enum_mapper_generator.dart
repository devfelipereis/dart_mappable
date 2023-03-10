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
    bool hasAllStringValues = target.mode == ValuesMode.named;
    bool useCustomProperty = target.mode == ValuesMode.customProperty;

    var values = await Future.wait(target.element.fields //
        .where((f) => f.isEnumConstant)
        .mapIndexed((i, f) async {
      if (valueChecker.hasAnnotationOf(f)) {
        hasAllStringValues = false;
        return MapEntry(f.name, await getAnnotatedValue(f));
      } else {
        if (target.mode == ValuesMode.named) {
          return MapEntry(f.name, "'${target.caseStyle.transform(f.name)}'");
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
        'class ${target.mapperName} extends EnumMapper<${target.prefixedClassName}> {\n'
        '  static MapperContainer container = MapperContainer(\n'
        '    mappers: {${target.mapperName}()},\n'
        '  );\n\n'
        '  static final fromValue = container.fromValue<${target.prefixedClassName}>;\n\n'
        '  $decode '
        '  $encode '
        '}\n\n'
        'extension ${target.mapperName}Extension on ${target.prefixedClassName} {\n'
        '  ${hasAllStringValues ? 'String' : 'dynamic'} toValue() => ${target.mapperName}.container.toValue(this)${hasAllStringValues ? ' as String' : ''};\n'
        '}';
  }

  String _generateDefaultDecode(List<MapEntry<String, Object>> values) {
    return '  @override\n'
        '  ${target.prefixedClassName} decode(dynamic value) {\n'
        '    switch (value) {\n'
        '      ${values.map((v) => "case ${v.value}: return ${target.prefixedClassName}.${v.key};").join("\n      ")}\n'
        '      default: ${_generateDefaultCase()}\n'
        '    }\n'
        '  }\n\n';
  }

  String _generateDefaultEncode(List<MapEntry<String, Object>> values) {
    return '  @override\n'
        '  dynamic encode(${target.prefixedClassName} self) {\n'
        '    switch (self) {\n'
        '      ${values.map((v) => "case ${target.prefixedClassName}.${v.key}: return ${v.value};").join("\n      ")}\n'
        '    }\n'
        '  }\n';
  }

  String _generateEncodeByCustomProperty() {
    return '  @override\n'
        '  dynamic encode(${target.prefixedClassName} self) {\n'
        '    return self.token;\n'
        '  }\n';
  }

  String _generateDecodeByCustomProperty() {
    return '  @override\n'
        '  ${target.prefixedClassName} decode(dynamic value) {\n'
        '    return ${target.prefixedClassName}.values.firstWhere(\n'
        '      (element) => element.${target.customProperty} == value,\n'
        '      orElse: () => throw MapperException.unknownEnumValue(value),\n'
        '    );\n'
        '  }\n\n';
  }

  String _generateDefaultCase() {
    if (target.defaultValue != null) {
      return 'return ${target.prefixedClassName}.values[${target.defaultValue}];';
    }
    return 'throw MapperException.unknownEnumValue(value);';
  }

  Future<String> getAnnotatedValue(FieldElement f) async {
    var node = await getResolvedAnnotationNode(f, MappableValue, 0);
    return node!.toSource();
  }
}
