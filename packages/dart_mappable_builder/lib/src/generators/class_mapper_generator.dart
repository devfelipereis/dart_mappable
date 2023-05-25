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
  final T element;

  MapperGenerator(this.element);

  Future<String> generate();
}

/// Generates code for a specific class
class ClassMapperGenerator extends MapperGenerator<TargetClassMapperElement> {
  ClassMapperGenerator(super.element);

  @override
  Future<String> generate() async {
    var output = StringBuffer();

    var encoderGen = EncoderGenerator(element);
    var decoderGen = DecoderGenerator(element);
    var stringifyGen = ToStringGenerator(element);
    var equalsGen = EqualsGenerator(element);
    var copyGen = CopyWithGenerator(element);

    output.write('''
      class ${element.mapperName} extends ${element.isDiscriminatingSubclass ? 'Sub' : ''}ClassMapperBase<${element.prefixedClassName}> {
        ${element.mapperName}._();
        
        static ${element.mapperName}? _instance;
        static ${element.mapperName} ensureInitialized() {
          if (_instance == null) {   
    ''');

    var typesConfigs = element.typesConfigs;
    if (typesConfigs.isNotEmpty) {
      for (var t in typesConfigs) {
        output.write('      MapperBase.addType<$t>();\n');
      }
    }

    output.write(
        '      MapperContainer.globals.use(_instance = ${element.mapperName}._());\n');

    if (element.isDiscriminatingSubclass) {
      var s = element.superElement!;
      var prefix = element.parent.prefixOfElement(s.annotatedElement);
      output.write(
          '      $prefix${s.mapperName}.ensureInitialized().addSubMapper(_instance!);\n');
    } else if (element.isSubclass) {
      var s = element.superElement!;
      var prefix = element.parent.prefixOfElement(s.annotatedElement);
      output.write('      $prefix${s.mapperName}.ensureInitialized();\n');
    }

    var customMappers = element.customMappers;
    if (customMappers.isNotEmpty) {
      for (var t in customMappers) {
        output.write('      MapperContainer.globals.use($t);\n');
      }
    }

    var linked = element.linkedElements;
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
        "  final String id = '${element.uniqueId}';\n");

    if (element.typeParamsList.isNotEmpty) {
      output.write(decoderGen.generateTypeFactory());
    }

    output.write('\n');

    var fields = element.fields;

    for (var f in fields) {
      output.write(
          '  static ${f.staticGetterType} _\$${f.field.name}(${element.prefixedClassName} v) => v.${f.field.name};\n');
      if (f.generic) {
        output.write(
            '  static dynamic _arg\$${f.field.name}${element.typeParamsDeclaration}(f) => f<${f.argType}>();\n');
      }
      output.write(
          "  static const Field<${element.prefixedClassName}, ${f.staticArgType}> _f\$${f.field.name} = Field('${f.field.name}', _\$${f.field.name}${f.key}${f.mode}${f.opt}${await f.def}${f.arg}${await f.hook});\n");
    }

    output.write(
        '\n  @override\n  final Map<Symbol, Field<${element.prefixedClassName}, dynamic>> fields = const {\n');

    for (var f in fields) {
      output.write('    #${f.field.name}: _f\$${f.field.name},\n');
    }

    output.write('  };\n');

    if (element.ignoreNull) {
      output.write('  @override\n  final bool ignoreNull = true;\n');
    }

    if (element.isDiscriminatingSubclass) {
      output.write(await decoderGen.generateDiscriminatorFields());
      output.write(decoderGen.generateInheritOverride());
    }

    output.write(await decoderGen.generateInstantiateMethod());

    var fromJsonName = element.options.renameMethods['fromJson'] ?? 'fromJson';
    var fromMapName = element.options.renameMethods['fromMap'] ?? 'fromMap';

    if (element.shouldGenerate(GenerateMethods.decode)) {
      output.write('\n'
          '  static ${element.prefixedDecodingClassName}${element.typeParams} $fromMapName${element.typeParamsDeclaration}(Map<String, dynamic> map) {\n'
          '    return _guard((c) => c.fromMap<${element.prefixedDecodingClassName}${element.typeParams}>(map));\n'
          '  }\n'
          '  static ${element.prefixedDecodingClassName}${element.typeParams} $fromJsonName${element.typeParamsDeclaration}(String json) {\n'
          '    return _guard((c) => c.fromJson<${element.prefixedDecodingClassName}${element.typeParams}>(json));\n'
          '  }\n');
    }

    output.write('}\n\n');

    if (element.generateAsMixin) {
      await _checkMixinUsed();

      output.write(
          'mixin ${element.uniqueClassName}Mappable${element.typeParamsDeclaration} {\n');
      output.writeAll([
        encoderGen.generateEncoderMixin(),
        copyGen.generateCopyWithMixin(),
        stringifyGen.generateToStringMixin(),
        equalsGen.generateEqualsMixin(),
      ]);
      output.write('}');
    } else {
      output.write(
          'extension ${element.mapperName}Extension${element.typeParamsDeclaration} on ${element.prefixedClassName}${element.typeParams} {\n');
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
    var className = element.className;
    var mixinName = '${element.uniqueClassName}Mappable';

    void warnUnusedMixin(String classCode) {
      var pen = AnsiPen()..xterm(3);
      var pen2 = AnsiPen()..xterm(2);
      print(pen('\nClass \'$className\' is configured to generate a mixin '
          '\'$mixinName\'.\nIt is required that you use this mixin on this class.\n'
          'Otherwise your code might behave faulty or won\'t compile.\n\n'
          'To solve this, change your class signature to:\n'));
      print('${pen2(classCode)}\n');
    }

    var node = await element.element.getNode();
    if (node is ClassDeclaration) {
      var hasCopyWithMixin = node.withClause?.mixinTypes.any((t) {
            // ignore: deprecated_member_use
            return t.name.name == mixinName;
          }) ??
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
      var hasCopyWithMixin = node.withClause.mixinTypes.any((t) {
        // ignore: deprecated_member_use
        return t.name.name == mixinName;
      });

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
