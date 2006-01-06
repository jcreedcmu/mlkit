
functor Manager(structure ManagerObjects : MANAGER_OBJECTS where type absprjid = string
		structure IntModules : INT_MODULES where type absprjid = string
		sharing type ManagerObjects.IntBasis = IntModules.IntBasis
		sharing type ManagerObjects.modcode = IntModules.modcode) 
    : MANAGER =
  struct
    structure PP = PrettyPrint
    structure MO = ManagerObjects
    structure Basis = MO.Basis
    structure FunStamp = MO.FunStamp
    structure ModCode = MO.ModCode
    structure IntBasis = MO.IntBasis
    structure ElabBasis = ModuleEnvironments.B
    structure ErrorCode = ParseElab.ErrorCode
    structure H = Polyhash

    fun testout(s: string):unit = TextIO.output(TextIO.stdOut, s)
    fun testouttree(t:PP.StringTree) = PP.outputTree(testout,t,80)

    type absprjid = ModuleEnvironments.absprjid
    type InfixBasis = ManagerObjects.InfixBasis
    type ElabBasis = ManagerObjects.ElabBasis
    type IntBasis = ManagerObjects.IntBasis
    type opaq_env = ManagerObjects.opaq_env

    fun die s = Crash.impossible ("Manager." ^ s)

    val op ## = OS.Path.concat infix ##

    val region_profiling = Flags.is_on0 "region_profiling"

    val extendedtyping = 
	(Flags.add_bool_entry 
	 {long="extended_typing", short=SOME "xt", neg=false, 
	  item=ref false,
	  menu=["Control", "extended typing (SMLserver)"],
	  desc="When this flag is enabled, SMLserver requires\n\
	   \scripts to be functor SCRIPTLET's, which are\n\
	   \automatically instantiated by SMLserver in a\n\
	   \type safe way. To construct and link to XHTML\n\
	   \forms in a type safe way, SMLserver constructs an\n\
	   \abstract interface to the forms from the functor\n\
	   \arguments of the scriptlets. This interface is\n\
	   \constructed and written to the file scripts.gen.sml\n\
	   \prior to the actual type checking and compilation\n\
	   \of the project."}
	  ; Flags.is_on0 "extended_typing")	      

    val print_export_bases = 
	(Flags.add_bool_entry 
	 {long="print_export_bases", short=SOME "Peb", neg=false, 
	  item=ref false,
	  menu=["Debug", "print export bases"],
	  desc="Controls printing of export bases."}
	  ; Flags.is_on0 "print_export_bases")	      

    val print_closed_export_bases = 
	(Flags.add_bool_entry 
	 {long="print_closed_export_bases", short=SOME "Pceb", neg=false, 
	  item=ref false,
	  menu=["Debug", "print closed export bases"],
	  desc="Controls printing of closed export bases."}
	  ; Flags.is_on0 "print_closed_export_bases")	      
	  
    val run_file = ref "run"
    val _ = Flags.add_string_entry 
      {long="output", short=SOME "o", item=run_file,
       menu=["File", "output file name"],
       desc="The name of the executable file generated by\n\
	\the Kit."}

    val _ = Flags.add_stringlist_entry 
      {long="link_code", short=SOME "link", item=ref nil,
       menu=["File", "link files"],
       desc="Link-files to be linked together to form an\n\
	\executable."}

    val _ = Flags.add_stringlist_entry 
      {long="link_code_scripts", short=SOME "link_scripts", item=ref nil,
       menu=["File", "link files scripts"],
       desc="Link-files for SMLserver scripts; link-files\n\
	\specified with -link represent libraries when\n\
	\mlkit is used with SMLserver."}

    val _ = Flags.add_stringlist_entry 
      {long="load_basis_files", short=SOME "load", item=ref nil,
       menu=["File", "Basis files to load before compilation"],
       desc="Basis files to be loaded before compilation\n\
	\proper."}

    val _ = Flags.add_string_entry 
      {long="namebase", short=NONE, item=ref "dummyBase",
       menu=["File", "Name base"],
       desc="Name base to enforce unique names when compiling\n\
	\mlb-files."}

    exception PARSE_ELAB_ERROR = MO.PARSE_ELAB_ERROR
    fun error a = MO.error a
    val quot = MO.quot

    (* SMLserver components *)

    (* Support for parsing scriptlet form argument - i.e., functor
     * arguments *)
    structure Scriptlet = Scriptlet(val error = error)

    (* -----------------------------------------
     * Unit names, file names and directories
     * ----------------------------------------- *)

    type filename = MO.filename       (* At some point we should use *)
                                      (* abstract types for these things *)
                                      (* so that we correctly distinguish *)
                                      (* unit names and file names. *)

    fun unitname_to_logfile unitname = unitname ^ ".log"
    fun unitname_to_sourcefile unitname = MO.mk_filename unitname (*mads ^ ".sml"*)
    fun filename_to_unitname (f:filename) : string = MO.filename_to_string f

    val log_to_file = Flags.lookup_flag_entry "log_to_file"

    (* ----------------------------------------------------
     * log_init  gives you back a function for cleaning up
     * ---------------------------------------------------- *)

    fun log_init unitname =
      let val old_log_stream = !Flags.log
	  val log_file = unitname_to_logfile unitname
	  val source_file = unitname_to_sourcefile unitname
      in if !log_to_file then
	   let val log_stream = TextIO.openOut log_file
	             handle IO.Io {name=msg,...} => 
		       die ("Cannot open log file\n\
			    \(non-exsisting directory or write-\
			    \protected existing log file?)\n" ^ msg)
	       fun log_init() = (Flags.log := log_stream;
				 TextIO.output (log_stream, "\n\n********** "
					 ^ MO.filename_to_string source_file ^ " *************\n\n"))
	       fun log_cleanup() = (Flags.log := old_log_stream; TextIO.closeOut log_stream;
				    TextIO.output (TextIO.stdOut, "[wrote log file:\t" ^ log_file ^ "]\n"))
	   in log_init();
	      log_cleanup
	   end
	 else 
	   let val log_stream = TextIO.stdOut
	       fun log_init() = Flags.log := log_stream
	       fun log_cleanup() = Flags.log := old_log_stream
	   in log_init();
	      log_cleanup
	   end
      end

    fun log (s:string) : unit = TextIO.output (!Flags.log, s)
    fun log_st (st) : unit = PP.outputTree (log, st, 70)
    fun pr_st (st) : unit = PP.outputTree (print, st, 120)
    fun chat s = if !Flags.chat then log (s ^ "\n") else ()
	  	
    (* ------------------------------------------- 
     * Debugging and reporting
     * ------------------------------------------- *)

    fun print_error_report report = Report.print' report (!Flags.log)
    fun print_result_report report = (Report.print' report (!Flags.log);
				      Flags.report_warnings ())

    type Basis = MO.Basis
    type modcode = MO.modcode

    local (* Pickling *)

	fun readFile f : string = 
	    let val is = BinIO.openIn f
	    in let val v = BinIO.inputAll is
		   val s = Byte.bytesToString v
	       in BinIO.closeIn is; s
	       end handle ? => (BinIO.closeIn is; raise ?)
	    end

	val pchat = chat
	fun sizeToStr sz = 
	    if sz < 10000 then Int.toString sz ^ " bytes"
	    else if sz < 10000000 then Int.toString (sz div 1024) ^ "Kb (" ^ Int.toString sz ^ " bytes)" 
		 else Int.toString ((sz div 1024) div 1024) ^ "Mb (" ^ Int.toString sz ^ " bytes)"
		     
	type timer = (string * Timer.cpu_timer * Timer.real_timer)
	    
	fun timerStart (s:string) : timer =
	    (s,Timer.startCPUTimer(),Timer.startRealTimer())
	    
	fun timerReport ((s,cputimer,realtimer):timer) : unit = 
	    let fun showTimerResult (s,{usr,sys},real) =
		print ("\nTiming " ^ s ^ ":" 
		       ^ "\n  usr  = " ^ Time.toString usr 
		       ^ "\n  sys  = " ^ Time.toString sys
		       ^ "\n  real = " ^ Time.toString real
		       ^ "\n")
	    in showTimerResult (s, Timer.checkCPUTimer cputimer, 
				Timer.checkRealTimer realtimer)	    
	    end handle _ => print "\ntimerReport.Uncaught exception\n"
    in
	fun targetFromSmlFile smlfile ext =
	    let val file = Flags.get_string_entry "output"
	    in file ^ "." ^ ext
	    end

	fun isFileContentStringBIN f s =
	    let val is = BinIO.openIn f
	    in ((Byte.bytesToString (BinIO.inputAll is) = s)
		handle _ => (BinIO.closeIn is; false))
		before BinIO.closeIn is
	    end handle _ => false

	fun writePickle file pickleString =
	    let val os = BinIO.openOut file
		val _ = pchat (" [Writing pickle to file " ^ file ^ "...]")
	    in (  BinIO.output(os,Byte.stringToBytes pickleString)
		; BinIO.closeOut os
		) handle X => (BinIO.closeOut os; raise X)
	    end

	fun 'a doPickleGen0 (punit:string) (pu_obj: 'a Pickle.pu) (ext: string) (obj:'a) : string =
	    let val os : Pickle.outstream = Pickle.empty()
		val _ = pchat (" [Begin pickling " ^ ext ^ "-result for " ^ punit ^ "...]")
		(*  val timer = timerStart "Pickler" *)
		val os : Pickle.outstream = Pickle.pickler pu_obj obj os
		(* val _ = timerReport timer *)
		val res = Pickle.toString os
		val _ = pchat (" [End pickling " ^ ext ^ " (sz = " ^ sizeToStr (size res) ^ ")]")
	    in res
	    end

	fun 'a doPickleGen (punit:string) (pu_obj: 'a Pickle.pu) (ext: string) (obj:'a) =
	    let val res = doPickleGen0 punit pu_obj ext obj
		val file = targetFromSmlFile punit ext		
	    in writePickle file res
	    end

	fun unpickleGen smlfile pu ext : 'a option =    (* MEMO: perhaps use hashconsing *)
	    let val s = readFile (targetFromSmlFile smlfile ext)
		val (res,is) = Pickle.unpickler pu (Pickle.fromString s)
	    in SOME res
	    end handle _ => NONE

	val Hexn = Fail "Manager.Polyhash.failure"

	fun renameN H N i =
	    let fun nextAvailableKey(H,i) =
		  case H.peek H i of
		      SOME _ => nextAvailableKey(H,i+1)
		    | NONE => i
	    in foldl (fn (n,i) => 
		      let val i = nextAvailableKey(H,i)
		      in Name.assignKey(n,i)
			  ; i + 1
		      end) i N
	    end

	type name = Name.name

	fun app2 f l1 l2 = (List.app f l1 ; List.app f l2)		
	fun 'a matchGen (match:'a*'a->'a) ((N,B:'a),(N0,B0:'a)) : name list * 'a =
	    let val _ = app2 Name.mark_gen N N0
		val B = match(B,B0)
		val _ = app2 Name.unmark_gen N N0
	    in (N,B)
	    end

	val pu_names = Pickle.listGen Name.pu
	val pu_NB0 = Pickle.pairGen(pu_names,Basis.pu_Basis0)
	val pu_NB1 = Pickle.pairGen(pu_names,Basis.pu_Basis1)
	    
	(* Before we determine not to write to disk, we need to check
	 * that *both* NB0's and NB1's are identical. *)

	(* We need to read in both NB0_0 and NB1_0 from disk in order
	 * to choose fresh names for NB0_1 and NB1_1 *)

	fun rename (N,N') (N0,N1) =
	    let (* How do we make sure that (N of NB0) U (N of NB1) are disjoint from
		 * (N U N') ? We do this by an explicit renaming of 
		 * (N of NB0) to N0' and (N of NB1) to N1 such that (N0 U N1)(B0,B1,m) = (N0' U N1')(B0',B1',m') and 
		 * N0 \cap N1 = \emptyset and (N0 U N1) \cap (N U N') = \emptyset. 
		 *   Idea: insert keys of members of N and N' in a hashSet; 
		 * for each member n in (N of NB0 U N of NB1), starting with 1, 
		 * pick a new key k not in hashSet and reset key(n) 
		 * to k. This implements a capture free renaming of 
		 * (N)(B,m) because basenames((N)(B,m)) \cap basenames(N) 
		 * = \emptyset. This last assumption holds only because
		 * different basenames are used for eb and eb1 export 
		 * bases. *)
		val H : (int,unit) H.hash_table = 
		    H.mkTable (fn x => x, op =) (31, Hexn)
		val _ = app2 (fn n => H.insert H (#1(Name.key n),())) N N'
		val _ = renameN H N1 
		         (renameN H N0 1)
	    in ()
	    end			    

	fun eqNB eqB ((N,B),(N',B')) =
	    length N = length N' andalso eqB (B,B')

	datatype when_to_pickle = NOT_STRING_EQUAL | NOT_ALPHA_EQUAL | ALWAYS

	val whenToPickle : when_to_pickle = NOT_STRING_EQUAL
	fun doPickleNB smlfile (NB0,NB1) : unit = 
	    let val (ext0,ext1) = ("eb","eb1")	       
		fun pickleBoth(NB0,NB1) =
		    (doPickleGen smlfile pu_NB0 ext0 NB0;
		     doPickleGen smlfile pu_NB1 ext1 NB1)
	    in case whenToPickle of 
		ALWAYS => pickleBoth(NB0,NB1)
	      | NOT_STRING_EQUAL => 
		    let val f0 = targetFromSmlFile smlfile ext0
			val f1 = targetFromSmlFile smlfile ext1
			val p0 = doPickleGen0 smlfile pu_NB0 ext0 NB0
			val p1 = doPickleGen0 smlfile pu_NB1 ext1 NB1
		    in if (isFileContentStringBIN f0 p0 
			   andalso isFileContentStringBIN f1 p1) then 
			(pchat "[No writing: valid pickle strings already in eb-files.]")
		       else (writePickle f0 p0 ; writePickle f1 p1)
		    end
	      | NOT_ALPHA_EQUAL => 
		case (unpickleGen smlfile pu_NB0 ext0,
		      unpickleGen smlfile pu_NB1 ext1) of
		(SOME NB0_0, SOME NB1_0) =>
		    let val (NB0,NB1) =			
			    let val () = rename (#1 NB0_0,#1 NB1_0) (#1 NB0,#1 NB1) 
				val NB0 = matchGen Basis.matchBasis0 (NB0,NB0_0)
				val _ = List.app Name.mk_rigid (#1 NB0)
				val NB1 = matchGen Basis.matchBasis1 (NB1,NB1_0)
				val _ = List.app Name.mk_rigid (#1 NB1)
			    in (NB0,NB1)
			    end
		    in if eqNB Basis.eqBasis0 (NB0,NB0_0) andalso 
			  eqNB Basis.eqBasis1 (NB1,NB1_0) then ()
		       else pickleBoth(NB0,NB1)
		    end
	      | _ => pickleBoth(NB0,NB1)
	    end

	fun doPickleLnkFile punit (modc: modcode) : unit =
	    doPickleGen punit ModCode.pu "lnk" modc 

	fun readLinkFiles lnkFiles =
	    let fun process (nil,is,modc) = modc
		  | process (lf::lfs,is,modc) =
		    let val s = readFile lf
			    handle _ => die ("readLinkFiles.error reading file " ^ lf)
			val (modc',is) = Pickle.unpickler ModCode.pu 
			    (Pickle.fromStringHashCons is s)
			    handle _ => die ("readLinkFiles.error deserializing link code for " ^ lf)
			val modc' = ModCode.dirMod (OS.Path.dir lf) modc'
			    handle _ => die ("readLinkFiles.error during dirMod modc'")
		    in process(lfs,is,ModCode.seq(modc,modc'))
		    end
	    in case lnkFiles of 
		nil => ModCode.empty
	      | lf::lfs => 
		    let val s = readFile lf
			    handle _ => die ("readLinkFiles.error reading file " ^ lf)
			val (modc,is) = Pickle.unpickler ModCode.pu (Pickle.fromString s)
			    handle _ => die ("readLinkFiles.error deserializing link code for " ^ lf)
			val modc = ModCode.dirMod (OS.Path.dir lf) modc
			    handle _ => die ("readLinkFiles.error during dirMod modc")
		    in process(lfs,is,modc) 
		    end 
	    end
(*
	fun doUnpickleBases ebfiles : Basis = 
	    let val _ = pchat "\n [Begin unpickling...]\n"
		fun process (nil,is,B) = B
		  | process (ebfile::ebfiles,is,B) =
		    let val s = readFile ebfile
			val ((_,B'),is) = Pickle.unpickler pu_NB
			    (Pickle.fromStringHashCons is s)
		    in process(ebfiles,is,Basis.plus(B,B'))
		    end
		val B0 = Basis.initial()
		val B = 
		    case ebfiles of 
			nil => B0
		      | ebfile::ebfiles => 
			    let val s = readFile ebfile
				val ((_,B),is) = Pickle.unpickler pu_NB (Pickle.fromString s)
			    in process(ebfiles,is,Basis.plus(B0,B))
			    end handle _ => die ("doUnpickleBases. error \n")
	    in B
	    end 
*)
	fun doUnpickleBases0 ebfiles 
	    : Pickle.instream option * {ebfile:string,infixElabBasis:InfixBasis*ElabBasis,used:bool ref}list =
	    let val _ = pchat "\n [Begin unpickling elaboration bases...]\n"
		fun process (nil,is,acc) = (is, rev acc)
		  | process (ebfile::ebfiles,is,acc) =
		    let val s = readFile ebfile handle _ => die("doUnpickleBases0.error reading file " ^ ebfile)
			val ((_,infixElabBasis),is) = Pickle.unpickler pu_NB0
			    (Pickle.fromStringHashCons is s)
			    handle _ => die("doUnpickleBases0.error unpickling infixElabBasis from file " ^ ebfile)
			val entry = {ebfile=ebfile,infixElabBasis=infixElabBasis,
				     used=ref false}
		    in process(ebfiles,is,entry::acc)
		    end
	    in
		case ebfiles of 
		    nil => (NONE,nil)
		  | ebfile::ebfiles => 
			let val s = readFile ebfile handle _ => 
			      die("doUnpickleBases0.error reading file " ^ ebfile)
			    val ((_,infixElabBasis),is) = 
			      Pickle.unpickler pu_NB0 (Pickle.fromString s)
				handle Fail st => 
				         die("doUnpickleBases0.error unpickling infixElabBasis from file " 
					     ^ ebfile ^ ": Fail(" ^ st ^ "); sz(s) = " ^ Int.toString (size s))
				     | e => 
					 die("doUnpickleBases0.error unpickling infixElabBasis from file " 
					     ^ ebfile ^ ": " ^ General.exnMessage e)
			    val (is, entries) = 
			      process(ebfiles,is,[{ebfile=ebfile,
						   infixElabBasis=infixElabBasis,
						   used=ref false}])
			in (SOME is, entries)
			end handle _ => die ("doUnpickleBases. error \n")
	    end 

	fun doUnpickleBases1 (is: Pickle.instream option) ebfiles : opaq_env * IntBasis = 
	    let val _ = pchat "\n [Begin unpickling compiler bases...]\n"
		fun process (nil,is,basisPair) = basisPair
		  | process (ebfile::ebfiles,is,basisPair) =
		    let val s = readFile ebfile
			val is = Pickle.fromStringHashCons is s
			val ((_,basisPair'),is) = Pickle.unpickler pu_NB1 is
		    in process(ebfiles,is,Basis.plusBasis1(basisPair,basisPair'))
		    end
		val basisPair0 = Basis.initialBasis1()
	    in
		case ebfiles of 
		    nil => basisPair0
		  | ebfile::ebfiles => 
			let val s = readFile ebfile
			    val is = 
				case is of
				    SOME is => Pickle.fromStringHashCons is s
				  | NONE => Pickle.fromString s
			    val ((_,basisPair),is) = Pickle.unpickler pu_NB1 is
			in process(ebfiles,is,Basis.plusBasis1(basisPair0,basisPair))
			end handle _ => die ("doUnpickleBases1. error \n")
	    end 

	fun lnkFileConsistent {lnkFile} =
	    let val s = readFile lnkFile
		val (mc,is) = Pickle.unpickler ModCode.pu 
		    (Pickle.fromString s)
	    in true
	    end handle _ => false

    end (* Pickling *)

    fun fid_topdec a = FreeIds.fid_topdec a
    fun opacity_elimination a = OpacityElim.opacity_elimination a

    (* -------------------------------
     * Compute actual dependencies 
     * ------------------------------- *)

    fun lookup (look: ElabBasis -> 'a -> bool) elabBasesInfo (eb0:ElabBasis) (id:'a) =
	let fun loop nil = 
	      if look eb0 id then ()
	      else die "computing actual dependencies.lookup failed"
	      | loop ({ebfile,infixElabBasis=(_,eb),used}::xs) =
	    if look eb id then used:=true
	    else loop xs
	in loop elabBasesInfo
	end

    fun collapse (longstrids,longtycons,longvids) =
	let fun exists e l = List.exists (fn x => x = e) l
	    fun ins e l = if exists e l then l else e::l	       
	    val strids = 
		foldl (fn (longstrid,acc) => 
		       case StrId.explode_longstrid longstrid of
			   (s::_,_) => ins s acc
			 | (nil,s) => ins s acc)
		nil longstrids		
	    val (strids,tycons) = 
		foldl (fn (longtycon,(strids,tycons)) => 
		       case TyCon.explode_LongTyCon longtycon of
			   (s::_,_) => (ins s strids,tycons)
			 | (nil,tycon) => (strids,ins tycon tycons)) 
		(strids,nil) longtycons		
	    val (strids,vids) = 
		foldl (fn (longvid,(strids,vids)) => 
		       case Ident.decompose longvid of
			   (s::_,_) => (ins s strids,vids)
			 | (nil,vid) => (strids,ins vid vids)) 
		(strids,nil) longvids		
	in (vids,tycons,strids)
	end
		
    fun compute_acual_deps 
	(eb0:ElabBasis)
	(elabBasesInfo:{ebfile:string,infixElabBasis:InfixBasis*ElabBasis,used:bool ref}list)
	{funids,sigids,longstrids,longtycons,longvids} =
	let val (vids,tycons,strids) = collapse (longstrids,longtycons,longvids)
	    fun look_vid B vid = Option.isSome 
		(Environments.VE.lookup(Environments.E.to_VE(ElabBasis.to_E B)) vid)
	    fun look_tycon B tycon = Option.isSome 
		(Environments.TE.lookup(Environments.E.to_TE(ElabBasis.to_E B)) tycon)
	    fun look_sigid B sigid = Option.isSome 
		(ModuleEnvironments.G.lookup(ElabBasis.to_G B) sigid)
	    fun look_funid B funid = Option.isSome 
		(ModuleEnvironments.F.lookup(ElabBasis.to_F B) funid)
	    fun look_strid B strid = Option.isSome 
		(Environments.SE.lookup(Environments.E.to_SE(ElabBasis.to_E B)) strid)
	    (* look into newest basis first *)
	    val rev_elabBasesInfo = rev elabBasesInfo
	in    app (lookup look_vid rev_elabBasesInfo eb0) vids
	    ; app (lookup look_tycon rev_elabBasesInfo eb0) tycons
	    ; app (lookup look_strid rev_elabBasesInfo eb0) strids
	    ; app (lookup look_sigid rev_elabBasesInfo eb0) sigids
	    ; app (lookup look_funid rev_elabBasesInfo eb0) funids
	    ; map #ebfile (List.filter (! o #used) elabBasesInfo)
	end

    fun add_longstrid longstrid {funids, sigids, longstrids, longtycons, longvids} =
	let val longstrids = longstrid::longstrids
	in {funids=funids, sigids=sigids, longstrids=longstrids, 
	    longtycons=longtycons, longvids=longvids}
	end
	
    val intinfrep = StrId.mk_LongStrId ["IntInfRep"]

    (* -------------------------------------------------------------------
     * Build SML source file for mlb-project ; flag compile_only enabled 
     * ------------------------------------------------------------------- *)

    fun build_mlb_one (mlbfile, ebfiles, smlfile) : unit =
	let (* load the bases that smlfile depends on *)
	    val _ = print("[reading source file:\t" ^ smlfile)
	    val (unpickleStream, elabBasesInfo) = doUnpickleBases0 ebfiles
	    val initialBasis0 = Basis.initialBasis0()
	    val (infB,elabB) = 
		List.foldl (fn ({infixElabBasis,...}, acc) =>
			    Basis.plusBasis0(acc,infixElabBasis))
		initialBasis0
		elabBasesInfo
	    val _ = print("]")
	    val log_cleanup = log_init smlfile
	    val _ = Flags.reset_warnings ()
	    val abs_mlbfile = ModuleEnvironments.mk_absprjid mlbfile
(*	    val _ = (print "Names generated prior to compilation: ";
		     PP.printTree (PP.layout_list (PP.LEAF o (fn (i,s) => s ^ "#" ^ Int.toString i) o Name.key) (!Name.bucket));
		     print "\n")
*)
	    val _ = Name.bucket := []
	    val _ = Name.baseSet (mlbfile ^ "." ^ smlfile)
	    val res = ParseElab.parse_elab {absprjid = abs_mlbfile,
					    file = smlfile,
					    infB = infB, elabB = elabB} 
	in (case res of 
		ParseElab.FAILURE (report, error_codes) => 
		    (  print "\n"
		     ; print_error_report report
		     ; raise PARSE_ELAB_ERROR error_codes)
	      | ParseElab.SUCCESS {report,infB=infB',elabB=elabB',topdec} =>
	      let 
		val _ = chat "[finding free identifiers begin...]"
		val freelongids = add_longstrid intinfrep (fid_topdec topdec)
		val _ = chat "[finding free identifiers end...]"

		val _ = chat "[computing actual dependencies begin...]"
		val ebfiles_actual = compute_acual_deps 
		    (#2 initialBasis0) elabBasesInfo freelongids
		val ebfiles_actual = map (fn x => x ^ "1") ebfiles_actual
		val _ = chat "[computing actual dependencies end...]"

		val (B_im,_) = 
		    let val (opaq_env,intB) = 
			doUnpickleBases1 unpickleStream ebfiles_actual
			val B = Basis.mk(infB,elabB,opaq_env,intB)
		    in Basis.restrict(B,freelongids)
		    end
		val _ = print "\n"
		val (_,_,opaq_env_im,intB_im) = Basis.un B_im

		(* Setting up for generation of second export basis (eb1) *)
		val names_elab = !Name.bucket
		val _ = List.app Name.mk_rigid names_elab
		val _ = Name.bucket := []
		val _ = Name.baseSet (mlbfile ^ "." ^ smlfile ^ "1")

		val _ = chat "[opacity elimination begin...]"
		val (topdec', opaq_env') = opacity_elimination(opaq_env_im, topdec)
		val _ = chat "[opacity elimination end...]"
		  
		val _ = chat "[interpretation begin...]"
		val functor_inline = false
		val (intB', modc) = 
		    IntModules.interp(functor_inline, abs_mlbfile, 
				      intB_im, topdec', smlfile)
		val names_int = !Name.bucket
		val _ = List.app Name.mk_rigid names_int
		val _ = Name.bucket := []
		val _ = chat "[interpretation end...]"

		(* compute result basis *)
		val B' = Basis.mk(infB',elabB',opaq_env',intB')

		(* Construct export bases *)
		val (NB0',NB1') =
		    let 
			val _ = 
			    if print_export_bases() then
				(  print ("[Export basis for " ^ smlfile ^ " before closure:]\n")
				 ; pr_st (MO.Basis.layout B')
				 ; print "\n")
			    else ()
				
			val B'Closed = Basis.closure (B_im,B')

			val _ = 
			    if print_closed_export_bases() then
				(  print ("[Closed export basis for " ^ smlfile ^ ":]\n")
				 ; pr_st (MO.Basis.layout B'Closed)
				 ; print "\n")
			    else ()

			val (b1,b2,b3,b4) = Basis.un B'Closed
		    in ((names_elab,(b1,b2)),
			(names_int, (b3,b4)))
		    end

		(* Write export bases to disk if there are not 
		 * already identical export bases on disk *)
		val _ = doPickleNB smlfile (NB0',NB1')

		val modc = ModCode.emit (abs_mlbfile,modc)
		val _ = doPickleLnkFile smlfile modc

	      in print_result_report report;
		log_cleanup()
	      end handle ? => (print_result_report report; raise ?)
		) handle XX => (log_cleanup(); raise XX)
      end  

(*	
    fun smlserver_preprocess prj = 
	if not(extendedtyping()) then prj
	else
	    case Project.getParbody prj of
		NONE => prj
	      | SOME unitids => 
		    let (* Parse scriptlets *)
			fun valspecToField (n,t) = {name=n,typ=t}
			val formIfaceFile = "scripts.gen.sml"
			val _ = print "[parsing arguments of scriptlet functors]\n"
			val formIfaces = map Scriptlet.parseArgsFile unitids
			val formIfaces = 
			    map (fn {funid,valspecs} => 
				 {name=funid,fields=map valspecToField valspecs})
			    formIfaces
			val prj = Project.prependUnit (formIfaceFile,prj)
			val prj = Project.appendFunctorInstances prj
		    in	  Scriptlet.genScriptletInstantiations formIfaces
			; Scriptlet.genFormInterface formIfaceFile formIfaces
			; prj 
		    end
*)

     fun writeAll (f,s) =
	 let val os = TextIO.openOut f
	 in (TextIO.output(os,s);
	     TextIO.closeOut os)
	     handle X => (TextIO.closeOut os; raise X)
	 end	       

    (* ------------------------------------------------
     * Link together lnk-files and generate executable
     * ------------------------------------------------ *)

     fun objFileExt() = if MO.backend_name = "KAM" then ".uo" else ".o"	    
     local
	 fun fileFromSmlFile smlfile ext =
	    let val {dir,file} = OS.Path.splitDirFile smlfile
		infix ##
		val op ## = OS.Path.concat
	    in dir ## MO.mlbdir () ## (file ^ ext)
	    end
	 fun objFileFromSmlFile smlfile =
	     fileFromSmlFile smlfile (objFileExt())
	     
	 fun lnkFileFromSmlFile smlfile = 
	     objFileFromSmlFile smlfile ^ ".lnk"
     in
	 fun getUoFiles (smlfile:string) : string list =
	     let val lnkfile = lnkFileFromSmlFile smlfile
		 val modc = readLinkFiles [lnkfile]
	     in ModCode.target_files modc
	     end
     end

    structure MlbProject = MlbProject()
    structure UlFile = UlFile(MlbProject)
    fun mlb_to_ulfile (f:string->string list) 
	{mlbfile:string} : string =
	let val ul  = UlFile.from_mlbfile f mlbfile
	in UlFile.pp_ul ul
	end

    fun link_lnk_files (mlbfile_opt:string option) : unit =  
	let val _ = chat "reading link files"
	    val lnkFiles = Flags.get_stringlist_entry "link"
	    val modc = readLinkFiles lnkFiles
	in if !Flags.SMLserver then
	    (case mlbfile_opt of
		 SOME mlbfile =>
		     let val s = mlb_to_ulfile getUoFiles {mlbfile=mlbfile}
			 val ulfile = !run_file
		     in writeAll(ulfile,s) 
		      ; print("[wrote file " ^ ulfile ^ "]\n")
		     end
	       | NONE => 
		     let val lnkFilesScripts = Flags.get_stringlist_entry "link_scripts"
			 val modc_scripts = readLinkFiles lnkFilesScripts		
		     in ModCode.makeUlfile (!run_file,modc,ModCode.seq(modc,modc_scripts))
		     end)
	   else 
	       (chat "making executable";
		ModCode.mk_exe_all_emitted(modc, nil, !run_file))
	end

    (* ----------------------------
     * Build an MLB project
     * ---------------------------- *)

    exception IsolateFunExn

    local
	fun failSig s signal =
	    raise Fail ("isolate error: " ^ s ^ "(" ^ 
			SysWord.toString (Posix.Signal.toWord signal) ^ ")")
    in
	fun isolate (f : 'a -> unit) (a:'a) : unit =
	    case Posix.Process.fork() of
		SOME pid => 
		    let val (pid2,status) = Posix.Process.waitpid (Posix.Process.W_CHILD pid,[])
		    in if pid2 = pid then 
			(case status of
			     Posix.Process.W_EXITED => ()
			   | Posix.Process.W_EXITSTATUS _ => raise IsolateFunExn
			   | Posix.Process.W_STOPPED s => failSig "W_STOPPED" s
			   | Posix.Process.W_SIGNALED s => failSig "W_SIGNALED" s)
		   else raise Fail "isolate error 2"
		end
	  | NONE => (f a before Posix.Process.exit 0w0
		     handle _ => Posix.Process.exit 0w1)
    end

    structure MlbPlugIn : MLB_PLUGIN  =
	struct
	    fun compile0 target flags a =
		let
		    (* deal with annotations (from mlb-file) *)
		    val flags = String.tokens Char.isSpace flags
		    val () = List.app Flags.turn_on flags
		    val () = Flags.turn_on "compile_only"
		    val () = Flags.lookup_string_entry "output" := target
		in build_mlb_one a
		end handle Fail s => print ("Compile error: " ^ s ^ "\n")

	    fun compile {verbose} {basisFiles,source,namebase,target,flags} :unit =
		isolate (compile0 target flags) (namebase, basisFiles, source)
(*
	      | compile _ _ = die "MlbPlugIn.compile.flags non-empty"
*)
	    fun link0 mlbfile target lnkFiles lnkFilesScripts () =
		(Flags.lookup_string_entry "output" := target;
		 Flags.lookup_stringlist_entry "link" := lnkFiles;
		 Flags.lookup_stringlist_entry "link_scripts" := lnkFilesScripts;
		 link_lnk_files (SOME mlbfile))

	    fun link {verbose} {mlbfile,target,lnkFiles,lnkFilesScripts,flags=""} :unit =
		isolate (link0 mlbfile target lnkFiles lnkFilesScripts) ()
	      | link _ _ = die "MlbPlugIn.link.flags non-empty"

	    fun mlbdir() = MO.mlbdir()
	    val objFileExt = objFileExt

	    fun maybeSetRegionEffectVarCounter n =
		let val b = region_profiling()
		    val _ = if b then Flags.lookup_int_entry "regionvar" := n
			    else ()
		in b 
		end

	    val lnkFileConsistent = lnkFileConsistent
	end


    structure MlbMake = MlbMake(structure MlbProject = MlbProject
                                structure MlbPlugIn = MlbPlugIn
				val verbose = Flags.is_on0 "chat"
				val oneSrcFile : string option ref = ref NONE)		   

    datatype source = SML of string | MLB of string | WRONG_FILETYPE of string 

    fun determine_source (s:string) : source = 
	let fun wrong s = WRONG_FILETYPE ("File name must have extension '.mlb', '.sml', or '.sig'.\n" ^
					  "*** The file name you gave me has " ^ s)
	in case OS.Path.ext s of 
	    SOME "mlb" => MLB s
	  | SOME ext => if Flags.has_sml_source_ext ext then SML s
			else wrong ("extension " ^ quot ext ^ ".")
	  | NONE => wrong ("no extension.")
	end
    
    val import_basislib = Flags.is_on0 "import_basislib"
    fun gen_wrap_mlb filepath =
	let val mlb_file = OS.Path.base filepath ^ ".auto.mlb"
	    val _ = chat ("Generating MLB-file " ^ mlb_file)
	    val os = TextIO.openOut mlb_file
	    val basislib = !Flags.install_dir ## "basis/basis.mlb"
	    val _ = chat ("Using basis library " ^ quot basislib)
	    val body = 
		if import_basislib() then
		    "local " ^ basislib ^ " in " ^ filepath ^ " end"
		else filepath
	in 
	    let val _ = TextIO.output(os, body)
		val _ = TextIO.closeOut os
	    in mlb_file
	    end handle X => (TextIO.closeOut os; raise X)
	end

    fun comp0 files : unit =
	if Flags.get_stringlist_entry "link" <> nil then link_lnk_files NONE
	else
	    case files of
		[file] => 
		    (case determine_source file of 
			 SML s => 
			     if Flags.is_on "compile_only" then
				 let val ebfiles = Flags.get_stringlist_entry "load_basis_files"
				     val namebase = Flags.get_string_entry "namebase"
				 in build_mlb_one (namebase, ebfiles, s)
				 end
			     else 
				 let val mlb_file = gen_wrap_mlb s
				     val _ = comp0 [mlb_file]
					 handle X => (OS.FileSys.remove mlb_file; raise X)
				 in OS.FileSys.remove mlb_file
				 end
		       | MLB s => 
				 let val target =
				     if !Flags.SMLserver then
					 let val {dir,file} = OS.Path.splitDirFile s
					     val op ## = OS.Path.concat infix ##
					 in dir ## MO.mlbdir() ## (OS.Path.base file ^ ".ul")
					 end
				     else Flags.get_string_entry "output"
				 in  
				     (MlbMake.build{flags="",mlbfile=s,target=target} 
				      handle Fail s => raise Fail s
					   | IsolateFunExn => 
					      (print "Stopping compilation of MLB-file due to errors.\n";
					       raise PARSE_ELAB_ERROR nil)
					   | _ => (print "Stopping compilation due to errors.\n";
						   raise PARSE_ELAB_ERROR nil))
				 end
		       | WRONG_FILETYPE s => raise Fail s)
	      | _ => raise Fail "I expect exactly one file name"
			     
    val timingfile = "KITtimings"
    fun comp files : unit =
      if Flags.is_on "compiler_timings" then
	let val os = (TextIO.openOut (timingfile)
		      handle _ => (print ("Error: I could not open file `" ^ timingfile ^ "' for writing");
				   raise PARSE_ELAB_ERROR nil))
	  fun close () = (TextIO.closeOut os; 
			  Flags.timings_stream := NONE;
			  print ("[wrote compiler timings file: "  ^ timingfile ^ "]\n"))
	in Flags.timings_stream := SOME os;
	  comp0 files handle E => (close(); raise E);
	    close()
	end
      else comp0 files

    (* initialize Flags.comp_ref to contain build (for interaction), etc.
     * See comment in FLAGS.*)
    fun wrap f a = (f a) handle PARSE_ELAB_ERROR _ => 
      TextIO.output(TextIO.stdOut, "\n ** Parse or elaboration error occurred. **\n")
    val _ = Flags.comp_ref := wrap (fn s => comp [s])

  end
