const Token = preload("res://addons/mod_loader/_export_plugin/tokenizer/token.gd");
const Type = Token.Type;
const Codepoint = preload("res://addons/mod_loader/_export_plugin/tokenizer/codepoint.gd");
const Keyword = preload("res://addons/mod_loader/_export_plugin/tokenizer/keyword.gd");

class IndentStack:
	var a: Array[int] = [];

class Comments:
	var _dict: Dictionary = {};

	func insert(key: int, comment: String, new_line: bool) -> void:
		_dict[key] = {comment: comment, new_line: new_line};

	func has(key: int) -> bool:
		return _dict.has(key);

	## unsafe, use has() first
	func comment(key: int) -> String:
		assert(_dict.has(key));
		return _dict[key].comment;

	## unsafe, use has() first
	func new_line(key: int) -> bool:
		assert(_dict.has(key));
		return _dict[key].new_line;

var _source: String = "";

## value of `_peek()`, updated by `_advance()`
var _current_char: int = Codepoint.NULL;
## value of `_peek(-1)`, updated by `_advance()`
var _previous_char: int = Codepoint.NULL;

var _line: int = -1;
var _column: int = -1;
# var cursor_line: int = -1;
# var cursor_column: int = -1;
var _tab_size: int = 4;

# multichar tokens
var _start_index: int = -1;
var _start_line: int = 0;
var _start_column: int = 0;
# multiline tokens
var _leftmost_column: int = 0;
var _rightmost_column: int = 0;

# == info cache ==
var _line_continuation: bool = false; # previous line ends with '\'
var _multiline_mode: bool = false;
var _error_stack: Array[Token] = [];
var _pending_newline: bool = false;
var _last_token: Token = Token.new(Type.EMPTY);
var _last_newline: Token = Token.new(Type.EMPTY);
var _pending_indents: int = 0;
var _indent_stack: IndentStack = IndentStack.new();
# for lambdas, which require manipulating the indentation point.
var _indent_stack_stack: Array[IndentStack] = [];
## array of Codepoint
var _paren_stack: Array[int] = [];
## Codepoint
var _indent_char: int = Codepoint.NULL;
## position
var _index: int = 0;
## length
var _length: int = 0;
var _continuation_lines: Array[int] = [];
# var keyword_list: Array[String] = [];
var _comments: Comments = Comments.new();
var _keep_comments: bool = true;

## public
## I believe this should be used as a const reference by the parser
func get_continuation_lines() -> Array[int]:
	return _continuation_lines;

## public
func is_text() -> bool:
	return true;

## public
## only populated if _keep_comments is true
func get_comments() -> Comments:
	return _comments;

## public
func set_source_code(source: String) -> void:
	_source = source;
	_length = source.length();
	if _length == 0:
		_current_char = Codepoint.NULL;
	else:
		_current_char = _source.unicode_at(0);
	_previous_char = Codepoint.NULL;
	_line = 1;
	_column = 1;
	_index = 0;

## public
## the parser keeps a multiline_stack
func set_multiline_mode(state: bool) -> void:
	_multiline_mode = state;

## public
## called when a lambda is encountered
func push_expression_indented_block() -> void:
	_indent_stack_stack.push_back(_indent_stack);

## public
## return the indentation tracking to the outer scope once the lambda is done
func pop_expression_indented_block() -> void:
	assert(not _indent_stack_stack.is_empty());
	_indent_stack = _indent_stack_stack.pop_back();

func _is_at_end() -> bool:
	return _index >= _length;

func _peek(offset: int = 0) -> int:
	var idx = _index + offset;
	if idx >= 0 and idx < _length:
		return _source.unicode_at(idx);
	else:
		return Codepoint.NULL;

func _indent_level() -> int:
	return _indent_stack.a.size();

func _has_error() -> bool:
	return not _error_stack.is_empty();

func _advance() -> int:
	if _is_at_end():
		return Codepoint.NULL;
	_previous_char = _current_char;
	_column += 1;
	_index += 1;
	if (_column > _rightmost_column):
		_rightmost_column = _column;
	if _is_at_end():
		_newline(true);
		_check_indent();
		_current_char = Codepoint.NULL;
	else:
		_current_char = _source.unicode_at(_index);
	# guarenteed valid
	return _source.unicode_at(_index - 1);

func _consume_if_eq(ch: int) -> bool:
	if _current_char != ch:
		return false;
	_advance();
	return true;

func _push_paren(paren: int) -> void:
	_paren_stack.push_back(paren);

