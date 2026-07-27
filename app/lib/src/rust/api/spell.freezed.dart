// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'spell.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SpellActionResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SpellActionResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SpellActionResult()';
}


}

/// @nodoc
class $SpellActionResultCopyWith<$Res>  {
$SpellActionResultCopyWith(SpellActionResult _, $Res Function(SpellActionResult) __);
}


/// Adds pattern-matching-related methods to [SpellActionResult].
extension SpellActionResultPatterns on SpellActionResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SpellActionResult_Applied value)?  applied,TResult Function( SpellActionResult_NoSuchDocument value)?  noSuchDocument,TResult Function( SpellActionResult_NoScriptPath value)?  noScriptPath,TResult Function( SpellActionResult_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SpellActionResult_Applied() when applied != null:
return applied(_that);case SpellActionResult_NoSuchDocument() when noSuchDocument != null:
return noSuchDocument(_that);case SpellActionResult_NoScriptPath() when noScriptPath != null:
return noScriptPath(_that);case SpellActionResult_Failed() when failed != null:
return failed(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SpellActionResult_Applied value)  applied,required TResult Function( SpellActionResult_NoSuchDocument value)  noSuchDocument,required TResult Function( SpellActionResult_NoScriptPath value)  noScriptPath,required TResult Function( SpellActionResult_Failed value)  failed,}){
final _that = this;
switch (_that) {
case SpellActionResult_Applied():
return applied(_that);case SpellActionResult_NoSuchDocument():
return noSuchDocument(_that);case SpellActionResult_NoScriptPath():
return noScriptPath(_that);case SpellActionResult_Failed():
return failed(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SpellActionResult_Applied value)?  applied,TResult? Function( SpellActionResult_NoSuchDocument value)?  noSuchDocument,TResult? Function( SpellActionResult_NoScriptPath value)?  noScriptPath,TResult? Function( SpellActionResult_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case SpellActionResult_Applied() when applied != null:
return applied(_that);case SpellActionResult_NoSuchDocument() when noSuchDocument != null:
return noSuchDocument(_that);case SpellActionResult_NoScriptPath() when noScriptPath != null:
return noScriptPath(_that);case SpellActionResult_Failed() when failed != null:
return failed(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  applied,TResult Function()?  noSuchDocument,TResult Function()?  noScriptPath,TResult Function( String message)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SpellActionResult_Applied() when applied != null:
return applied();case SpellActionResult_NoSuchDocument() when noSuchDocument != null:
return noSuchDocument();case SpellActionResult_NoScriptPath() when noScriptPath != null:
return noScriptPath();case SpellActionResult_Failed() when failed != null:
return failed(_that.message);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  applied,required TResult Function()  noSuchDocument,required TResult Function()  noScriptPath,required TResult Function( String message)  failed,}) {final _that = this;
switch (_that) {
case SpellActionResult_Applied():
return applied();case SpellActionResult_NoSuchDocument():
return noSuchDocument();case SpellActionResult_NoScriptPath():
return noScriptPath();case SpellActionResult_Failed():
return failed(_that.message);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  applied,TResult? Function()?  noSuchDocument,TResult? Function()?  noScriptPath,TResult? Function( String message)?  failed,}) {final _that = this;
switch (_that) {
case SpellActionResult_Applied() when applied != null:
return applied();case SpellActionResult_NoSuchDocument() when noSuchDocument != null:
return noSuchDocument();case SpellActionResult_NoScriptPath() when noScriptPath != null:
return noScriptPath();case SpellActionResult_Failed() when failed != null:
return failed(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class SpellActionResult_Applied extends SpellActionResult {
  const SpellActionResult_Applied(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SpellActionResult_Applied);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SpellActionResult.applied()';
}


}




/// @nodoc


class SpellActionResult_NoSuchDocument extends SpellActionResult {
  const SpellActionResult_NoSuchDocument(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SpellActionResult_NoSuchDocument);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SpellActionResult.noSuchDocument()';
}


}




/// @nodoc


class SpellActionResult_NoScriptPath extends SpellActionResult {
  const SpellActionResult_NoScriptPath(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SpellActionResult_NoScriptPath);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SpellActionResult.noScriptPath()';
}


}




/// @nodoc


class SpellActionResult_Failed extends SpellActionResult {
  const SpellActionResult_Failed({required this.message}): super._();
  

 final  String message;

/// Create a copy of SpellActionResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SpellActionResult_FailedCopyWith<SpellActionResult_Failed> get copyWith => _$SpellActionResult_FailedCopyWithImpl<SpellActionResult_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SpellActionResult_Failed&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'SpellActionResult.failed(message: $message)';
}


}

/// @nodoc
abstract mixin class $SpellActionResult_FailedCopyWith<$Res> implements $SpellActionResultCopyWith<$Res> {
  factory $SpellActionResult_FailedCopyWith(SpellActionResult_Failed value, $Res Function(SpellActionResult_Failed) _then) = _$SpellActionResult_FailedCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$SpellActionResult_FailedCopyWithImpl<$Res>
    implements $SpellActionResult_FailedCopyWith<$Res> {
  _$SpellActionResult_FailedCopyWithImpl(this._self, this._then);

  final SpellActionResult_Failed _self;
  final $Res Function(SpellActionResult_Failed) _then;

/// Create a copy of SpellActionResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(SpellActionResult_Failed(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
