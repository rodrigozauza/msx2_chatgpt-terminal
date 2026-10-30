"""Build the MSX2 SCREEN 7 gateway MSXCHAT.COM from complete Z80 sources."""
import hashlib
import pathlib
import subprocess
import sys
base=pathlib.Path(__file__).resolve().parent
subprocess.run([sys.executable,'-S',str(base/'tools/make_font.py')],check=True)
subprocess.run([sys.executable,'-S',str(base/'tools/pyz80.py'),
    '--obj='+str(base/'MSXCHAT.COM'),'--mapfile='+str(base/'MSXCHAT.MAP'),
    '--lstfile='+str(base/'MSXCHAT.LST'),str(base/'src/MAIN.ASM')],check=True)
data=(base/'MSXCHAT.COM').read_bytes()
# 8.3 alias matching the filename used during SM-X homologation.
(base/'MSX_CHAT.COM').write_bytes(data)
assert data[:3]==bytes([0xc3,0x03,0x01])
assert len(data)+256<0x4000
print('MSXCHAT.COM',len(data),'bytes',hashlib.sha256(data).hexdigest())
