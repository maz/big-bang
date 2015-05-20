open Batteries;;

open Tiny_bang_ast_pretty;;
open Tiny_bang_interpreter;;
open Tiny_bang_typechecker;;

let toploop_operate e =
  print_string "\n";
  (if typecheck e
    then
      let v,env = eval e in
      print_string (pretty_var v ^ " where "  ^ pretty_env env ^ "\n");
      print_string "\n"
    else
      print_string "Type error.\n");
  print_string "Please enter an expression to evaluate followed by \";;\".\n";
  print_string "\n";
  flush stdout
;;

let () =
  print_string "TinyBang 0.3 Toploop\n";
  print_string "--------------------\n";
  print_string "\n";
  print_string "Please enter an expression to evaluate followed by \";;\".\n";
  print_string "\n";
  flush stdout;
  Tiny_bang_parser.parse_tiny_bang_expressions IO.stdin
    |> LazyList.map fst
    |> LazyList.iter toploop_operate
;;
