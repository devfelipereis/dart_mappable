import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:dart_mappable/dart_mappable.dart'
    show GenerateMethods, InitializerScope;
import 'package:glob/glob.dart';
import 'package:path/path.dart';

import 'builder_options.dart';
import 'elements/class/alias_class_mapper_element.dart';
import 'elements/class/class_mapper_element.dart';
import 'elements/class/dependent_class_mapper_element.dart';
import 'elements/class/factory_constructor_mapper_element.dart';
import 'elements/class/none_class_mapper_element.dart';
import 'elements/class/target_class_mapper_element.dart';
import 'elements/enum/dependent_enum_mapper_element.dart';
import 'elements/enum/target_enum_mapper_element.dart';
import 'elements/mapper_element.dart';
import 'utils.dart';

class MapperElementGroup {
  MapperElementGroup(this.library, this.options) {
    var names = <String, Element>{};
    for (var i in library.libraryImports) {
      names.addAll(i.namespace.definedNames);
    }
    names.addAll(library.publicNamespace.definedNames);

    for (var name in names.entries) {
      if (name.key.contains('.')) {
        prefixes[name.value] = name.key.substring(0, name.key.indexOf('.') + 1);
      } else {
        prefixes[name.value] = '';
      }
    }
  }

  final LibraryElement library;
  final MappableOptions options;

  Map<Element, String> prefixes = {};
  Map<InterfaceElement, MapperElement> targets = {};

  late String packageName;
  bool isPackage(Uri lib) {
    if (lib.scheme == 'package' || lib.scheme == 'asset') {
      return lib.pathSegments.first == packageName;
    } else {
      return false;
    }
  }

  Future<T> addMapper<T extends MapperElement>(T mapper) async {
    await mapper.init();
    return targets[mapper.element] = mapper;
  }

  Future<void> analyze() async {
    var elements = elementsOf(library);

    for (var element in elements) {
      if (element.isPrivate || getMapperForElement(element) != null) {
        continue;
      }

      if (classChecker.hasAnnotationOf(element)) {
        if (element is ClassElement) {
          await addMapper(TargetClassMapperElement(this, element, options));

          for (var c in element.constructors) {
            if (c.isFactory &&
                c.redirectedConstructor != null &&
                classChecker.hasAnnotationOf(c)) {
              // Disable copy methods for factory elements.
              var subOptions = options.apply(MappableOptions(
                  generateMethods:
                      ~(~(options.generateMethods ?? GenerateMethods.all) |
                          GenerateMethods.copy)));

              await addMapper(
                  FactoryConstructorMapperElement(this, c, subOptions));
            }
          }
        } else if (element is TypeAliasElement &&
            element.aliasedType.element is ClassElement) {
          await addMapper(AliasClassMapperElement(this, element,
              element.aliasedType.element as ClassElement, options));
        }
      } else if (element is EnumElement &&
          enumChecker.hasAnnotationOf(element)) {
        await addMapper(TargetEnumMapperElement(this, element, options));
      }
    }

    for (var target in targets.values.toList()) {
      await analyzeElement(target);
    }
  }

  Future<void> analyzeElement(MapperElement element) async {
    if (element is! ClassMapperElement) return;

    ClassElement? getElementFor(InterfaceType? t) {
      if (t != null && !t.isDartCoreObject && t.element is ClassElement) {
        return t.element as ClassElement;
      }
      return null;
    }

    if (element.extendsElement == null) {
      var superElement = getElementFor(element.element.supertype);
      if (superElement != null) {
        ClassMapperElement superTarget =
            await getOrAddMapperForElement(superElement, orNone: true)
                as ClassMapperElement;

        element.extendsElement = superTarget;
        if (!superTarget.subElements.contains(element)) {
          superTarget.subElements.add(element);
        }
      }
    }
    if (element.interfaceElements.isEmpty) {
      for (var interface in element.element.interfaces) {
        var interfaceElement = getElementFor(interface);
        if (interfaceElement != null) {
          ClassMapperElement interfaceTarget =
              await getOrAddMapperForElement(interfaceElement, orNone: true)
                  as ClassMapperElement;

          element.interfaceElements.add(interfaceTarget);
          if (!interfaceTarget.subElements.contains(element)) {
            interfaceTarget.subElements.add(element);
          }
        }
      }
    }

    for (var elem in element.getSubClasses()) {
      ClassMapperElement? subMapper =
          await getOrAddMapperForElement(elem) as ClassMapperElement?;

      if (subMapper == null) {
        throw 'Cannot include subclass ${elem.getDisplayString(withNullability: false)}, '
            'since it has no generated mapper.';
      }

      if (subMapper.element.supertype?.element == element.element) {
        subMapper.extendsElement = element;
      } else if (subMapper.element.interfaces
          .map((i) => i.element)
          .contains(element.element)) {
        if (!subMapper.interfaceElements.contains(element)) {
          subMapper.interfaceElements.add(element);
        }
      } else {
        throw 'Cannot determine supertype ${element.className} of ${subMapper.className}.';
      }
      if (!element.subElements.contains(subMapper)) {
        element.subElements.add(subMapper);
      }
    }

    Future<void> checkType(DartType t) async {
      var e = t.element;
      await getOrAddMapperForElement(e);
      if (t is ParameterizedType) {
        for (var arg in t.typeArguments) {
          await checkType(arg);
        }
      }
    }

    for (var param in element.params) {
      await checkType(param.parameter.type);
    }

    for (var param in element.element.typeParameters) {
      if (param.bound != null) {
        await getOrAddMapperForElement(param.bound!.element);
      }
    }
  }

