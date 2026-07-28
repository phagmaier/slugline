// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'doc.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$EditCommand {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'EditCommand()';
}


}

/// @nodoc
class $EditCommandCopyWith<$Res>  {
$EditCommandCopyWith(EditCommand _, $Res Function(EditCommand) __);
}


/// Adds pattern-matching-related methods to [EditCommand].
extension EditCommandPatterns on EditCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( EditCommand_ReplaceText value)?  replaceText,TResult Function( EditCommand_SplitBlock value)?  splitBlock,TResult Function( EditCommand_MergeBlocks value)?  mergeBlocks,TResult Function( EditCommand_SetKind value)?  setKind,TResult Function( EditCommand_InsertBlocks value)?  insertBlocks,TResult Function( EditCommand_DeleteRange value)?  deleteRange,TResult Function( EditCommand_MoveScene value)?  moveScene,TResult Function( EditCommand_SetDual value)?  setDual,required TResult orElse(),}){
final _that = this;
switch (_that) {
case EditCommand_ReplaceText() when replaceText != null:
return replaceText(_that);case EditCommand_SplitBlock() when splitBlock != null:
return splitBlock(_that);case EditCommand_MergeBlocks() when mergeBlocks != null:
return mergeBlocks(_that);case EditCommand_SetKind() when setKind != null:
return setKind(_that);case EditCommand_InsertBlocks() when insertBlocks != null:
return insertBlocks(_that);case EditCommand_DeleteRange() when deleteRange != null:
return deleteRange(_that);case EditCommand_MoveScene() when moveScene != null:
return moveScene(_that);case EditCommand_SetDual() when setDual != null:
return setDual(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( EditCommand_ReplaceText value)  replaceText,required TResult Function( EditCommand_SplitBlock value)  splitBlock,required TResult Function( EditCommand_MergeBlocks value)  mergeBlocks,required TResult Function( EditCommand_SetKind value)  setKind,required TResult Function( EditCommand_InsertBlocks value)  insertBlocks,required TResult Function( EditCommand_DeleteRange value)  deleteRange,required TResult Function( EditCommand_MoveScene value)  moveScene,required TResult Function( EditCommand_SetDual value)  setDual,}){
final _that = this;
switch (_that) {
case EditCommand_ReplaceText():
return replaceText(_that);case EditCommand_SplitBlock():
return splitBlock(_that);case EditCommand_MergeBlocks():
return mergeBlocks(_that);case EditCommand_SetKind():
return setKind(_that);case EditCommand_InsertBlocks():
return insertBlocks(_that);case EditCommand_DeleteRange():
return deleteRange(_that);case EditCommand_MoveScene():
return moveScene(_that);case EditCommand_SetDual():
return setDual(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( EditCommand_ReplaceText value)?  replaceText,TResult? Function( EditCommand_SplitBlock value)?  splitBlock,TResult? Function( EditCommand_MergeBlocks value)?  mergeBlocks,TResult? Function( EditCommand_SetKind value)?  setKind,TResult? Function( EditCommand_InsertBlocks value)?  insertBlocks,TResult? Function( EditCommand_DeleteRange value)?  deleteRange,TResult? Function( EditCommand_MoveScene value)?  moveScene,TResult? Function( EditCommand_SetDual value)?  setDual,}){
final _that = this;
switch (_that) {
case EditCommand_ReplaceText() when replaceText != null:
return replaceText(_that);case EditCommand_SplitBlock() when splitBlock != null:
return splitBlock(_that);case EditCommand_MergeBlocks() when mergeBlocks != null:
return mergeBlocks(_that);case EditCommand_SetKind() when setKind != null:
return setKind(_that);case EditCommand_InsertBlocks() when insertBlocks != null:
return insertBlocks(_that);case EditCommand_DeleteRange() when deleteRange != null:
return deleteRange(_that);case EditCommand_MoveScene() when moveScene != null:
return moveScene(_that);case EditCommand_SetDual() when setDual != null:
return setDual(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int block,  int startUtf16,  int endUtf16,  String with_)?  replaceText,TResult Function( int block,  int atUtf16)?  splitBlock,TResult Function( int first)?  mergeBlocks,TResult Function( int block,  BlockKind kind,  int sectionLevel,  bool forced)?  setKind,TResult Function( int? after,  List<NewBlock> blocks)?  insertBlocks,TResult Function( DocPosition from,  DocPosition to)?  deleteRange,TResult Function( int scene,  int? before)?  moveScene,TResult Function( int block,  bool dual)?  setDual,required TResult orElse(),}) {final _that = this;
switch (_that) {
case EditCommand_ReplaceText() when replaceText != null:
return replaceText(_that.block,_that.startUtf16,_that.endUtf16,_that.with_);case EditCommand_SplitBlock() when splitBlock != null:
return splitBlock(_that.block,_that.atUtf16);case EditCommand_MergeBlocks() when mergeBlocks != null:
return mergeBlocks(_that.first);case EditCommand_SetKind() when setKind != null:
return setKind(_that.block,_that.kind,_that.sectionLevel,_that.forced);case EditCommand_InsertBlocks() when insertBlocks != null:
return insertBlocks(_that.after,_that.blocks);case EditCommand_DeleteRange() when deleteRange != null:
return deleteRange(_that.from,_that.to);case EditCommand_MoveScene() when moveScene != null:
return moveScene(_that.scene,_that.before);case EditCommand_SetDual() when setDual != null:
return setDual(_that.block,_that.dual);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int block,  int startUtf16,  int endUtf16,  String with_)  replaceText,required TResult Function( int block,  int atUtf16)  splitBlock,required TResult Function( int first)  mergeBlocks,required TResult Function( int block,  BlockKind kind,  int sectionLevel,  bool forced)  setKind,required TResult Function( int? after,  List<NewBlock> blocks)  insertBlocks,required TResult Function( DocPosition from,  DocPosition to)  deleteRange,required TResult Function( int scene,  int? before)  moveScene,required TResult Function( int block,  bool dual)  setDual,}) {final _that = this;
switch (_that) {
case EditCommand_ReplaceText():
return replaceText(_that.block,_that.startUtf16,_that.endUtf16,_that.with_);case EditCommand_SplitBlock():
return splitBlock(_that.block,_that.atUtf16);case EditCommand_MergeBlocks():
return mergeBlocks(_that.first);case EditCommand_SetKind():
return setKind(_that.block,_that.kind,_that.sectionLevel,_that.forced);case EditCommand_InsertBlocks():
return insertBlocks(_that.after,_that.blocks);case EditCommand_DeleteRange():
return deleteRange(_that.from,_that.to);case EditCommand_MoveScene():
return moveScene(_that.scene,_that.before);case EditCommand_SetDual():
return setDual(_that.block,_that.dual);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int block,  int startUtf16,  int endUtf16,  String with_)?  replaceText,TResult? Function( int block,  int atUtf16)?  splitBlock,TResult? Function( int first)?  mergeBlocks,TResult? Function( int block,  BlockKind kind,  int sectionLevel,  bool forced)?  setKind,TResult? Function( int? after,  List<NewBlock> blocks)?  insertBlocks,TResult? Function( DocPosition from,  DocPosition to)?  deleteRange,TResult? Function( int scene,  int? before)?  moveScene,TResult? Function( int block,  bool dual)?  setDual,}) {final _that = this;
switch (_that) {
case EditCommand_ReplaceText() when replaceText != null:
return replaceText(_that.block,_that.startUtf16,_that.endUtf16,_that.with_);case EditCommand_SplitBlock() when splitBlock != null:
return splitBlock(_that.block,_that.atUtf16);case EditCommand_MergeBlocks() when mergeBlocks != null:
return mergeBlocks(_that.first);case EditCommand_SetKind() when setKind != null:
return setKind(_that.block,_that.kind,_that.sectionLevel,_that.forced);case EditCommand_InsertBlocks() when insertBlocks != null:
return insertBlocks(_that.after,_that.blocks);case EditCommand_DeleteRange() when deleteRange != null:
return deleteRange(_that.from,_that.to);case EditCommand_MoveScene() when moveScene != null:
return moveScene(_that.scene,_that.before);case EditCommand_SetDual() when setDual != null:
return setDual(_that.block,_that.dual);case _:
  return null;

}
}

}

