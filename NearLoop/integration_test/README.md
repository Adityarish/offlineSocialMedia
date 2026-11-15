# Integration verification boundary

The current automated HTTPS integration case lives in `apps/nearloop/test/core_test.dart` so it can execute on a Flutter development host with loopback sockets and SQLite. It does not use device radios or prove two independent processes. Follow `docs/testing.md` for the outstanding physical-device and multi-process acceptance cases. Native device-driven integration tests remain to be added after runner generation and first successful launch.