  MapperElement? getMapperForElement(Element? e) {
    return targets[e];
  }

  Future<MapperElement?> getOrAddMapperForElement(Element? e,
      {bool orNone = false}) async {
    var m = getMapperForElement(e);
    if (m != null) {
      return m;
    } else if (e is ClassElement && classChecker.hasAnnotationOf(e)) {
      var m = await addMapper(DependentClassMapperElement(this, e, options));
      await analyzeElement(m);
      return m;
    } else if (e is ClassElement && orNone) {
      var m = await addMapper(NoneClassMapperElement(this, e, options));
      await analyzeElement(m);
      return m;
    } else if (e is EnumElement && enumChecker.hasAnnotationOf(e)) {
      var m = await addMapper(DependentEnumMapperElement(this, e, options));
      return m;
    } else {
      return null;
    }
  }

  String prefixOfElement(Element elem) {
    return prefixes[elem] ?? '';
  }

  String prefixedType(DartType t,
      {bool withNullability = true, bool resolveBounds = false}) {
    if (t is TypeParameterType) {
      if (resolveBounds) {
        return prefixedType(t.bound, resolveBounds: resolveBounds);
      }
      return t.element.name;
    } else if (t is! InterfaceType) {
      return t.getDisplayString(withNullability: withNullability);
    }

    var typeArgs = '';
    if (t.typeArguments.isNotEmpty) {
      typeArgs =
          '<${t.typeArguments.map((t) => prefixedType(t, resolveBounds: resolveBounds)).join(', ')}>';
    }

    var type = '${t.element.name}$typeArgs';

    if (withNullability && t.nullabilitySuffix == NullabilitySuffix.question) {
      type += '?';
    }

    return '${prefixOfElement(t.element)}$type';
  }

  /// All of the declared classes and enums in this library.
  Iterable<Element> elementsOf(LibraryElement element) sync* {
    for (var cu in element.units) {
      yield* cu.enums;
      yield* cu.classes;
      yield* cu.typeAliases;
    }
  }

  Future<List<MapEntry<LibraryElement, Iterable<Element>>>> discover(
      BuildStep buildStep) async {
    var scope = options.initializerScope;

    bool isMapper(Element e) {
      return (e is ClassElement && classChecker.hasAnnotationOf(e)) ||
          (e is EnumElement && enumChecker.hasAnnotationOf(e));
    }

    if (scope == InitializerScope.package ||
        scope == InitializerScope.directory) {
      var glob = scope == InitializerScope.package
          ? Glob('**.dart')
          : Glob('${dirname(buildStep.inputId.path)}/**.dart');
      return await buildStep
          .findAssets(glob)
          .asyncMap((id) async {
            if (await buildStep.resolver.isLibrary(id)) {
              return buildStep.resolver.libraryFor(id);
            }
            return null;
          })
          .where((l) => l != null)
          .map((lib) => MapEntry(lib!, lib.topLevelElements.where(isMapper)))
          .where((e) => e.value.isNotEmpty)
          .toList();
    } else if (scope == InitializerScope.library) {
      var lib = await buildStep.inputLibrary;

      return [MapEntry(lib, lib.topLevelElements.where(isMapper))];
    }

    return [];
  }
}
