import 'package:crimson/crimson.dart';
import 'package:type_plus/type_plus.dart';

import '../annotations.dart';
import '../internals/json_object.dart';
import '../internals/mapping_context.dart';
import '../mapper_utils.dart';
import 'mapper_base.dart';

class DecodingData<T extends Object> {
  DecodingData(this.context, this.mapper);

  final DecodingContext<JsonObject> context;
  final ClassMapperBase<T> mapper;

  JsonObject get value => context.value;
  bool _wasLoaded = false;
  final Map<Symbol, dynamic> _loadedValues = {};

  V get<V>(Symbol name) {
    if (_wasLoaded) {
      if (_loadedValues.containsKey(name)) {
        return _loadedValues[name] as V;
      } else {
        return mapper.fields[name]!.decodeValue(context, null) as V;
      }
    }
    return mapper.fields[name]!.decode(context);
  }

  void load() {
    var iterator = context.value.iterator;
    int key = 0;

    while ((key = iterator.nextKey()) != -1) {
      var f = mapper.fieldsByKey[key];
      if (f == null || f.mode == FieldMode.member) continue;

      _loadedValues[Symbol(f.name)] = f.decodeValue(context, iterator.current);
    }
    _wasLoaded = true;
  }
}

abstract class SubClassMapperBase<T extends Object> extends ClassMapperBase<T> {
  SubClassMapperBase() {
    superMapper.addSubMapper(this);
  }

  String get discriminatorKey;
  dynamic get discriminatorValue;
  ClassMapperBase get superMapper;

  bool canDecode(DecodingContext<JsonObject> context) {
    var value = discriminatorValue;
    if (identical(value, MappingFlags.useAsDefault)) {
      return true;
    } else if (value is Function) {
      if (value is bool Function(JsonObject)) {
        return value(context.value);
      } else {
        throw AssertionError(
            'Discriminator function must be of type "bool Function(Map<String, dynamic>)".');
      }
    } else if (value == context.value.get(discriminatorKey)) {
      return true;
    }

    if (_subMappers.isNotEmpty) {
      for (var m in _subMappers) {
        if (m.discriminatorKey == discriminatorKey && m.canDecode(context)) {
          return true;
        }
      }
    }
    if (_defaultSubMapper != null &&
        _defaultSubMapper!.discriminatorKey == discriminatorKey) {
      return true;
    }

    return false;
  }

  late final bool _shouldEncodeDiscriminatorParam = () {
    return _params.every((p) => p.key != discriminatorKey) &&
        !identical(discriminatorValue, MappingFlags.useAsDefault) &&
        discriminatorValue is! Function;
  }();

  @override
  // ignore: overridden_fields
  late final Map<String, dynamic> _encodedStaticParams = {
    ...?superMapper._encodedStaticParams,
    if (_shouldEncodeDiscriminatorParam) discriminatorKey: discriminatorValue
  };

  @override
  bool includeTypeId<V>(v) {
    // Skip type id for non-generic poly types.
    if (V.nonNull == superMapper.type) {
      return false;
    }
    return super.includeTypeId<V>(v) && superMapper.includeTypeId<V>(v);
  }
}

abstract class ClassMapperBase<T extends Object> extends MapperBase<T> {
  Map<Symbol, Field<T, dynamic>> get fields;

  bool get ignoreNull => false;
  MappingHook? get hook => null;
  MappingHook? get superHook => null;

  SubClassMapperBase<T>? _defaultSubMapper;
  final Set<SubClassMapperBase<T>> _subMappers = {};

  @override
  bool includeTypeId<V>(v) => MapperBase.matchesStaticType<V>(v);

  DecodingContext<Object> inherit(DecodingContext<Object> context) {
    return context.inherit();
  }

  void addSubMapper(SubClassMapperBase<T> mapper) {
    assert(identical(mapper.superMapper, this));
    if (identical(mapper.discriminatorValue, MappingFlags.useAsDefault)) {
      assert(_defaultSubMapper == null,
          'Cannot have multiple default mappers for a polymorphic class.');
      _defaultSubMapper = mapper;
    } else {
      _subMappers.add(mapper);
    }
  }

