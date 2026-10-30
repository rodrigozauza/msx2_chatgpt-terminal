; TERMINAL.ASM -- in-memory 80-column window, local preview and overlays.
; Rendering only; NETWORK handles transport. No model response is generated here.

put_line:
    call mark_row
put_line_unmarked:
    ld (line_row),a
    ld (line_source),hl
    call grid_row_address
    ld (line_dest),hl
    ld bc,GRID_STRIDE
    ld a,32
    call fill_memory
    ld hl,(line_source)
    ld de,(line_dest)
    ld b,COLUMNS
put_line_loop:
    ld a,(hl)
    or a
    ret z
    ld (de),a
    inc hl
    inc de
    djnz put_line_loop
    ret

ui_initial:
    ld a,0
    ld hl,title_text
    call put_line
    ld a,1
    ld hl,intro_text
    call put_line
    ld a,2
    ld hl,user_text
    call put_line
    ld a,3
    ld hl,chatgpt_text
    call put_line
    ld a,4
    ld hl,history_intro
    call put_line
    ld a,5
    ld hl,cancel_intro
    call put_line
    ld a,FOOTER_ROW
    ld hl,footer_text
    call put_line
    ld a,7
    ld (term_row),a
    ret

term_string:
    ld a,(hl)
    or a
    ret z
    call term_char
    inc hl
    jp term_string
term_char:
    ld (term_value),a
    push hl
    push de
    push bc
    cp 10
    jp z,term_do_newline
    xor a
    ld (term_wrapped),a
    ld a,(term_row)
    call mark_row
    call grid_row_address
    ld a,(term_col)
    ld e,a
    ld d,0
    add hl,de
    ld a,(term_value)
    ld (hl),a
    ld a,(term_row)
    ld e,a
    ld d,0
    ld hl,ROWCOLORS
    add hl,de
    ld a,(term_color)
    ld (hl),a
    ld a,(term_col)
    inc a
    cp COLUMNS
    jp z,term_do_wrap
    ld (term_col),a
    jp term_char_done
term_do_newline:
    ld a,(term_wrapped)
    or a
    jp z,term_force_newline
    xor a
    ld (term_wrapped),a
    jp term_char_done
term_do_wrap:
    call term_newline
    ld a,1
    ld (term_wrapped),a
    jp term_char_done
term_force_newline:
    call term_newline
term_char_done:
    pop bc
    pop de
    pop hl
    ret
term_newline:
    xor a
    ld (term_wrapped),a
    ld (term_col),a
    ld a,(term_row)
    inc a
    cp STATUS_ROW
    jp c,term_store_row
    call term_scroll
    ld a,STATUS_ROW-1
term_store_row:
    ld (term_row),a
    ret
term_scroll:
    ld hl,GRID+2*GRID_STRIDE
    ld de,GRID+GRID_STRIDE
    ld bc,(OVERLAY_ROWS-1)*GRID_STRIDE
    ldir
    ld hl,GRID+(STATUS_ROW-1)*GRID_STRIDE
    ld bc,GRID_STRIDE
    ld a,32
    call fill_memory
    ld hl,ROWCOLORS+2
    ld de,ROWCOLORS+1
    ld bc,OVERLAY_ROWS-1
    ldir
    ld a,(term_color)
    ld (ROWCOLORS+STATUS_ROW-1),a
    ld a,1
term_dirty_loop:
    call mark_row
    inc a
    cp STATUS_ROW
    jp nz,term_dirty_loop
    ret

preview_local:
    call overlay_restore
    ld hl,(editor_length)
    ld a,h
    or l
    ret z
    ld a,(term_col)
    or a
    call nz,term_newline
    ld a,&B1
    ld (term_color),a
    ld hl,preview_label
    call term_string
    ld a,10
    call term_char
    ld a,&F1
    ld (term_color),a
    ld hl,EDITOR
    call term_string
    ld a,10
    call term_char
    ld a,&71
    ld (term_color),a
    ld hl,local_status
    call term_string
    ld a,10
    call term_char
    ld a,&F1
    ld (term_color),a
    ret

help_toggle:
    ld a,1
    jp overlay_toggle
calibration_toggle:
    ld a,2
overlay_toggle:
    ld (overlay_requested),a
    ld b,a
    ld a,(overlay_mode)
    cp b
    jp z,overlay_restore
    or a
    call z,overlay_save
    ld a,(overlay_requested)
    ld (overlay_mode),a
    ld hl,GRID+GRID_STRIDE
    ld bc,OVERLAY_ROWS*GRID_STRIDE
    ld a,32
    call fill_memory
    ld hl,ROWCOLORS+1
    ld bc,OVERLAY_ROWS
    ld a,&F1
    call fill_memory
    ld a,(overlay_mode)
    cp 2
    jp z,draw_calibration
    call draw_help
    jp mark_all
