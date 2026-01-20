
### server
```sh
cd server
zig build
valgrind --leak-check=full zig-out/bin/tcpsys_server client1
```

### client 1
```sh
cd client
zig build
valgrind --leak-check=full zig-out/bin/tcpsys_clienf client1
```

### client 2
```sh
cd client
zig build
valgrind --leak-check=full zig-out/bin/tcpsys_cli client2
```