func _pop_paren(expected: int) -> bool:
	if _paren_stack.is_empty():
		return false;
	return _paren_stack.pop_back() == expected;

func _make_token(type: Type) -> Token:
	var token: Token = Token.new(type);
	token.start_line = _start_line;
	token.end_line = _line;
	token.start_column = _start_column;
	token.end_column = _column;
	token.leftmost_column = _leftmost_column;
	token.rightmost_column = _rightmost_column;
	# _current == _source[_index]
	# _start == _source[_start_index] 
	token.source = _source.substr(_start_index, _index - _start_index);

	_last_token = token;
	return token;

func _make_literal(literal: Variant) -> Token:
	var token: Token = _make_token(Type.LITERAL);
	token.literal = literal;
	return token;

func _make_identifier(identifier: StringName) -> Token:
	var token: Token = _make_token(Type.IDENTIFIER);
	token.literal = identifier;
	return token;

func _make_error(message: String) -> Token:
	var token: Token = _make_token(Type.ERROR);
	token.literal = message;
	return token;

func _report_error(error: Variant) -> void:
	if error is Token:
		_error_stack.push_back(error);
	elif error is String:
		_error_stack.push_back(_make_error(error));
	else:
		assert(false);
		push_error('Invalid error type: ' + str(typeof(error)));

func _report_char_error(message: String) -> void:
	var token: Token = _make_error(message);
	token.start_column = _column;
	token.leftmost_column = _column;
	token.end_column = _column + 1;
	token.rightmost_column = _column + 1;
	_report_error(token);

func _make_paren_error(paren: int) -> Token:
	if _paren_stack.is_empty():
		return _make_error("Closing \"%s\" doesn't have an opening counterpart." % String.chr(paren));
	var token: Token = _make_error("Closing \"%s\" doesn't match opening \"%s\"." %
		[String.chr(paren), String.chr(_paren_stack.back())]);
	return token;

func _check_vcs_marker(test: int, double_type: Type) -> Token:
	var next: int = _peek(1);
	var chars: int = 2; # Two already matched
	# Test before consuming characters, since we don't want to consume more than needed.
	while next == test:
		chars += 1;
		next += 1;
	if chars >= 7:
		# It is a VCS conflict marker.
		while chars > 1:
			# Consume all characters (first was already consumed by scan()).
			_advance();
			chars -= 1;
		return _make_token(Type.VCS_CONFLICT_MARKER);
	else:
		# It is only a regular double character token, so we consume the second character.
		_advance();
		return _make_token(double_type);

func _annotation() -> Token:
	if Codepoint.is_unicode_identifier_start(_peek()):
		_advance(); # Consume start character.
	else:
		push_error("Expected token identifier after \"@\".");
	while Codepoint.is_unicode_identifier_continue(_peek()):
		_advance(); # Consume all identifier characters.
	var token: Token = _make_token(Type.ANNOTATION);
	# TODO: StringName?
	token.literal = token.source;
	return token;

func _potential_identifier() -> Token:
	var only_ascii: bool = _peek(-1) < 128;

	# Consume all identifier characters.
	while Codepoint.is_unicode_identifier_continue(_peek()):
		var c: int = _advance();
		only_ascii = only_ascii and c < 128;
	
	var len: int = _index - _start_index;

	if len == 1 and _peek(-1) == Codepoint.UNDERSCORE:
		# Lone underscore
		var token: Token = _make_token(Type.UNDERSCORE);
		token.literal = "_";
		return token;
	
	var name: String = _source.substr(_start_index, len);

	if len < Keyword.MIN_LENGTH or len > Keyword.MAX_LENGTH:
		return _make_identifier(name);
	
	if not only_ascii:
		return _make_identifier(name);

	var first_char: int = name.unicode_at(0);
	var kw_type: Type = Keyword.keyword(name);
	if kw_type != Type.EMPTY:
		var token: Token = _make_token(kw_type);
		token.literal = name;
		return token;
	
	# special literals
	if len == 4:
		if name == "true":
			return _make_literal(true as Variant);
		elif name == "null":
			return _make_literal(null as Variant);
	elif len == 5:
		if name == "false":
			return _make_literal(false as Variant);

	# must be a regular identifier
	return _make_identifier(name);

func _newline(_make_token: bool) -> void:
	# Don't overwrite previous newline, nor create if we want a line continuation.
	if _make_token and not _pending_newline and not _line_continuation:
		var token: Token = Token.new(Type.NEWLINE);
		token.start_line = _line;
		token.end_line = _line;
		token.start_column = _column - 1;
		token.end_column = _column;
		token.leftmost_column = token.start_column;
		token.rightmost_column = token.end_column;
		_pending_newline = true;
		_last_token = token;
		_last_newline = token;

	_line += 1;
	_column = 1;
	_leftmost_column = 1;