/// @nodoc


class EditCommand_ReplaceText extends EditCommand {
  const EditCommand_ReplaceText({required this.block, required this.startUtf16, required this.endUtf16, required this.with_}): super._();
  

 final  int block;
 final  int startUtf16;
 final  int endUtf16;
 final  String with_;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditCommand_ReplaceTextCopyWith<EditCommand_ReplaceText> get copyWith => _$EditCommand_ReplaceTextCopyWithImpl<EditCommand_ReplaceText>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditCommand_ReplaceText&&(identical(other.block, block) || other.block == block)&&(identical(other.startUtf16, startUtf16) || other.startUtf16 == startUtf16)&&(identical(other.endUtf16, endUtf16) || other.endUtf16 == endUtf16)&&(identical(other.with_, with_) || other.with_ == with_));
}


@override
int get hashCode => Object.hash(runtimeType,block,startUtf16,endUtf16,with_);

@override
String toString() {
  return 'EditCommand.replaceText(block: $block, startUtf16: $startUtf16, endUtf16: $endUtf16, with_: $with_)';
}


}

/// @nodoc
abstract mixin class $EditCommand_ReplaceTextCopyWith<$Res> implements $EditCommandCopyWith<$Res> {
  factory $EditCommand_ReplaceTextCopyWith(EditCommand_ReplaceText value, $Res Function(EditCommand_ReplaceText) _then) = _$EditCommand_ReplaceTextCopyWithImpl;
@useResult
$Res call({
 int block, int startUtf16, int endUtf16, String with_
});




}
/// @nodoc
class _$EditCommand_ReplaceTextCopyWithImpl<$Res>
    implements $EditCommand_ReplaceTextCopyWith<$Res> {
  _$EditCommand_ReplaceTextCopyWithImpl(this._self, this._then);

  final EditCommand_ReplaceText _self;
  final $Res Function(EditCommand_ReplaceText) _then;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? block = null,Object? startUtf16 = null,Object? endUtf16 = null,Object? with_ = null,}) {
  return _then(EditCommand_ReplaceText(
block: null == block ? _self.block : block // ignore: cast_nullable_to_non_nullable
as int,startUtf16: null == startUtf16 ? _self.startUtf16 : startUtf16 // ignore: cast_nullable_to_non_nullable
as int,endUtf16: null == endUtf16 ? _self.endUtf16 : endUtf16 // ignore: cast_nullable_to_non_nullable
as int,with_: null == with_ ? _self.with_ : with_ // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EditCommand_SplitBlock extends EditCommand {
  const EditCommand_SplitBlock({required this.block, required this.atUtf16}): super._();
  

 final  int block;
 final  int atUtf16;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditCommand_SplitBlockCopyWith<EditCommand_SplitBlock> get copyWith => _$EditCommand_SplitBlockCopyWithImpl<EditCommand_SplitBlock>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditCommand_SplitBlock&&(identical(other.block, block) || other.block == block)&&(identical(other.atUtf16, atUtf16) || other.atUtf16 == atUtf16));
}


@override
int get hashCode => Object.hash(runtimeType,block,atUtf16);

@override
String toString() {
  return 'EditCommand.splitBlock(block: $block, atUtf16: $atUtf16)';
}


}

