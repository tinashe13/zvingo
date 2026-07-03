import struct
import pytest
from app.binproto.codec import BinProtoCodec, LocationPayload

def test_encode_decode_header():
    # Construct a valid header
    # Magic(2) + Ver(1) + Type(1) + SessionID(8) + Seq(4) + PayloadLen(2) + Reserved(2)
    magic = b'ZV'
    ver = 1
    ptype = 0x01
    session_id = b'12345678'
    seq = 100
    payload_len = 8
    reserved = 0
    
    data = struct.pack(BinProtoCodec.HEADER_FMT, magic, ver, ptype, session_id, seq, payload_len, reserved)
    
    decoded = BinProtoCodec.decode_header(data)
    
    assert decoded['version'] == ver
    assert decoded['type'] == ptype
    assert decoded['session_id'] == session_id
    assert decoded['seq'] == seq
    assert decoded['payload_len'] == payload_len

def test_encode_decode_location():
    # Location payload: 8 bytes
    # lat_delta (h) + lng_delta (h) + speed (B) + heading (B) + accuracy (B) + battery (B)
    lat_d = -50
    lng_d = 100
    spd = 25
    hdg = 180
    acc = 10
    bat = 85
    
    data = struct.pack(BinProtoCodec.LOC_PAYLOAD_FMT, lat_d, lng_d, spd, hdg, acc, bat)
    
    loc = BinProtoCodec.decode_location(data)
    
    assert loc.lat_delta == lat_d
    assert loc.lng_delta == lng_d
    assert loc.speed == spd
    assert loc.heading == hdg
    assert loc.accuracy == acc
    assert loc.battery == bat
