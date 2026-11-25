# Local patches to peerdart 0.5.6

- `lib/src/negotiator.dart`: don't close a connection when ICE reports
  `disconnected`. That state is usually temporary and recovers by itself;
  closing on it made players drop out of rooms for no real reason. A
  connection that truly dies still goes to `failed` and is closed then.

## Added in 0.2.1 (multi-player joining fixes)

- `lib/src/socket.dart`: when the server socket closes, emit `Disconnected`
  *before* closing the event emitter. Upstream closed the emitter first, so the
  emit threw `Bad state: Cannot add new events after calling close`, the Peer
  never learned the socket was gone and kept `open == true`. For a host this
  meant: once its server connection dropped (very common on phones when you
  switch apps to share the invite), nobody new could ever join the room, while
  players already connected kept playing. Also added `Socket.isOpen` and an
  `onError` handler.
- `lib/src/option_interfaces.dart`: honor a `token` passed in `PeerOptions`
  (upstream always overwrote it with a random one). The PeerJS server lets a
  client with the same id *and* token take over a stale registration, so the
  host can reclaim its room id immediately instead of getting "ID taken" until
  the server times out the old socket.
- `lib/src/negotiator.dart`: queue ICE candidates that arrive before the
  RTCPeerConnection exists or before the remote description is set, and replay
  signaling messages that were parked while the connection was being created.
  Upstream dropped them, which can stop a connection from ever opening.
- `lib/src/baseconnection.dart`: `closeRequest()` no longer throws if the
  emitter was already closed.
