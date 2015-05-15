(** A module containing the types publicly used by the type compatibility
    proof search module. *)
    
open Batteries;;

open Tiny_bang_types;;
    
type compatibility_result =
  | Compatibility_result of Constraint_database.t * bool list
;;

module Compatibility_result_ord =
struct
  type t = compatibility_result
  let compare = compare
end;;

module Compatibility_result_set = Set.Make(Compatibility_result_ord);;