func _number() -> Token:
	var base: int = 10;
	var has_decimal: bool = false;
	var has_exponent: bool = false;
	var has_error: bool = false;
	var need_digits: bool = false;
	var digit_check_func: Callable = Codepoint.is_digit;

	# sign before hexadecimal or binary.
	var ch: int = _peek(-1);
	if (ch == Codepoint.PLUS or ch == Codepoint.MINUS) and _peek() == Codepoint.DIGIT_0:
		ch = _advance();

	if ch == Codepoint.PERIOD:
		has_decimal = true;
	elif ch == Codepoint.DIGIT_0:
		if _current_char == Codepoint.LO_X:
			# hexadecimal
			base = 16;
			digit_check_func = Codepoint.is_hex_digit;
			need_digits = true;
			_advance();
		elif _current_char == Codepoint.LO_B:
			base = 2;
			digit_check_func = Codepoint.is_binary_digit;
			need_digits = true;
			_advance();

	# initial digit
	ch = _peek();
	# disallow `0x_` and `0b_`
	if base != 10 and ch == Codepoint.UNDERSCORE:
		_report_char_error("Unexpected underscore after 0%c" % _peek(-1));
		has_error = true;

	var previous_was_underscore: bool = false;
	while true:
		if not (digit_check_func.call(_current_char) or _current_char == Codepoint.UNDERSCORE):
			break ;

		if _current_char == Codepoint.UNDERSCORE:
			if previous_was_underscore:
				_report_char_error("Multiple underscores cannot be adjacent in a numeric literal.");
				# not a fatal error
			previous_was_underscore = true;
		else:
			need_digits = false;
			previous_was_underscore = false;

		_advance();
	
	ch = _peek();
	# might be a ".." token instead of decimal point
	if ch == Codepoint.PERIOD and _peek(1) != Codepoint.PERIOD:
		if base == 10 and not has_decimal:
			has_decimal = true;
		elif base == 10:
			_report_char_error("Cannot use a decimal point twice in a _number.");
			has_error = true;
		elif base == 16:
			_report_char_error("Cannot use a decimal point in a hexadecimal _number.");
			has_error = true;
		else:
			_report_char_error("Cannot use a decimal point in a binary _number.");
			has_error = true;
		if not has_error:
			_advance();
	
		if not has_error:
			_advance();
			ch = _peek();
			# consume decimal token
			if Codepoint.UNDERSCORE == ch:
				_report_char_error("Unexpected underscore after decimal point.");
				has_error = true;
			previous_was_underscore = false;
			while Codepoint.is_digit(ch) or ch == Codepoint.UNDERSCORE:
				ch = _peek();
				if ch == Codepoint.UNDERSCORE:
					if previous_was_underscore:
						_report_char_error("Multiple underscores cannot be adjacent in a numeric literal.");
						# not a fatal error
					previous_was_underscore = true;
				else:
					previous_was_underscore = false;
				_advance();
	
	if base == 10 and (_current_char == Codepoint.LO_E or _current_char == Codepoint.UP_E):
		has_exponent = true;
		_advance();
		if _current_char == Codepoint.PLUS or _current_char == Codepoint.MINUS:
			# exponent sign
			_advance();
		# consume exponent digits
		if not Codepoint.is_digit(_current_char):
			_report_char_error("Expected digit after exponent.");
		previous_was_underscore = false;
		while Codepoint.is_digit(_current_char) or _current_char == Codepoint.UNDERSCORE:
			if _current_char == Codepoint.UNDERSCORE:
				if previous_was_underscore:
					_report_char_error("Multiple underscores cannot be adjacent in a numeric literal.");
					# not a fatal error
				previous_was_underscore = true;
			else:
				previous_was_underscore = false;
			_advance();
	
	if need_digits:
		_report_char_error("Expected %s digit after \"0%c\"" %
			["hexadecimal" if base == 16 else "binary", "x" if base == 16 else "b"]);

	if not has_error and has_decimal and _current_char == Codepoint.PERIOD and _peek(1) != Codepoint.PERIOD:
		_report_char_error("Cannot use a decimal point twice in a _number.");
		has_error = true;
	elif Codepoint.is_unicode_identifier_start(_current_char) or Codepoint.is_unicode_identifier_continue(_current_char):
		# letter at the end of the _number.
		_report_error("Invalid numeric notation.");
	
	var len: int = _index - _start_index;
	var number_str = _source.substr(_start_index, len).replace("_", "");

	if base == 16:
		return _make_literal(number_str.hex_to_int());
	elif base == 2:
		return _make_literal(number_str.bin_to_int());
	elif has_decimal or has_exponent:
		return _make_literal(number_str.to_float());
	else:
		return _make_literal(number_str.to_int());

