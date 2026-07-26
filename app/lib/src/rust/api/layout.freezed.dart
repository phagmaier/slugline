// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'layout.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PaginationOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PaginationOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PaginationOutcome()';
}


}

/// @nodoc
class $PaginationOutcomeCopyWith<$Res>  {
$PaginationOutcomeCopyWith(PaginationOutcome _, $Res Function(PaginationOutcome) __);
}


/// Adds pattern-matching-related methods to [PaginationOutcome].
extension PaginationOutcomePatterns on PaginationOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PaginationOutcome_Current value)?  current,TResult Function( PaginationOutcome_Stale value)?  stale,TResult Function( PaginationOutcome_NoSuchDocument value)?  noSuchDocument,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PaginationOutcome_Current() when current != null:
return current(_that);case PaginationOutcome_Stale() when stale != null:
return stale(_that);case PaginationOutcome_NoSuchDocument() when noSuchDocument != null:
return noSuchDocument(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PaginationOutcome_Current value)  current,required TResult Function( PaginationOutcome_Stale value)  stale,required TResult Function( PaginationOutcome_NoSuchDocument value)  noSuchDocument,}){
final _that = this;
switch (_that) {
case PaginationOutcome_Current():
return current(_that);case PaginationOutcome_Stale():
return stale(_that);case PaginationOutcome_NoSuchDocument():
return noSuchDocument(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PaginationOutcome_Current value)?  current,TResult? Function( PaginationOutcome_Stale value)?  stale,TResult? Function( PaginationOutcome_NoSuchDocument value)?  noSuchDocument,}){
final _that = this;
switch (_that) {
case PaginationOutcome_Current() when current != null:
return current(_that);case PaginationOutcome_Stale() when stale != null:
return stale(_that);case PaginationOutcome_NoSuchDocument() when noSuchDocument != null:
return noSuchDocument(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PaginationView pagination)?  current,TResult Function( PaginationView pagination)?  stale,TResult Function()?  noSuchDocument,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PaginationOutcome_Current() when current != null:
return current(_that.pagination);case PaginationOutcome_Stale() when stale != null:
return stale(_that.pagination);case PaginationOutcome_NoSuchDocument() when noSuchDocument != null:
return noSuchDocument();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PaginationView pagination)  current,required TResult Function( PaginationView pagination)  stale,required TResult Function()  noSuchDocument,}) {final _that = this;
switch (_that) {
case PaginationOutcome_Current():
return current(_that.pagination);case PaginationOutcome_Stale():
return stale(_that.pagination);case PaginationOutcome_NoSuchDocument():
return noSuchDocument();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PaginationView pagination)?  current,TResult? Function( PaginationView pagination)?  stale,TResult? Function()?  noSuchDocument,}) {final _that = this;
switch (_that) {
case PaginationOutcome_Current() when current != null:
return current(_that.pagination);case PaginationOutcome_Stale() when stale != null:
return stale(_that.pagination);case PaginationOutcome_NoSuchDocument() when noSuchDocument != null:
return noSuchDocument();case _:
  return null;

}
}

}

/// @nodoc


class PaginationOutcome_Current extends PaginationOutcome {
  const PaginationOutcome_Current({required this.pagination}): super._();
  

 final  PaginationView pagination;

/// Create a copy of PaginationOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PaginationOutcome_CurrentCopyWith<PaginationOutcome_Current> get copyWith => _$PaginationOutcome_CurrentCopyWithImpl<PaginationOutcome_Current>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PaginationOutcome_Current&&(identical(other.pagination, pagination) || other.pagination == pagination));
}


@override
int get hashCode => Object.hash(runtimeType,pagination);

@override
String toString() {
  return 'PaginationOutcome.current(pagination: $pagination)';
}


}

/// @nodoc
abstract mixin class $PaginationOutcome_CurrentCopyWith<$Res> implements $PaginationOutcomeCopyWith<$Res> {
  factory $PaginationOutcome_CurrentCopyWith(PaginationOutcome_Current value, $Res Function(PaginationOutcome_Current) _then) = _$PaginationOutcome_CurrentCopyWithImpl;
@useResult
$Res call({
 PaginationView pagination
});




}
/// @nodoc
class _$PaginationOutcome_CurrentCopyWithImpl<$Res>
    implements $PaginationOutcome_CurrentCopyWith<$Res> {
  _$PaginationOutcome_CurrentCopyWithImpl(this._self, this._then);

  final PaginationOutcome_Current _self;
  final $Res Function(PaginationOutcome_Current) _then;

/// Create a copy of PaginationOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? pagination = null,}) {
  return _then(PaginationOutcome_Current(
pagination: null == pagination ? _self.pagination : pagination // ignore: cast_nullable_to_non_nullable
as PaginationView,
  ));
}


}

/// @nodoc


class PaginationOutcome_Stale extends PaginationOutcome {
  const PaginationOutcome_Stale({required this.pagination}): super._();
  

 final  PaginationView pagination;

/// Create a copy of PaginationOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PaginationOutcome_StaleCopyWith<PaginationOutcome_Stale> get copyWith => _$PaginationOutcome_StaleCopyWithImpl<PaginationOutcome_Stale>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PaginationOutcome_Stale&&(identical(other.pagination, pagination) || other.pagination == pagination));
}


@override
int get hashCode => Object.hash(runtimeType,pagination);

@override
String toString() {
  return 'PaginationOutcome.stale(pagination: $pagination)';
}


}

/// @nodoc
abstract mixin class $PaginationOutcome_StaleCopyWith<$Res> implements $PaginationOutcomeCopyWith<$Res> {
  factory $PaginationOutcome_StaleCopyWith(PaginationOutcome_Stale value, $Res Function(PaginationOutcome_Stale) _then) = _$PaginationOutcome_StaleCopyWithImpl;
@useResult
$Res call({
 PaginationView pagination
});




}
/// @nodoc
class _$PaginationOutcome_StaleCopyWithImpl<$Res>
    implements $PaginationOutcome_StaleCopyWith<$Res> {
  _$PaginationOutcome_StaleCopyWithImpl(this._self, this._then);

  final PaginationOutcome_Stale _self;
  final $Res Function(PaginationOutcome_Stale) _then;

/// Create a copy of PaginationOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? pagination = null,}) {
  return _then(PaginationOutcome_Stale(
pagination: null == pagination ? _self.pagination : pagination // ignore: cast_nullable_to_non_nullable
as PaginationView,
  ));
}


}

/// @nodoc


class PaginationOutcome_NoSuchDocument extends PaginationOutcome {
  const PaginationOutcome_NoSuchDocument(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PaginationOutcome_NoSuchDocument);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PaginationOutcome.noSuchDocument()';
}


}




// dart format on
