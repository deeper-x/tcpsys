build:
	cd ${HOME}/zigprojs/tcpsys/server && zig build
	cd ${HOME}/zigprojs/tcpsys/client && zig build

run_server:
	cd ${HOME}/zigprojs/tcpsys/server && valgrind --leak-check=full ./zig-out/bin/tcpsys_server server

run_client1:
	cd ${HOME}/zigprojs/tcpsys/client && valgrind --leak-check=full ./zig-out/bin/tcpsys_client client1

run_client2:
	cd ${HOME}/zigprojs/tcpsys/client && valgrind --leak-check=full ./zig-out/bin/tcpsys_client client2
