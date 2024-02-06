signature OS_PROCESS =
  sig
    type status
    val success   : status
    val failure   : status
    val exit      : status -> 'a
  end

structure Process :> OS_PROCESS =
struct
  type status = int
  val success: status = 0
  val failure: status = ~1
  fun terminate(s:status): 'a = prim("_terminate", s)
  fun exit status = terminate status
end

signature OS_FILE_SYS =
  sig
    val chDir : string -> unit
    val getDir : unit -> string
    val modTime : string -> Time.time
  end

structure FileSys =
  struct
    val cwd = ref "/"
    fun chDir x = cwd := x
    fun getDir() = !cwd
    fun modTime f = Time.zeroTime (* XXX *)
  end
  
structure Process :> OS_PROCESS =
struct
  type status = int
  val success: status = 0
  val failure: status = ~1
  fun terminate(s:status): 'a = prim("_terminate", s)
  fun exit status = terminate status
end

signature OS = 
  sig
    type syserror

    exception SysErr of string * syserror option

    val errorMsg : syserror -> string
    val errorName : syserror -> string
    val syserror : string -> syserror option

    structure Path : OS_PATH

    structure Process : OS_PROCESS
    structure FileSys : OS_FILE_SYS
  end

structure OS :> OS = 
  struct
    type syserror = string

    exception SysErr of string * syserror option

    val errorMsg : syserror -> string = fn x => x
    val errorName : syserror -> string = fn x => x
    val syserror : string -> syserror option = fn _ => NONE

    structure Path = Path
    structure Process = Process
    structure FileSys = FileSys
  end