/// @nodoc
abstract mixin class $EditCommand_SplitBlockCopyWith<$Res> implements $EditCommandCopyWith<$Res> {
  factory $EditCommand_SplitBlockCopyWith(EditCommand_SplitBlock value, $Res Function(EditCommand_SplitBlock) _then) = _$EditCommand_SplitBlockCopyWithImpl;
@useResult
$Res call({
 int block, int atUtf16
});




}
/// @nodoc
class _$EditCommand_SplitBlockCopyWithImpl<$Res>
    implements $EditCommand_SplitBlockCopyWith<$Res> {
  _$EditCommand_SplitBlockCopyWithImpl(this._self, this._then);

  final EditCommand_SplitBlock _self;
  final $Res Function(EditCommand_SplitBlock) _then;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? block = null,Object? atUtf16 = null,}) {
  return _then(EditCommand_SplitBlock(
block: null == block ? _self.block : block // ignore: cast_nullable_to_non_nullable
as int,atUtf16: null == atUtf16 ? _self.atUtf16 : atUtf16 // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class EditCommand_MergeBlocks extends EditCommand {
  const EditCommand_MergeBlocks({required this.first}): super._();
  

 final  int first;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditCommand_MergeBlocksCopyWith<EditCommand_MergeBlocks> get copyWith => _$EditCommand_MergeBlocksCopyWithImpl<EditCommand_MergeBlocks>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditCommand_MergeBlocks&&(identical(other.first, first) || other.first == first));
}


@override
int get hashCode => Object.hash(runtimeType,first);

@override
String toString() {
  return 'EditCommand.mergeBlocks(first: $first)';
}


}

