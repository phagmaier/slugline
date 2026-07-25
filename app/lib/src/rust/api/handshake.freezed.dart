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
mixin _$ProofEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProofEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ProofEvent()';
}


}

/// @nodoc
class $ProofEventCopyWith<$Res>  {
$ProofEventCopyWith(ProofEvent _, $Res Function(ProofEvent) __);
}


/// Adds pattern-matching-related methods to [ProofEvent].
extension ProofEventPatterns on ProofEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ProofEvent_Ready value)?  ready,TResult Function( ProofEvent_Pong value)?  pong,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ProofEvent_Ready() when ready != null:
return ready(_that);case ProofEvent_Pong() when pong != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ProofEvent_Ready value)  ready,required TResult Function( ProofEvent_Pong value)  pong,}){
final _that = this;
switch (_that) {
case ProofEvent_Ready():
return ready(_that);case ProofEvent_Pong():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ProofEvent_Ready value)?  ready,TResult? Function( ProofEvent_Pong value)?  pong,}){
final _that = this;
switch (_that) {
case ProofEvent_Ready() when ready != null:
return ready(_that);case ProofEvent_Pong() when pong != null:
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
case ProofEvent_Ready() when ready != null:
return ready(_that.coreVersion);case ProofEvent_Pong() when pong != null:
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
case ProofEvent_Ready():
return ready(_that.coreVersion);case ProofEvent_Pong():
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
case ProofEvent_Ready() when ready != null:
return ready(_that.coreVersion);case ProofEvent_Pong() when pong != null:
return pong(_that.text,_that.lenUtf16);case _:
  return null;

}
}

}

/// @nodoc


class ProofEvent_Ready extends ProofEvent {
  const ProofEvent_Ready({required this.coreVersion}): super._();
  

 final  String coreVersion;

/// Create a copy of ProofEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProofEvent_ReadyCopyWith<ProofEvent_Ready> get copyWith => _$ProofEvent_ReadyCopyWithImpl<ProofEvent_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProofEvent_Ready&&(identical(other.coreVersion, coreVersion) || other.coreVersion == coreVersion));
}


@override
int get hashCode => Object.hash(runtimeType,coreVersion);

@override
String toString() {
  return 'ProofEvent.ready(coreVersion: $coreVersion)';
}


}

/// @nodoc
abstract mixin class $ProofEvent_ReadyCopyWith<$Res> implements $ProofEventCopyWith<$Res> {
  factory $ProofEvent_ReadyCopyWith(ProofEvent_Ready value, $Res Function(ProofEvent_Ready) _then) = _$ProofEvent_ReadyCopyWithImpl;
@useResult
$Res call({
 String coreVersion
});




}
/// @nodoc
class _$ProofEvent_ReadyCopyWithImpl<$Res>
    implements $ProofEvent_ReadyCopyWith<$Res> {
  _$ProofEvent_ReadyCopyWithImpl(this._self, this._then);

  final ProofEvent_Ready _self;
  final $Res Function(ProofEvent_Ready) _then;

/// Create a copy of ProofEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? coreVersion = null,}) {
  return _then(ProofEvent_Ready(
coreVersion: null == coreVersion ? _self.coreVersion : coreVersion // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ProofEvent_Pong extends ProofEvent {
  const ProofEvent_Pong({required this.text, required this.lenUtf16}): super._();
  

 final  String text;
 final  int lenUtf16;

/// Create a copy of ProofEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProofEvent_PongCopyWith<ProofEvent_Pong> get copyWith => _$ProofEvent_PongCopyWithImpl<ProofEvent_Pong>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProofEvent_Pong&&(identical(other.text, text) || other.text == text)&&(identical(other.lenUtf16, lenUtf16) || other.lenUtf16 == lenUtf16));
}


@override
int get hashCode => Object.hash(runtimeType,text,lenUtf16);

@override
String toString() {
  return 'ProofEvent.pong(text: $text, lenUtf16: $lenUtf16)';
}


}

/// @nodoc
abstract mixin class $ProofEvent_PongCopyWith<$Res> implements $ProofEventCopyWith<$Res> {
  factory $ProofEvent_PongCopyWith(ProofEvent_Pong value, $Res Function(ProofEvent_Pong) _then) = _$ProofEvent_PongCopyWithImpl;
@useResult
$Res call({
 String text, int lenUtf16
});




}
/// @nodoc
class _$ProofEvent_PongCopyWithImpl<$Res>
    implements $ProofEvent_PongCopyWith<$Res> {
  _$ProofEvent_PongCopyWithImpl(this._self, this._then);

  final ProofEvent_Pong _self;
  final $Res Function(ProofEvent_Pong) _then;

/// Create a copy of ProofEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,Object? lenUtf16 = null,}) {
  return _then(ProofEvent_Pong(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,lenUtf16: null == lenUtf16 ? _self.lenUtf16 : lenUtf16 // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