enum StringType {
	REGULAR,
	STRING_NAME,
	NODEPATH
}

func _string() -> Token:
	var is_raw: bool = false;
	var is_multiline: bool = false;
	var type: StringType = StringType.REGULAR;

	if _previous_char == Codepoint.LO_R:
		is_raw = true;
		_advance();
	elif _previous_char == Codepoint.AMPERSAND:
		type = StringType.STRING_NAME;
		_advance();
	elif _previous_char == Codepoint.CARET:
		type = StringType.NODEPATH;
		_advance();

	var quote_char: int = _previous_char;

	if _current_char == quote_char and _peek(1) == quote_char:
		is_multiline = true;
		# consume all quotes
		_advance();
		_advance();
	
	# TODO: use PackedStringArray with String.join() instead of concatenation
	var result: String = "";

	# for building a utf-16 codepoint from a surrogate pair
	var prev_char: int = Codepoint.NULL;
	var prev_pos: int = 0;

	while true:
		# consume actual _string
		if _is_at_end():
			return _make_error("Unterminated _string.");
		if Codepoint.is_invisible_direction_control(_current_char):
			if is_raw:
				_report_char_error("Invisible text direction control character present in the _string, use regular _string literal instead of r-_string.");
			else:
				_report_char_error("Invisible text direction control character present in the _string, escape it (\"\\u%s\") to avoid confusion."
					% String.num_int64(_current_char, 16));
		if _current_char == Codepoint.BACKSLASH:
			# escape pattern
			_advance();
			if _is_at_end():
				return _make_error("Unterminated _string.");
			if is_raw:
				if _consume_if_eq(quote_char):
					if _is_at_end():
						return _make_error("Unterminated _string.");
					result += "\\";
					result += String.chr(quote_char);
				elif _consume_if_eq(Codepoint.BACKSLASH):
					if _is_at_end():
						return _make_error("Unterminated _string.");
					result += "\\";
					result += "\\";
				else:
					result += "\\";
				continue ; # while true

			var escape_char: int = _current_char;
			_advance();
			if _is_at_end():
				return _make_error("Unterminated _string.");
			## `Codepoint` constant or unicode 8/16 codepoint value
			var escaped: int = 0;
			var valid_escape := true;
			
			match escape_char:
				Codepoint.LO_A: escaped = Codepoint.ALERT;
				Codepoint.LO_B: escaped = Codepoint.BACKSPACE;
				Codepoint.LO_F: escaped = Codepoint.FORM_FEED;
				Codepoint.LO_N: escaped = Codepoint.LINE_FEED;
				Codepoint.LO_R: escaped = Codepoint.CARRIAGE_RETURN;
				Codepoint.LO_T: escaped = Codepoint.TAB;
				Codepoint.LO_V: escaped = Codepoint.VERTICAL_TAB;
				Codepoint.SINGLE_QUOTE: escaped = Codepoint.SINGLE_QUOTE;
				Codepoint.DOUBLE_QUOTE: escaped = Codepoint.DOUBLE_QUOTE;
				Codepoint.BACKSLASH: escaped = Codepoint.BACKSLASH;
				Codepoint.UP_U, Codepoint.LO_U:
					var hex_len: int = 6 if escape_char == Codepoint.UP_U else 4;
					for i in range(hex_len):
						if _is_at_end():
							return _make_error("Unterminated _string.");
						
						var digit: int = _current_char;
						var value: int = 0;
						if Codepoint.is_digit(digit):
							value = digit - Codepoint.DIGIT_0;
						elif digit >= Codepoint.LO_A and digit <= Codepoint.LO_F:
							value = (digit - Codepoint.LO_A) + 10;
						elif digit >= Codepoint.UP_A and digit <= Codepoint.UP_F:
							value = (digit - Codepoint.UP_A) + 10;
						else:
							_report_char_error("Invalid hexadecimal digit in unicode escape sequence");
							valid_escape = false;
							break ; # for i in range(hex_len)
						
						escaped <<= 4;
						escaped |= value;
						_advance();
				# escape at the end of a line, breaking a _string across multiple lines
				Codepoint.CARRIAGE_RETURN, Codepoint.LINE_FEED:
					if escape_char == Codepoint.CARRIAGE_RETURN:
						if _current_char != Codepoint.LINE_FEED:
							# carraige return without newline
							# just add it and keep going
							result += "\r";
							_advance();
					# escaping newline
					_newline(false);
					# to not add it to the _string
					valid_escape = false;
				_:
					var error: Token = _make_error("Invalid escape in _string.");
					error.start_column = _column - 2;
					error.leftmost_column = error.start_column;
					_report_error(error);
					valid_escape = false;

			if valid_escape:
				if (escaped & 0xfffffc00) == 0xd800:
					if prev_char == Codepoint.NULL:
						prev_char = escaped;
						prev_pos = _column - 2;
						continue ; # while true
					else:
						var error: Token = _make_error("Invalid UTF-16 sequence in _string, unpaired lead surrogate.");
						error.start_column = prev_pos;
						error.leftmost_column = error.start_column;
						_report_error(error);
						valid_escape = false;
						prev_char = Codepoint.NULL;
				elif (escaped & 0xfffffc00) == 0xdc00:
					if prev_char == Codepoint.NULL:
						var error: Token = _make_error("Invalid UTF-16 sequence in _string, unpaired trail surrogate.");
						error.start_column = _column - 2;
						error.leftmost_column = error.start_column;
						_report_error(error);
						valid_escape = false;
					else:
						# 0x35fdc00 == ((0xd800 << 10UL) + 0xdc00 - 0x10000)
						escaped = (prev_char << 0xA) + escaped - 0x35fdc00;
						prev_char = Codepoint.NULL;
				if prev_char != Codepoint.NULL:
					var error: Token = _make_error("Invalid UTF-16 sequence in _string, unpaired lead surrogate.");
					error.start_column = prev_pos;
					error.leftmost_column = error.start_column;
					_report_error(error);
					prev_char = Codepoint.NULL;
			
			if valid_escape:
				result += String.chr(escaped);
			
		elif _current_char == quote_char:
			if prev_char != Codepoint.NULL:
				var error: Token = _make_error("Invalid UTF-16 sequence in _string, unpaired lead surrogate.");
				error.start_column = prev_pos;
				error.leftmost_column = error.start_column;
				_report_error(error);
				prev_char = Codepoint.NULL;
			_advance();
			if is_multiline:
				if _current_char == quote_char and _peek(1) == quote_char:
					# ended the multiline _string
					_advance();
					_advance();
					break ; # while true
				else:
					result += String.chr(quote_char);
			else:
				# ended single line _string
				break ; # while true

		else:
			if prev_char != Codepoint.NULL:
				var error: Token = _make_error("Invalid UTF-16 sequence in _string, unpaired lead surrogate.");
				error.start_column = prev_pos;
				error.leftmost_column = error.start_column;
				_report_error(error);
				prev_char = Codepoint.NULL;
			result += String.chr(_current_char);
			_advance();
			if _current_char == Codepoint.LINE_FEED:
				_newline(false);
		
	if prev_char != Codepoint.NULL:
		var error: Token = _make_error("Invalid UTF-16 sequence in _string, unpaired lead surrogate.");
		error.start_column = prev_pos;
		error.leftmost_column = error.start_column;
		_report_error(error);
		prev_char = Codepoint.NULL;
		
	match type:
		StringType.STRING_NAME:
			return _make_literal(StringName(result));
		StringType.NODEPATH:
			return _make_literal(NodePath(result));
		StringType.REGULAR:
			return _make_literal(result);

	assert(false, "type %i is not a StringType" % type);
	return Token.new(Type.EMPTY);