/// @nodoc
abstract mixin class $EditCommand_MergeBlocksCopyWith<$Res> implements $EditCommandCopyWith<$Res> {
  factory $EditCommand_MergeBlocksCopyWith(EditCommand_MergeBlocks value, $Res Function(EditCommand_MergeBlocks) _then) = _$EditCommand_MergeBlocksCopyWithImpl;
@useResult
$Res call({
 int first
});




}
/// @nodoc
class _$EditCommand_MergeBlocksCopyWithImpl<$Res>
    implements $EditCommand_MergeBlocksCopyWith<$Res> {
  _$EditCommand_MergeBlocksCopyWithImpl(this._self, this._then);

  final EditCommand_MergeBlocks _self;
  final $Res Function(EditCommand_MergeBlocks) _then;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? first = null,}) {
  return _then(EditCommand_MergeBlocks(
first: null == first ? _self.first : first // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class EditCommand_SetKind extends EditCommand {
  const EditCommand_SetKind({required this.block, required this.kind, required this.sectionLevel, required this.forced}): super._();
  

 final  int block;
 final  BlockKind kind;
 final  int sectionLevel;
 final  bool forced;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditCommand_SetKindCopyWith<EditCommand_SetKind> get copyWith => _$EditCommand_SetKindCopyWithImpl<EditCommand_SetKind>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditCommand_SetKind&&(identical(other.block, block) || other.block == block)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.sectionLevel, sectionLevel) || other.sectionLevel == sectionLevel)&&(identical(other.forced, forced) || other.forced == forced));
}


@override
int get hashCode => Object.hash(runtimeType,block,kind,sectionLevel,forced);

@override
String toString() {
  return 'EditCommand.setKind(block: $block, kind: $kind, sectionLevel: $sectionLevel, forced: $forced)';
}


}

/// @nodoc
abstract mixin class $EditCommand_SetKindCopyWith<$Res> implements $EditCommandCopyWith<$Res> {
  factory $EditCommand_SetKindCopyWith(EditCommand_SetKind value, $Res Function(EditCommand_SetKind) _then) = _$EditCommand_SetKindCopyWithImpl;
@useResult
$Res call({
 int block, BlockKind kind, int sectionLevel, bool forced
});




}
/// @nodoc
class _$EditCommand_SetKindCopyWithImpl<$Res>
    implements $EditCommand_SetKindCopyWith<$Res> {
  _$EditCommand_SetKindCopyWithImpl(this._self, this._then);

  final EditCommand_SetKind _self;
  final $Res Function(EditCommand_SetKind) _then;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? block = null,Object? kind = null,Object? sectionLevel = null,Object? forced = null,}) {
  return _then(EditCommand_SetKind(
block: null == block ? _self.block : block // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as BlockKind,sectionLevel: null == sectionLevel ? _self.sectionLevel : sectionLevel // ignore: cast_nullable_to_non_nullable
as int,forced: null == forced ? _self.forced : forced // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class EditCommand_InsertBlocks extends EditCommand {
  const EditCommand_InsertBlocks({this.after, required final  List<NewBlock> blocks}): _blocks = blocks,super._();
  

 final  int? after;
 final  List<NewBlock> _blocks;
 List<NewBlock> get blocks {
  if (_blocks is EqualUnmodifiableListView) return _blocks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_blocks);
}


/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditCommand_InsertBlocksCopyWith<EditCommand_InsertBlocks> get copyWith => _$EditCommand_InsertBlocksCopyWithImpl<EditCommand_InsertBlocks>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditCommand_InsertBlocks&&(identical(other.after, after) || other.after == after)&&const DeepCollectionEquality().equals(other._blocks, _blocks));
}


