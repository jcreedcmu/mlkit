signature SOCKET =
 sig
     type active
     type 'mode stream
     type ('af,'sock_type) sock
     val sendVec: ('af, active stream) sock * Word8VectorSlice.slice -> int
 end