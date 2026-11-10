using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;

// Optional LAN discovery. Gameplay continues to use the existing TCP transport.
public sealed class OnlineCoopDiscovery : IDisposable
{
    const int Port = 27842;
    readonly UdpClient search = new UdpClient(0);
    readonly string nonce = Guid.NewGuid().ToString("N");
    readonly Dictionary<string, Room> rooms = new Dictionary<string, Room>();
    readonly string[] targets;
    UdpClient listener;
    string advertised = "";
    DateTime nextSearch;
    sealed class Room { public string Line; public DateTime Seen; }

    public OnlineCoopDiscovery(string[] broadcasts)
    {
        targets = broadcasts;
        search.EnableBroadcast = true;
        // An unanswered loopback probe must not turn into a fatal UDP reset
        // before a friend has created their room (Windows SIO_UDP_CONNRESET).
        try { search.Client.IOControl(unchecked((int)0x9800000C), new byte[4], null); }
        catch (SocketException) { }
    }

    void Send(UdpClient socket, string message, IPEndPoint endpoint)
    {
        byte[] bytes = Encoding.ASCII.GetBytes(message);
        try { socket.Send(bytes, bytes.Length, endpoint); }
        catch (SocketException) { } // Discovery failure must not break a game.
    }

    public string Poll(string invite, bool browse)
    {
        if (invite != advertised)
        {
            if (listener != null) listener.Close();
            listener = null;
            advertised = invite;
            if (invite.Length > 0)
            {
                try { listener = new UdpClient(Port); }
                catch (SocketException) { } // Another local host may own discovery.
            }
        }
        DateTime now = DateTime.UtcNow;
        if (browse && now >= nextSearch)
        {
            nextSearch = now.AddSeconds(2);
            foreach (string address in targets)
                Send(search, "SKCD1|FIND|" + nonce, new IPEndPoint(IPAddress.Parse(address), Port));
        }
        if (listener != null)
        {
            for (int i = 0; i < 32 && listener.Available > 0; i++)
            {
                IPEndPoint peer = new IPEndPoint(IPAddress.Any, 0);
                byte[] packet = listener.Receive(ref peer);
                if (packet.Length > 80) continue;
                Match query = Regex.Match(Encoding.ASCII.GetString(packet), "^SKCD1\\|FIND\\|([a-f0-9]{32})$");
                if (!query.Success) continue;
                string name = Regex.Replace(Environment.MachineName, "[^A-Za-z0-9 _-]", "_");
                name = name.Substring(0, Math.Min(20, name.Length));
                Send(listener, "SKCD1|ROOM|" + query.Groups[1].Value + "|" + advertised + "|" + name, peer);
            }
        }
        for (int i = 0; i < 64 && search.Available > 0; i++)
        {
            IPEndPoint peer = new IPEndPoint(IPAddress.Any, 0);
            byte[] packet = search.Receive(ref peer);
            if (!browse || packet.Length > 160) continue;
            string[] parts = Encoding.ASCII.GetString(packet).Split('|');
            if (parts.Length != 5 || parts[0] != "SKCD1" || parts[1] != "ROOM" || parts[2] != nonce) continue;
            Match endpoint = Regex.Match(parts[3], "^([0-9]{1,3}(?:\\.[0-9]{1,3}){3}):([0-9]{1,5}):([a-f0-9]{32})$");
            IPAddress ip;
            int port;
            if (!endpoint.Success || !IPAddress.TryParse(endpoint.Groups[1].Value, out ip)
                || !Int32.TryParse(endpoint.Groups[2].Value, out port) || port < 1 || port > 65535
                || !Regex.IsMatch(parts[4], "^[A-Za-z0-9 _-]{1,20}$")) continue;
            if (IPAddress.IsLoopback(ip) && !IPAddress.IsLoopback(peer.Address)) continue;
            string key = ip + ":" + port;
            if (rooms.Count >= 32 && !rooms.ContainsKey(key)) continue;
            rooms[key] = new Room { Line = parts[3] + "|" + parts[4], Seen = now };
        }
        var keys = new List<string>(rooms.Keys);
        keys.Sort(StringComparer.Ordinal);
        var lines = new List<string>();
        foreach (string key in keys)
        {
            if ((now - rooms[key].Seen).TotalSeconds > 6) rooms.Remove(key);
            else lines.Add(rooms[key].Line);
        }
        return String.Join("\n", lines.ToArray());
    }

    public void Dispose()
    {
        search.Close();
        if (listener != null) listener.Close();
    }
}
