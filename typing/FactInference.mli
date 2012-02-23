(** This module analyzes data type declaration to synthetize facts about the
   data types. *)

val analyze_data_types: Types.env -> Types.env
val analyze_type: Types.env -> Types.typ -> Types.fact