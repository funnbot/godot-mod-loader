const Token = preload("res://addons/mod_loader/_export_plugin/tokenizer/token.gd");

const SPACE = " ";
const TAB = "\t";
const NEWLINE = "\n";

# better than String concat, stand in for a StringBuilder
var _output: PackedStringArray;
var _indent_char: int;
var _indent_char_size: int;
var _indent_level: int;

func output() -> String:
    return "".join(_output);

func clear() -> void:
    _output = PackedStringArray();
    _indent_char = 0;
    _indent_level = 0;

func _newline() -> void:
    _output.push_back(NEWLINE);