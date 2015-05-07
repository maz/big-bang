%{
open TinyBang_Ast;;
%}
  
%token <string> IDENTIFIER
%token <string> LABEL
%token OPEN_BRACE
%token CLOSE_BRACE
%token BACKSLASH
%token SEMICOLON
%token EQUALS
%token AMPERSAND
%token ARROW
%token EMPTY_ONION
%token ASTERISK
%token EOF

%start <TinyBang_Ast.expr> prog

%%

prog:
  | expr EOF
      { $1 }
  ;

expr:
  | separated_nonempty_list(SEMICOLON, clause) SEMICOLON?
      { Expr $1 }
  ;

clause:
  | variable EQUALS redex
      { Clause($1,$3) }
  ;

variable:
  | identifier
      { Var $1 }
  ;
  
label:
  | LABEL
      { Label (Ident $1) }
  ;
  
identifier:
  | IDENTIFIER
      { Ident $1 }
  ;

redex:
  | value
      { Value_redex $1 }
  | variable
      { Var_redex $1 }
  | variable variable
      { Appl_redex($1,$2) }
  ;

value:
  | EMPTY_ONION
      { Empty_onion_value }
  | label variable
      { Label_value($1,$2) }
  | variable AMPERSAND variable
      { Onion_value($1,$3) }
  | pattern ARROW OPEN_BRACE expr CLOSE_BRACE
      { Function_value($1,$4) }

pattern:
  | variable BACKSLASH OPEN_BRACE filter_rule_set CLOSE_BRACE
      { Pattern($1,$4) }

filter_rule_set:
  | separated_nonempty_list(SEMICOLON, filter_rule) SEMICOLON?
      { Pattern_filter_rule_set.of_list $1 }

filter_rule:
  | variable EQUALS filter
      { Pattern_filter_rule($1,$3) }

filter:
  | EMPTY_ONION
      { Empty_filter }
  | label variable
      { Label_filter($1,$2) }
  | variable ASTERISK variable
      { Conjunction_filter($1,$3) }

