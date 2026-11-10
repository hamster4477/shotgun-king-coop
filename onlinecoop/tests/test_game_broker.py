"""Exercise the native lobby's broker over loopback, without a game process."""
from pathlib import Path
import json
import os
import socket
import subprocess
import time
import uuid
import threading
import select

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / 'tests' / time.strftime('broker-%Y%m%d-%H%M%S')
REPORT.mkdir()
processes, streams, sides = [], [], []


def read(path):
    try:
        return path.read_text(encoding='utf-8-sig')
    except (OSError, UnicodeError):
        return ''


def status(side):
    values = read(side['box'] / 'status.txt').split('|')
    return values if len(values) == 8 and values[-1] == 'END' else None


def wait(side, state, seconds=25):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        value = status(side)
        if value and value[1] == state and int(value[5]) == side['seq']:
            return value
        time.sleep(.1)
    raise AssertionError(f"Expected {state}, got {status(side)}: {REPORT}")


def request(side, role, ip, port, key='-'):
    side['seq'] += 1
    seq = side['seq']
    (side['box'] / f'request-{seq}.txt').write_text(
        f'LB1|{seq}|{role}|{ip}|{port}|{key}|END', encoding='ascii')


occupied = socket.socket()
occupied.bind(('127.0.0.1', 0))
occupied.listen()
port = occupied.getsockname()[1]
try:
    for role in ('host', 'client'):
        runtime = REPORT / role
        session = uuid.uuid4().hex
        box = runtime / 'lan' / 'lobby' / session
        log = open(REPORT / f'{role}.log', 'w', encoding='utf-8')
        streams.append(log)
        proc = subprocess.Popen([
            'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            str(ROOT / 'Lan-GameBroker.ps1'), '-Root', str(runtime),
            '-Session', session, '-OwnerPID', str(os.getpid())],
            stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        processes.append(proc)
        side = {'root': runtime, 'box': box, 'seq': 0}
        sides.append(side)
        wait(side, 'ready')
    host, client = sides
    (client['box'] / 'discover.txt').write_text('ON')
    time.sleep(3)  # Browsing starts before any host is listening.
    assert processes[1].poll() is None

    request(host, 'host', '256.1.1.1', port)
    wait(host, 'error')
    request(host, 'cancel', '127.0.0.1', port)
    wait(host, 'ready')
    request(host, 'hostmapped', '127.0.0.1', port)
    failed = wait(host, 'error')
    assert failed[4] == 'port', failed
    request(host, 'cancel', '127.0.0.1', port)
    wait(host, 'ready')
    request(host, 'host', '127.0.0.1', port)
    value = wait(host, 'waiting')
    ip, assigned_port, key = value[3].split(':')
    assert int(assigned_port) != port, 'Occupied port was not skipped'
    (client['box'] / 'discover.txt').write_text('ON')
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and value[3] not in read(client['box'] / 'rooms.txt'):
        time.sleep(.1)
    assert value[3] in read(client['box'] / 'rooms.txt'), 'Host was not discovered'
    assert read(host['box'] / 'adapters.txt'), 'Missing adapter names'
    (client['box'] / 'discover.txt').write_text('OFF')
    request(client, 'client', ip, assigned_port, key)
    wait(host, 'connected')
    wait(client, 'connected')
    request(host, 'cancel', '127.0.0.1', port)
    request(client, 'cancel', '127.0.0.1', port)
    wait(host, 'ready')
    wait(client, 'ready')
    assert read(host['root'] / 'lan/config.txt') == 'OFF'
    deadline = time.monotonic() + 9
    while time.monotonic() < deadline and value[3] in read(client['box'] / 'rooms.txt'):
        time.sleep(.1)
    assert value[3] not in read(client['box'] / 'rooms.txt'), 'Closed room did not expire'
    request(host, 'host', '127.0.0.1', port)
    new_value = wait(host, 'waiting')
    assert new_value[3] != value[3], 'New room reused the previous key'
    request(host, 'cancel', '127.0.0.1', port)
    wait(host, 'ready')
    # A TCP relay has a different external port, as with FRP/router forwarding.
    occupied.close()
    request(host, 'hostmapped', '127.0.0.1', port)
    mapped = wait(host, 'waiting')
    assert int(mapped[3].split(':')[1]) == port
    key = mapped[3].split(':')[2]
    relay = socket.socket(); relay.bind(('127.0.0.1', 0)); relay.listen(); relay.settimeout(20)
    public_port = relay.getsockname()[1]
    relay_errors = []
    def forward():
        try:
            with relay:
                peer, _ = relay.accept()
                with peer, socket.create_connection(('127.0.0.1', port), timeout=8) as upstream:
                    peer.settimeout(8); upstream.settimeout(8)
                    while True:
                        ready, _, _ = select.select([peer, upstream], [], [], 15)
                        if not ready: return
                        for source in ready:
                            data = source.recv(65536)
                            if not data: return
                            (upstream if source is peer else peer).sendall(data)
        except Exception as e:
            relay_errors.append(str(e))
    thread=threading.Thread(target=forward, daemon=True); thread.start()
    request(client, 'client', 'localhost', public_port, key)
    wait(host, 'connected'); wait(client, 'connected')
    for sender, receiver in ((host, client), (client, host)):
        send_session=read(sender['root']/'lan/config.txt').split('|')[1]
        receive_session=read(receiver['root']/'lan/config.txt').split('|')[1]
        outgoing=sender['root']/'lan'/send_session/'out/1.msg'
        incoming=receiver['root']/'lan'/receive_session/'in/1.msg'
        outgoing.write_text(f'OC1|{send_session}|1|data|relay-test|END')
        deadline=time.monotonic()+10
        while time.monotonic()<deadline and not read(incoming): time.sleep(.05)
        assert '|data|relay-test|END' in read(incoming), read(incoming)
    request(host, 'cancel', '127.0.0.1', port)
    request(client, 'cancel', '127.0.0.1', port)
    wait(host, 'ready'); wait(client, 'ready')
    thread.join(timeout=10)
    assert not thread.is_alive()
    assert not relay_errors, relay_errors
    vacant = socket.socket()
    vacant.bind(('127.0.0.1', 0))
    refused_port = vacant.getsockname()[1]
    vacant.close()
    request(client, 'client', '127.0.0.1', refused_port, 'a'*32)
    assert wait(client, 'error')[4] == 'refused'
    local_ip = [ip for ip in status(host)[2].split(',') if ip != '127.0.0.1'][-1]
    request(host, 'host', local_ip, port)
    native_room = wait(host, 'waiting')[3].split(':')
    request(client, 'client', native_room[0], native_room[1], native_room[2])
    wait(host, 'connected'); wait(client, 'connected')
    assert read(host['root'] / 'lan/last-host-adapter.txt'), 'Successful adapter not saved'
    request(host, 'cancel', '127.0.0.1', port)
    request(client, 'cancel', '127.0.0.1', port)
    wait(host, 'ready'); wait(client, 'ready')
    (host['box'] / 'stop.txt').write_text('stop')
    processes[0].wait(timeout=10)
    session = uuid.uuid4().hex
    log = open(REPORT / 'host-restarted.log', 'w', encoding='utf-8')
    streams.append(log)
    proc = subprocess.Popen([
        'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        str(ROOT / 'Lan-GameBroker.ps1'), '-Root', str(host['root']),
        '-Session', session, '-OwnerPID', str(os.getpid())],
        stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    processes.append(proc)
    restarted = {'root': host['root'], 'box': host['root']/'lan/lobby'/session, 'seq': 0}
    sides.append(restarted)
    assert wait(restarted, 'ready')[2].split(',')[0] == local_ip, 'Preferred adapter was not restored'
    result = {'discovery_and_expiry': True, 'adapter_names_and_memory': True, 'refused_and_retry': True,'mapped_port_conflict_rejected': True, 'domain_tcp_relay_bidirectional': True, 'invalid_address_rejected': True, 'occupied_port_skipped': True,
              'real_handshake': True, 'cancel_clears_config': True,
              'create_after_cancel': True, 'fresh_room_key': True}
    (REPORT / 'results.json').write_text(json.dumps(result, indent=2))
    print(REPORT, flush=True)
    print(json.dumps(result), flush=True)
finally:
    occupied.close()
    for side in sides:
        (side['box'] / 'stop.txt').write_text('stop')
    for proc in processes:
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.terminate()
            proc.wait(timeout=10)
    for log in streams:
        log.close()

