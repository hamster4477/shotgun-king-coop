// Headless co-op adapter for SteamP2PTunnel (Moody_zh, MIT).
// Retains its 7-byte stream id + little-endian message type wire format.
// Adaptations: bounded queues, loopback-only sockets, two-member lobby, stop file,
// retry reliable sends, and a file status channel instead of a Tauri window.
use std::{
    collections::VecDeque,
    env, fs,
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    path::PathBuf,
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};
use steamworks::networking_sockets::NetConnection;
use steamworks::networking_types::{
    ListenSocketEvent, NetworkingConnectionState, NetworkingIdentity, SendFlags,
};
use steamworks::{Client, LobbyId, LobbyType, SteamError};
const CAP: usize = 512 * 1024;
const ID: &[u8; 7] = b"coop001";
fn packet(kind: u32, data: &[u8]) -> Vec<u8> {
    let mut v = ID.to_vec();
    v.extend(kind.to_le_bytes());
    v.extend(data);
    v
}
fn unpack(data: &[u8]) -> Result<(u32, &[u8]), String> {
    if data.len() < 11 || &data[..7] != ID || data.len() > 8203 {
        return Err("invalid tunnel packet".into());
    }
    let kind = u32::from_le_bytes(data[7..11].try_into().unwrap());
    if kind > 1 {
        return Err("invalid tunnel kind".into());
    }
    Ok((kind, &data[11..]))
}
struct Args {
    role: String,
    port: u16,
    lobby: u64,
    status: PathBuf,
    stop: PathBuf,
}
fn args() -> Result<Args, String> {
    let mut a = env::args().skip(1);
    let mut m = std::collections::HashMap::new();
    while let Some(k) = a.next() {
        let v = a.next().ok_or("missing argument")?;
        if m.insert(k, v).is_some() {
            return Err("duplicate argument".into());
        }
    }
    let role = m.remove("--role").ok_or("role")?;
    if role != "host" && role != "client" {
        return Err("role".into());
    }
    let port = m
        .remove("--port")
        .ok_or("port")?
        .parse::<u16>()
        .map_err(|_| "port")?;
    if port == 0 {
        return Err("port".into());
    }
    let lobby = m
        .remove("--lobby")
        .unwrap_or("0".into())
        .parse::<u64>()
        .map_err(|_| "lobby")?;
    let status = PathBuf::from(m.remove("--status").ok_or("status")?);
    let stop = PathBuf::from(m.remove("--stop").ok_or("stop")?);
    if !m.is_empty() || role == "client" && lobby == 0 {
        return Err("arguments".into());
    }
    Ok(Args {
        role,
        port,
        lobby,
        status,
        stop,
    })
}
fn status(a: &Args, s: &str, lobby: u64, code: &str) {
    // A partially-read record fails the broker's strict parser and is retried.
    let _ = fs::write(&a.status, format!("SP1|{}|{}|{}|END", s, lobby, code));
}
fn wait<T>(client: &Client, a: &Args, rx: mpsc::Receiver<T>) -> Result<T, String> {
    let until = Instant::now() + Duration::from_secs(60);
    loop {
        client.run_callbacks();
        if a.stop.exists() {
            return Err("stopped".into());
        }
        if let Ok(v) = rx.try_recv() {
            return Ok(v);
        }
        if Instant::now() > until {
            return Err("timeout".into());
        }
        thread::sleep(Duration::from_millis(10));
    }
}
fn run(a: &Args) -> Result<(), String> {
    status(a, "starting", 0, "none");
    let client = Client::init_app(480).map_err(|e| format!("steam_init: {e:?}"))?;
    client.networking_utils().init_relay_network_access();
    let _ = client.networking_sockets().init_authentication();
    let (tx, rx) = mpsc::channel();
    let lobby = if a.role == "host" {
        client.matchmaking().create_lobby(
            LobbyType::FriendsOnly,
            2,
            move |r: Result<LobbyId, SteamError>| {
                let _ = tx.send(r.map_err(|e| format!("{e:?}")));
            },
        );
        wait(&client, a, rx)??
    } else {
        client.matchmaking().join_lobby(
            LobbyId::from_raw(a.lobby),
            move |r: Result<LobbyId, ()>| {
                let _ = tx.send(r.map_err(|_| "join_failed".to_string()));
            },
        );
        wait(&client, a, rx)??
    };
    // Always leave, including early network failure.
    let result = transfer(&client, a, lobby);
    client.matchmaking().leave_lobby(lobby);
    result
}
fn transfer(client: &Client, a: &Args, lobby: LobbyId) -> Result<(), String> {
    // A shared example App ID must not connect to an unrelated application's lobby.
    if a.role == "host" {
        if !client
            .matchmaking()
            .set_lobby_data(lobby, "onlinecoop_protocol", "SKCOOPS1")
        {
            return Err("lobby_metadata".into());
        }
    } else if client
        .matchmaking()
        .lobby_data(lobby, "onlinecoop_protocol")
        .as_deref()
        != Some("SKCOOPS1")
    {
        return Err("wrong_lobby".into());
    }
    let sockets = client.networking_sockets();
    let mut conn: Option<NetConnection> = None;
    let listen = if a.role == "host" {
        Some(
            sockets
                .create_listen_socket_p2p(0, vec![])
                .map_err(|e| format!("listen: {e:?}"))?,
        )
    } else {
        None
    };
    let tcp_listener = if a.role == "client" {
        let owner = client.matchmaking().lobby_owner(lobby);
        if owner == client.user().steam_id() {
            return Err("self_connect".into());
        }
        conn = Some(
            sockets
                .connect_p2p(NetworkingIdentity::new_steam_id(owner), 0, vec![])
                .map_err(|e| format!("p2p: {e:?}"))?,
        );
        let l = TcpListener::bind(("127.0.0.1", a.port)).map_err(|e| format!("port: {e}"))?;
        l.set_nonblocking(true).map_err(|e| e.to_string())?;
        Some(l)
    } else {
        None
    };
    let mut tcp: Option<TcpStream> = None;
    let mut to_tcp = VecDeque::<Vec<u8>>::new();
    let mut bytes_tcp = 0usize;
    let mut offset = 0;
    let mut pending: Option<Vec<u8>> = None;
    let mut retry = Instant::now();
    let mut active = false;
    let began = Instant::now();
    let mut ready = false;
    status(a, "waiting", lobby.raw(), "none");
    loop {
        if a.stop.exists() {
            break;
        }
        client.run_callbacks();
        if let Some(l) = &listen {
            while let Some(event) = l.try_receive_event() {
                match event {
                    ListenSocketEvent::Connecting(req) => {
                        // Spacewar is shared: only accept our room's guest, never arbitrary peers.
                        let member = req
                            .remote()
                            .steam_id()
                            .map(|id| client.matchmaking().lobby_members(lobby).contains(&id))
                            .unwrap_or(false);
                        if member && conn.is_none() {
                            req.accept().map_err(|e| format!("accept: {e:?}"))?;
                        }
                    }
                    ListenSocketEvent::Connected(c) => {
                        if conn.is_some() {
                            return Err("extra_peer".into());
                        }
                        conn = Some(c.take_connection());
                    }
                    ListenSocketEvent::Disconnected(_) => {
                        if active {
                            return Err("disconnected".into());
                        }
                    }
                }
            }
        }
        if let Some(c) = conn.as_mut() {
            let state = c
                .info()
                .map_err(|e| format!("info: {e:?}"))?
                .state()
                .map_err(|e| format!("state: {e:?}"))?;
            if matches!(
                state,
                NetworkingConnectionState::ClosedByPeer
                    | NetworkingConnectionState::ProblemDetectedLocally
            ) {
                return Err("disconnected".into());
            }
            if state == NetworkingConnectionState::Connected {
                active = true;
                if !ready {
                    ready = true;
                    status(a, "ready", lobby.raw(), "none")
                }
                if tcp.is_none() && a.role == "client" {
                    if let Some(l) = &tcp_listener {
                        match l.accept() {
                            Ok((s, _)) => {
                                s.set_nonblocking(true).map_err(|e| e.to_string())?;
                                s.set_nodelay(true).ok();
                                tcp = Some(s)
                            }
                            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
                            Err(e) => return Err(e.to_string()),
                        }
                    }
                }
                // Receive only when there is room. Steam handles backpressure above this bound.
                if bytes_tcp < CAP - 32 * 8192 {
                    let msgs = c
                        .receive_messages(32)
                        .map_err(|e| format!("receive: {e:?}"))?;
                    for msg in msgs {
                        let (kind, data) = unpack(msg.data())?;
                        if kind == 1 {
                            return Err("peer_closed".into());
                        }
                        if tcp.is_none() && a.role == "host" {
                            let s = TcpStream::connect_timeout(
                                &format!("127.0.0.1:{}", a.port).parse().unwrap(),
                                Duration::from_secs(2),
                            )
                            .map_err(|e| format!("local_host: {e}"))?;
                            s.set_nonblocking(true).map_err(|e| e.to_string())?;
                            s.set_nodelay(true).ok();
                            tcp = Some(s);
                        }
                        if !data.is_empty() {
                            bytes_tcp += data.len();
                            to_tcp.push_back(data.to_vec());
                        }
                    }
                }
                if let Some(s) = tcp.as_mut() {
                    while let Some(front) = to_tcp.front() {
                        match s.write(&front[offset..]) {
                            Ok(0) => return Err("local_closed".into()),
                            Ok(n) => {
                                offset += n;
                                bytes_tcp -= n;
                                if offset == front.len() {
                                    to_tcp.pop_front();
                                    offset = 0;
                                }
                            }
                            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                            Err(e) => return Err(e.to_string()),
                        }
                    }
                    if pending.is_none() {
                        let mut buf = [0u8; 8192];
                        match s.read(&mut buf) {
                            Ok(0) => {
                                let _ = c.send_message(&packet(1, &[]), SendFlags::RELIABLE);
                                return Err("local_closed".into());
                            }
                            Ok(n) => {
                                pending = Some(packet(0, &buf[..n]));
                                retry = Instant::now();
                            }
                            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
                            Err(e) => return Err(e.to_string()),
                        }
                    }
                    if let Some(data) = &pending {
                        if c.send_message(data, SendFlags::RELIABLE).is_ok() {
                            pending = None
                        } else if retry.elapsed() > Duration::from_secs(30) {
                            return Err("send_timeout".into());
                        }
                    }
                }
            }
        }
        if a.role == "client" && !active && began.elapsed() > Duration::from_secs(90) {
            return Err("connect_timeout".into());
        }
        thread::sleep(Duration::from_millis(2));
    }
    Ok(())
}
fn main() {
    if env::args().any(|a| a == "--self-test") {
        let data = packet(0, b"hello");
        assert_eq!(unpack(&data).unwrap(), (0, b"hello".as_slice()));
        assert!(unpack(b"bad").is_err());
        println!("PASS packet framing");
        return;
    }
    let a = match args() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2)
        }
    };
    match run(&a) {
        Ok(()) => status(&a, "stopped", 0, "none"),
        Err(e) => {
            eprintln!("{e}");
            status(
                &a,
                "error",
                0,
                if e.starts_with("steam_init") {
                    "steam"
                } else if e.starts_with("port") {
                    "port"
                } else {
                    "connect"
                },
            );
            std::process::exit(1)
        }
    }
}
