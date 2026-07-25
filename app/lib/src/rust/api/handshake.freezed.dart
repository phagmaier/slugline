// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'handshake.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CoreEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'CoreEvent()';
}


}

/// @nodoc
class $CoreEventCopyWith<$Res>  {
$CoreEventCopyWith(CoreEvent _, $Res Function(CoreEvent) __);
}


/// Adds pattern-matching-related methods to [CoreEvent].
extension CoreEventPatterns on CoreEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoreEvent_Ready value)?  ready,TResult Function( CoreEvent_Pong value)?  pong,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoreEvent_Ready() when ready != null:
return ready(_that);case CoreEvent_Pong() when pong != null:
return pong(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoreEvent_Ready value)  ready,required TResult Function( CoreEvent_Pong value)  pong,}){
final _that = this;
switch (_that) {
case CoreEvent_Ready():
return ready(_that);case CoreEvent_Pong():
return pong(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoreEvent_Ready value)?  ready,TResult? Function( CoreEvent_Pong value)?  pong,}){
final _that = this;
switch (_that) {
case CoreEvent_Ready() when ready != null:
return ready(_that);case CoreEvent_Pong() when pong != null:
return pong(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String coreVersion)?  ready,TResult Function( String text,  int lenUtf16)?  pong,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoreEvent_Ready() when ready != null:
return ready(_that.coreVersion);case CoreEvent_Pong() when pong != null:
return pong(_that.text,_that.lenUtf16);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String coreVersion)  ready,required TResult Function( String text,  int lenUtf16)  pong,}) {final _that = this;
switch (_that) {
case CoreEvent_Ready():
return ready(_that.coreVersion);case CoreEvent_Pong():
return pong(_that.text,_that.lenUtf16);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String coreVersion)?  ready,TResult? Function( String text,  int lenUtf16)?  pong,}) {final _that = this;
switch (_that) {
case CoreEvent_Ready() when ready != null:
return ready(_that.coreVersion);case CoreEvent_Pong() when pong != null:
return pong(_that.text,_that.lenUtf16);case _:
  return null;

}
}

}

/// @nodoc


class CoreEvent_Ready extends CoreEvent {
  const CoreEvent_Ready({required this.coreVersion}): super._();
  

 final  String coreVersion;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_ReadyCopyWith<CoreEvent_Ready> get copyWith => _$CoreEvent_ReadyCopyWithImpl<CoreEvent_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_Ready&&(identical(other.coreVersion, coreVersion) || other.coreVersion == coreVersion));
}


@override
int get hashCode => Object.hash(runtimeType,coreVersion);

@override
String toString() {
  return 'CoreEvent.ready(coreVersion: $coreVersion)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_ReadyCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_ReadyCopyWith(CoreEvent_Ready value, $Res Function(CoreEvent_Ready) _then) = _$CoreEvent_ReadyCopyWithImpl;
@useResult
$Res call({
 String coreVersion
});




}
/// @nodoc
class _$CoreEvent_ReadyCopyWithImpl<$Res>
    implements $CoreEvent_ReadyCopyWith<$Res> {
  _$CoreEvent_ReadyCopyWithImpl(this._self, this._then);

  final CoreEvent_Ready _self;
  final $Res Function(CoreEvent_Ready) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? coreVersion = null,}) {
  return _then(CoreEvent_Ready(
coreVersion: null == coreVersion ? _self.coreVersion : coreVersion // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreEvent_Pong extends CoreEvent {
  const CoreEvent_Pong({required this.text, required this.lenUtf16}): super._();
  

 final  String text;
 final  int lenUtf16;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_PongCopyWith<CoreEvent_Pong> get copyWith => _$CoreEvent_PongCopyWithImpl<CoreEvent_Pong>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_Pong&&(identical(other.text, text) || other.text == text)&&(identical(other.lenUtf16, lenUtf16) || other.lenUtf16 == lenUtf16));
}


@override
int get hashCode => Object.hash(runtimeType,text,lenUtf16);

@override
String toString() {
  return 'CoreEvent.pong(text: $text, lenUtf16: $lenUtf16)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_PongCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_PongCopyWith(CoreEvent_Pong value, $Res Function(CoreEvent_Pong) _then) = _$CoreEvent_PongCopyWithImpl;
@useResult
$Res call({
 String text, int lenUtf16
});




}
/// @nodoc
class _$CoreEvent_PongCopyWithImpl<$Res>
    implements $CoreEvent_PongCopyWith<$Res> {
  _$CoreEvent_PongCopyWithImpl(this._self, this._then);

  final CoreEvent_Pong _self;
  final $Res Function(CoreEvent_Pong) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,Object? lenUtf16 = null,}) {
  return _then(CoreEvent_Pong(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,lenUtf16: null == lenUtf16 ? _self.lenUtf16 : lenUtf16 // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
