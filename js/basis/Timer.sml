structure Timer : TIMER =
  struct
    type tusage = {gcSec : int,  gcUsec : int,
                   sysSec : int, sysUsec : int,
                   usrSec : int, usrUsec : int}

    fun getrutime_ () : tusage = {gcSec=0,gcUsec=0,
                                  sysSec=0,sysUsec=0,
                                  usrSec=0,usrUsec=0}
    open Time

    type cpu_timer  = {usr : time, sys : time, gc : time};
    type real_timer = time;

    val fromSeconds = fn s => fromSeconds(LargeInt.fromInt s)
    val fromMicroseconds = fn s => fromMicroseconds(LargeInt.fromInt s)

    fun CPUTimer rutime = 
	let val {gcSec, gcUsec, sysSec, sysUsec, usrSec, usrUsec} 
	        = rutime 
	in {usr = fromSeconds usrSec + fromMicroseconds usrUsec,
	    sys = fromSeconds sysSec + fromMicroseconds sysUsec,
	    gc  = fromSeconds gcSec  + fromMicroseconds gcUsec}
	end

    fun startCPUTimer () = CPUTimer (getrutime_ ())

    fun checkCPUTimer {usr, sys, gc} = 
	let val {gcSec, gcUsec, sysSec, sysUsec, usrSec, usrUsec} 
	        = getrutime_ () 
	    val gc  = fromSeconds gcSec  + fromMicroseconds gcUsec  - gc
	in {usr = fromSeconds usrSec + fromMicroseconds usrUsec - usr,
	    sys = fromSeconds sysSec + fromMicroseconds sysUsec - sys + gc
	    }
	end

    fun checkGCTime {usr, sys, gc} = 
	let val {gcSec, gcUsec, sysSec, sysUsec, usrSec, usrUsec} 
	        = getrutime_ () 
	    val gc  = fromSeconds gcSec  + fromMicroseconds gcUsec  - gc
	in  gc
	end

    fun startRealTimer () = now ();

    fun checkRealTimer time1 = now () - time1;

    fun totalCPUTimer _  = CPUTimer Initial.initial_rutime
    fun totalRealTimer _ = Initial.initial_realtime
  end