func _check_indent() -> void:
	assert(_column == 1, "Checking tokenizer indentation in the middle of a line.");
	if _is_at_end():
		_pending_indents -= _indent_level();
		_indent_stack.a.clear();
		return ;

	while true:
		var current_indent_char: int = _current_char;
		var indent_count: int = 0;

		if current_indent_char != Codepoint.SPACE and current_indent_char != Codepoint.TAB and \
			current_indent_char != Codepoint.CARRIAGE_RETURN and current_indent_char != Codepoint.LINE_FEED and \
			current_indent_char != Codepoint.NUMBER_SIGN:
			# first char of line is not whitespace, so clear all indentation levels
			# unless inside expression
			if _line_continuation or _multiline_mode:
				return ;
			_pending_indents -= _indent_level();
			_indent_stack.a.clear();
			return ;
		
		if _current_char == Codepoint.CARRIAGE_RETURN:
			_advance();
			if _current_char != Codepoint.LINE_FEED:
				_report_error("Stray carriage return character in source code.");
		if _current_char == Codepoint.LINE_FEED:
			# empty new line, keep going
			_advance();
			_newline(false);
			continue ;

		var mixed := false;
		while !_is_at_end():
			if _current_char == Codepoint.TAB:
				# consider individual tab columns
				_column += _tab_size - 1;
				indent_count += _tab_size;
			elif _current_char == Codepoint.SPACE:
				indent_count += 1;
			else:
				break ;
			mixed = mixed or _current_char != current_indent_char;
			_advance();
		
		if _is_at_end():
			# reached the end with an empty line, dedent as much as needed
			_pending_indents -= _indent_level();
			_indent_stack.a.clear();
			return ;
		
		if _current_char == Codepoint.CARRIAGE_RETURN:
			_advance();
			if _current_char != Codepoint.LINE_FEED:
				_report_error("Stray carriage return character in source code.");
		if _current_char == Codepoint.LINE_FEED:
			# empty line, keep going
			_advance();
			_newline(false);
			continue ;
		if _current_char == Codepoint.NUMBER_SIGN:
			# comment, _advance to next line
			if _keep_comments:
				var comment: String = "";
				while _current_char != Codepoint.LINE_FEED and not _is_at_end():
					comment += String.chr(_advance());
				_comments.insert(_line, comment, true);
			else:
				while _current_char != Codepoint.LINE_FEED and not _is_at_end():
					_advance();
			if _is_at_end():
				_pending_indents -= _indent_level();
				_indent_stack.a.clear();
				return ;
			_advance(); # consume newline
			_newline(false);
			continue ;
		
		if mixed and not _line_continuation and not _multiline_mode:
			var error: Token = _make_error("Mixed indentation (spaces and tabs) not allowed.");
			error.start_column = 1;
			error.leftmost_column = 1;
			error.rightmost_column = _column;
			_report_error(error);
		
		if _line_continuation or _multiline_mode:
			# already cleared whitespace at beginning of line
			# don't want any indentation changes
			return ;
		
		if _indent_char == Codepoint.NULL:
			# first time indenting, choose character now
			_indent_char = current_indent_char;
		elif current_indent_char != _indent_char:
			var error: Token = _make_error("Used %s character for indentation instead of %s as used before in the file." %
				[_get_indent_char_name(current_indent_char), _get_indent_char_name(_indent_char)]);
			error.start_line = _line;
			error.start_column = 1;
			error.leftmost_column = 1;
			error.rightmost_column = _column;
			_report_error(error);

		# check if indent or dedent
		var previous_indent: int = 0;
		if _indent_level() > 0:
			previous_indent = _indent_stack.a.back();
		if indent_count == previous_indent:
			# no change in indentation
			return ;
		if indent_count > previous_indent:
			# indent increase
			_indent_stack.a.push_back(indent_count);
			_pending_indents += 1;
		else:
			# indent decrease
			if _indent_level() == 0:
				_report_error("Tokenizer bug: trying to dedent without previous indent.");
				return ;
			while _indent_level() > 0 and _indent_stack.a.back() > indent_count:
				_indent_stack.a.pop_back();
				_pending_indents -= 1;
			if (_indent_level() > 0 and _indent_stack.a.back() != indent_count) or (_indent_level() == 0 and indent_count != 0):
				var error: Token = _make_error("Unindent doesn't match any outer indentation level.");
				error.start_line = _line;
				error.start_column = 1;
				error.leftmost_column = 1;
				error.end_column = _column + 1;
				error.rightmost_column = _column + 1;
				_report_error(error);
				# keep going to report more errors
				_indent_stack.a.push_back(indent_count);
		break ;

