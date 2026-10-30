; SCREEN7.ASM -- V9938 bitmap, page 0, 512x212, 80x24 cells, 6x8 pixels each, 16-pixel margins.
; Uses MAIN-ROM WRTVDP/LDIRMV/LDIRVM only; no SUB-ROM trampoline.
bios_call:
    ld iy,(EXPTBL-1)
    call CALSLT
    ei
    ret
screen_enter:
    ld hl,RG0SAV
    ld de,saved_regs
    ld bc,8
    ldir
    ld hl,&FFE7
    ld bc,16
    ldir
    ld a,(SCRMOD)
    ld (saved_mode),a
    ld a,(CNSDFG)
    ld (saved_cnsdfg),a
    ld a,1
    ld (CNSDFG),a
    ld a,(&FAF6)
    ld (saved_acpage),a
    xor a
    ld (&FAF6),a
    ld hl,0
    ld de,VRAM_BACKUP
    ld bc,&4000
    ld ix,&0059
    call bios_call
    ld a,1
    ld (video_saved),a
    ld b,&20
    ld c,1
    ld ix,&0047
    call bios_call
    ld a,7
    ld (SCRMOD),a
    ; Select Graphic 6, display page 0; preserve palette and PAL/NTSC.
    ld b,&0A
    ld c,0
    call screen_reg
    ld b,&1F
    ld c,2
    call screen_reg
    ld b,1
    ld c,7
    call screen_reg
    ld b,&0A
    ld c,8
    call screen_reg
    ld a,(saved_regs+9)
    and &02
    or &80
    ld b,a
    ld c,9
    call screen_reg
    ld b,0
    ld c,14
    call screen_reg
    ld b,0
    ld c,23
    call screen_reg
    ; Clear bottom 20 scanlines. ROWBUF remains a single scanline.
    ld hl,ROWBUF
    ld bc,256
    ld a,&11
    call fill_memory
    ld a,192
    ld (render_y),a
screen_bottom:
    call render_send
    ld a,(render_y)
    inc a
    ld (render_y),a
    cp 212
    jp nz,screen_bottom
    call mark_all
    call render_dirty
    ld b,&60
    ld c,1
screen_reg:
    ld ix,&0047
    jp bios_call
screen_leave:
    ld a,(video_saved)
    or a
    ret z
    ld b,&20
    ld c,1
    call screen_reg
    ; Restore low 16K while SCRMOD is still 7, ACPAGE=0.
    ld hl,VRAM_BACKUP
    ld de,0
    ld bc,&4000
    ld ix,&005C
    call bios_call
    xor a
    ld (register_index),a
screen_restore_reg:
    ld a,(register_index)
    cp 1
    jp z,screen_restore_next
    ld e,a
    ld d,0
    ld hl,saved_regs
    add hl,de
    ld b,(hl)
    ld c,a
    call screen_reg
screen_restore_next:
    ld a,(register_index)
    inc a
    ld (register_index),a
    cp 24
    jp nz,screen_restore_reg
    ld a,(saved_mode)
    ld (SCRMOD),a
    ld a,(saved_cnsdfg)
    ld (CNSDFG),a
    ld a,(saved_acpage)
    ld (&FAF6),a
    ld a,(saved_regs+1)
    ld b,a
    ld c,1
    call screen_reg
    xor a
    ld (video_saved),a
    ret
; A=row. Pattern+color invalidation. Preserves main registers.
mark_row:
    push af
    push hl
    push de
    ld e,a
    ld d,0
    ld hl,DIRTY
    add hl,de
    ld a,(hl)
    or 3
    ld (hl),a
    pop de
    pop hl
    pop af
    ret
mark_cursor_row:
    ld a,(cursor_screen_row)
mark_pattern_row:
    push af
    push hl
    push de
    ld e,a
    ld d,0
    ld hl,DIRTY
    add hl,de
    ld a,(hl)
    or 1
    ld (hl),a
    pop de
    pop hl
    pop af
    ret
mark_all:
    ld hl,DIRTY
    ld bc,TEXT_ROWS
    ld a,3
    jp fill_memory

; Fill BC bytes at HL with A, including safe zero/one-byte handling.
fill_memory:
    ld (fill_value),a
    ld a,b
    or c
    ret z
    ld a,(fill_value)
    ld (hl),a
    dec bc
    ld a,b
    or c
    ret z
    ld d,h
    ld e,l
    inc de
    ldir
    ret

