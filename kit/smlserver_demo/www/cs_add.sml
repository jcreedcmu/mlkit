val s = Option.valOf (FormVar.getString "text")

val sql_insert = "insert into cs (text, id) values ('" ^ (Db.qq s) ^ "'," ^ (Db.seq_nextval_exp "cs_seq") ^ ")"
val _ = Db.dml sql_insert

val _ = Ns.returnRedirect "cs_form.sml"