func _get_indent_char_name(ch: int) -> String:
	assert(ch == Codepoint.SPACE or ch == Codepoint.TAB);
	return "space" if ch == Codepoint.SPACE else "tab";

func _skip_whitespace() -> void:
	if _pending_indents != 0:
		return ;
	
	var is_bol: bool = _column == 1;
	if is_bol:
		_check_indent();
		return ;
	
	while true:
		match _current_char:
			Codepoint.SPACE:
				_advance();
			Codepoint.TAB:
				_advance();
				_column += _tab_size - 1;
			Codepoint.CARRIAGE_RETURN:
				_advance();
				if _current_char != Codepoint.LINE_FEED:
					_report_error("Stray carriage return character in source code.");
					return ;
			Codepoint.LINE_FEED:
				_advance();
				_newline(not is_bol);
				_check_indent();
			Codepoint.NUMBER_SIGN:
				if _keep_comments:
					var comment: String = "";
					while _current_char != Codepoint.LINE_FEED and not _is_at_end():
						comment += String.chr(_advance());
					_comments.insert(_line, comment, is_bol);
				else:
					while _current_char != Codepoint.LINE_FEED and not _is_at_end():
						_advance();
				if _is_at_end():
					return ;
				_advance(); # consume newline
				_newline(not is_bol);
				_check_indent();
			_:
				return ;

