import 'package:analyzer/dart/ast/ast.dart';
import 'package:ansicolor/ansicolor.dart';
import 'package:dart_mappable/dart_mappable.dart';

import '../elements/class/target_class_mapper_element.dart';
import '../elements/mapper_element.dart';
import '../utils.dart';
import 'copywith_generator.dart';
import 'decoder_generator.dart';
import 'encoder_generator.dart';
import 'equals_generator.dart';
import 'tostring_generator.dart';

abstract class MapperGenerator<T extends MapperElement> {
  final T target;

  MapperGenerator(this.target);

  Future<String> generate();
}

/// Generates code for a specific class
class ClassMapperGenerator extends MapperGenerator<TargetClassMapperElement> {
  ClassMapperGenerator(super.target);

  @override
  Future<String> generate() async {
    var output = StringBuffer();

    var encoderGen = EncoderGenerator(target);
    var decoderGen = DecoderGenerator(target);
    var stringifyGen = ToStringGenerator(target);
    var equalsGen = EqualsGenerator(target);
    var copyGen = CopyWithGenerator(target);

    var isSubClass = await target.isDiscriminatingSubclass;

    output.write(
        'class ${target.mapperName} extends ${isSubClass ? 'Sub' : ''}ClassMapperBase<${target.prefixedClassName}> {\n'
        '  ${target.mapperName}._();\n'
        '  static ${target.mapperName}? _instance;\n'
        '  static ${target.mapperName} ensureInitialized() {\n'
        '    if (_instance == null) {\n');

    var typesConfigs = target.typesConfigs;
    if (typesConfigs.isNotEmpty) {
      for (var t in typesConfigs) {
        output.write('      MapperBase.addType<$t>();\n');
      }
    }

    output.write(
        '      MapperContainer.globals.use(_instance = ${target.mapperName}._());\n');

    if (isSubClass) {
      var prefix =
          target.parent.prefixOfElement(target.superTarget!.annotatedElement);
      output.write(
          '      $prefix${target.superTarget!.mapperName}.ensureInitialized().addSubMapper(_instance!);\n');
    }

    var customMappers = await target.customMappers;
    if (customMappers.isNotEmpty) {
      for (var t in customMappers) {
        output.write('      MapperContainer.globals.use($t);\n');
      }
    }

    var linked = target.linkedElements;
    if (linked.isNotEmpty) {
      for (var l in linked.values) {
        output.write('      $l.ensureInitialized();\n');
      }
    }

    output.write('    }\n'
        '    return _instance!;\n'
        '  }\n'
        '  static T _guard<T>(T Function(MapperContainer) fn) {\n'
        '    ensureInitialized();\n'
        '    return fn(MapperContainer.globals);\n'
        '  }');

    output.write('\n'
        '  @override\n'
        "  final String id = '${target.uniqueId}';\n");

    if (target.typeParamsList.isNotEmpty) {
      output.write(decoderGen.generateTypeFactory());
    }

    output.write('\n');

    var fields = target.fields;

    for (var f in fields) {
      output.write(
          '  static ${f.staticType} _\$${f.field.name}(${target.prefixedClassName} v) => v.${f.field.name};\n');
      if (f.generic) {
        output.write(
            '  static dynamic _arg\$${f.field.name}${target.typeParamsDeclaration}(f) => f<${f.type}>();\n');
      }
    }

    output.write(
        '\n  @override\n  final Map<Symbol, Field<${target.prefixedClassName}, dynamic>> fields = const {\n');

    for (var f in fields) {
      output.write(
          "    #${f.field.name}: Field<${target.prefixedClassName}, ${f.staticType}>('${f.field.name}', _\$${f.field.name}${f.key}${f.mode}${f.opt}${await f.def}${f.arg}${await f.hook}),\n");
    }

    output.write('  };\n');

    if (target.ignoreNull) {
      output.write('  @override\n  final bool ignoreNull = true;\n');
    }

    if (isSubClass) {
      output.write(await decoderGen.generateDiscriminatorFields());
      output.write(decoderGen.generateInheritOverride());
    }

    output.write(await decoderGen.generateInstantiateMethod());

    if (target.shouldGenerate(GenerateMethods.decode)) {
      output.write('\n'
          '  static ${target.prefixedDecodingClassName}${target.typeParams} fromMap${target.typeParamsDeclaration}(Map<String, dynamic> map) {\n'
          '    return _guard((c) => c.fromMap<${target.prefixedDecodingClassName}${target.typeParams}>(map));\n'
          '  }\n'
          '  static ${target.prefixedDecodingClassName}${target.typeParams} fromJson${target.typeParamsDeclaration}(String json) {\n'
          '    return _guard((c) => c.fromJson<${target.prefixedDecodingClassName}${target.typeParams}>(json));\n'
          '  }\n');
    }

    output.write('}\n\n');

    if (target.generateAsMixin) {
      await _checkMixinUsed();

      output.write(
          'mixin ${target.uniqueClassName}Mappable${target.typeParamsDeclaration} {\n');
      output.writeAll([
        encoderGen.generateEncoderMixin(),
        copyGen.generateCopyWithMixin(),
        stringifyGen.generateToStringMixin(),
        equalsGen.generateEqualsMixin(),
      ]);
      output.write('}');
    } else {
      output.write(
          'extension ${target.mapperName}Extension${target.typeParamsDeclaration} on ${target.prefixedClassName}${target.typeParams} {\n');
      output.writeAll([
        encoderGen.generateEncoderExtensions(),
        copyGen.generateCopyWithExtension(),
      ]);
      output.write('}');
    }

    output.writeAll([
      copyGen.generateCopyWithClasses(),
    ]);

    return output.toString();
  }

