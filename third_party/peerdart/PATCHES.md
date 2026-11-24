# Local patches to peerdart 0.5.6

- `lib/src/negotiator.dart`: don't close a connection when ICE reports
  `disconnected`. That state is usually temporary and recovers by itself;
  closing on it made players drop out of rooms for no real reason. A
  connection that truly dies still goes to `failed` and is closed then.
