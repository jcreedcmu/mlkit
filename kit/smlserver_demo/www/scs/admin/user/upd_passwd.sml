val user_id = ScsLogin.auth_roles [ScsRole.SiteAdm]

val new_passwd = ScsDict.s [(ScsLang.en,`New Password`),(ScsLang.da,`Nyt kodeord`)]
val nullify_passwd = ScsDict.s [(ScsLang.en,`Nullify Password`),(ScsLang.da,`Slet kodeord`)]

val (person_id,errs) = ScsPerson.getPersonIdErr("person_id",ScsFormVar.emptyErr)
val (submit,errs) = ScsFormVar.getEnumErr [new_passwd,nullify_passwd] ("submit","",errs)
val _ = ScsFormVar.anyErrors errs

val _ =
  if submit = new_passwd then
    ScsDb.panicDml `update scs_users
                       set password = scs_user.gen_passwd(8)
                     where scs_users.user_id = '^(Int.toString person_id)'`
  else
    ScsDb.panicDml `update scs_users
                       set password = null
                     where scs_users.user_id = '^(Int.toString person_id)'`

val _ = ScsConn.returnRedirect "/scs/admin/user/index.sml" [("person_id",Int.toString person_id)]