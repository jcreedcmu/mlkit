signature SML_OF_NJ =
sig
 (* https://www.smlnj.org/doc/SMLofNJ/pages/smlnj.html *)
 val exnHistory : exn -> string list
end

structure SMLofNJ =
struct
 fun exnHistory e = [] (* XXX *)
end