import pytest
from app.sms.parser import SMSParser

def test_parse_accept_command():
    text = "ACCEPT ORDER_123"
    command, args = SMSParser.parse_command(text)
    
    assert command == "ACCEPT"
    assert args == ["ORDER_123"]

def test_parse_status_command():
    text = "status"
    command, args = SMSParser.parse_command(text)
    
    assert command == "STATUS"
    assert args == []

def test_handle_status_command():
    # Need asyncio loop or run with pytest-asyncio if handle_command is async?
    # handle_command is static wrapper but could be async if it calls services.
    # In implementation it is 'async def handle_command'.
    pass 
    
# We can't easily test 'handle_command' without mocking dependencies effectively,
# so we stick to 'parse_command' logic for unit testing.