@override
int get hashCode => Object.hash(runtimeType,after,const DeepCollectionEquality().hash(_blocks));

@override
String toString() {
  return 'EditCommand.insertBlocks(after: $after, blocks: $blocks)';
}


}

/// @nodoc
abstract mixin class $EditCommand_InsertBlocksCopyWith<$Res> implements $EditCommandCopyWith<$Res> {
  factory $EditCommand_InsertBlocksCopyWith(EditCommand_InsertBlocks value, $Res Function(EditCommand_InsertBlocks) _then) = _$EditCommand_InsertBlocksCopyWithImpl;
@useResult
$Res call({
 int? after, List<NewBlock> blocks
});




}
/// @nodoc
class _$EditCommand_InsertBlocksCopyWithImpl<$Res>
    implements $EditCommand_InsertBlocksCopyWith<$Res> {
  _$EditCommand_InsertBlocksCopyWithImpl(this._self, this._then);

  final EditCommand_InsertBlocks _self;
  final $Res Function(EditCommand_InsertBlocks) _then;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? after = freezed,Object? blocks = null,}) {
  return _then(EditCommand_InsertBlocks(
after: freezed == after ? _self.after : after // ignore: cast_nullable_to_non_nullable
as int?,blocks: null == blocks ? _self._blocks : blocks // ignore: cast_nullable_to_non_nullable
as List<NewBlock>,
  ));
}


}

/// @nodoc


class EditCommand_DeleteRange extends EditCommand {
  const EditCommand_DeleteRange({required this.from, required this.to}): super._();
  

 final  DocPosition from;
 final  DocPosition to;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditCommand_DeleteRangeCopyWith<EditCommand_DeleteRange> get copyWith => _$EditCommand_DeleteRangeCopyWithImpl<EditCommand_DeleteRange>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditCommand_DeleteRange&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to));
}


@override
int get hashCode => Object.hash(runtimeType,from,to);

@override
String toString() {
  return 'EditCommand.deleteRange(from: $from, to: $to)';
}


}

/// @nodoc
abstract mixin class $EditCommand_DeleteRangeCopyWith<$Res> implements $EditCommandCopyWith<$Res> {
  factory $EditCommand_DeleteRangeCopyWith(EditCommand_DeleteRange value, $Res Function(EditCommand_DeleteRange) _then) = _$EditCommand_DeleteRangeCopyWithImpl;
@useResult
$Res call({
 DocPosition from, DocPosition to
});




}
/// @nodoc
class _$EditCommand_DeleteRangeCopyWithImpl<$Res>
    implements $EditCommand_DeleteRangeCopyWith<$Res> {
  _$EditCommand_DeleteRangeCopyWithImpl(this._self, this._then);

  final EditCommand_DeleteRange _self;
  final $Res Function(EditCommand_DeleteRange) _then;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? to = null,}) {
  return _then(EditCommand_DeleteRange(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as DocPosition,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as DocPosition,
  ));
}


}

/// @nodoc


class EditCommand_MoveScene extends EditCommand {
  const EditCommand_MoveScene({required this.scene, this.before}): super._();
  

