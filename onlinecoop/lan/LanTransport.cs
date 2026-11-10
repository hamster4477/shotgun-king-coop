// Data-only, one-peer TCP bridge. No downloaded code or remote commands are executed.
using System;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;
using System.Diagnostics;
using System.Threading;
using System.Collections.Generic;

public static class OnlineCoopLan {
    const int MaxMessages = 300000;
    static readonly Encoding Utf8 = new UTF8Encoding(false, true);
    static readonly Regex Payload = new Regex("^[A-Za-z0-9_,:.=-]{0,16384}$");
    static void Atomic(string path, string value) {
        string temp = path + ".tmp";
        File.WriteAllText(temp, value, Utf8);
        for (int attempt = 0; ; attempt++) {
            try {
                if (File.Exists(path)) File.Replace(temp, path, null);
                else File.Move(temp, path);
                return;
            } catch (IOException) {
                // A Lua/diagnostic reader can briefly hold a non-delete-sharing
                // handle. Keep the old complete record until replacement works.
                if (attempt >= 39) throw;
                Thread.Sleep(10);
            }
        }
    }
    static bool Retire(string path) {
        try { File.Delete(path); return true; }
        catch (IOException) { return false; /* Consumed: retry deletion, never replay. */ }
    }
    static string Read(string path, int limit = 20480) {
        try {
            // Records are written once; an incomplete record is retried below.
            // Open once and bound the read even if a writer grows the file.
            using (var input = new FileStream(path, FileMode.Open, FileAccess.Read,
                    FileShare.ReadWrite | FileShare.Delete)) {
                if (input.Length > limit) return null;
                using (var reader = new StreamReader(input, Utf8)) {
                    char[] chars = new char[4096]; int count;
                    var value = new StringBuilder();
                    while ((count = reader.Read(chars, 0, chars.Length)) > 0) {
                        if (value.Length + count > limit) return null;
                        value.Append(chars, 0, count);
                    }
                    return value.ToString();
                }
            }
        } catch (IOException) { return null; }
    }
    static bool Kind(string value) { return value == "ping" || value == "pong" || value == "data"; }
    // OC4 negotiates lossless inter-frame compression and receive credits.
    // Local game mailboxes retain
    // OC1 records, so neither gameplay nor pixel decoding needs a second path.
    static string WirePayload(string value, ref string kind) {
        if (kind != "data" || value.Length < 512) return value;
        byte[] bytes = Utf8.GetBytes(value);
        using (var output = new MemoryStream()) {
            using (var zip = new GZipStream(output, CompressionMode.Compress, true))
                zip.Write(bytes, 0, bytes.Length);
            string encoded = Convert.ToBase64String(output.ToArray());
            if (encoded.Length + 16 >= value.Length) return value;
            kind = "zdata"; return bytes.Length + ":" + encoded;
        }
    }
    static string InflatePayload(string value) {
        if (value.Length > 16384) throw new IOException("Compressed payload too large");
        int colon = value.IndexOf(':'), expected;
        if (colon < 1 || colon > 5 || !Int32.TryParse(value.Substring(0, colon), out expected)
            || expected < 1 || expected > 16384) throw new IOException("Invalid inflated length");
        byte[] input = Convert.FromBase64String(value.Substring(colon + 1));
        using (var source = new MemoryStream(input))
        using (var zip = new GZipStream(source, CompressionMode.Decompress))
        using (var output = new MemoryStream()) {
            byte[] chunk = new byte[1024]; int count;
            while ((count = zip.Read(chunk, 0, chunk.Length)) > 0) {
                if (output.Length + count > 16384) throw new IOException("Inflated payload too large");
                output.Write(chunk, 0, count);
            }
            if (output.Length != expected) throw new IOException("Inflated length mismatch");
            string result = Utf8.GetString(output.ToArray());
            if (!Payload.IsMatch(result)) throw new IOException("Invalid inflated payload");
            return result;
        }
    }
    sealed class FrameBasis {
        public string Key, Text;
        public int Sequence;
    }
    // Only native visual messages use a dictionary. Commands and snapshots keep
    // their existing independent representation; extra header fields are opaque.
    static string FrameKey(string value) {
        if (!(value.StartsWith("F1,") || value.StartsWith("F2,"))) return null;
        int colon = value.IndexOf(':');
        if (colon < 0 || colon > 192 || value.Length - colon < 65) return null;
        string[] h = value.Substring(0, colon).Split(',');
        int index = h[0] == "F1" ? 4 : 6, part;
        if (h.Length <= index + 1 || !Int32.TryParse(h[index], out part) || part < 1 || part > 5) return null;
        for (int i = 1; i < h.Length; i++) {
            long number;
            if (!Int64.TryParse(h[i], out number) || number < 0) return null;
        }
        for (int i = colon + 1; i < value.Length; i++) {
            char c = value[i];
            if (!(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f')) return null;
        }
        return h[0] + ":" + part;
    }
    static uint Four(string value, int i) {
        return (uint)value[i] | ((uint)value[i + 1] << 8) | ((uint)value[i + 2] << 16) | ((uint)value[i + 3] << 24);
    }
    static byte[] Delta(string basis, string value) {
        var positions = new Dictionary<uint, List<int>>();
        for (int i = 0; i + 4 <= basis.Length; i++) {
            uint key = Four(basis, i); List<int> list;
            if (!positions.TryGetValue(key, out list)) positions[key] = list = new List<int>(8);
            // Bound work even for a maliciously repetitive frame.
            if (list.Count < 8) list.Add(i);
            else list[i % 8] = i;
        }
        using (var output = new MemoryStream())
        using (var writer = new BinaryWriter(output)) {
            int literal = 0, at = 0;
            while (at < value.Length) {
                int best = 0, start = 0; List<int> list;
                if (at + 8 <= value.Length && positions.TryGetValue(Four(value, at), out list)) {
                    foreach (int offset in list) {
                        int length = 4, max = Math.Min(basis.Length - offset, value.Length - at);
                        while (length < max && basis[offset + length] == value[at + length]) length++;
                        if (length > best) { best = length; start = offset; }
                    }
                }
                if (best < 8) { at++; continue; }
                if (at > literal) {
                    writer.Write((byte)0); writer.Write((ushort)(at - literal));
                    writer.Write(Utf8.GetBytes(value.Substring(literal, at - literal)));
                }
                writer.Write((byte)1); writer.Write((ushort)start); writer.Write((ushort)best);
                at += best; literal = at;
            }
            if (at > literal) {
                writer.Write((byte)0); writer.Write((ushort)(at - literal));
                writer.Write(Utf8.GetBytes(value.Substring(literal, at - literal)));
            }
            return output.ToArray();
        }
    }
    static string FramePayload(string value, ref string kind, int sequence, Dictionary<string, FrameBasis> bases) {
        string encoded = WirePayload(value, ref kind), key = FrameKey(value);
        if (key == null) return encoded;
        FrameBasis basis;
        if (bases.TryGetValue(key, out basis)) {
            byte[] delta = Delta(basis.Text, value);
            using (var output = new MemoryStream()) {
                using (var zip = new GZipStream(output, CompressionMode.Compress, true)) zip.Write(delta, 0, delta.Length);
                string candidate = value.Length + ":" + basis.Sequence + ":" + Convert.ToBase64String(output.ToArray());
                if (candidate.Length < encoded.Length) { encoded = candidate; kind = "ddata"; }
            }
        }
        bases[key] = new FrameBasis { Key = key, Text = value, Sequence = sequence };
        return encoded;
    }
    static string InflateDelta(string value, Dictionary<string, FrameBasis> bases) {
        if (value.Length > 16384) throw new IOException("Delta payload too large");
        string[] h = value.Split(':'); int expected, sequence;
        if (h.Length != 3 || !Int32.TryParse(h[0], out expected) || expected < 1 || expected > 16384
            || !Int32.TryParse(h[1], out sequence) || sequence < 1) throw new IOException("Invalid delta header");
        FrameBasis basis = null;
        foreach (FrameBasis candidate in bases.Values) if (candidate.Sequence == sequence) { basis = candidate; break; }
        if (basis == null) throw new IOException("Missing delta basis");
        byte[] packed = Convert.FromBase64String(h[2]);
        using (var source = new MemoryStream(packed))
        using (var zip = new GZipStream(source, CompressionMode.Decompress))
        using (var delta = new MemoryStream()) {
            byte[] chunk = new byte[1024]; int count;
            while ((count = zip.Read(chunk, 0, chunk.Length)) > 0) {
                if (delta.Length + count > 65536) throw new IOException("Delta expansion too large");
                delta.Write(chunk, 0, count);
            }
            delta.Position = 0;
            using (var reader = new BinaryReader(delta))
            using (var output = new MemoryStream()) {
                while (delta.Position < delta.Length) {
                    byte op = reader.ReadByte();
                    int first = reader.ReadUInt16(), length = op == 1 ? reader.ReadUInt16() : first;
                    if (length < 1 || output.Length + length > expected) throw new IOException("Invalid delta length");
                    if (op == 0) {
                        if (delta.Length - delta.Position < length) throw new IOException("Truncated delta literal");
                        byte[] literal = reader.ReadBytes(length); output.Write(literal, 0, literal.Length);
                    } else if (op == 1) {
                        if (first + length > basis.Text.Length) throw new IOException("Invalid delta copy");
                        byte[] copy = Utf8.GetBytes(basis.Text.Substring(first, length)); output.Write(copy, 0, copy.Length);
                    } else throw new IOException("Invalid delta operation");
                }
                if (output.Length != expected) throw new IOException("Delta output length mismatch");
                string result = Utf8.GetString(output.ToArray());
                if (!Payload.IsMatch(result) || FrameKey(result) != basis.Key) throw new IOException("Invalid delta frame");
                return result;
            }
        }
    }
    sealed class PendingWrite {
        public IAsyncResult Operation;
        public byte[] Bytes;
        public double Started;
        public int Sequence;
        public PendingWrite(NetworkStream stream, string value, double now, int sequence) {
            Bytes = Utf8.GetBytes(value + "\n");
            Started = now; Sequence = sequence;
            Operation = stream.BeginWrite(Bytes, 0, Bytes.Length, null, null);
        }
    }
    sealed class LocalRecord { public int Sequence; public string Kind, Payload; }
    sealed class LocalGroup { public int Last; public string Path; }
    static bool ReadLocalGroup(string path, string session, int first, Queue<LocalRecord> pending, Queue<LocalGroup> groups) {
        string text = Read(path, 65536);
        if (text == null) return false;
        string[] lines = text.Split('\n'); int start = 0, count = 1;
        // Some Windows text writers produce CRLF; a record's payload still
        // cannot contain either newline character.
        for (int i = 0; i < lines.Length; i++)
            if (lines[i].EndsWith("\r")) lines[i] = lines[i].Substring(0, lines[i].Length - 1);
        if (text.StartsWith("OCB1|")) {
            string[] h = lines[0].Split('|'); int sequence;
            if (h.Length != 5 || h[0] != "OCB1" || h[1] != session || h[4] != "END"
                || !Int32.TryParse(h[2], out sequence) || sequence != first
                || !Int32.TryParse(h[3], out count) || count < 2 || count > 16 || lines.Length != count + 1) return false;
            start = 1;
        } else if (lines.Length != 1) return false;
        var records = new List<LocalRecord>();
        for (int i = 0; i < count; i++) {
            string[] p = lines[start + i].Split('|'); int sequence;
            if (p.Length != 6 || p[0] != "OC1" || p[1] != session || p[5] != "END"
                || !Int32.TryParse(p[2], out sequence) || sequence != first + i || sequence > MaxMessages
                || !Kind(p[3]) || !Payload.IsMatch(p[4])) return false;
            // Batch production is deliberately limited to reliable animation
            // frames. A control message always flushes any earlier animation.
            if (start == 1 && (p[3] != "data" || !p[4].StartsWith("F2,"))) return false;
            records.Add(new LocalRecord { Sequence = sequence, Kind = p[3], Payload = p[4] });
        }
        foreach (LocalRecord record in records) pending.Enqueue(record);
        groups.Enqueue(new LocalGroup { Last = first + count - 1, Path = path });
        return true;
    }
    static void CompleteWrite(NetworkStream stream, PendingWrite writing, Queue<LocalGroup> groups, ref int sent) {
        stream.EndWrite(writing.Operation);
        // A batch contains only consecutive local records. Retire them after
        // the entire asynchronous write completes, never when merely staged.
        sent = Math.Max(sent, writing.Sequence);
        // Keep a file visible to Lua backpressure until its last logical
        // message is sent, even if the socket batch split it in the middle.
        RetireGroups(groups, sent);
    }
    static void RetireGroups(Queue<LocalGroup> groups, int sent) {
        while (groups.Count > 0 && groups.Peek().Last <= sent) {
            if (!Retire(groups.Peek().Path)) break;
            groups.Dequeue();
        }
    }
    public static int Run(string root, string role, string address, int port, string key, int seconds) {
        if (role != "host" && role != "client") throw new ArgumentException("Invalid role");
        if (!Regex.IsMatch(key, "^[A-Fa-f0-9]{32}$")) throw new ArgumentException("Room key must be 32 hex characters");
        IPAddress ip = null;
        if (role == "host") {
            ip = IPAddress.Parse(address);
            if (ip.AddressFamily != AddressFamily.InterNetwork) throw new ArgumentException("IPv4 required");
        }
        string lan = Path.Combine(Path.GetFullPath(root), "lan");
        Directory.CreateDirectory(lan);
        // Lock prevents two helpers from taking over the same game's mailbox.
        using (var processLock = new FileStream(Path.Combine(lan, "bridge.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None)) {
            string session = Guid.NewGuid().ToString("N");
            string box = Path.Combine(lan, session);
            Directory.CreateDirectory(Path.Combine(box, "in"));
            Directory.CreateDirectory(Path.Combine(box, "out"));
            Directory.CreateDirectory(Path.Combine(box, "ack"));
            string status = Path.Combine(box, "status.txt");
            Atomic(status, "OC1|" + session + "|waiting|END");
            // Mailbox OC3 adds bounded outgoing F2 batches; individual OC1
            // records and per-message acknowledgements remain supported.
            Atomic(Path.Combine(lan, "config.txt"), "OC3|" + session + "|" + role + "|END");
            TcpListener listener = null;
            TcpClient client = null;
            var elapsed = Stopwatch.StartNew();
            int sent = 0, received = 0, consumed = 0, peerConsumed = 0, creditSent = -1;
            var sendBases = new Dictionary<string, FrameBasis>();
            var receiveBases = new Dictionary<string, FrameBasis>();
            var localRecords = new Queue<LocalRecord>();
            var localGroups = new Queue<LocalGroup>();
            bool connected = false;
            PendingWrite writing = null;
            string stagedLine = null;
            int stagedSequence = 0;
            int partialBytes = 0;
            long rawBytes = 0, wireBytes = 0;
            long outboundReadTicks = 0, encodeTicks = 0;
            int socketBatches = 0, maxBatchRecords = 0;
            try {
                Console.WriteLine("LAN bridge " + role + " " + address + ":" + port + " session=" + session);
                if (role == "host") {
                    listener = new TcpListener(ip, port);
                    listener.Start(1);
                    while (!listener.Pending()) {
                        if (elapsed.Elapsed.TotalSeconds > seconds || File.Exists(Path.Combine(box, "stop.txt"))) return 0;
                        Thread.Sleep(20);
                    }
                    client = listener.AcceptTcpClient();
                    listener.Stop(); listener = null;
                } else {
                    client = new TcpClient(AddressFamily.InterNetwork);
                    var pending = client.BeginConnect(address, port, null, null);
                    using (pending.AsyncWaitHandle) {
                        if (!pending.AsyncWaitHandle.WaitOne(8000)) throw new IOException("Connection timeout");
                        client.EndConnect(pending);
                    }
                }
                client.NoDelay = true;
                // Bound the OS backlog as well as the one pending async frame.
                // Lua can then shed visual frames via its existing out/ guard.
                client.SendBufferSize = 16384;
                NetworkStream stream = client.GetStream();
                writing = new PendingWrite(stream, "OC4|HELLO|" + key + "|" + role + "|END", elapsed.Elapsed.TotalSeconds, 0);
                double helloAt = elapsed.Elapsed.TotalSeconds, lastReceive = helloAt, lastHeartbeat = helloAt;
                double partialAt = 0;
                string buffer = "";
                byte[] bytes = new byte[20480];
                while (elapsed.Elapsed.TotalSeconds < seconds && !File.Exists(Path.Combine(box, "stop.txt"))) {
                    double now = elapsed.Elapsed.TotalSeconds;
                    // A temporary reader/antivirus lock must not leave Lua's
                    // file-based backpressure permanently stuck after delivery.
                    RetireGroups(localGroups, sent);
                    if (client.Client.Poll(0, SelectMode.SelectRead) && client.Client.Available == 0) throw new IOException("Peer disconnected");
                    if (!connected && now - helloAt > 8) throw new IOException("Handshake timeout");
                    if (connected && now - lastReceive > 12) throw new IOException("Heartbeat timeout");
                    if (partialAt > 0 && now - partialAt > 30) throw new IOException("Frame assembly timeout");
                    if (writing != null && now - writing.Started > 30) throw new IOException("Send stalled for 30 seconds");
                    if (writing != null && writing.Operation.IsCompleted) {
                        CompleteWrite(stream, writing, localGroups, ref sent);
                        writing = null;
                    }
                    if (stream.DataAvailable) {
                        int count = stream.Read(bytes, 0, bytes.Length);
                        if (count == 0) throw new IOException("Peer disconnected");
                        for (int b = 0; b < count; b++) if (bytes[b] > 127 || (bytes[b] < 32 && bytes[b] != 10)) throw new IOException("Invalid wire encoding");
                        // TCP may deliver a frame in pieces on a slow tunnel.
                        // Valid incoming bytes are activity, even before '\n'.
                        lastReceive = now;
                        if (buffer.Length == 0) partialAt = now;
                        buffer += Utf8.GetString(bytes, 0, count);
                        int end;
                        while ((end = buffer.IndexOf('\n')) >= 0) {
                            string line = buffer.Substring(0, end);
                            buffer = buffer.Substring(end + 1);
                            if (line.Length > 20480) throw new IOException("Frame too large");
                            if (!connected) {
                                if (line != "OC4|HELLO|" + key + "|" + (role == "host" ? "client" : "host") + "|END") throw new IOException("Room key, role or protocol mismatch (both players must update)");
                                connected = true;
                                Atomic(status, "OC1|" + session + "|connected|END");
                                Console.WriteLine("CONNECTED");
                            } else if (line.StartsWith("OC4|CREDIT|")) {
                                string[] credit = line.Split('|'); int acknowledgement;
                                int queued = writing != null ? Math.Max(sent, writing.Sequence) : sent;
                                if (credit.Length != 4 || credit[3] != "END" || !Int32.TryParse(credit[2], out acknowledgement)
                                    || acknowledgement < peerConsumed || acknowledgement > queued) throw new IOException("Invalid receive credit");
                                peerConsumed = acknowledgement;
                            } else if (line != "OC4|HEARTBEAT|END") {
                                string[] parts = line.Split('|');
                                int sequence;
                                if (parts.Length != 5 || parts[0] != "OC4" || parts[4] != "END"
                                    || !Int32.TryParse(parts[1], out sequence) || sequence != received + 1
                                    || sequence > MaxMessages || (!Kind(parts[2]) && parts[2] != "zdata" && parts[2] != "ddata")) throw new IOException("Invalid message or sequence");
                                if (parts[2] == "zdata") { parts[3] = InflatePayload(parts[3]); parts[2] = "data"; }
                                else if (parts[2] == "ddata") { parts[3] = InflateDelta(parts[3], receiveBases); parts[2] = "data"; }
                                if (!Payload.IsMatch(parts[3])) throw new IOException("Invalid message payload");
                                string frameKey = parts[2] == "data" ? FrameKey(parts[3]) : null;
                                if (frameKey != null) receiveBases[frameKey] = new FrameBasis { Key = frameKey, Text = parts[3], Sequence = sequence };
                                if (received - consumed >= 64) throw new IOException("Game receive queue full");
                                received = sequence;
                                Atomic(Path.Combine(box, "in", received + ".msg"), "OC1|" + session + "|" + sequence + "|" + parts[2] + "|" + parts[3] + "|END");
                                if (received % 25 == 0) Console.WriteLine("RECEIVED " + received + " messages");
                            }
                            lastReceive = now;
                            partialAt = buffer.Length == 0 ? 0 : now;
                        }
                        partialBytes = buffer.Length;
                        if (buffer.Length > 20480) throw new IOException("Unterminated oversized frame");
                    }
                    if (connected) {
                        for (int burst = 0; burst < 64 && consumed < received; burst++) {
                            string ackPath = Path.Combine(box, "ack", (consumed + 1) + ".msg");
                            string ack = Read(ackPath);
                            if (ack == null) break;
                            string[] a = ack.Split('|'); int ackSequence;
                            if (a.Length == 4 && a[0] == "OC1" && a[1] == session && a[3] == "END"
                                && Int32.TryParse(a[2], out ackSequence) && ackSequence == consumed + 1) {
                                Retire(Path.Combine(box, "in", (++consumed) + ".msg"));
                                Retire(ackPath);
                            } else break;
                        }
                        for (int outgoingBurst = 0; outgoingBurst < 4; outgoingBurst++) {
                        // Never wait for the peer's TCP window here: inbound
                        // commands, heartbeats, acknowledgements and stop.txt
                        // must continue to be processed during a slow write.
                        if (writing != null) {
                            if (!writing.Operation.IsCompleted) break;
                            CompleteWrite(stream, writing, localGroups, ref sent);
                            writing = null;
                        }
                        if (now - lastHeartbeat >= 2) {
                            writing = new PendingWrite(stream, "OC4|HEARTBEAT|END", now, 0);
                            lastHeartbeat = now;
                            continue;
                        }
                        if (creditSent != consumed) {
                            writing = new PendingWrite(stream, "OC4|CREDIT|" + consumed + "|END", now, 0);
                            creditSent = consumed;
                            continue;
                        }
                        // Loading or pausing the game must apply backpressure,
                        // not overflow the peer's 64-record mailbox. Credits do
                        // not enter that mailbox, so both directions stay live.
                        if (sent - peerConsumed >= 48) break;
                        var batch = new StringBuilder();
                        int batchEnd = sent;
                        double batchStarted = elapsed.Elapsed.TotalSeconds;
                        // Drain an existing backlog in one socket write. Never
                        // delay an interactive command to wait for a full batch.
                        // 8 KiB/16 records limits head-of-line work; a single
                        // larger legal record still gets through unchanged.
                        while (batchEnd - sent < 16 && batchEnd - peerConsumed < 48) {
                            int n = batchEnd + 1;
                            string line = stagedLine;
                            if (line != null) {
                                if (stagedSequence != n) throw new IOException("Invalid staged sequence");
                            } else {
                            string path = Path.Combine(box, "out", n + ".msg");
                            long readStarted = Stopwatch.GetTimestamp();
                            bool available = localRecords.Count > 0 || ReadLocalGroup(path, session, n, localRecords, localGroups);
                            outboundReadTicks += Stopwatch.GetTimestamp() - readStarted;
                            if (!available) break;
                            LocalRecord record = localRecords.Dequeue();
                            if (record.Sequence != n) throw new IOException("Invalid local batch sequence");
                                string kind = record.Kind;
                                long encodeStarted = Stopwatch.GetTimestamp();
                                string payload = kind == "data" ? FramePayload(record.Payload, ref kind, n, sendBases) : record.Payload;
                                encodeTicks += Stopwatch.GetTimestamp() - encodeStarted;
                                rawBytes += record.Payload.Length; wireBytes += payload.Length;
                                line = "OC4|" + n + "|" + kind + "|" + payload + "|END";
                            }
                            if (batch.Length > 0 && batch.Length + line.Length + 1 > 8192) {
                                stagedLine = line; stagedSequence = n;
                                break;
                            }
                            stagedLine = null; stagedSequence = 0;
                            if (batch.Length > 0) batch.Append('\n');
                            batch.Append(line); batchEnd = n;
                            if (batch.Length >= 8192 || elapsed.Elapsed.TotalSeconds - batchStarted >= .004) break;
                        }
                        if (batchEnd == sent) break;
                        socketBatches++;
                        maxBatchRecords = Math.Max(maxBatchRecords, batchEnd - sent);
                        writing = new PendingWrite(stream, batch.ToString(), now, batchEnd);
                        }
                    }
                    // Avoid adding a 20 ms bridge tick to every request/frame.
                    // Idle polling remains bounded and yields the CPU.
                    Thread.Sleep(writing != null || sent > peerConsumed || received > consumed ? 2 : 10);
                }
                return 0;
            } catch (Exception ex) {
                string detail = ex.GetType().Name + ": " + ex.Message
                    + (ex is SocketException ? " socket_error=" + ((SocketException)ex).NativeErrorCode : "")
                    + " sent=" + sent + " received=" + received + " consumed=" + consumed
                    + " pending_bytes=" + (writing == null ? 0 : writing.Bytes.Length)
                    + " partial_receive_bytes=" + partialBytes
                    + " pending_seconds=" + (writing == null ? 0 : (int)(elapsed.Elapsed.TotalSeconds - writing.Started));
                Atomic(Path.Combine(box, "error.txt"), detail);
                Atomic(status, "OC1|" + session + "|error|END");
                Console.Error.WriteLine(detail);
                return 1;
            } finally {
                if (client != null) client.Close();
                if (listener != null) listener.Stop();
                if (Read(status) != "OC1|" + session + "|error|END") Atomic(status, "OC1|" + session + "|stopped|END");
                Console.WriteLine("STOP sent=" + sent + " received=" + received + " raw_bytes=" + rawBytes + " wire_bytes=" + wireBytes
                    + " socket_batches=" + socketBatches + " max_batch_records=" + maxBatchRecords
                    + " read_ms=" + (outboundReadTicks * 1000 / Stopwatch.Frequency) + " encode_ms=" + (encodeTicks * 1000 / Stopwatch.Frequency));
            }
        }
    }
}
