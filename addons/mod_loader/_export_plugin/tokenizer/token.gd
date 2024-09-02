const _TokenType = preload("res://addons/mod_loader/_export_plugin/tokenizer/token_type.gd");
const Type = _TokenType.Type;
const TOKEN_NAMES = _TokenType.TOKEN_NAMES;

var type: Type = Type.EMPTY;
var literal: Variant = null;
var start_line: int = 0;
var end_line: int = 0;
var start_column: int = 0;
var end_column: int = 0;
# column span for multiline tokens
var leftmost_column: int = 0;
var rightmost_column: int = 0;
var source: String = String();

func _init(_type: Type) -> void:
	type = _type;

func get_name() -> String:
	assert(type >= 0 && type < TOKEN_NAMES.size());
	return TOKEN_NAMES[type];

func can_precede_bin_op() -> bool:
	match type:
		Type.IDENTIFIER, Type.LITERAL, Type.SELF, \
		Type.BRACKET_CLOSE, Type.BRACE_CLOSE, Type.PARENTHESIS_CLOSE, \
		Type.CONST_PI, Type.CONST_TAU, Type.CONST_INF, Type.CONST_NAN:
			return true;
		_:
			return false;

func is_identifier() -> bool:
	# Note: Most keywords should not be recognized as identifiers.
	# These are only exceptions for stuff that already is on the engine's API.

	# MATCH: Used in String.match().
	# WHEN: New keyword, avoid breaking existing code.
	# Allow constants to be treated as regular identifiers.
	match type:
		Type.IDENTIFIER, \
		Type.MATCH, \
		Type.WHEN, \
		Type.CONST_PI, Type.CONST_INF, Type.CONST_NAN, Type.CONST_TAU:
			return true;
		_:
			return false;

## public
func is_node_name() -> bool:
	# This is meant to allow keywords with the $ notation, but not as general identifiers.
	match type:
		Type.IDENTIFIER, \
		Type.AND, \
		Type.AS, \
		Type.ASSERT, \
		Type.AWAIT, \
		Type.BREAK, \
		Type.BREAKPOINT, \
		Type.CLASS_NAME, \
		Type.CLASS, \
		Type.CONST, \
		Type.CONST_PI, \
		Type.CONST_INF, \
		Type.CONST_NAN, \
		Type.CONST_TAU, \
		Type.CONTINUE, \
		Type.ELIF, \
		Type.ELSE, \
		Type.ENUM, \
		Type.EXTENDS, \
		Type.FOR, \
		Type.FUNC, \
		Type.IF, \
		Type.IN, \
		Type.IS, \
		Type.MATCH, \
		Type.NAMESPACE, \
		Type.NOT, \
		Type.OR, \
		Type.PASS, \
		Type.PRELOAD, \
		Type.RETURN, \
		Type.SELF, \
		Type.SIGNAL, \
		Type.STATIC, \
		Type.SUPER, \
		Type.TRAIT, \
		Type.UNDERSCORE, \
		Type.VAR, \
		Type.VOID, \
		Type.WHILE, \
		Type.WHEN, \
		Type.YIELD:
			return true;
		_:
			return false;

# TODO: String or StringName?
func get_identifier() -> StringName:
	return literal;

func _to_string() -> String:
	return get_name();