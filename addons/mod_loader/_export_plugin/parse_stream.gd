## This parser is not designed to be complete
## It must identify function definitions, top level or in inner classes.

const Tokenizer = preload("res://addons/mod_loader/_export_plugin/tokenizer/tokenizer.gd")
const Token = Tokenizer.Token;
const TType = Tokenizer.Type;

enum State {
    TOP_LEVEL,
    KW_STATIC,
    FUNC_DEF,
    CLASS_DEF,
    ASSIGNMENT,
    EXPRESSION,
    GROUPING,
    LAMBDA,
    ERROR,
    END
}

class ASTNode:
    var _tokens: Array[Token];
    pass ;

class ClassDef extends ASTNode:
    ## if class_name or is inner class
    var name: String;
    ## the parent class, extends
    var parent: String;
    ## null if top level class
    var outer: ASTNode;
    var stmts: Array[ASTNode];

class FuncDef extends ASTNode:
    var name: String;
    var args: String;
    var return_type: String;
    var is_static: bool;

class VarDef extends ASTNode:
    var name: String;
    var type: String;
    var value: String;
    var is_static: bool;
    var is_const: bool;
    var annotation: ASTNode;

class ErrorNode:
    var _message: String;
    func _init(message: String) -> void:
        _message = message;

var _tokenizer: Tokenizer;
var _indent_level: int;
var _state_stack: Array[State];
var _source: String;
var _ast: ClassDef;
var _current_token: Token;
var _consumed_token: Token;

func set_source_code(source: String) -> void:
    clear();
    _source = source;

func clear() -> void:
    _tokenizer = Tokenizer.new();
    _indent_level = 0;
    _state_stack = [State.TOP_LEVEL];
    _source = String();
    _ast = ClassDef.new();

func parse(source: String) -> Error:
    while true:
        var state := _state_stack.pop_back();
        var token := _tokenizer.scan();
        match token.type:
            TType.TK_EOF:
                if state != State.TOP_LEVEL:
                    return ERR_PARSE_ERROR;
                return OK;
            TType.ERROR: return ERR_PARSE_ERROR;
            TType.INDENT: _indent_level += 1;
            TType.DEDENT: _indent_level -= 1;
        assert(_indent_level >= 0);

        if state == State.END:
            return OK;
        if state == State.ERROR:
            return ERR_PARSE_ERROR;
        _state_stack.push_back(state);

    assert(false);
    return ERR_PARSE_ERROR;

func ast() -> ASTNode:
    return _ast;

func _advance() -> void:
    _consumed_token = _current_token;
    _current_token = _tokenizer.scan();