## public
func scan() -> Token:
	if _has_error():
		return _error_stack.pop_back();
	
	_skip_whitespace();

	if _pending_newline:
		_pending_newline = false;
		if not _multiline_mode:
			return _last_newline;
	
	if _has_error():
		return _error_stack.pop_back();
	
	_start_index = _index;
	_start_line = _line;
	_start_column = _column;
	_leftmost_column = _column;
	_rightmost_column = _column;

	if _pending_indents != 0:
		_start_index -= _start_column - 1;
		_start_column = 1;
		_leftmost_column = 1;
		if _pending_indents > 0:
			_pending_indents -= 1;
			return _make_token(Type.INDENT);
		else:
			# dedents
			_pending_indents += 1;
			var dedent: Token = _make_token(Type.DEDENT);
			dedent.end_column += 1;
			dedent.rightmost_column += 1;
			return dedent;
	
	if _is_at_end():
		return _make_token(Type.TK_EOF);
	
	_advance();

	if _previous_char == Codepoint.BACKSLASH:
		# line continuation with backslash
		if _current_char == Codepoint.CARRIAGE_RETURN:
			if _peek(1) != Codepoint.LINE_FEED:
				return _make_error("Unexpected carriage return character.");
			_advance();
		if _current_char != Codepoint.LINE_FEED:
			return _make_error("Expected new line after \"\\\".");
		_advance();
		_newline(false);
		_line_continuation = true;
		_skip_whitespace(); # Skip whitespace/comment lines after `\`. See GH-89403.
		_continuation_lines.push_back(_line);
		return scan();
	
	_line_continuation = false;

	if Codepoint.is_digit(_previous_char):
		return _number();
	elif _previous_char == Codepoint.LO_R and (_current_char == Codepoint.SINGLE_QUOTE or _current_char == Codepoint.DOUBLE_QUOTE):
		return _string();
	elif Codepoint.is_unicode_identifier_start(_previous_char):
		return _potential_identifier();
	
	match _previous_char:
		Codepoint.DOUBLE_QUOTE, Codepoint.SINGLE_QUOTE:
			return _string();
		Codepoint.AT:
			return _annotation();
		Codepoint.TILDE:
			return _make_token(Type.TILDE);
		Codepoint.COMMA:
			return _make_token(Type.COMMA);
		Codepoint.COLON:
			return _make_token(Type.COLON);
		Codepoint.SEMICOLON:
			return _make_token(Type.SEMICOLON);
		Codepoint.DOLLAR:
			return _make_token(Type.DOLLAR);
		Codepoint.AMPERSAND:
			return _make_token(Type.AMPERSAND);
		Codepoint.QUESTION_MARK:
			return _make_token(Type.QUESTION_MARK);
		Codepoint.GRAVE:
			return _make_token(Type.BACKTICK);
		Codepoint.PARENTHESES_OPEN:
			_push_paren(Codepoint.PARENTHESES_OPEN);
			return _make_token(Type.PARENTHESIS_OPEN);
		Codepoint.BRACKET_OPEN:
			_push_paren(Codepoint.BRACKET_OPEN);
			return _make_token(Type.BRACKET_OPEN);
		Codepoint.BRACE_OPEN:
			_push_paren(Codepoint.BRACE_OPEN);
			return _make_token(Type.BRACE_OPEN);
		Codepoint.PARENTHESES_CLOSE:
			if not _pop_paren(Codepoint.PARENTHESES_OPEN):
				return _make_paren_error(Codepoint.PARENTHESES_CLOSE);
			return _make_token(Type.PARENTHESIS_CLOSE);
		Codepoint.BRACE_CLOSE:
			if not _pop_paren(Codepoint.BRACE_OPEN):
				return _make_paren_error(Codepoint.BRACE_CLOSE);
			return _make_token(Type.BRACE_CLOSE);
		Codepoint.BRACKET_CLOSE:
			if not _pop_paren(Codepoint.BRACKET_OPEN):
				return _make_paren_error(Codepoint.BRACKET_CLOSE);
			return _make_token(Type.BRACKET_CLOSE);
		Codepoint.EXCLAMATION:
			if _consume_if_eq(Codepoint.EQUAL):
				return _make_token(Type.BANG_EQUAL);
			return _make_token(Type.BANG);
		Codepoint.PERIOD:
			if _consume_if_eq(Codepoint.PERIOD):
				return _make_token(Type.PERIOD_PERIOD);
			return _make_token(Type.PERIOD);
		Codepoint.PLUS:
			if _consume_if_eq(Codepoint.EQUAL):
				return _make_token(Type.PLUS_EQUAL);
			elif Codepoint.is_digit(_current_char) and not _last_token.can_precede_bin_op():
				return _number();
			return _make_token(Type.PLUS);
		Codepoint.MINUS:
			if _consume_if_eq(Codepoint.EQUAL):
				return _make_token(Type.MINUS_EQUAL);
			elif Codepoint.is_digit(_current_char) and not _last_token.can_precede_bin_op():
				return _number();
			elif _consume_if_eq(Codepoint.GREATER_THAN):
				return _make_token(Type.FORWARD_ARROW);
			return _make_token(Type.MINUS);
		Codepoint.ASTERISK:
			if _consume_if_eq(Codepoint.EQUAL):
				return _make_token(Type.STAR_EQUAL);
			elif _consume_if_eq(Codepoint.ASTERISK):
				if _consume_if_eq(Codepoint.EQUAL):
					return _make_token(Type.STAR_STAR_EQUAL);
				return _make_token(Type.STAR_STAR);
			return _make_token(Type.STAR);
		Codepoint.FORWARD_SLASH:
			if _consume_if_eq(Codepoint.EQUAL):
				return _make_token(Type.SLASH_EQUAL);
			return _make_token(Type.SLASH);
		Codepoint.PERCENT:
			if _consume_if_eq(Codepoint.EQUAL):
				return _make_token(Type.PERCENT_EQUAL);
			return _make_token(Type.PERCENT);
		Codepoint.CARET:
			if _consume_if_eq(Codepoint.EQUAL):
				return _make_token(Type.CARET_EQUAL);
			elif _current_char == Codepoint.DOUBLE_QUOTE or _current_char == Codepoint.SINGLE_QUOTE:
				return _string(); # node path
			return _make_token(Type.CARET);
		Codepoint.AMPERSAND:
			if _consume_if_eq(Codepoint.AMPERSAND):
				return _make_token(Type.AMPERSAND_AMPERSAND);
			elif _consume_if_eq(Codepoint.EQUAL):
				return _make_token(Type.AMPERSAND_EQUAL);
			elif _current_char == Codepoint.DOUBLE_QUOTE or _current_char == Codepoint.SINGLE_QUOTE:
				return _string(); # string name
			return _make_token(Type.AMPERSAND);
		Codepoint.VERTICAL_BAR:
			if _consume_if_eq(Codepoint.VERTICAL_BAR):
				return _make_token(Type.PIPE_PIPE);
			elif _consume_if_eq(Codepoint.EQUAL):
				return _make_token(Type.PIPE_EQUAL);
			return _make_token(Type.PIPE);
		Codepoint.EQUAL:
			if _current_char == Codepoint.EQUAL:
				return _check_vcs_marker(Codepoint.EQUAL, Type.EQUAL_EQUAL);
			return _make_token(Type.EQUAL);
		Codepoint.LESS_THAN:
			if _consume_if_eq(Codepoint.EQUAL):
				return _make_token(Type.LESS_EQUAL);
			elif _current_char == Codepoint.LESS_THAN:
				if _peek(1) == Codepoint.EQUAL:
					_advance();
					_advance();
					return _make_token(Type.LESS_LESS_EQUAL);
				else:
					return _check_vcs_marker(Codepoint.LESS_THAN, Type.LESS_LESS);
			return _make_token(Type.LESS);
		Codepoint.GREATER_THAN:
			if _consume_if_eq(Codepoint.EQUAL):
				return _make_token(Type.GREATER_EQUAL);
			elif _current_char == Codepoint.GREATER_THAN:
				if _peek(1) == Codepoint.EQUAL:
					_advance();
					_advance();
					return _make_token(Type.GREATER_GREATER_EQUAL);
				else:
					return _check_vcs_marker(Codepoint.GREATER_THAN, Type.GREATER_GREATER);
			return _make_token(Type.GREATER);
		_:
			if Codepoint.is_whitespace(_previous_char):
				return _make_error("Invalid white space character U+%04X." % _previous_char);
			else:
				return _make_error("Invalid character \"%c\" (U+%04X)." % [_current_char, _current_char]);

func _init():
	pass ;
