structure Socket : SOCKET = struct
type active = unit
type 'mode stream = unit
type ('af,'sock_type) sock = unit
fun sendVec(s, sl) = 0

end