  late final Map<int, Field> fieldsByKey =
      fields.map((_, f) => MapEntry(Crimson.hash(f.key), f));

  late final List<Field<T, dynamic>> _members =
      fields.values.where((f) => f.mode != FieldMode.param).toList();
  late final List<Field<T, dynamic>> _params =
      fields.values.where((f) => f.mode != FieldMode.member).toList();

  Function get instantiate;

  @override
  T decoder(DecodingContext<Object> context) {
    return context.wrap(hook: superHook, skipInherited: true, (c) {
      return c.wrap(hook: hook, (c) {
        var c2 = c.change(JsonObject.from(c.value));
        if (_subMappers.isNotEmpty) {
          for (var m in _subMappers) {
            if (m.canDecode(c2)) {
              return m.decoder(m.inherit(c2));
            }
          }
        }
        if (_defaultSubMapper != null) {
          return _defaultSubMapper!.decoder(_defaultSubMapper!.inherit(c2));
        }
        return c.callWith(instantiate, DecodingData<T>(c2, this));
      });
    });
  }

  final Map<String, dynamic>? _encodedStaticParams = null;

  @override
  Object? encoder(EncodingContext<Object> context) {
    return context.checked<T>().wrap(hook: superHook, (c) {
      return c.wrap(hook: hook, (c) {
        return {
          for (var f in _params)
            if (!ignoreNull || f.get(c.value) != null) f.key: f.encode(c),
          ...?_encodedStaticParams,
        };
      });
    });
  }

  @override
  String stringify(MappingContext<Object> context) {
    var value = context.checked<T>().value;
    return '$id(${_members.map((f) {
      return '${f.name}: ${context.container.asString(f.get(value))}';
    }).join(', ')})';
  }

  @override
  int hash(MappingContext<Object> context) {
    var value = context.checked<T>().value;
    return Object.hashAll(_members.map((f) {
      return context.container.hash(f.get(value));
    }));
  }

  @override
  bool equals(MappingContext<Object> context, T other) {
    var value = context.checked<T>().value;
    return _members.every((f) {
      return context.container.isEqual(f.get(value), f.get(other));
    });
  }
}

enum FieldMode {
  field,
  member,
  param;
}

class Field<T extends Object, V> {
  final String name;
  final V Function(T) getter;
  final String key;
  final FieldMode mode;
  final Function? arg;
  final bool opt;
  final V? def;
  final MappingHook? hook;

  const Field(this.name, this.getter,
      {String? key,
      this.mode = FieldMode.field,
      this.arg,
      this.opt = false,
      this.def,
      this.hook})
      : key = key ?? name;

  V get(T value) {
    return getter(value);
  }

  dynamic encode(EncodingContext<T> context) {
    var container = context.container;
    if (arg == null) {
      return container.$enc<V>(get(context.value), name, hook);
    } else {
      return context.callWith(arg!,
          <U>() => container.$enc<U>(get(context.value) as U, name, hook));
    }
  }

  R decode<R>(DecodingContext<JsonObject> context) {
    var value = opt || def != null
        ? context.container.$dec<R?>(context.value.get(key), key, hook)
        : context.container.$dec<R>(context.value.get(key), key, hook);
    return value ?? (def as R);
  }

  dynamic decodeValue(DecodingContext<JsonObject> context, Object? v) {
    if (context.args.isEmpty || this.arg == null) {
      return _decodeValue<V>(context, v);
    } else {
      return context.callWith(arg!, <U>() => _decodeValue<U>(context, v));
    }
  }

  R _decodeValue<R>(DecodingContext<JsonObject> context, Object? v) {
    var value = opt || def != null
        ? context.container.$dec<R?>(v, key, hook)
        : context.container.$dec<R>(v, key, hook);
    return value ?? (def as R);
  }
}