overlay_save:
    ld hl,GRID+GRID_STRIDE
    ld de,OVERLAY_BACKUP
    ld bc,OVERLAY_ROWS*GRID_STRIDE
    ldir
    ld hl,ROWCOLORS+1
    ld de,OVERLAY_COLORS
    ld bc,OVERLAY_ROWS
    ldir
    ret
overlay_restore:
    ld a,(overlay_mode)
    or a
    ret z
    ld hl,OVERLAY_BACKUP
    ld de,GRID+GRID_STRIDE
    ld bc,OVERLAY_ROWS*GRID_STRIDE
    ldir
    ld hl,OVERLAY_COLORS
    ld de,ROWCOLORS+1
    ld bc,OVERLAY_ROWS
    ldir
    xor a
    ld (overlay_mode),a
    jp mark_all

draw_help:
    ld a,1
    ld hl,help_title
    call put_line
    ld a,2
    ld hl,help_1
    call put_line
    ld a,3
    ld hl,help_2
    call put_line
    ld a,4
    ld hl,help_3
    call put_line
    ld a,5
    ld hl,help_4
    call put_line
    ld a,6
    ld hl,help_5
    call put_line
    ld a,7
    ld hl,help_6
    call put_line
    ld a,8
    ld hl,help_7
    call put_line
    ld a,9
    ld hl,help_8
    call put_line
    ld a,10
    ld hl,help_9
    call put_line
    jp mark_all

draw_calibration:
    ld a,1
    ld hl,cal_title
    call put_line
    ld a,2
    ld hl,ruler_text
    call put_line
    ld a,3
    ld hl,cal_upper
    call put_line
    ld a,4
    ld hl,cal_lower
    call put_line
    ld a,5
    ld hl,font_text
    call put_line
    ld a,6
    ld hl,accents_text
    call put_line
    ld a,7
    ld hl,accents_upper
    call put_line
    ld a,8
    ld hl,json_text
    call put_line
    ld a,10
    ld hl,cal_note
    call put_line
    jp mark_all

term_row: db 1
term_col: db 0
term_wrapped: db 0
term_color: db &F1
term_value: db 0
overlay_mode: db 0
overlay_requested: db 0
line_row: db 0
line_source: dw 0
line_dest: dw 0
title_text: dm "MSX CHATGPT 80x24 | OFFLINE"
    db 0
ruler_text: dm "01234567890123456789012345678901234567890123456789012345678901234567890123456789"
    db 0
intro_text: dm "SCREEN7 | Fonte 5x7, celula 6x8"
    db 0
user_text: dm "Digite abaixo. ^Q publica."
    db 0
chatgpt_text: dm "^W envia/consulta; ^Y historico"
    db 0
history_intro: dm "^S salva  ^D abre  ^G ajuda"
    db 0
cancel_intro: dm "^R fonte  ^P previa local"
    db 0
font_text: dm "O0 I1l | {} [] () /\ +-= _:;"
    db 0
json_text: dm "JSON: {texto} [ ] : , . ; ! ?"
    db 0
accents_text: dm "BR: "
    db 160,32,133,32,131,32,177,32,130,32,136,32,161,32,162,32,147,32,181,32,163,32,129,32,135,0
accents_upper: dm "BR: "
    db 132,32,143,32,140,32,176,32,144,32,141,32,137,32,138,32,142,32,180,32,139,32,154,32,128,0
footer_text: dm "Esc sair | ^Q pedir | ^G ajuda"
    db 0
preview_label: dm "[USER / PREVIA LOCAL]"
    db 0
local_status: dm "[LOCAL] Nada foi enviado."
    db 0
help_title: dm "AJUDA | ^G volta"
    db 0
help_1: dm "Setas movem; Enter nova linha"
    db 0
help_2: dm "BS apaga antes; DEL no cursor"
    db 0
help_3: dm "^A/Home inicio; ^E fim"
    db 0
help_4: dm "^S salva; ^D abre rascunho"
    db 0
help_5: dm "^Q publica; ^W envia/consulta"
    db 0
help_6: dm "^O importa; ^B rever resposta"
    db 0
help_7: dm "^Y historico ^T auto ^P previa"
    db 0
help_8: dm "^L limpa; ^X 2x cancela pedido"
    db 0
help_9: dm "Esc sai | Editor: 2047 bytes"
    db 0
cal_title: dm "FONTE 5x7 / 6x8 | ^R volta"
    db 0
cal_upper: dm "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    db 0
cal_lower: dm "abcdefghijklmnopqrstuvwxyz"
    db 0
cal_note: dm "80 colunas | 24 linhas | MSX-BR"
    db 0
