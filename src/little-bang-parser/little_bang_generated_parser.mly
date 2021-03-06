%{
open Little_bang_ast;;
open Tiny_bang_ast;;
open Tiny_bang_parser_support;;
%}

%token <string> IDENTIFIER
%token <string> LABEL
%token <int> INT
%token EQUALS
%token AMPERSAND
%token ARROW
%token EMPTY_ONION
%token LEFT_PAREN
%token RIGHT_PAREN
%token ASTERISK
%token PLUS
%token MINUS
%token EQUALITY
%token LESS_THAN
%token KEYWORD_FUN
%token KEYWORD_LET
%token KEYWORD_IN
%token DOUBLE_SEMICOLON
%token EOF

%left LAM
%right KEYWORD_IN
(* %nonassoc '<=' '>=' '==' *)
%nonassoc EQUALITY LESS_THAN
(* %right '<-' *)
(* %left '+' '-' *)
%left PLUS MINUS
%left ASTERISK (* '/' '%' *)
%left AMPERSAND
(* %right 'putChar' *)

%start <Little_bang_ast.expr> prog
%start <Little_bang_ast.expr option> delim_expr

%%

prog:
  | expr EOF
      { $1 }
  ;

delim_expr:
  | EOF
      { None }
  | expr DOUBLE_SEMICOLON
      { Some($1) }
  | expr EOF
      { Some($1) }
  ;

expr:
  | KEYWORD_FUN pattern ARROW expr %prec LAM
      {
        Value_expr(
          (next_uid $startpos $endpos),
          Function((next_uid $startpos $endpos),$2,$4)
        )
      }
  | expr AMPERSAND expr
      { Onion_expr((next_uid $startpos $endpos),$1,$3) }
  | KEYWORD_LET variable EQUALS expr KEYWORD_IN expr
      { Let_expr((next_uid $startpos $endpos),$2,$4,$6) }
  | infix_expr
      { $1 }
  | appl_expr
      { $1 }
  ;

infix_expr:
  | expr PLUS expr
    { Builtin_expr ((next_uid $startpos $endpos),Op_int_plus,[$1;$3]) }
  | expr ASTERISK expr
    { Builtin_expr ((next_uid $startpos $endpos),Op_int_times,[$1;$3]) }
  | expr MINUS expr
    { Builtin_expr ((next_uid $startpos $endpos),Op_int_minus,[$1;$3]) }
  | expr EQUALITY expr
    { Builtin_expr ((next_uid $startpos $endpos),Op_int_equal,[$1;$3]) }
  | expr LESS_THAN expr
    { Builtin_expr ((next_uid $startpos $endpos),Op_int_lessthan,[$1;$3]) }
  ;

appl_expr:
  | appl_expr prefix_expr
      { Appl_expr((next_uid $startpos $endpos),$1,$2) }
  | prefix_expr
      { $1 }
  ;

prefix_expr:
  | label prefix_expr
      { Label_expr((next_uid $startpos $endpos),$1,$2) }
  | primary_expr
      { $1 }
  ;

primary_expr:
  | literal
      { Value_expr((next_uid $startpos $endpos),$1) }
  | variable
      { Var_expr((next_uid $startpos $endpos),$1) }
  | LEFT_PAREN expr RIGHT_PAREN
      { $2 }
  ;

literal:
  | EMPTY_ONION
      { Empty_onion((next_uid $startpos $endpos)) }
  | INT
      { Little_bang_ast.Int_value ((next_uid $startpos $endpos), $1) }
;

variable:
  | identifier
      { Little_bang_ast.Var((next_uid $startpos $endpos),$1) }
  ;

label:
  | LABEL
      { Label (Tiny_bang_ast.Ident $1) }
  ;

identifier:
  | IDENTIFIER
      { Little_bang_ast.Ident $1 }
  ;


pattern:
  | pattern ASTERISK pattern
      { Conjunction_pattern((next_uid $startpos $endpos),$1,$3) }
  | primary_pattern
      { $1 }
  ;

primary_pattern:
  | variable
      { Var_pattern((next_uid $startpos $endpos),$1) }
  | EMPTY_ONION
      { Empty_pattern((next_uid $startpos $endpos)) }
  | label primary_pattern
      { Label_pattern((next_uid $startpos $endpos),$1,$2) }
  | LEFT_PAREN pattern RIGHT_PAREN
      { $2 }
  ;
