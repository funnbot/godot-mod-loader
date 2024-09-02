const Codepoint = preload("res://addons/mod_loader/_export_plugin/tokenizer/codepoint.gd");
const Type = preload("res://addons/mod_loader/_export_plugin/tokenizer/token.gd").Type;

const MIN_LENGTH: int = 2;
const MAX_LENGTH: int = 10;

static func keyword(name: String) -> Type:
	# TODO: use StringName for faster comparison?
	# this isn't used for a real parser, so it wouldn't offer the same benefits that string internment usually does.
	match name.unicode_at(0):
		Codepoint.LO_A:
			match name:
				"as": return Type.AS;
				"and": return Type.AND;
				"assert": return Type.ASSERT;
				"await": return Type.AWAIT;
		Codepoint.LO_B:
			match name:
				"break": return Type.BREAK;
				"breakpoint": return Type.BREAKPOINT;
		Codepoint.LO_C:
			match name:
				"class": return Type.CLASS;
				"class_name": return Type.CLASS_NAME;
				"const": return Type.CONST;
				"continue": return Type.CONTINUE;
		Codepoint.LO_E:
			match name:
				"elif": return Type.ELIF;
				"else": return Type.ELSE;
				"enum": return Type.ENUM;
				"extends": return Type.EXTENDS;
		Codepoint.LO_F:
			match name:
				"for": return Type.FOR;
				"func": return Type.FUNC;
		Codepoint.LO_I:
			match name:
				"if": return Type.IF;
				"in": return Type.IN;
				"is": return Type.IS;
		Codepoint.LO_M:
			match name:
				"match": return Type.MATCH;
		Codepoint.LO_N:
			match name:
				"namespace": return Type.NAMESPACE;
				"not": return Type.NOT;
		Codepoint.LO_O:
			match name:
				"or": return Type.OR;
		Codepoint.LO_P:
			match name:
				"pass": return Type.PASS;
				"preload": return Type.PRELOAD;
		Codepoint.LO_R:
			match name:
				"return": return Type.RETURN;
		Codepoint.LO_S:
			match name:
				"self": return Type.SELF;
				"signal": return Type.SIGNAL;
				"static": return Type.STATIC;
				"super": return Type.SUPER;
		Codepoint.LO_T:
			match name:
				"trait": return Type.TRAIT;
		Codepoint.LO_V:
			match name:
				"var": return Type.VAR;
				"void": return Type.VOID;
		Codepoint.LO_W:
			match name:
				"while": return Type.WHILE;
				"when": return Type.WHEN;
		Codepoint.LO_Y:
			match name:
				"yield": return Type.YIELD;
		Codepoint.UP_I:
			match name:
				"INF": return Type.CONST_INF;
		Codepoint.UP_N:
			match name:
				"NAN": return Type.CONST_NAN;
		Codepoint.UP_P:
			match name:
				"PI": return Type.CONST_PI;
		Codepoint.UP_T:
			match name:
				"TAU": return Type.CONST_TAU;
	return Type.EMPTY;