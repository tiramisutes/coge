import socket
from nwalign import global_align
import sys
import atexit

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 1233
CHUNK = 32768 * 8
HOST = 'localhost'

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.bind((HOST, PORT))
server.listen(4)
print "\nstarted server on %s:%i\n" % (HOST, PORT)

def get_args(astr):
    kwargsab = astr.split(" ")
    a, b = kwargsab[-2:]
    kwargs = [v.lstrip("-") for v in kwargsab[:-2]]
    kw = {}
    for i, k in enumerate(kwargs[::2]):
        if k == 'matrix':
            kw[k] = kwargs[2 * i + 1]
        else:
            kw[k] = int(kwargs[2 * i + 1])
    return a, b, kw




while True:
    client, address = server.accept()
    data = True 
    while data:
        try: 
            data = client.recv(CHUNK).strip()
            if data == "EXIT":
                client.close()
                server.close()
                print "EXITING service"
                sys.exit(0)

            a,b, kwargs = get_args(data)
            r = global_align(a, b, **kwargs)
            client.send(" ".join(r))
        except Exception, e:
            try:
                client.send("ERROR:" + str(e))
            except socket.error:
                # they already closed...
                client.close()
                break


    client.close()

atexit.register(server.close)
