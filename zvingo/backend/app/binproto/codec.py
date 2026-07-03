import struct
from dataclasses import dataclass

# Packet types
PTYPE_LOCATION = 0x01
PTYPE_ACK = 0x02
PTYPE_ORDER_STATE = 0x03

# Harare base coordinates (used for delta encoding)
BASE_LAT = -17.8292  # degrees
BASE_LNG = 31.0522   # degrees
COORD_SCALE = 10000   # delta units per degree


@dataclass
class LocationPayload:
    lat_delta: int  # int16
    lng_delta: int  # int16
    speed: int      # uint8
    heading: int    # uint8
    accuracy: int   # uint8
    battery: int    # uint8

    @property
    def lat(self) -> float:
        return BASE_LAT + (self.lat_delta / COORD_SCALE)

    @property
    def lng(self) -> float:
        return BASE_LNG + (self.lng_delta / COORD_SCALE)


class BinProtoCodec:
    # Header: Magic(2) + Ver(1) + Type(1) + SessionID(8) + Seq(4) + PayloadLen(2) + Reserved(2) = 20 bytes
    HEADER_FMT = "!2sBB8sIHH"  # Big-endian
    HEADER_SIZE = struct.calcsize(HEADER_FMT)

    # Location Payload: lat_delta(h) + lng_delta(h) + speed(B) + heading(B) + accuracy(B) + battery(B) = 8 bytes
    LOC_PAYLOAD_FMT = "!hhBBBB"
    LOC_PAYLOAD_SIZE = struct.calcsize(LOC_PAYLOAD_FMT)

    # ACK Payload: Magic(2) + Type(1) + Seq(4) = 7 bytes
    ACK_FMT = "!2sBI"

    @staticmethod
    def decode_header(data: bytes) -> dict:
        if len(data) < BinProtoCodec.HEADER_SIZE:
            raise ValueError("Data too short for header")

        magic, ver, ptype, session_id, seq, payload_len, _ = struct.unpack(
            BinProtoCodec.HEADER_FMT, data[:BinProtoCodec.HEADER_SIZE]
        )

        if magic != b'ZV':
            raise ValueError("Invalid magic bytes")

        return {
            "version": ver,
            "type": ptype,
            "session_id": session_id,
            "seq": seq,
            "payload_len": payload_len
        }

    @staticmethod
    def encode_header(ptype: int, session_id: bytes, seq: int, payload_len: int, version: int = 1) -> bytes:
        if len(session_id) < 8:
            session_id = session_id.ljust(8, b'\x00')
        return struct.pack(
            BinProtoCodec.HEADER_FMT,
            b'ZV', version, ptype, session_id[:8], seq, payload_len, 0
        )

    @staticmethod
    def decode_location(data: bytes) -> LocationPayload:
        if len(data) != BinProtoCodec.LOC_PAYLOAD_SIZE:
            raise ValueError(f"Invalid location payload size: {len(data)}")

        lat_d, lng_d, spd, hdg, acc, bat = struct.unpack(BinProtoCodec.LOC_PAYLOAD_FMT, data)
        return LocationPayload(
            lat_delta=lat_d,
            lng_delta=lng_d,
            speed=spd,
            heading=hdg,
            accuracy=acc,
            battery=bat
        )

    @staticmethod
    def encode_location(lat: float, lng: float, speed: int = 0, heading: int = 0, accuracy: int = 10, battery: int = 100) -> bytes:
        lat_delta = int((lat - BASE_LAT) * COORD_SCALE)
        lng_delta = int((lng - BASE_LNG) * COORD_SCALE)
        lat_delta = max(-32768, min(32767, lat_delta))
        lng_delta = max(-32768, min(32767, lng_delta))
        return struct.pack(BinProtoCodec.LOC_PAYLOAD_FMT, lat_delta, lng_delta, speed, heading, accuracy, battery)

    @staticmethod
    def encode_ack(seq: int, ptype: int = PTYPE_ACK) -> bytes:
        return struct.pack(BinProtoCodec.ACK_FMT, b'ZV', ptype, seq)
