signature SCS_DB =
  sig
    val dbClickDml    : string -> string -> string -> string -> quot -> unit
    val panicDml      : quot -> unit
    val panicDmlTrans : (Db.db -> 'a) -> 'a
    val errorDml      : quot -> quot -> unit
    val toggleP       : string -> string -> string -> string -> unit

    val oneFieldErrPg : quot * quot -> string
    val oneRowErrPg'  : (((string -> string)->'a) * quot * quot) -> 'a

    val ppDate        : string -> string
  end

structure ScsDb :> SCS_DB =
  struct
    fun dbClickDml table_name id_column_name generated_id return_url insert_sql =
      if Db.dml insert_sql = Ns.OK then
        (Ns.returnRedirect return_url; Ns.exit())
      else if Db.existsOneRow `select 1 as num from ^table_name where ^id_column_name = '^(Db.qq generated_id)'` 
	     then (Ns.returnRedirect return_url; Ns.exit()) (* it's a double click, so just redirect the user to the index page *)
	   else ScsError.panic (`DbFunctor.dbClickDml choked. DB returned error on SQL ` ^^ insert_sql)
	     handle X => ScsError.panic (`DbFunctor.dbClickDml choked. DB returned error on SQL ` ^^ insert_sql ^^ `^(General.exnMessage X)`)

    fun panicDml f = Db.panicDml ScsError.panic f
    fun panicDmlTrans f = Db.panicDmlTrans ScsError.panic f
    fun errorDml emsg sql = (Db.errorDml (fn () => (Ns.log (Ns.Notice, "hej");ScsPage.returnPg "Databasefejl" emsg)) sql;())
    fun toggleP table column_id column id =
      panicDml `update ^table set ^column=(case when ^column = 't' then 'f' else 't' end)
                 where ^table.^column_id=^(Db.qq' id)`

    fun oneRowErrPg' (f,sql,emsg) =
      Db.oneRow' (f,sql) handle _ => (ScsPage.returnPg "" emsg;Ns.exit())

    fun oneFieldErrPg (sql,emsg) =
      Db.oneField sql handle _ => (ScsPage.returnPg "" emsg;Ns.exit())

    val ppDate = ScsDate.ppDb o Db.toDate
  end







