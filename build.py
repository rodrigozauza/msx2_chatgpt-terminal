"""Atomically build the MSX2 SCREEN 7 terminal and identical COM aliases."""
import hashlib,pathlib,subprocess,sys,tempfile,os
base=pathlib.Path(__file__).resolve().parent
subprocess.run([sys.executable,'-S',str(base/'tools/make_font.py')],check=True)
with tempfile.TemporaryDirectory(prefix='msxchat-build-',dir=base) as folder:
    stage=pathlib.Path(folder)
    subprocess.run([sys.executable,'-S',str(base/'tools/pyz80.py'),
        '--obj='+str(stage/'MSXCHAT.COM'),'--mapfile='+str(stage/'MSXCHAT.MAP'),
        '--lstfile='+str(stage/'MSXCHAT.LST'),str(base/'src/MAIN.ASM')],check=True)
    data=(stage/'MSXCHAT.COM').read_bytes()
    assert data[:3]==bytes([0xc3,3,1])
    assert len(data)+256<0x4400
    for name in ['MSXCHAT.COM','MSXCHAT.MAP','MSXCHAT.LST']:os.replace(stage/name,base/name)
    (stage/'MSX_CHAT.COM').write_bytes(data)
    os.replace(stage/'MSX_CHAT.COM',base/'MSX_CHAT.COM')
print('MSXCHAT.COM',len(data),'bytes',hashlib.sha256(data).hexdigest())