; A=row -> HL=GRID+row*80; destroys DE.
grid_row_address:
    ld h,0
    ld l,a
    call grid_row_offset
    ld de,GRID
    add hl,de
    ret
; HL=row -> HL=row*80, used by editor/history after bounds checks.
grid_row_offset:
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl
    add hl,de
    ret
glyph_address:
    ld h,0
    ld l,a
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,font8x8
    add hl,de
    ret


render_dirty:
    xor a
    ld (render_row),a
render_next_row:
    ld a,(render_row)
    ld e,a
    ld d,0
    ld hl,DIRTY
    add hl,de
    ld a,(hl)
    or a
    call nz,render_patterns
    ld a,(render_row)
    ld e,a
    ld d,0
    ld hl,DIRTY
    add hl,de
    ld (hl),0
    ld a,(render_row)
    inc a
    ld (render_row),a
    cp TEXT_ROWS
    jp nz,render_next_row
    ret
render_patterns:
    ld a,(render_row)
    ld e,a
    ld d,0
    ld hl,ROWCOLORS
    add hl,de
    ld a,(hl)
    and 15
    ld b,a
    rlca
    rlca
    rlca
    rlca
    or b
    ld (bg_pair),a
    ld a,(hl)
    and &F0
    ld b,a
    rrca
    rrca
    rrca
    rrca
    or b
    ld (fg_pair),a
    xor a
    ld (render_scan),a
render_scanline:
    ld a,(render_row)
    call grid_row_address
    ld (render_grid_ptr),hl
    ld hl,ROWBUF
    ld bc,256
    ld a,(bg_pair)
    call fill_memory
    ld hl,ROWBUF+8
    ld (render_buffer_ptr),hl
    xor a
    ld (render_col),a
render_character:
    ld hl,(render_grid_ptr)
    ld a,(hl)
    inc hl
    ld (render_grid_ptr),hl
    call glyph_address
    ld a,(render_scan)
    ld e,a
    ld d,0
    add hl,de
    ld a,(hl)
    ld (glyph_bits),a
    ld a,(cursor_phase)
    or a
    jp z,render_pixels
    ld a,(cursor_screen_row)
    ld b,a
    ld a,(render_row)
    cp b
    jp nz,render_pixels
    ld a,(cursor_col)
    ld b,a
    ld a,(render_col)
    cp b
    jp nz,render_pixels
    ld a,(glyph_bits)
    xor 255
    ld (glyph_bits),a
render_pixels:
    ld a,(glyph_bits)
    ld c,a
    ld b,3
    ld de,(render_buffer_ptr)
render_pixel_pair:
    sla c
    ld a,(bg_pair)
    jp nc,render_pixel_high
    ld a,(fg_pair)
render_pixel_high:
    and &F0
    ld (pixel_high),a
    sla c
    ld a,(bg_pair)
    jp nc,render_pixel_low
    ld a,(fg_pair)
render_pixel_low:
    and 15
    push hl
    ld hl,pixel_high
    or (hl)
    pop hl
    ld (de),a
    inc de
    djnz render_pixel_pair
    ld (render_buffer_ptr),de
    ld a,(render_col)
    inc a
    ld (render_col),a
    cp COLUMNS
    jp nz,render_character
    ld a,(render_row)
    add a,a
    add a,a
    add a,a
    ld b,a
    ld a,(render_scan)
    add a,b
    ld (render_y),a
    call render_send
    ld a,(render_scan)
    inc a
    ld (render_scan),a
    cp CELL_HEIGHT
    jp nz,render_scanline
    ret
render_send:
    ld a,(render_y)
    ld d,a
    ld e,0
    ld hl,ROWBUF
    ld bc,256
    ld ix,&005C
    jp bios_call
saved_regs: ds 24
saved_mode: db 0
saved_cnsdfg: db 0
saved_acpage: db 0
video_saved: db 0
register_index: db 0
render_row: db 0
render_scan: db 0
render_col: db 0
render_y: db 0
render_grid_ptr: dw 0
render_buffer_ptr: dw 0
glyph_bits: db 0
fg_pair: db 0
bg_pair: db 0
fill_value: db 0

pixel_high: db 0
