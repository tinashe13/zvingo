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


def test_header_padding_ack_and_validation():
    header = BinProtoCodec.encode_header(1, b"abc", 7, 0, version=2)
    decoded = BinProtoCodec.decode_header(header)
    assert decoded == {
        "version": 2,
        "type": 1,
        "session_id": b"abc\x00\x00\x00\x00\x00",
        "seq": 7,
        "payload_len": 0,
    }
    assert BinProtoCodec.encode_ack(7) == struct.pack("!2sBI", b"ZV", 2, 7)
    with pytest.raises(ValueError, match="too short"):
        BinProtoCodec.decode_header(b"short")
    invalid = bytearray(header)
    invalid[0:2] = b"NO"
    with pytest.raises(ValueError, match="magic"):
        BinProtoCodec.decode_header(bytes(invalid))


def test_location_encoding_clamps_and_validates():
    data = BinProtoCodec.encode_location(100, -100, 1, 2, 3, 4)
    location = BinProtoCodec.decode_location(data)
    assert location.lat_delta == 32767
    assert location.lng_delta == -32768
    assert location.lat == pytest.approx(-14.5525)
    assert location.lng == pytest.approx(27.7754)
    with pytest.raises(ValueError, match="payload size"):
        BinProtoCodec.decode_location(b"bad")
