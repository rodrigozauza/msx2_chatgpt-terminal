"""Create a verified distribution after build.py and the five regression suites."""
import argparse,hashlib,json,pathlib,zipfile
BASE=pathlib.Path(__file__).resolve().parent.parent
SKIP={'.git','__pycache__','dist','node_modules','.venv','gateway-state'}
def sha(data):return hashlib.sha256(data).hexdigest()
def read(name):return json.loads((BASE/name).read_text(encoding='utf-8'))
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=pathlib.Path,default=BASE/'dist')
    args=parser.parse_args()
    metadata=read('RELEASE.json')
    binary=(BASE/'MSXCHAT.COM').read_bytes()
    assert binary==(BASE/'MSX_CHAT.COM').read_bytes(),'COM aliases differ'
    assert binary[:3]==bytes([0xc3,3,1]) and len(binary)+256<0x4000
    reports={key:read(name) for key,name in {'z80':'TEST-RESULTS.json','gateway':'GATEWAY-RESULTS.json','lanServer':'LAN-SERVER-RESULTS.json','publisher':'HELPER-RESULTS.json','backup':'BACKUP-RESULTS.json'}.items()}
    assert reports['z80']['binarySha256']==sha(binary),'Tests do not match this COM'
    counts={}
    for key,report in reports.items():
        assert report['results'] and all(r['status']=='PASS' for r in report['results']),key
        counts[key]=len(report['results'])
    assert counts=={'z80':211,'gateway':37,'lanServer':18,'publisher':12,'backup':16},counts
    metadata['binary']={'file':'MSXCHAT.COM','alias':'MSX_CHAT.COM','bytes':len(binary),'sha256':sha(binary),'entry':'0100h','endExclusive':format(len(binary)+256,'04X')+'h'}
    metadata['tests'].update(counts,currentRunTotal=sum(counts.values()))
    (BASE/'RELEASE.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (BASE/'BUILD-LOG.txt').write_text('Version '+metadata['version']+'\nPython build.py: PASS; COM aliases identical\nCOM SHA256: '+sha(binary)+'\n'+json.dumps(counts)+'; total '+str(sum(counts.values()))+' PASS\n',encoding='utf-8')
    output=args.output.resolve()
    output.mkdir(parents=True,exist_ok=True)
    files=sorted([p for p in BASE.rglob('*') if p.is_file() and not p.is_symlink() and not p.name.startswith('.env') and not (p.suffix.upper()=='.COM' and p.name.upper() not in {'MSXCHAT.COM','MSX_CHAT.COM'}) and not any(s in SKIP for s in p.relative_to(BASE).parts) and output not in p.parents and p.name!='SHA256SUMS.txt'], key=lambda p:p.relative_to(BASE).as_posix())
    manifest=''.join(sha(p.read_bytes())+'  '+p.relative_to(BASE).as_posix()+'\n' for p in files)
    (BASE/'SHA256SUMS.txt').write_text(manifest,encoding='utf-8')
    archive=output/('MSX2-CHATGPT-v'+metadata['version']+'.zip')
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p in sorted(files+[BASE/'SHA256SUMS.txt'],key=lambda p:p.relative_to(BASE).as_posix()):
            info=zipfile.ZipInfo('MSX2-CHATGPT/'+p.relative_to(BASE).as_posix(),date_time=(2026,10,29,0,0,0))
            info.create_system=3
            info.compress_type=zipfile.ZIP_DEFLATED
            info.external_attr=0o100644<<16
            z.writestr(info,p.read_bytes())
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for line in manifest.splitlines():
            digest,name=line.split('  ',1)
            assert sha(z.read('MSX2-CHATGPT/'+name))==digest,name
    archive.with_suffix('.zip.sha256').write_text(sha(archive.read_bytes())+'  '+archive.name+'\n',encoding='ascii')
    print(json.dumps({'package':str(archive),'zipSha256':sha(archive.read_bytes()),'binarySha256':sha(binary),'bytes':len(binary),'checks':sum(counts.values())}))
if __name__=='__main__':main()
