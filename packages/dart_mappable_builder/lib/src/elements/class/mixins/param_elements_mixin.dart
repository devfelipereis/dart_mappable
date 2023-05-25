import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:collection/collection.dart';

import '../../../utils.dart';
import '../../mapper_element.dart';
import '../../param/mapper_param_element.dart';
import '../class_mapper_element.dart';

mixin ParamElementsMixin on MapperElement<ClassElement> {
  ConstructorElement? get constructor;
  AstNode? get constructorNode;
  ClassMapperElement? get extendsElement;
  List<ClassMapperElement> get interfaceElements;
  ClassMapperElement? get superElement;

  late List<MapperParamElement> params = () {
    var params = <MapperParamElement>[];
    if (constructor == null) {
      return params;
    }

    for (var param in constructor!.parameters) {
      params.add(getParameterConfig(param));
    }

    var unresolved = params.whereType<UnresolvedParamElement>();
    if (unresolved.isNotEmpty) {
      print('\nClass $className defines constructor parameters that could not '
          'be resolved against any field or getter in the class.\nThis won\'t '
          'break your code, but may lead to unexpected behaviour when '
          'serializing this class. Also \'.copyWith()\' won\'t work on these '
          'parameters.\n\nThe following problematic parameters were detected:\n'
          '${unresolved.map((p) => '- ${p.parameter.name}: ${p.message}').join('\n')}\n\n'
          'Please make sure every constructor parameter can be resolved to a '
          'field or getter.\nIf you think this is a bug with dart_mappable '
          'and the listed parameters should be resolved correctly, please file '
          'an issue here: https://github.com/schultek/dart_mappable/issues\n');
    }

    return params;
  }();

  MapperParamElement getParameterConfig(ParameterElement param) {
    var dec = param.declaration;

    if (dec is FieldFormalParameterElement) {
      return FieldParamElement(param, dec.field!, getSuperField(dec.field!));
    }

    if (dec is SuperFormalParameterElement) {
      if (dec.superConstructorParameter == null) {
        return UnresolvedParamElement(
          param,
          'Cannot resolve formal super parameter',
        );
      }
      var superConfig =
          superElement!.getParameterConfig(dec.superConstructorParameter!);
      if (superConfig is UnresolvedParamElement) {
        return UnresolvedParamElement(
          param,
          'Problem in super constructor: ${superConfig.message}',
        );
      } else {
        return SuperParamElement(param, superConfig);
      }
    }

    ParameterElement? superParameter = _findSuperParameter(param);
    if (superParameter != null) {
      var superConfig = superElement!.getParameterConfig(superParameter);
      if (superConfig is UnresolvedParamElement) {
        return UnresolvedParamElement(
          param,
          'Problem in super constructor: ${superConfig.message}',
        );
      } else {
        return SuperParamElement(param, superConfig);
      }
    }

    var getter = element.lookUpGetter(param.name, parent.library);
    if (getter != null) {
      var getterType = getter.type.returnType;
      if (getterType == param.type) {
        return FieldParamElement(
            param, getter.variable, getSuperField(getter.variable));
      }

      if (!getterType.isNullable &&
          param.type.isNullable &&
          getterType.getDisplayString(withNullability: false) ==
              param.type.getDisplayString(withNullability: false)) {
        return FieldParamElement(
            param, getter.variable, getSuperField(getter.variable));
      }

      return UnresolvedParamElement(
        param,
        'Found getter or field related to this parameter, but it has a '
        'non-matching type. Expected ${param.type} but got ${getter.type.returnType}.',
      );
    }

    return UnresolvedParamElement(
      param,
      'Cannot find field or getter related to this parameter.',
    );
  }

  ParameterElement? _findSuperParameter(ParameterElement param) {
    if (superElement == null) return null;

    var node = constructorNode;
    if (node is ConstructorDeclaration && node.initializers.isNotEmpty) {
      var last = node.initializers.last;
      if (last is SuperConstructorInvocation) {
        var superConstructorName = last.constructorName?.name ?? '';
        var superConstructor = superElement!.element.constructors
            .firstWhere((c) => c.name == superConstructorName);

        var args = last.argumentList.arguments;
        var i = 0;
        for (var arg in args) {
          if (arg is SimpleIdentifier) {
            if (arg.name == param.name) {
              return superConstructor.parameters[i];
            }
          } else if (arg is NamedExpression) {
            var exp = arg.expression;
            if (exp is SimpleIdentifier) {
              if (exp.name == param.name) {
                var superName = arg.name.label.name;
                return superConstructor.parameters
                    .firstWhere((p) => p.isNamed && p.name == superName);
              }
            }
          }
          i++;
        }
      }
    }
    return null;
  }

  PropertyInducingElement? getSuperField(PropertyInducingElement field) {
    return [if (extendsElement != null) extendsElement!, ...interfaceElements]
        .expand((e) => e.fields)
        .where((f) => f.field.name == field.name)
        .map((f) => f.field)
        .firstOrNull;
  }
}