  Future<void> _checkMixinUsed() async {
    var className = target.className;
    var mixinName = '${target.uniqueClassName}Mappable';

    void warnUnusedMixin(String classCode) {
      var pen = AnsiPen()..xterm(3);
      var pen2 = AnsiPen()..xterm(2);
      print(pen('\nClass \'$className\' is configured to generate a mixin '
          '\'$mixinName\'.\nIt is required that you use this mixin on this class.\n'
          'Otherwise your code might behave faulty or won\'t compile.\n\n'
          'To solve this, change your class signature to:\n'));
      print('${pen2(classCode)}\n');
    }

    var node = await target.element.getNode();
    if (node is ClassDeclaration) {
      var hasCopyWithMixin =
          node.withClause?.mixinTypes.any((t) => t.name.name == mixinName) ??
              false;

      if (!hasCopyWithMixin) {
        var classDeclarationSource = 'class $className';
        if (node.abstractKeyword != null) {
          classDeclarationSource = 'abstract $classDeclarationSource';
        }
        if (node.extendsClause != null) {
          classDeclarationSource += ' ${node.extendsClause!.toSource()}';
        }
        if (node.withClause != null) {
          classDeclarationSource +=
              ' ${node.withClause!.toSource().replaceFirst('with', 'with $mixinName,')}';
        } else {
          classDeclarationSource += ' with $mixinName';
        }
        if (node.implementsClause != null) {
          classDeclarationSource += ' ${node.implementsClause!.toSource()}';
        }
        warnUnusedMixin(classDeclarationSource);
      }
    } else if (node is ClassTypeAlias) {
      var hasCopyWithMixin =
          node.withClause.mixinTypes.any((t) => t.name.name == mixinName);

      if (!hasCopyWithMixin) {
        var classDeclarationSource = 'class $className';
        if (node.abstractKeyword != null) {
          classDeclarationSource = 'abstract $classDeclarationSource';
        }
        classDeclarationSource +=
            ' ${node.withClause.toSource().replaceFirst('with', 'with $mixinName,')}';

        if (node.implementsClause != null) {
          classDeclarationSource += ' ${node.implementsClause!.toSource()}';
        }
        warnUnusedMixin(classDeclarationSource);
      }
    }
  }
}
