// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'files.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RecoveryOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RecoveryOutcome()';
}


}

/// @nodoc
class $RecoveryOutcomeCopyWith<$Res>  {
$RecoveryOutcomeCopyWith(RecoveryOutcome _, $Res Function(RecoveryOutcome) __);
}


/// Adds pattern-matching-related methods to [RecoveryOutcome].
extension RecoveryOutcomePatterns on RecoveryOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RecoveryOutcome_Recovered value)?  recovered,TResult Function( RecoveryOutcome_Degraded value)?  degraded,TResult Function( RecoveryOutcome_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RecoveryOutcome_Recovered() when recovered != null:
return recovered(_that);case RecoveryOutcome_Degraded() when degraded != null:
return degraded(_that);case RecoveryOutcome_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RecoveryOutcome_Recovered value)  recovered,required TResult Function( RecoveryOutcome_Degraded value)  degraded,required TResult Function( RecoveryOutcome_Failed value)  failed,}){
final _that = this;
switch (_that) {
case RecoveryOutcome_Recovered():
return recovered(_that);case RecoveryOutcome_Degraded():
return degraded(_that);case RecoveryOutcome_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RecoveryOutcome_Recovered value)?  recovered,TResult? Function( RecoveryOutcome_Degraded value)?  degraded,TResult? Function( RecoveryOutcome_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case RecoveryOutcome_Recovered() when recovered != null:
return recovered(_that);case RecoveryOutcome_Degraded() when degraded != null:
return degraded(_that);case RecoveryOutcome_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( DocumentHandle handle)?  recovered,TResult Function( DocumentHandle handle,  String message)?  degraded,TResult Function( String message)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RecoveryOutcome_Recovered() when recovered != null:
return recovered(_that.handle);case RecoveryOutcome_Degraded() when degraded != null:
return degraded(_that.handle,_that.message);case RecoveryOutcome_Failed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( DocumentHandle handle)  recovered,required TResult Function( DocumentHandle handle,  String message)  degraded,required TResult Function( String message)  failed,}) {final _that = this;
switch (_that) {
case RecoveryOutcome_Recovered():
return recovered(_that.handle);case RecoveryOutcome_Degraded():
return degraded(_that.handle,_that.message);case RecoveryOutcome_Failed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( DocumentHandle handle)?  recovered,TResult? Function( DocumentHandle handle,  String message)?  degraded,TResult? Function( String message)?  failed,}) {final _that = this;
switch (_that) {
case RecoveryOutcome_Recovered() when recovered != null:
return recovered(_that.handle);case RecoveryOutcome_Degraded() when degraded != null:
return degraded(_that.handle,_that.message);case RecoveryOutcome_Failed() when failed != null:
return failed(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class RecoveryOutcome_Recovered extends RecoveryOutcome {
  const RecoveryOutcome_Recovered({required this.handle}): super._();
  

 final  DocumentHandle handle;

/// Create a copy of RecoveryOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryOutcome_RecoveredCopyWith<RecoveryOutcome_Recovered> get copyWith => _$RecoveryOutcome_RecoveredCopyWithImpl<RecoveryOutcome_Recovered>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryOutcome_Recovered&&(identical(other.handle, handle) || other.handle == handle));
}


@override
int get hashCode => Object.hash(runtimeType,handle);

@override
String toString() {
  return 'RecoveryOutcome.recovered(handle: $handle)';
}


}

/// @nodoc
abstract mixin class $RecoveryOutcome_RecoveredCopyWith<$Res> implements $RecoveryOutcomeCopyWith<$Res> {
  factory $RecoveryOutcome_RecoveredCopyWith(RecoveryOutcome_Recovered value, $Res Function(RecoveryOutcome_Recovered) _then) = _$RecoveryOutcome_RecoveredCopyWithImpl;
@useResult
$Res call({
 DocumentHandle handle
});




}
/// @nodoc
class _$RecoveryOutcome_RecoveredCopyWithImpl<$Res>
    implements $RecoveryOutcome_RecoveredCopyWith<$Res> {
  _$RecoveryOutcome_RecoveredCopyWithImpl(this._self, this._then);

  final RecoveryOutcome_Recovered _self;
  final $Res Function(RecoveryOutcome_Recovered) _then;

/// Create a copy of RecoveryOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? handle = null,}) {
  return _then(RecoveryOutcome_Recovered(
handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as DocumentHandle,
  ));
}


}

/// @nodoc


class RecoveryOutcome_Degraded extends RecoveryOutcome {
  const RecoveryOutcome_Degraded({required this.handle, required this.message}): super._();
  

 final  DocumentHandle handle;
 final  String message;

/// Create a copy of RecoveryOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryOutcome_DegradedCopyWith<RecoveryOutcome_Degraded> get copyWith => _$RecoveryOutcome_DegradedCopyWithImpl<RecoveryOutcome_Degraded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryOutcome_Degraded&&(identical(other.handle, handle) || other.handle == handle)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,handle,message);

@override
String toString() {
  return 'RecoveryOutcome.degraded(handle: $handle, message: $message)';
}


}

/// @nodoc
abstract mixin class $RecoveryOutcome_DegradedCopyWith<$Res> implements $RecoveryOutcomeCopyWith<$Res> {
  factory $RecoveryOutcome_DegradedCopyWith(RecoveryOutcome_Degraded value, $Res Function(RecoveryOutcome_Degraded) _then) = _$RecoveryOutcome_DegradedCopyWithImpl;
@useResult
$Res call({
 DocumentHandle handle, String message
});




}
/// @nodoc
class _$RecoveryOutcome_DegradedCopyWithImpl<$Res>
    implements $RecoveryOutcome_DegradedCopyWith<$Res> {
  _$RecoveryOutcome_DegradedCopyWithImpl(this._self, this._then);

  final RecoveryOutcome_Degraded _self;
  final $Res Function(RecoveryOutcome_Degraded) _then;

/// Create a copy of RecoveryOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? handle = null,Object? message = null,}) {
  return _then(RecoveryOutcome_Degraded(
handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as DocumentHandle,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RecoveryOutcome_Failed extends RecoveryOutcome {
  const RecoveryOutcome_Failed({required this.message}): super._();
  

 final  String message;

/// Create a copy of RecoveryOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryOutcome_FailedCopyWith<RecoveryOutcome_Failed> get copyWith => _$RecoveryOutcome_FailedCopyWithImpl<RecoveryOutcome_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryOutcome_Failed&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'RecoveryOutcome.failed(message: $message)';
}


}

/// @nodoc
abstract mixin class $RecoveryOutcome_FailedCopyWith<$Res> implements $RecoveryOutcomeCopyWith<$Res> {
  factory $RecoveryOutcome_FailedCopyWith(RecoveryOutcome_Failed value, $Res Function(RecoveryOutcome_Failed) _then) = _$RecoveryOutcome_FailedCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$RecoveryOutcome_FailedCopyWithImpl<$Res>
    implements $RecoveryOutcome_FailedCopyWith<$Res> {
  _$RecoveryOutcome_FailedCopyWithImpl(this._self, this._then);

  final RecoveryOutcome_Failed _self;
  final $Res Function(RecoveryOutcome_Failed) _then;

/// Create a copy of RecoveryOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(RecoveryOutcome_Failed(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$SaveOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SaveOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SaveOutcome()';
}


}

/// @nodoc
class $SaveOutcomeCopyWith<$Res>  {
$SaveOutcomeCopyWith(SaveOutcome _, $Res Function(SaveOutcome) __);
}


/// Adds pattern-matching-related methods to [SaveOutcome].
extension SaveOutcomePatterns on SaveOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SaveOutcome_Saved value)?  saved,TResult Function( SaveOutcome_Unchanged value)?  unchanged,TResult Function( SaveOutcome_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SaveOutcome_Saved() when saved != null:
return saved(_that);case SaveOutcome_Unchanged() when unchanged != null:
return unchanged(_that);case SaveOutcome_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SaveOutcome_Saved value)  saved,required TResult Function( SaveOutcome_Unchanged value)  unchanged,required TResult Function( SaveOutcome_Failed value)  failed,}){
final _that = this;
switch (_that) {
case SaveOutcome_Saved():
return saved(_that);case SaveOutcome_Unchanged():
return unchanged(_that);case SaveOutcome_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SaveOutcome_Saved value)?  saved,TResult? Function( SaveOutcome_Unchanged value)?  unchanged,TResult? Function( SaveOutcome_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case SaveOutcome_Saved() when saved != null:
return saved(_that);case SaveOutcome_Unchanged() when unchanged != null:
return unchanged(_that);case SaveOutcome_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String path,  int bytes,  BackupView? backup)?  saved,TResult Function()?  unchanged,TResult Function( SaveFailure failure,  String path,  String message)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SaveOutcome_Saved() when saved != null:
return saved(_that.path,_that.bytes,_that.backup);case SaveOutcome_Unchanged() when unchanged != null:
return unchanged();case SaveOutcome_Failed() when failed != null:
return failed(_that.failure,_that.path,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String path,  int bytes,  BackupView? backup)  saved,required TResult Function()  unchanged,required TResult Function( SaveFailure failure,  String path,  String message)  failed,}) {final _that = this;
switch (_that) {
case SaveOutcome_Saved():
return saved(_that.path,_that.bytes,_that.backup);case SaveOutcome_Unchanged():
return unchanged();case SaveOutcome_Failed():
return failed(_that.failure,_that.path,_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String path,  int bytes,  BackupView? backup)?  saved,TResult? Function()?  unchanged,TResult? Function( SaveFailure failure,  String path,  String message)?  failed,}) {final _that = this;
switch (_that) {
case SaveOutcome_Saved() when saved != null:
return saved(_that.path,_that.bytes,_that.backup);case SaveOutcome_Unchanged() when unchanged != null:
return unchanged();case SaveOutcome_Failed() when failed != null:
return failed(_that.failure,_that.path,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class SaveOutcome_Saved extends SaveOutcome {
  const SaveOutcome_Saved({required this.path, required this.bytes, this.backup}): super._();
  

 final  String path;
 final  int bytes;
/// The backup written alongside, if one was.
 final  BackupView? backup;

/// Create a copy of SaveOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SaveOutcome_SavedCopyWith<SaveOutcome_Saved> get copyWith => _$SaveOutcome_SavedCopyWithImpl<SaveOutcome_Saved>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SaveOutcome_Saved&&(identical(other.path, path) || other.path == path)&&(identical(other.bytes, bytes) || other.bytes == bytes)&&(identical(other.backup, backup) || other.backup == backup));
}


@override
int get hashCode => Object.hash(runtimeType,path,bytes,backup);

@override
String toString() {
  return 'SaveOutcome.saved(path: $path, bytes: $bytes, backup: $backup)';
}


}

/// @nodoc
abstract mixin class $SaveOutcome_SavedCopyWith<$Res> implements $SaveOutcomeCopyWith<$Res> {
  factory $SaveOutcome_SavedCopyWith(SaveOutcome_Saved value, $Res Function(SaveOutcome_Saved) _then) = _$SaveOutcome_SavedCopyWithImpl;
@useResult
$Res call({
 String path, int bytes, BackupView? backup
});




}
/// @nodoc
class _$SaveOutcome_SavedCopyWithImpl<$Res>
    implements $SaveOutcome_SavedCopyWith<$Res> {
  _$SaveOutcome_SavedCopyWithImpl(this._self, this._then);

  final SaveOutcome_Saved _self;
  final $Res Function(SaveOutcome_Saved) _then;

/// Create a copy of SaveOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,Object? bytes = null,Object? backup = freezed,}) {
  return _then(SaveOutcome_Saved(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as int,backup: freezed == backup ? _self.backup : backup // ignore: cast_nullable_to_non_nullable
as BackupView?,
  ));
}


}

/// @nodoc


class SaveOutcome_Unchanged extends SaveOutcome {
  const SaveOutcome_Unchanged(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SaveOutcome_Unchanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SaveOutcome.unchanged()';
}


}




/// @nodoc


class SaveOutcome_Failed extends SaveOutcome {
  const SaveOutcome_Failed({required this.failure, required this.path, required this.message}): super._();
  

 final  SaveFailure failure;
/// The file the user asked for, never the temporary one.
 final  String path;
/// Human-readable, and specific: it names the file and the reason.
 final  String message;

/// Create a copy of SaveOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SaveOutcome_FailedCopyWith<SaveOutcome_Failed> get copyWith => _$SaveOutcome_FailedCopyWithImpl<SaveOutcome_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SaveOutcome_Failed&&(identical(other.failure, failure) || other.failure == failure)&&(identical(other.path, path) || other.path == path)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,failure,path,message);

@override
String toString() {
  return 'SaveOutcome.failed(failure: $failure, path: $path, message: $message)';
}


}

/// @nodoc
abstract mixin class $SaveOutcome_FailedCopyWith<$Res> implements $SaveOutcomeCopyWith<$Res> {
  factory $SaveOutcome_FailedCopyWith(SaveOutcome_Failed value, $Res Function(SaveOutcome_Failed) _then) = _$SaveOutcome_FailedCopyWithImpl;
@useResult
$Res call({
 SaveFailure failure, String path, String message
});




}
/// @nodoc
class _$SaveOutcome_FailedCopyWithImpl<$Res>
    implements $SaveOutcome_FailedCopyWith<$Res> {
  _$SaveOutcome_FailedCopyWithImpl(this._self, this._then);

  final SaveOutcome_Failed _self;
  final $Res Function(SaveOutcome_Failed) _then;

/// Create a copy of SaveOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,Object? path = null,Object? message = null,}) {
  return _then(SaveOutcome_Failed(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as SaveFailure,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
