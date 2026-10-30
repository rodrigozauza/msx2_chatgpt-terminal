"""Generate original CC0 5x7 glyphs in 6x8 cells and the existing MSX-BR map."""
import json,pathlib
base=pathlib.Path(__file__).resolve().parent.parent
spec=json.loads((base/'src/FONTSPEC.json').read_text(encoding='utf-8'))
source=json.loads((base/'tools/font5x7.json').read_text(encoding='utf-8'))
patterns={ch:[int(v,16)<<3 for v in rows.split('/')]+[0] for ch,rows in source.items()}
assert set(patterns)==set(chr(c) for c in range(32,127))
box=[248,136,168,136,168,136,248,0]
font=[list(box) for _ in range(256)]
font[0]=[0]*8
for ch,rows in patterns.items():font[ord(ch)]=rows
marks={'acute':[16,32],'grave':[64,32],'circumflex':[32,80],'tilde':[72,176],'diaeresis':[80,0]}
for code,(letter,accent,ch) in spec['accents'].items():
    rows=list(patterns[letter])
    if accent=='cedilla':
        rows[7]=32
    elif letter.islower():
        rows[:2]=marks[accent]
    else:
        # Two accent rasters and five independently drawn capital body rasters.
        compact={'A':[14,17,31,17,17],'E':[31,16,30,16,31],
                 'I':[14,4,4,4,14],'O':[14,17,17,17,14],
                 'U':[17,17,17,17,14],'N':[17,25,21,19,17]}
        rows=marks[accent]+[v<<3 for v in compact[letter]]+[0]
    font[int(code)]=rows
assert all(len(row)==8 and all(v&7==0 for v in row) for row in font)
data=bytes(v for row in font for v in row)
(base/'FONT8X8.bin').write_bytes(data)
lines=['; Original CC0 5x7 font in 6x8 cells; MSB left, sixth column blank.','font8x8:']
for code,row in enumerate(font):lines.append('    db '+','.join(str(v) for v in row)+' ; '+str(code))
lines+=['font8x8_end:','    assert font8x8_end-font8x8 == 2048','']
(base/'src/FONT8X8.ASM').write_text('\n'.join(lines),encoding='ascii')
spec['patterns']={chr(c):[format(v,'08b') for v in font[c]] for c in range(32,127)}
spec['font']={'width':5,'height':7,'cellWidth':6,'cellHeight':8,'columns':80,'rows':24,'license':'CC0-1.0','source':'tools/font5x7.json'}
(base/'src/FONTSPEC.json').write_text(json.dumps(spec,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
records=['; Generated MSX-BR to BMP Unicode mapping.','unicode_table:']
for code,entry in spec['accents'].items():
    point=ord(entry[2]);records.append(' db '+str(code)+','+str(point&255)+','+str(point>>8))
records.append(' db 0')
(base/'src/UNICODE.ASM').write_text('\n'.join(records)+'\n',encoding='ascii')
