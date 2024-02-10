structure TextIO :> TEXT_IO where type elem = char and type vector = string
  = struct
  type elem = char
  type vector = CharVector.vector

  datatype file0 = Open_file of string list ref
                 | Closed_file of string

  type file = file0 ref

  type fs = (string * file) list ref

  datatype outstream = stdOut | stdErr | FileOs of file

  val fs : fs = ref []

  fun openOut0 append s =
      case List.find (fn (s',_) => s = s') (!fs) of
        SOME (_,r) =>
        (case !r of
           Closed_file f =>
           let val f = if append then [f] else []
           in r := Open_file(ref f)
            ; FileOs r
           end
         | Open_file _ => raise Fail ("File already open: " ^ s))
      | NONE =>
        let val f : file = ref (Open_file(ref[]))
        in fs := (s,f) :: !fs
         ; FileOs f
        end
  val openOut = openOut0 false
  val openAppend = openOut0 true

  fun output(os,s) =
      case os of
        stdOut => print s
      | stdErr => print s
      | FileOs (ref(Open_file f)) => f := s :: !f
      | _ => raise Fail "output: outstream closed"

  fun closeOut os =
      case os of
        FileOs r =>
        (case !r of
           Open_file f =>
           r := Closed_file (String.concat(rev(!f)))
         | _ => ())
      | _ => ()

  fun output1(os,c) = output(os,Char.toString c)
  fun outputSubstr(os,ss) = output(os,Substring.string ss)

  fun flushOut _ = ()

  val print = print


  (* input *)
  datatype instream =
			  Null
			  | stdIn
			  | StringStream of string * int ref

  fun unimpl s = raise (Fail ("TextIO." ^ s ^ ": unimplemented"))
  fun openIn _ = unimpl "openIn"
  fun openString s = StringStream(s, ref 0)
  fun closeIn _ = unimpl "closeIn"
  fun input _ = unimpl "input"
  fun inputAll _ = unimpl "inputAll"

(*not supported by MOSCOW ML either; it raises an exception.
  val inputNoBlock : instream -> vector option
*)
  fun input1 stdIn = NONE
	 | input1 Null = NONE
	 | input1 (StringStream(s,pos)) =
		let
		  val c = String.sub (s, !pos)
		  val _ = pos := (!pos) + 1
		in
		  SOME c
		end
		handle Subscript => NONE

  fun inputN _ = unimpl "inputN"

  fun inputLine is =
      let fun loop(acc) =
	           case input1 is
					of SOME (c as #"\n") => SOME(implode(rev(c :: acc)))
					 | SOME c => loop(c::acc)
					 | NONE => case acc
									of [] => NONE
									 | _ => SOME(implode(rev(#"\n" :: acc)))
      in loop([])
      end

  fun endOfStream _ = unimpl "endOfStream"
  fun lookahead _ = unimpl "lookahead"

  type cs = unit (* character source state *)

  fun scanStream _ _ = unimpl "scanStream"

end