 final  int scene;
 final  int? before;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditCommand_MoveSceneCopyWith<EditCommand_MoveScene> get copyWith => _$EditCommand_MoveSceneCopyWithImpl<EditCommand_MoveScene>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditCommand_MoveScene&&(identical(other.scene, scene) || other.scene == scene)&&(identical(other.before, before) || other.before == before));
}


@override
int get hashCode => Object.hash(runtimeType,scene,before);

@override
String toString() {
  return 'EditCommand.moveScene(scene: $scene, before: $before)';
}


}

/// @nodoc
abstract mixin class $EditCommand_MoveSceneCopyWith<$Res> implements $EditCommandCopyWith<$Res> {
  factory $EditCommand_MoveSceneCopyWith(EditCommand_MoveScene value, $Res Function(EditCommand_MoveScene) _then) = _$EditCommand_MoveSceneCopyWithImpl;
@useResult
$Res call({
 int scene, int? before
});




}
/// @nodoc
class _$EditCommand_MoveSceneCopyWithImpl<$Res>
    implements $EditCommand_MoveSceneCopyWith<$Res> {
  _$EditCommand_MoveSceneCopyWithImpl(this._self, this._then);

  final EditCommand_MoveScene _self;
  final $Res Function(EditCommand_MoveScene) _then;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? scene = null,Object? before = freezed,}) {
  return _then(EditCommand_MoveScene(
scene: null == scene ? _self.scene : scene // ignore: cast_nullable_to_non_nullable
as int,before: freezed == before ? _self.before : before // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class EditCommand_SetDual extends EditCommand {
  const EditCommand_SetDual({required this.block, required this.dual}): super._();
  

 final  int block;
 final  bool dual;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditCommand_SetDualCopyWith<EditCommand_SetDual> get copyWith => _$EditCommand_SetDualCopyWithImpl<EditCommand_SetDual>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditCommand_SetDual&&(identical(other.block, block) || other.block == block)&&(identical(other.dual, dual) || other.dual == dual));
}


@override
int get hashCode => Object.hash(runtimeType,block,dual);

@override
String toString() {
  return 'EditCommand.setDual(block: $block, dual: $dual)';
}


}

