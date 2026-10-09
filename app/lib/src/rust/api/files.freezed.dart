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
mixin _$BackupReadOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupReadOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BackupReadOutcome()';
}


}

/// @nodoc
class $BackupReadOutcomeCopyWith<$Res>  {
$BackupReadOutcomeCopyWith(BackupReadOutcome _, $Res Function(BackupReadOutcome) __);
}


/// Adds pattern-matching-related methods to [BackupReadOutcome].
extension BackupReadOutcomePatterns on BackupReadOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BackupReadOutcome_Read value)?  read,TResult Function( BackupReadOutcome_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BackupReadOutcome_Read() when read != null:
return read(_that);case BackupReadOutcome_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BackupReadOutcome_Read value)  read,required TResult Function( BackupReadOutcome_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BackupReadOutcome_Read():
return read(_that);case BackupReadOutcome_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BackupReadOutcome_Read value)?  read,TResult? Function( BackupReadOutcome_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BackupReadOutcome_Read() when read != null:
return read(_that);case BackupReadOutcome_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String source,  bool? hasBom)?  read,TResult Function( String message)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BackupReadOutcome_Read() when read != null:
return read(_that.source,_that.hasBom);case BackupReadOutcome_Failed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String source,  bool? hasBom)  read,required TResult Function( String message)  failed,}) {final _that = this;
switch (_that) {
case BackupReadOutcome_Read():
return read(_that.source,_that.hasBom);case BackupReadOutcome_Failed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String source,  bool? hasBom)?  read,TResult? Function( String message)?  failed,}) {final _that = this;
switch (_that) {
case BackupReadOutcome_Read() when read != null:
return read(_that.source,_that.hasBom);case BackupReadOutcome_Failed() when failed != null:
return failed(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class BackupReadOutcome_Read extends BackupReadOutcome {
  const BackupReadOutcome_Read({required this.source, this.hasBom}): super._();
  

 final  String source;
 final  bool? hasBom;

/// Create a copy of BackupReadOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupReadOutcome_ReadCopyWith<BackupReadOutcome_Read> get copyWith => _$BackupReadOutcome_ReadCopyWithImpl<BackupReadOutcome_Read>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupReadOutcome_Read&&(identical(other.source, source) || other.source == source)&&(identical(other.hasBom, hasBom) || other.hasBom == hasBom));
}


@override
int get hashCode => Object.hash(runtimeType,source,hasBom);

@override
String toString() {
  return 'BackupReadOutcome.read(source: $source, hasBom: $hasBom)';
}


}

/// @nodoc
abstract mixin class $BackupReadOutcome_ReadCopyWith<$Res> implements $BackupReadOutcomeCopyWith<$Res> {
  factory $BackupReadOutcome_ReadCopyWith(BackupReadOutcome_Read value, $Res Function(BackupReadOutcome_Read) _then) = _$BackupReadOutcome_ReadCopyWithImpl;
@useResult
$Res call({
 String source, bool? hasBom
});




}
/// @nodoc
class _$BackupReadOutcome_ReadCopyWithImpl<$Res>
    implements $BackupReadOutcome_ReadCopyWith<$Res> {
  _$BackupReadOutcome_ReadCopyWithImpl(this._self, this._then);

  final BackupReadOutcome_Read _self;
  final $Res Function(BackupReadOutcome_Read) _then;

/// Create a copy of BackupReadOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? source = null,Object? hasBom = freezed,}) {
  return _then(BackupReadOutcome_Read(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,hasBom: freezed == hasBom ? _self.hasBom : hasBom // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

/// @nodoc


class BackupReadOutcome_Failed extends BackupReadOutcome {
  const BackupReadOutcome_Failed({required this.message}): super._();
  

 final  String message;

/// Create a copy of BackupReadOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupReadOutcome_FailedCopyWith<BackupReadOutcome_Failed> get copyWith => _$BackupReadOutcome_FailedCopyWithImpl<BackupReadOutcome_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupReadOutcome_Failed&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'BackupReadOutcome.failed(message: $message)';
}


}

/// @nodoc
abstract mixin class $BackupReadOutcome_FailedCopyWith<$Res> implements $BackupReadOutcomeCopyWith<$Res> {
  factory $BackupReadOutcome_FailedCopyWith(BackupReadOutcome_Failed value, $Res Function(BackupReadOutcome_Failed) _then) = _$BackupReadOutcome_FailedCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$BackupReadOutcome_FailedCopyWithImpl<$Res>
    implements $BackupReadOutcome_FailedCopyWith<$Res> {
  _$BackupReadOutcome_FailedCopyWithImpl(this._self, this._then);

  final BackupReadOutcome_Failed _self;
  final $Res Function(BackupReadOutcome_Failed) _then;

/// Create a copy of BackupReadOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(BackupReadOutcome_Failed(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$FdxExportOutcome {

 List<String> get warnings;
/// Create a copy of FdxExportOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FdxExportOutcomeCopyWith<FdxExportOutcome> get copyWith => _$FdxExportOutcomeCopyWithImpl<FdxExportOutcome>(this as FdxExportOutcome, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FdxExportOutcome&&const DeepCollectionEquality().equals(other.warnings, warnings));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(warnings));

@override
String toString() {
  return 'FdxExportOutcome(warnings: $warnings)';
}


}

/// @nodoc
abstract mixin class $FdxExportOutcomeCopyWith<$Res>  {
  factory $FdxExportOutcomeCopyWith(FdxExportOutcome value, $Res Function(FdxExportOutcome) _then) = _$FdxExportOutcomeCopyWithImpl;
@useResult
$Res call({
 List<String> warnings
});




}
/// @nodoc
class _$FdxExportOutcomeCopyWithImpl<$Res>
    implements $FdxExportOutcomeCopyWith<$Res> {
  _$FdxExportOutcomeCopyWithImpl(this._self, this._then);

  final FdxExportOutcome _self;
  final $Res Function(FdxExportOutcome) _then;

/// Create a copy of FdxExportOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? warnings = null,}) {
  return _then(_self.copyWith(
warnings: null == warnings ? _self.warnings : warnings // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [FdxExportOutcome].
extension FdxExportOutcomePatterns on FdxExportOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FdxExportOutcome_NeedsConfirmation value)?  needsConfirmation,TResult Function( FdxExportOutcome_Finished value)?  finished,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FdxExportOutcome_NeedsConfirmation() when needsConfirmation != null:
return needsConfirmation(_that);case FdxExportOutcome_Finished() when finished != null:
return finished(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FdxExportOutcome_NeedsConfirmation value)  needsConfirmation,required TResult Function( FdxExportOutcome_Finished value)  finished,}){
final _that = this;
switch (_that) {
case FdxExportOutcome_NeedsConfirmation():
return needsConfirmation(_that);case FdxExportOutcome_Finished():
return finished(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FdxExportOutcome_NeedsConfirmation value)?  needsConfirmation,TResult? Function( FdxExportOutcome_Finished value)?  finished,}){
final _that = this;
switch (_that) {
case FdxExportOutcome_NeedsConfirmation() when needsConfirmation != null:
return needsConfirmation(_that);case FdxExportOutcome_Finished() when finished != null:
return finished(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<String> warnings,  int revision)?  needsConfirmation,TResult Function( SaveOutcome outcome,  List<String> warnings)?  finished,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FdxExportOutcome_NeedsConfirmation() when needsConfirmation != null:
return needsConfirmation(_that.warnings,_that.revision);case FdxExportOutcome_Finished() when finished != null:
return finished(_that.outcome,_that.warnings);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<String> warnings,  int revision)  needsConfirmation,required TResult Function( SaveOutcome outcome,  List<String> warnings)  finished,}) {final _that = this;
switch (_that) {
case FdxExportOutcome_NeedsConfirmation():
return needsConfirmation(_that.warnings,_that.revision);case FdxExportOutcome_Finished():
return finished(_that.outcome,_that.warnings);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<String> warnings,  int revision)?  needsConfirmation,TResult? Function( SaveOutcome outcome,  List<String> warnings)?  finished,}) {final _that = this;
switch (_that) {
case FdxExportOutcome_NeedsConfirmation() when needsConfirmation != null:
return needsConfirmation(_that.warnings,_that.revision);case FdxExportOutcome_Finished() when finished != null:
return finished(_that.outcome,_that.warnings);case _:
  return null;

}
}

}

/// @nodoc


class FdxExportOutcome_NeedsConfirmation extends FdxExportOutcome {
  const FdxExportOutcome_NeedsConfirmation({required final  List<String> warnings, required this.revision}): _warnings = warnings,super._();
  

 final  List<String> _warnings;
@override List<String> get warnings {
  if (_warnings is EqualUnmodifiableListView) return _warnings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_warnings);
}

 final  int revision;

/// Create a copy of FdxExportOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FdxExportOutcome_NeedsConfirmationCopyWith<FdxExportOutcome_NeedsConfirmation> get copyWith => _$FdxExportOutcome_NeedsConfirmationCopyWithImpl<FdxExportOutcome_NeedsConfirmation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FdxExportOutcome_NeedsConfirmation&&const DeepCollectionEquality().equals(other._warnings, _warnings)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_warnings),revision);

@override
String toString() {
  return 'FdxExportOutcome.needsConfirmation(warnings: $warnings, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $FdxExportOutcome_NeedsConfirmationCopyWith<$Res> implements $FdxExportOutcomeCopyWith<$Res> {
  factory $FdxExportOutcome_NeedsConfirmationCopyWith(FdxExportOutcome_NeedsConfirmation value, $Res Function(FdxExportOutcome_NeedsConfirmation) _then) = _$FdxExportOutcome_NeedsConfirmationCopyWithImpl;
@override @useResult
$Res call({
 List<String> warnings, int revision
});




}
/// @nodoc
class _$FdxExportOutcome_NeedsConfirmationCopyWithImpl<$Res>
    implements $FdxExportOutcome_NeedsConfirmationCopyWith<$Res> {
  _$FdxExportOutcome_NeedsConfirmationCopyWithImpl(this._self, this._then);

  final FdxExportOutcome_NeedsConfirmation _self;
  final $Res Function(FdxExportOutcome_NeedsConfirmation) _then;

/// Create a copy of FdxExportOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? warnings = null,Object? revision = null,}) {
  return _then(FdxExportOutcome_NeedsConfirmation(
warnings: null == warnings ? _self._warnings : warnings // ignore: cast_nullable_to_non_nullable
as List<String>,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FdxExportOutcome_Finished extends FdxExportOutcome {
  const FdxExportOutcome_Finished({required this.outcome, required final  List<String> warnings}): _warnings = warnings,super._();
  

 final  SaveOutcome outcome;
 final  List<String> _warnings;
@override List<String> get warnings {
  if (_warnings is EqualUnmodifiableListView) return _warnings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_warnings);
}


/// Create a copy of FdxExportOutcome
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FdxExportOutcome_FinishedCopyWith<FdxExportOutcome_Finished> get copyWith => _$FdxExportOutcome_FinishedCopyWithImpl<FdxExportOutcome_Finished>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FdxExportOutcome_Finished&&(identical(other.outcome, outcome) || other.outcome == outcome)&&const DeepCollectionEquality().equals(other._warnings, _warnings));
}


@override
int get hashCode => Object.hash(runtimeType,outcome,const DeepCollectionEquality().hash(_warnings));

@override
String toString() {
  return 'FdxExportOutcome.finished(outcome: $outcome, warnings: $warnings)';
}


}

/// @nodoc
abstract mixin class $FdxExportOutcome_FinishedCopyWith<$Res> implements $FdxExportOutcomeCopyWith<$Res> {
  factory $FdxExportOutcome_FinishedCopyWith(FdxExportOutcome_Finished value, $Res Function(FdxExportOutcome_Finished) _then) = _$FdxExportOutcome_FinishedCopyWithImpl;
@override @useResult
$Res call({
 SaveOutcome outcome, List<String> warnings
});


$SaveOutcomeCopyWith<$Res> get outcome;

}
/// @nodoc
class _$FdxExportOutcome_FinishedCopyWithImpl<$Res>
    implements $FdxExportOutcome_FinishedCopyWith<$Res> {
  _$FdxExportOutcome_FinishedCopyWithImpl(this._self, this._then);

  final FdxExportOutcome_Finished _self;
  final $Res Function(FdxExportOutcome_Finished) _then;

/// Create a copy of FdxExportOutcome
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? outcome = null,Object? warnings = null,}) {
  return _then(FdxExportOutcome_Finished(
outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as SaveOutcome,warnings: null == warnings ? _self._warnings : warnings // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

/// Create a copy of FdxExportOutcome
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SaveOutcomeCopyWith<$Res> get outcome {
  
  return $SaveOutcomeCopyWith<$Res>(_self.outcome, (value) {
    return _then(_self.copyWith(outcome: value));
  });
}
}

/// @nodoc
mixin _$FdxImportOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FdxImportOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'FdxImportOutcome()';
}


}

/// @nodoc
class $FdxImportOutcomeCopyWith<$Res>  {
$FdxImportOutcomeCopyWith(FdxImportOutcome _, $Res Function(FdxImportOutcome) __);
}


/// Adds pattern-matching-related methods to [FdxImportOutcome].
extension FdxImportOutcomePatterns on FdxImportOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FdxImportOutcome_Imported value)?  imported,TResult Function( FdxImportOutcome_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FdxImportOutcome_Imported() when imported != null:
return imported(_that);case FdxImportOutcome_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FdxImportOutcome_Imported value)  imported,required TResult Function( FdxImportOutcome_Failed value)  failed,}){
final _that = this;
switch (_that) {
case FdxImportOutcome_Imported():
return imported(_that);case FdxImportOutcome_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FdxImportOutcome_Imported value)?  imported,TResult? Function( FdxImportOutcome_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case FdxImportOutcome_Imported() when imported != null:
return imported(_that);case FdxImportOutcome_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( DocumentHandle handle,  List<String> warnings)?  imported,TResult Function( String message)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FdxImportOutcome_Imported() when imported != null:
return imported(_that.handle,_that.warnings);case FdxImportOutcome_Failed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( DocumentHandle handle,  List<String> warnings)  imported,required TResult Function( String message)  failed,}) {final _that = this;
switch (_that) {
case FdxImportOutcome_Imported():
return imported(_that.handle,_that.warnings);case FdxImportOutcome_Failed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( DocumentHandle handle,  List<String> warnings)?  imported,TResult? Function( String message)?  failed,}) {final _that = this;
switch (_that) {
case FdxImportOutcome_Imported() when imported != null:
return imported(_that.handle,_that.warnings);case FdxImportOutcome_Failed() when failed != null:
return failed(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class FdxImportOutcome_Imported extends FdxImportOutcome {
  const FdxImportOutcome_Imported({required this.handle, required final  List<String> warnings}): _warnings = warnings,super._();
  

 final  DocumentHandle handle;
 final  List<String> _warnings;
 List<String> get warnings {
  if (_warnings is EqualUnmodifiableListView) return _warnings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_warnings);
}


/// Create a copy of FdxImportOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FdxImportOutcome_ImportedCopyWith<FdxImportOutcome_Imported> get copyWith => _$FdxImportOutcome_ImportedCopyWithImpl<FdxImportOutcome_Imported>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FdxImportOutcome_Imported&&(identical(other.handle, handle) || other.handle == handle)&&const DeepCollectionEquality().equals(other._warnings, _warnings));
}


@override
int get hashCode => Object.hash(runtimeType,handle,const DeepCollectionEquality().hash(_warnings));

@override
String toString() {
  return 'FdxImportOutcome.imported(handle: $handle, warnings: $warnings)';
}


}

/// @nodoc
abstract mixin class $FdxImportOutcome_ImportedCopyWith<$Res> implements $FdxImportOutcomeCopyWith<$Res> {
  factory $FdxImportOutcome_ImportedCopyWith(FdxImportOutcome_Imported value, $Res Function(FdxImportOutcome_Imported) _then) = _$FdxImportOutcome_ImportedCopyWithImpl;
@useResult
$Res call({
 DocumentHandle handle, List<String> warnings
});




}
/// @nodoc
class _$FdxImportOutcome_ImportedCopyWithImpl<$Res>
    implements $FdxImportOutcome_ImportedCopyWith<$Res> {
  _$FdxImportOutcome_ImportedCopyWithImpl(this._self, this._then);

  final FdxImportOutcome_Imported _self;
  final $Res Function(FdxImportOutcome_Imported) _then;

/// Create a copy of FdxImportOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? handle = null,Object? warnings = null,}) {
  return _then(FdxImportOutcome_Imported(
handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as DocumentHandle,warnings: null == warnings ? _self._warnings : warnings // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc


class FdxImportOutcome_Failed extends FdxImportOutcome {
  const FdxImportOutcome_Failed({required this.message}): super._();
  

 final  String message;

/// Create a copy of FdxImportOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FdxImportOutcome_FailedCopyWith<FdxImportOutcome_Failed> get copyWith => _$FdxImportOutcome_FailedCopyWithImpl<FdxImportOutcome_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FdxImportOutcome_Failed&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'FdxImportOutcome.failed(message: $message)';
}


}

/// @nodoc
abstract mixin class $FdxImportOutcome_FailedCopyWith<$Res> implements $FdxImportOutcomeCopyWith<$Res> {
  factory $FdxImportOutcome_FailedCopyWith(FdxImportOutcome_Failed value, $Res Function(FdxImportOutcome_Failed) _then) = _$FdxImportOutcome_FailedCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$FdxImportOutcome_FailedCopyWithImpl<$Res>
    implements $FdxImportOutcome_FailedCopyWith<$Res> {
  _$FdxImportOutcome_FailedCopyWithImpl(this._self, this._then);

  final FdxImportOutcome_Failed _self;
  final $Res Function(FdxImportOutcome_Failed) _then;

/// Create a copy of FdxImportOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(FdxImportOutcome_Failed(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

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