/// @nodoc
abstract mixin class $EditCommand_SetDualCopyWith<$Res> implements $EditCommandCopyWith<$Res> {
  factory $EditCommand_SetDualCopyWith(EditCommand_SetDual value, $Res Function(EditCommand_SetDual) _then) = _$EditCommand_SetDualCopyWithImpl;
@useResult
$Res call({
 int block, bool dual
});




}
/// @nodoc
class _$EditCommand_SetDualCopyWithImpl<$Res>
    implements $EditCommand_SetDualCopyWith<$Res> {
  _$EditCommand_SetDualCopyWithImpl(this._self, this._then);

  final EditCommand_SetDual _self;
  final $Res Function(EditCommand_SetDual) _then;

/// Create a copy of EditCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? block = null,Object? dual = null,}) {
  return _then(EditCommand_SetDual(
block: null == block ? _self.block : block // ignore: cast_nullable_to_non_nullable
as int,dual: null == dual ? _self.dual : dual // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$EditOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'EditOutcome()';
}


}

/// @nodoc
class $EditOutcomeCopyWith<$Res>  {
$EditOutcomeCopyWith(EditOutcome _, $Res Function(EditOutcome) __);
}


/// Adds pattern-matching-related methods to [EditOutcome].
extension EditOutcomePatterns on EditOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( EditOutcome_Applied value)?  applied,TResult Function( EditOutcome_Rejected value)?  rejected,required TResult orElse(),}){
final _that = this;
switch (_that) {
case EditOutcome_Applied() when applied != null:
return applied(_that);case EditOutcome_Rejected() when rejected != null:
return rejected(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( EditOutcome_Applied value)  applied,required TResult Function( EditOutcome_Rejected value)  rejected,}){
final _that = this;
switch (_that) {
case EditOutcome_Applied():
return applied(_that);case EditOutcome_Rejected():
return rejected(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( EditOutcome_Applied value)?  applied,TResult? Function( EditOutcome_Rejected value)?  rejected,}){
final _that = this;
switch (_that) {
case EditOutcome_Applied() when applied != null:
return applied(_that);case EditOutcome_Rejected() when rejected != null:
return rejected(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( EditResult result)?  applied,TResult Function( EditRejection reason,  String message)?  rejected,required TResult orElse(),}) {final _that = this;
switch (_that) {
case EditOutcome_Applied() when applied != null:
return applied(_that.result);case EditOutcome_Rejected() when rejected != null:
return rejected(_that.reason,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( EditResult result)  applied,required TResult Function( EditRejection reason,  String message)  rejected,}) {final _that = this;
switch (_that) {
case EditOutcome_Applied():
return applied(_that.result);case EditOutcome_Rejected():
return rejected(_that.reason,_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( EditResult result)?  applied,TResult? Function( EditRejection reason,  String message)?  rejected,}) {final _that = this;
switch (_that) {
case EditOutcome_Applied() when applied != null:
return applied(_that.result);case EditOutcome_Rejected() when rejected != null:
return rejected(_that.reason,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class EditOutcome_Applied extends EditOutcome {
  const EditOutcome_Applied({required this.result}): super._();
  

 final  EditResult result;

/// Create a copy of EditOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditOutcome_AppliedCopyWith<EditOutcome_Applied> get copyWith => _$EditOutcome_AppliedCopyWithImpl<EditOutcome_Applied>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditOutcome_Applied&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode => Object.hash(runtimeType,result);

@override
String toString() {
  return 'EditOutcome.applied(result: $result)';
}


}

/// @nodoc
abstract mixin class $EditOutcome_AppliedCopyWith<$Res> implements $EditOutcomeCopyWith<$Res> {
  factory $EditOutcome_AppliedCopyWith(EditOutcome_Applied value, $Res Function(EditOutcome_Applied) _then) = _$EditOutcome_AppliedCopyWithImpl;
@useResult
$Res call({
 EditResult result
});




}
/// @nodoc
class _$EditOutcome_AppliedCopyWithImpl<$Res>
    implements $EditOutcome_AppliedCopyWith<$Res> {
  _$EditOutcome_AppliedCopyWithImpl(this._self, this._then);

  final EditOutcome_Applied _self;
  final $Res Function(EditOutcome_Applied) _then;

/// Create a copy of EditOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? result = null,}) {
  return _then(EditOutcome_Applied(
result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as EditResult,
  ));
}


}

/// @nodoc


class EditOutcome_Rejected extends EditOutcome {
  const EditOutcome_Rejected({required this.reason, required this.message}): super._();
  

 final  EditRejection reason;
/// Human-readable, for the log and for test failures. Not for the UI.
 final  String message;

/// Create a copy of EditOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EditOutcome_RejectedCopyWith<EditOutcome_Rejected> get copyWith => _$EditOutcome_RejectedCopyWithImpl<EditOutcome_Rejected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EditOutcome_Rejected&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,reason,message);

@override
String toString() {
  return 'EditOutcome.rejected(reason: $reason, message: $message)';
}


}

/// @nodoc
abstract mixin class $EditOutcome_RejectedCopyWith<$Res> implements $EditOutcomeCopyWith<$Res> {
  factory $EditOutcome_RejectedCopyWith(EditOutcome_Rejected value, $Res Function(EditOutcome_Rejected) _then) = _$EditOutcome_RejectedCopyWithImpl;
@useResult
$Res call({
 EditRejection reason, String message
});




}
/// @nodoc
class _$EditOutcome_RejectedCopyWithImpl<$Res>
    implements $EditOutcome_RejectedCopyWith<$Res> {
  _$EditOutcome_RejectedCopyWithImpl(this._self, this._then);

  final EditOutcome_Rejected _self;
  final $Res Function(EditOutcome_Rejected) _then;

/// Create a copy of EditOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,Object? message = null,}) {
  return _then(EditOutcome_Rejected(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as EditRejection,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
